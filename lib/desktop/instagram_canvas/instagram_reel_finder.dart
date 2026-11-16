// ZenMusic · vorlon-dev
//
// Instagram reel canvas — resolution orchestrator.
//
// The whole chain is Instagram only, and it is found from the song itself:
//
//   1. Related-tag queries are built from THIS song (song videos / edits /
//      dance videos) and searched keylessly across public search engines.
//   2. Each top candidate is validated through the user's self-hosted
//      resolver service, then played through its Range-capable stream
//      proxy (or the direct CDN mp4 when preferProxyPlayback = false).
//
// Nothing else sits between the song and its reel — when no good reel is
// found the caller simply keeps its existing backdrop (never-stall: every
// stage is time-bounded and fail-soft, results are cached, misses cool down).
//
// Put at: lib/desktop/instagram_canvas/instagram_reel_finder.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zenmusic/desktop/instagram_canvas/instagram_canvas_config.dart';
import 'package:zenmusic/desktop/instagram_canvas/reel_discovery.dart';

/// A ready-to-play backdrop result.
class ReelResult {
  const ReelResult({
    required this.url,
    required this.headers,
    required this.source,
  });

  /// Playback URL — playable by VideoBackdrop as-is.
  final String url;

  /// Headers for the URL (always empty: reels stream via the service proxy
  /// or a public CDN — neither needs headers).
  final Map<String, String> headers;

  /// 'reel' — informational.
  final String source;
}

class InstagramReelFinder {
  InstagramReelFinder._();

  static final InstagramReelFinder instance = InstagramReelFinder._();

  // songKey -> (result, resolvedAt). A null result = negative entry.
  final Map<String, _Entry> _cache = {};

  // Songs currently being resolved (player + discover can ask together —
  // the work happens once).
  final Map<String, Future<ReelResult?>> _inflight = {};

  /// Resolve a backdrop for a song. Returns null when nothing was found
  /// (caller falls through to its existing chain). Never throws.
  Future<ReelResult?> resolve({
    required String songKey,
    required String title,
    required String artist,
  }) async {
    if (!InstagramCanvasConfig.enabled) return null;

    final key = songKey.isEmpty
        ? '${title.toLowerCase()}|${artist.toLowerCase()}'
        : songKey;
    if (key.trim().isEmpty) return null;

    // Cache / negative-cooldown check.
    final cached = _cache[key];
    if (cached != null) {
      final age = DateTime.now().difference(cached.at);
      if (cached.result != null &&
          age < InstagramCanvasConfig.cacheTtl) {
        return cached.result;
      }
      if (cached.result == null &&
          age < InstagramCanvasConfig.negativeCooldown) {
        return null;
      }
    }

    // Already resolving this song? Share that work instead of duplicating.
    final running = _inflight[key];
    if (running != null) {
      try {
        return await running;
      } catch (_) {
        return null;
      }
    }

    final fut = _gated(() => _resolveUncached(
          songKey: key,
          title: title,
          artist: artist,
        )).catchError((_) => null);
    _inflight[key] = fut;
    try {
      final result = await fut;
      _store(key, result);
      return result;
    } finally {
      _inflight.remove(key);
    }
  }

  // Only a couple of songs may be resolved at the same moment. Discover
  // asks for a reel for every card it pre-loads; unthrottled that sent
  // dozens of searches at once to the resolver service.
  static const int _maxParallel = 2;
  int _running = 0;
  final List<Completer<void>> _waiters = [];

  Future<T> _gated<T>(Future<T> Function() job) async {
    if (_running >= _maxParallel) {
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  /// Forget a cached entry (e.g. the user toggled the feature off/on).
  void invalidate(String songKey) => _cache.remove(songKey);

  void _store(String key, ReelResult? result) {
    if (_cache.length >= InstagramCanvasConfig.maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = _Entry(result, DateTime.now());
  }

  Future<ReelResult?> _resolveUncached({
    required String songKey,
    required String title,
    required String artist,
  }) async {
    final cleanTitle = _clean(title);
    final cleanArtist = _clean(artist);
    if (cleanTitle.isEmpty) return null;

    // One stage deadline covers discovery AND validations.
    final deadline =
        DateTime.now().add(InstagramCanvasConfig.reelStageBudget);
    final candidates = await ReelDiscovery.findReels(
      title: cleanTitle,
      artist: cleanArtist,
    );
    if (candidates.isEmpty) return null;

    for (final candidate in candidates) {
      if (candidate.score < InstagramCanvasConfig.minReelScore) break;
      if (DateTime.now().isAfter(deadline)) break;

      // Validate through the service: a bad/private/dead candidate returns
      // an error JSON and is skipped. This also warms the service's own
      // 1-hour resolve cache, making the first playback instant.
      final igUrl = candidate.isReel
          ? 'https://www.instagram.com/reel/${candidate.shortcode}/'
          : 'https://www.instagram.com/p/${candidate.shortcode}/';
      final direct = await _serviceVideoUrl(igUrl);
      if (direct == null) continue; // unresolvable — try the next candidate

      if (InstagramCanvasConfig.preferProxyPlayback) {
        return ReelResult(
          url: streamProxyUrlFor(igUrl),
          headers: const {},
          source: 'reel',
        );
      }
      return ReelResult(
        url: direct,
        headers: const {},
        source: 'reel',
      );
    }
    return null;
  }

  /// Build the Range-capable playback URL for a reel via the service proxy.
  static String streamProxyUrlFor(String igPostUrl) {
    final encoded = Uri.encodeComponent(igPostUrl);
    return '${InstagramCanvasConfig.serviceBaseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/api/stream?url=$encoded';
  }

  /// GET /api/video?url=... -> "videoUrl" from the JSON body, or null.
  ///
  /// Also acts as the validation step: a reel that the service cannot
  /// resolve (deleted / private / not a video) returns null here.
  Future<String?> _serviceVideoUrl(String postUrl) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      try {
        final uri = '${InstagramCanvasConfig.serviceBaseUrl.replaceAll(RegExp(r'/+$'), '')}'
            '/api/video?url=${Uri.encodeComponent(postUrl)}';
        final req = await client
            .getUrl(Uri.parse(uri))
            .timeout(InstagramCanvasConfig.serviceTimeout);
        final res =
            await req.close().timeout(InstagramCanvasConfig.serviceTimeout);
        if (res.statusCode != 200) return null;
        final body = await _readAll(res, InstagramCanvasConfig.serviceTimeout);
        if (body.isEmpty) return null;
        final json = jsonDecode(body);
        if (json is! Map) return null;
        final videoUrl = json['videoUrl']?.toString() ?? '';
        if (videoUrl.startsWith('http') && videoUrl.contains('.mp4')) {
          return videoUrl;
        }
        return null;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return null;
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Read a bounded response body as text (time-budgeted, never throws).
  static Future<String> _readAll(
      HttpClientResponse res, Duration budget) async {
    try {
      final chunks = <String>[];
      // Budget exceeded -> TimeoutException -> caught below -> ''.
      await for (final chunk in res.transform(utf8.decoder).timeout(budget)) {
        chunks.add(chunk);
      }
      return chunks.join();
    } catch (_) {
      return '';
    }
  }

  /// Drop noise so searches and scoring see the real song name.
  static String _clean(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
    s = s.replaceAll(
        RegExp(
            r'\b(feat|ft|official|video|audio|lyrics?|hd|4k)\b',
            caseSensitive: false),
        ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _Entry {
  const _Entry(this.result, this.at);
  final ReelResult? result;
  final DateTime at;
}
