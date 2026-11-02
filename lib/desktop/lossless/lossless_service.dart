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
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class LosslessService {
  LosslessService._();
  static final LosslessService instance = LosslessService._();

  /// The user's deployed qobuz-api instance. One-line change if it moves.
  static const String endpoint = 'https://jobfolw.antideploy.app/';

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
