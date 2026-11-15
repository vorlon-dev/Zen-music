// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, mapEquals;
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
// just_audio_background is imported for the MediaItem tag class ONLY —
// same as media_player.dart; the background plugin itself is never used.
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/lossless/lossless_quality.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class LosslessService {
  LosslessService._();
  static final LosslessService instance = LosslessService._();

  /// The user's deployed qobuz-api instance. One-line change if it moves.
  static const String endpoint = 'https://jobfolw.antideploy.app/';

  /// DEAD ENDPOINT (Nov 2026): the host above answers HTTP 404 for every
  /// track and then drops connections outright. It only burned 8-12 s per
  /// song (connect timeout + io timeout) and spammed the log before the
  /// real chain even started — the direct cause of "song loads and loads
  /// but never plays". While this flag is false every call returns null
  /// INSTANTLY (no request is ever made) and playback goes straight to
  /// the mirror pool / JioSaavn / cache / YouTube. Flip it back to true
  /// only if a fresh, working qobuz-api instance is deployed.
  static const bool endpointEnabled = false;
  static bool _warnedDisabled = false;

  static const _connectTimeout = Duration(seconds: 8);
  static const _ioTimeout = Duration(seconds: 12);
  static const _positiveTtl = Duration(minutes: 8);
  static const _negativeTtl = Duration(minutes: 5);

  static const _noMatchTtl = Duration(minutes: 30);

  static const _maxCacheEntries = 128;

  final Map<String, LosslessQuality> _served = {};

  /// Bumps whenever [_served] changes so the UI can rebuild.
  static final ValueNotifier<int> servedRevision = ValueNotifier<int>(0);

  LosslessQuality? servedTierFor(String songId) => _served[songId];

  /// MirrorSource (free Antra-pool FLAC) reports the tier it actually
  /// served for a song — same map, same revision counter, so the player
  /// page quality pill lights up with zero UI changes.
  void noteMirrorServed(String id, LosslessQuality? tier) =>
      _setServed(id, tier);

  void _setServed(String id, LosslessQuality? tier) {
    if (tier == null) {
      if (_served.remove(id) == null) return;
    } else {
      if (_served[id] == tier) return;
      _served[id] = tier;
      _evict(_served);
    }
    servedRevision.value++;
  }

  static const _maxConcurrent = 3;
  int _inFlight = 0;
  final List<Completer<void>> _gateWaiters = [];

  Future<void> _acquireSlot() async {
    if (_inFlight < _maxConcurrent) {
      _inFlight++;
      return;
    }
    final waiter = Completer<void>();
    _gateWaiters.add(waiter);
    await waiter.future; // _releaseSlot hands the slot over directly
  }

  void _releaseSlot() {
    if (_gateWaiters.isNotEmpty) {
      _gateWaiters.removeAt(0).complete();
      return;
    }
    _inFlight--;
  }

  /// videoId -> {tierKey -> stream url}. Signed CDN URLs, so short TTL.
  final Map<String, ({Map<String, String> streams, DateTime expiry})>
  _streamCache = {};

  /// videoId -> retry-not-before timestamp (no Qobuz match / endpoint down).
  final Map<String, DateTime> _failCache = {};

  /// JioSaavn id -> YouTube videoId (found once via a YTM song search).
  final Map<String, String> _saavnToYt = {};


  /// Returns a direct Qobuz AudioSource for [song] at the user's selected
  /// tier, or null when the song can't be upgraded (caller then falls back
  /// to its normal source). Never throws.
  Future<AudioSource?> tryBuildSource(
      Map<String, dynamic> song, MediaItem tag) async {
    if (!endpointEnabled) {
      if (!_warnedDisabled) {
        _warnedDisabled = true;
        print('[lossless] qobuz endpoint disabled (dead host) — skipping');
      }
      return null;
    }
    try {
      final videoId = await _youtubeIdFor(song);
      if (videoId == null || videoId.isEmpty) {
        _setServed(tag.id, null);
        return null;
      }

      final streams = await resolveStreams(videoId);
      if (streams == null) {
        _setServed(tag.id, null);
        return null;
      }

      final wanted = LosslessPrefs.current;
      for (final tier in _ladderFrom(wanted)) {
        final url = streams[tier.tierKey];
        if (url != null && url.isNotEmpty) {
          if (tier != wanted) {
            print('[lossless] $videoId: ${wanted.tierKey} unavailable, '
                'using ${tier.tierKey}');
          }
          _setServed(tag.id, tier);
          return AudioSource.uri(Uri.parse(url), tag: tag);
        }
      }
      print('[lossless] $videoId: matched but no stream URLs, falling back');
      _setServed(tag.id, null);
      return null;
    } catch (e) {
      print('[lossless] source error: $e');
      _setServed(tag.id, null);
      return null;
    }
  }

  /// The requested tier first, then every lower tier (never up — see
  /// header). LosslessQuality.values is ordered lightest -> heaviest.
  List<LosslessQuality> _ladderFrom(LosslessQuality wanted) {
    final all = LosslessQuality.values;
    final start = all.indexOf(wanted);
    return [for (var i = start; i >= 0; i--) all[i]];
  }


  /// Maps the song to the YouTube video ID the endpoint needs.
  /// YouTube videos are rejected here too (defence in depth — the caller
  /// in media_player.dart already screens them out).
  Future<String?> _youtubeIdFor(Map<String, dynamic> song) async {
    if (song['isYtVideo'] == true) return null;

    final isSaavn =
        (song['jiosaavnStreamUrl'] as String?)?.isNotEmpty == true ||
            song['type'] == 'JIOSAAVN';

    if (!isSaavn) {
      final id = song['videoId'] as String?;
      return (id != null && id.length == 11) ? id : null;
    }

    // JioSaavn song: 'videoId' is a JioSaavn id. Find the YouTube
    // counterpart once, then reuse the mapping for the session.
    final saavnId = song['videoId'] as String? ?? '';
    if (saavnId.isEmpty) return null;
    final mapped = _saavnToYt[saavnId];
    if (mapped != null) return mapped;

    final query = '${song['title'] ?? ''} ${song['artist'] ?? ''}'.trim();
    if (query.isEmpty) return null;
    try {
      final result = await GetIt.I<YTMusic>().search(query, filter: 'songs');
      final sections = result['sections'] as List?;
      if (sections == null || sections.isEmpty) return null;
      final contents = sections[0]['contents'] as List?;
      if (contents == null || contents.isEmpty) return null;
      final first = Map<String, dynamic>.from(contents[0] as Map);
      final id = first['videoId'] as String?;
      if (id == null || id.length != 11) return null;
      _saavnToYt[saavnId] = id;
      _evict(_saavnToYt);
      return id;
    } catch (e) {
      print('[lossless] JioSaavn YTM lookup failed: $e');
      return null;
    }
  }


  /// GET /?id=<videoId> -> {tierKey -> stream url}, with caching.
  /// Returns null on ANY failure (HTTP error, error status, timeout,
  /// no streams) — negative results are remembered for [_negativeTtl].
  Future<Map<String, String>?> resolveStreams(String videoId) async {
    if (!endpointEnabled) return null; // dead host — never contacted
    final now = DateTime.now();

    final hit = _streamCache[videoId];
    if (hit != null && now.isBefore(hit.expiry)) return hit.streams;

    final failedAt = _failCache[videoId];
    if (failedAt != null && now.isBefore(failedAt)) return null;

    HttpClient? client;
    bool held = false;
    try {
      await _acquireSlot();
      held = true;
      client = HttpClient()..connectionTimeout = _connectTimeout;
      client.userAgent = 'ZenMusic/1.0 (lossless)';
      final request = await client
          .getUrl(Uri.parse('$endpoint?id=$videoId'))
          .timeout(_ioTimeout);
      final response = await request.close().timeout(_ioTimeout);
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        print('[lossless] endpoint HTTP ${response.statusCode} for $videoId');
        _failCache[videoId] = now.add(response.statusCode == 404
            ? _noMatchTtl
            : _negativeTtl);
        _evict(_failCache);
        return null;
      }

      final data = jsonDecode(body);
      if (data is! Map || data['status'] != 'success') {
        print('[lossless] no Qobuz match for $videoId, falling back');
        _failCache[videoId] = now.add(_noMatchTtl);
        _evict(_failCache);
        return null;
      }

      final streams = <String, String>{};
      final raw = data['streams'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = '${entry.key}';
          final url = entry.value is Map ? entry.value['url'] as String? : null;
          if (url != null && url.isNotEmpty) streams[key] = url;
        }
      }
      if (streams.isEmpty) {
        print('[lossless] $videoId: response carried no streams');
        _failCache[videoId] = now.add(_negativeTtl);
        _evict(_failCache);
        return null;
      }

      _streamCache[videoId] =
      (streams: streams, expiry: now.add(_positiveTtl));
      _evict(_streamCache);
      return streams;
    } catch (e) {
      print('[lossless] endpoint error for $videoId: $e');
      _failCache[videoId] = now.add(_negativeTtl);
      _evict(_failCache);
      return null;
    } finally {
      if (held) _releaseSlot();
      client?.close(force: true);
    }
  }

  // Insertion-ordered eviction: drop the oldest keys past the cap.
  void _evict(Map map) {
    while (map.length > _maxCacheEntries) {
      final oldest = map.keys.first;
      map.remove(oldest);
    }
  }
}

