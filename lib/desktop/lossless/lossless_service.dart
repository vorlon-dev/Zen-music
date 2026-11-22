// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
// just_audio_background is imported for the MediaItem tag class ONLY —
// same as media_player.dart; the background plugin itself is never used.
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/lossless/lossless_quality.dart';
import 'package:zenmusic/desktop/lossless/mirror_arbiter.dart';
import 'package:zenmusic/desktop/lossless/mirror_source.dart';
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
  static const bool endpointEnabled = true; // endpoint is live again (Nov 2026)
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
    // 1) Your own endpoint first.
    if (endpointEnabled) {
      final direct = await _tryEndpoint(song, tag);
      if (direct != null) return direct;
      print('[lossless] endpoint gave no stream — trying the mirror chain');
    } else if (!_warnedDisabled) {
      _warnedDisabled = true;
      print('[lossless] qobuz endpoint disabled — using mirrors only');
    }
    // 2) Endpoint failed / has no match / is down: the dual-engine mirror
    //    chain takes over (Dart mirrors -> Kotlin engine -> emergency).
    return MirrorArbiter.instance.tryBuildSource(song, tag);
  }

  /// Forget cached endpoint answers for [song] (used when a stream died).
  void forgetSong(Map<String, dynamic> song) {
    final saavnId = song['videoId'] as String? ?? '';
    final id = _saavnToYt[saavnId] ?? saavnId;
    _streamCache.remove(id);
    _failCache.remove(id);
    _endpointDownUntil = null;
  }

  /// Endpoint trouble (timeouts, dropped sockets, HTTP 5xx) rests the
  /// endpoint for a minute so the next songs go straight to the mirrors
  /// instead of paying the connect timeout on every track.
  DateTime? _endpointDownUntil;

  Future<AudioSource?> _tryEndpoint(
      Map<String, dynamic> song, MediaItem tag) async {
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
          // The endpoint may answer with Qobuz' 30-second SAMPLE for tracks
          // it cannot stream in full. The mirror chain verifies every stream
          // before serving it; do the same here, otherwise a preview plays.
          if (!await _isFullStream(url, tier, song, tag)) {
            print('[lossless] $videoId: ${tier.tierKey} is a preview/short '
                'cut, rejected - using the mirror chain');
            _streamCache.remove(videoId);
            _failCache[videoId] = DateTime.now().add(_noMatchTtl);
            _setServed(tag.id, null);
            return null;
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

  /// True when [url] is verifiably the FULL track. FLAC tiers: the real
  /// duration is read from the STREAMINFO header of the first CDN bytes and
  /// must pass the same gate as the mirror engine. Anything unverifiable
  /// (not FLAC, probe failed) is rejected - never serve a possible preview.
  Future<bool> _isFullStream(String url, LosslessQuality tier,
      Map<String, dynamic> song, MediaItem tag) async {
    if (MirrorSource.looksLikePreviewUrl(url)) return false;
    if (tier == LosslessQuality.mp3_320) return true; // not probe-able
    int? expectedMs = tag.duration?.inMilliseconds;
    final d = song['duration'];
    if ((expectedMs == null || expectedMs <= 0) && d is Duration) {
      expectedMs = d.inMilliseconds;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-65535');
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != HttpStatus.partialContent &&
          res.statusCode != HttpStatus.ok) {
        return false;
      }
      final head = BytesBuilder();
      await for (final chunk in res.timeout(const Duration(seconds: 6),
          onTimeout: (sink) => sink.close())) {
        head.add(chunk);
        if (head.length > 65535) break;
      }
      final seconds = MirrorSource.flacDurationSeconds(head.toBytes());
      return MirrorSource.isFullTrack(seconds, expectedMs);
    } catch (e) {
      print('[lossless] endpoint probe error: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// The requested tier first, then every lower tier (never up — see
  /// header). LosslessQuality.values is ordered lightest -> heaviest.
  List<LosslessQuality> _ladderFrom(LosslessQuality wanted) {
    final all = LosslessQuality.values;
    final start = all.indexOf(wanted);
    // Strict lossless: a FLAC request must never be answered with the MP3
    // tier of the endpoint (that would be a silent lossy fallback).
    final skipMp3 =
        LosslessPrefs.strict && wanted != LosslessQuality.mp3_320;
    return [
      for (var i = start; i >= 0; i--)
        if (!(skipMp3 && all[i] == LosslessQuality.mp3_320)) all[i]
    ];
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
    final down = _endpointDownUntil;
    if (down != null && now.isBefore(down)) return null;

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
        if (response.statusCode >= 500) {
          _endpointDownUntil = now.add(const Duration(minutes: 1));
        }
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

      _endpointDownUntil = null;
      _streamCache[videoId] =
      (streams: streams, expiry: now.add(_positiveTtl));
      _evict(_streamCache);
      return streams;
    } catch (e) {
      print('[lossless] endpoint error for $videoId: $e');
      _endpointDownUntil = now.add(const Duration(minutes: 1));
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
