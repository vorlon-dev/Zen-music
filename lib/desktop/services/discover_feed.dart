// ZenMusic · vorlon-dev
//
// Discover feed data (mobile). Warmed once at app start so the Discover tab
// opens with songs + resolved streams already in memory.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/yt_video_engine.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class DiscoverStreams {
  final String videoUrl;
  final String? audioUrl;
  final Map<String, String> headers;
  const DiscoverStreams(this.videoUrl, this.audioUrl, this.headers);
}

class DiscoverFeed {
  DiscoverFeed._();
  static final DiscoverFeed instance = DiscoverFeed._();

  /// Indian-first mix: Hindi / Punjabi / Tamil / Telugu, official videos.
  static const _videoQueries = [
    'trending hindi songs official video',
    'new bollywood songs official video',
    'latest punjabi songs official video',
    'trending tamil songs official video',
    'new telugu songs official video',
    'arijit singh latest songs',
    'indian indie songs official video',
    'latest hindi songs 2026',
  ];
  static const _songQueries = [
    'trending hindi songs',
    'new punjabi songs',
    'bollywood hits',
  ];

  final List<Map<String, dynamic>> songs = [];
  final Set<String> _seen = {};
  final Map<String, Future<DiscoverStreams?>> _streams = {};

  Future<void>? _warming;
  bool _loadingMore = false;
  bool get ready => songs.isNotEmpty;

  /// Idempotent. Call at app start; the page awaits the same future.
  Future<void> warm({bool force = false}) {
    if (force) _warming = null;
    return _warming ??= _load();
  }

  Future<void> _load() async {
    final v = [..._videoQueries]..shuffle();
    final s = [..._songQueries]..shuffle();
    final results = await Future.wait([
      _search(v[0], 'videos'),
      _search(v[1], 'videos'),
      _search(v[2], 'videos'),
      _search(s[0], 'songs'),
    ]);
    var longest = 0;
    for (final l in results) {
      if (l.length > longest) longest = l.length;
    }
    for (var i = 0; i < longest; i++) {
      for (final l in results) {
        if (i < l.length) _add(l[i]);
      }
    }
    // Warm the first songs' streams so the first swipe-in plays instantly.
    for (var i = 0; i < songs.length && i < 2; i++) {
      unawaited(streams(songs[i]['videoId'] as String));
    }
  }

  Future<bool> loadMore() async {
    if (_loadingMore || songs.isEmpty) return false;
    _loadingMore = true;
    var added = false;
    try {
      final seed = songs[songs.length - 1]['videoId'];
      final more = await GetIt.I<YTMusic>()
          .getNextSongList(videoId: seed, radio: true, limit: 25);
      for (final s in more) {
        if (s is Map && _add(s)) added = true;
      }
    } catch (_) {
      // feed simply ends
    } finally {
      _loadingMore = false;
    }
    return added;
  }

  // ── filtering: no playlists / mixes / hour-long compilations ──

  static const _bad = [
    'playlist',
    'jukebox',
    'nonstop',
    'non stop',
    'mashup mix',
    'full album',
    'hours',
    'podcast',
    'compilation',
  ];

  static int? _seconds(Map m) {
    final n = m['duration_seconds'];
    if (n is num) return n.toInt();
    final d = m['duration']?.toString();
    if (d == null || !d.contains(':')) return null;
    var total = 0;
    for (final p in d.split(':')) {
      final v = int.tryParse(p.trim());
      if (v == null) return null;
      total = total * 60 + v;
    }
    return total;
  }

  bool _add(Map raw) {
    final id = raw['videoId']?.toString();
    if (id == null || id.length != 11 || _seen.contains(id)) return false;
    final title = (raw['title'] ?? '').toString().toLowerCase();
    if (_bad.any(title.contains)) return false;
    final secs = _seconds(raw);
    if (secs != null && (secs < 45 || secs > 600)) return false;
    _seen.add(id);
    songs.add(Map<String, dynamic>.from(raw));
    return true;
  }

  Future<List<Map>> _search(String q, String filter) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await GetIt.I<YTMusic>().search(q, filter: filter);
        final sections = res['sections'] as List?;
        if (sections == null || sections.isEmpty) continue;
        final list = ((sections[0]['contents'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {
        // retry once
      }
    }
    return <Map>[];
  }

  // ── streams: our native InnerTube (PO-token) first, Dart engine second ──

  Future<DiscoverStreams?> streams(String id) {
    return _streams.putIfAbsent(id, () async {
      final s = await _resolve(id);
      if (s == null) _streams.remove(id);
      return s;
    });
  }

  Future<DiscoverStreams?> _resolve(String id) async {
    const height = 480;
    if (Platform.isAndroid && InnertubexBridge.available != false) {
      try {
        final itx = await InnertubexBridge.extractVideo(id, maxHeight: height);
        final url = itx?.videoUrl;
        if (itx != null && url != null && url.isNotEmpty) {
          final a = itx.audioUrl;
          return DiscoverStreams(
              url, (a == null || a.isEmpty) ? null : a, itx.headers);
        }
      } catch (e) {
        debugPrint('[discover] native extract($id) failed: $e');
      }
    }
    try {
      final s = await YtVideoEngine.extractVideo(id, maxHeight: height);
      if (s?.videoUrl != null) {
        return DiscoverStreams(s!.videoUrl!, s.audioUrl, s.headers);
      }
    } catch (_) {}
    return null;
  }
}