// ───────── Real stream format (ExoPlayer decoder, Android) ─────────
//
// Codec / bitrate / sample rate of the track that is playing right now,
// read through the `zen.audio_format` channel of the just_audio fork.
// The player page's quality section overlays this on its estimate.

class RealAudioFormat {
  RealAudioFormat._();
  static final RealAudioFormat instance = RealAudioFormat._();

  static const MethodChannel _ch = MethodChannel('zen.audio_format');

  /// Bumped whenever a fresh format arrives (UI rebuild trigger).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Map<String, dynamic>? _current;
  String? _forId;
  bool _attached = false;
  bool _unsupported = false;

  /// Format of [songId] if it is the track we last measured, else null.
  Map<String, dynamic>? forSong(String songId) =>
      (_forId == songId) ? _current : null;

  void attach(AudioPlayer player) {
    if (_attached || _unsupported) return;
    _attached = true;
    player.currentIndexStream.listen((_) => _schedule(player));
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.ready) _schedule(player, quick: true);
    });
    _schedule(player);
  }

  Timer? _t1, _t2;

  void _schedule(AudioPlayer player, {bool quick = false}) {
    _t1?.cancel();
    _t2?.cancel();
    _t1 = Timer(const Duration(milliseconds: 350), () => refresh(player));
    if (!quick) {
      _t2 = Timer(const Duration(milliseconds: 1500), () => refresh(player));
    }
  }

  Future<void> refresh(AudioPlayer player) async {
    if (_unsupported) return;
    try {
      final tag = player.sequenceState?.currentSource?.tag;
      final id = tag is MediaItem ? tag.id : null;
      final raw = await _ch.invokeMethod<Map>('get');
      if (raw == null || id == null) return;
      final m = Map<String, dynamic>.from(raw);
      if (_forId == id && mapEquals(_current, m)) return;
      _forId = id;
      _current = m;
      revision.value++;
    } on MissingPluginException {
      _unsupported = true;
    } catch (_) {}
  }
}
