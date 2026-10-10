import 'dart:async';

import 'package:yt_extractor/yt_extractor.dart';
import '../models/collection.dart';
import '../models/song.dart';
import 'jiosaavn_service.dart';
import 'yt_music_service.dart';
import 'youtube_service.dart';

class HomeService {
  final _extractor = YtExtractor();
  final _jiosaavn = JiosaavnService();
  final _ytm = YtMusicService();
  final _ytService = YoutubeService();

  bool _extractorInitialized = false;

  Future<void> _ensureExtractorInit() async {
    if (_extractorInitialized) return;
    await _extractor.init();
    _extractorInitialized = true;
  }

  // ═════════════════════════════════════════════
  // SHORT-LIVED CACHE
  // Guards against home-screen rebuild storms without ever serving
  // stale hardcoded data. TTL is deliberately short (2 min) so the
  // screen reflects whatever is trending RIGHT NOW. UI can force a
  // refetch via clearCache() (pull-to-refresh).
  // ═════════════════════════════════════════════

  final Map<String, _CacheEntry<List<Song>>> _songCache = {};
  final Map<String, _CacheEntry<List<Collection>>> _collectionCache = {};
  static const _cacheTtl = Duration(minutes: 2);

  T? _fromCache<T>(Map<String, _CacheEntry<T>> cache, String key) {
    final e = cache[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _cacheTtl) {
      cache.remove(key);
      return null;
    }
    return e.value;
  }

  void _toCache<T>(Map<String, _CacheEntry<T>> cache, String key, T value) {
    cache[key] = _CacheEntry(value, DateTime.now());
  }

  /// Drop every cached shelf so the next call re-fetches live data.
  void clearCache() {
    _songCache.clear();
    _collectionCache.clear();
  }

  // ═════════════════════════════════════════════
  // DYNAMIC EDITORIAL SOURCES
  // No pinned playlist IDs — each section queries the live catalog and
  // uses whatever the top result is at call time. Fallback queries are
  // tried in order; the last resort is a direct song search.
  // ═════════════════════════════════════════════

  Future<List<Song>> _dynamicPlaylist({
    required List<String> queries,
    int max = 20,
  }) async {
    for (final q in queries) {
      try {
        final lists = await _jiosaavn.searchPlaylists(q, limit: 1);
        if (lists.isNotEmpty) {
          final detail = await _jiosaavn.getPlaylist(lists.first.id);
          final songs = detail?.songs ?? [];
          if (songs.isNotEmpty) return songs.take(max).toList();
        }
      } catch (e) {
        print('dynamic playlist "$q" failed: $e');
      }
    }
    // Fallback: direct live song search for the primary query.
    if (queries.isNotEmpty) {
      try {
        return await _jiosaavn.search(queries.first, limit: max);
      } catch (_) {}
    }
    return [];
  }

  // ═════════════════════════════════════════════
  // YT MUSIC — trending artists harvested LIVE from top songs
  // ═════════════════════════════════════════════

  /// Current top artists, harvested from real YT Music top-song rows.
  /// No hardcoded list — the ranking is whatever the live catalog
  /// returns right now.
  Future<List<String>> _fetchTrendingArtists({int max = 8}) async {
    final out = <String>[];
    final seen = <String>{};
    for (final q in ['top hits', 'trending songs']) {
      try {
        final songs = await _ytm.searchSongs(q, limit: 30);
        for (final s in songs) {
          // Song.artist may be "A, B & C" — keep the lead artist only.
          final lead = s.artist.split(RegExp(r'[,&]')).first.trim();
          if (lead.isEmpty) continue;
          if (seen.add(lead.toLowerCase())) out.add(lead);
          if (out.length >= max) break;
        }
      } catch (e) {
        print('_fetchTrendingArtists "$q" failed: $e');
      }
      if (out.length >= max) break;
    }
    return out;
  }

  Future<List<Song>> getYtTrendingSongs() async {
    const key = 'yt_trending_songs';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;

    try {
      final artists = await _fetchTrendingArtists(max: 8);
      if (artists.isEmpty) return [];

      // Rotate through the LIVE artist pool by day-of-week.
      final day = DateTime.now().weekday;
      final picks = [
        artists[day % artists.length],
        artists[(day + 3) % artists.length],
      ];

      final out = <Song>[];
      final seen = <String>{};
      for (final name in picks) {
        final ids = await _ytm.searchArtistIds(name, limit: 1);
        if (ids.isEmpty) continue;
        final songs = await _ytm.getArtistTopSongs(ids.first, limit: 8);
        for (final s in songs) {
          if (seen.add(s.id)) out.add(s);
        }
      }
      final result = out.take(15).toList();
      if (result.isNotEmpty) _toCache(_songCache, key, result);
      return result;
    } catch (e) {
      print('getYtTrendingSongs failed: $e');
      return [];
    }
  }

  /// YT Music songs-shelf search — real track rows from YouTube Music
  /// for editorial-style queries.
  Future<List<Song>> getYtmShelf(String query, {int limit = 12}) async {
    final key = 'shelf:$query:$limit';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;
    try {
      final result = await _ytm.searchSongs(query, limit: limit);
      if (result.isNotEmpty) _toCache(_songCache, key, result);
      return result;
    } catch (e) {
      print('getYtmShelf failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // CHART SHELF ROTATION (infinite home append)
  // Queries are BUILT at call time from rotating templates + the live
  // trending-artist pool. No fixed query list.
  // ═════════════════════════════════════════════

  static const _chartTemplates = [
    'top hits {decade}',
    'trending {region} songs',
    '{mood} hits',
    'best of {artist}',
    'top {region} hits this week',
    '{mood} playlist',
  ];

  static const _decades = ['2020s', '2010s', '2000s', '90s', '80s'];
  static const _regions = [
    'hindi', 'punjabi', 'tamil', 'telugu',
    'marathi', 'kannada', 'malayalam', 'bengali', 'bhojpuri',
  ];
  static const _moods = [
    'romantic', 'party', 'workout', 'chill', 'sad',
    'dance', 'lofi', 'feel good',
  ];

  int _chartCursor = 0;

  /// Next chart shelf — the query is composed at call time from live
  /// trending artists plus a rotating template.
  Future<List<Song>> getNextChartShelf() async {
    final artists = await _fetchTrendingArtists(max: 12);
    final q = _buildChartQuery(artists);
    _chartCursor++;
    return getYtmShelf(q, limit: 15);
  }

  String _buildChartQuery(List<String> artists) {
    final t = _chartTemplates[_chartCursor % _chartTemplates.length];
    if (t.contains('{artist}')) {
      final a = artists.isEmpty
          ? 'hits'
          : artists[_chartCursor % artists.length];
      return t.replaceAll('{artist}', a);
    }
    if (t.contains('{decade}')) {
      return t.replaceAll(
          '{decade}', _decades[_chartCursor % _decades.length]);
    }
    if (t.contains('{region}')) {
      return t.replaceAll(
          '{region}', _regions[_chartCursor % _regions.length]);
    }
    return t.replaceAll('{mood}', _moods[_chartCursor % _moods.length]);
  }

  // ═════════════════════════════════════════════
  // PERSONALIZED VIDEOS — seeded from listening history
  // ═════════════════════════════════════════════

  /// Related YouTube videos for the songs the user actually plays.
  /// Seeds = recently played (most recent first). Falls back to a
  /// generic trending-video search when there's no history yet.
  ///
  /// THUMBNAILS: hqdefault.jpg is 4:3 with the 16:9 frame letterboxed
  /// INSIDE the image — black bars baked into the pixels. maxresdefault
  /// is true 16:9 (bar-free), so it's used here.
  Future<List<Song>> getPersonalizedVideos(List<Song> seeds) async {
    if (seeds.isEmpty) return [];

    final out = <Song>[];
    final seen = <String>{};
    try {
      for (final seed in seeds.take(3)) {
        final related = await _ytService.getRelatedSongs(seed);
        for (final s in related) {
          if (seen.add(s.id)) out.add(s);
        }
        if (out.length >= 15) break;
      }
    } catch (e) {
      print('getPersonalizedVideos related failed: $e');
    }
    if (out.isNotEmpty) return out.take(15).toList();

    await _ensureExtractorInit();
    try {
      final page = await _extractor.search(
        'trending zen videos',
        filter: SearchFilter.musicVideos,
      );
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null || !seen.add(vid)) continue;
        out.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
        if (out.length >= 15) break;
      }
    } catch (e) {
      print('getPersonalizedVideos fallback failed: $e');
    }
    return out;
  }

  // ═════════════════════════════════════════════
  // SECTIONS — every shelf is a live catalog query
  // ═════════════════════════════════════════════

  Future<List<Song>> getTrendingNow() async {
    const key = 'trending_now';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;
    final r = await _dynamicPlaylist(
      queries: ['top 50 this week', 'top hits 2025', 'trending now'],
    );
    if (r.isNotEmpty) _toCache(_songCache, key, r);
    return r;
  }

  Future<List<Song>> getBiggestHits() async {
    const key = 'biggest_hits';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;
    final r = await _dynamicPlaylist(
      queries: ['biggest hits', 'top songs this week', 'chart toppers'],
    );
    if (r.isNotEmpty) _toCache(_songCache, key, r);
    return r;
  }

  Future<List<Song>> getTopCharts() async {
    const key = 'top_charts';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;
    final r = await _dynamicPlaylist(
      queries: ['billboard hot 100', 'top charts', 'music charts'],
    );
    if (r.isNotEmpty) _toCache(_songCache, key, r);
    return r;
  }

  Future<List<Song>> getStartListening() async {
    const key = 'start_listening';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;
    final r = await _dynamicPlaylist(
      queries: ['popular songs', 'most played songs', 'hits today'],
      max: 6,
    );
    if (r.isNotEmpty) _toCache(_songCache, key, r);
    return r;
  }

  Future<List<Song>> getRecommendedToday() async {
    const key = 'recommended_today';
    final hit = _fromCache(_songCache, key);
    if (hit != null) return hit;

    await _ensureExtractorInit();
    try {
      final page = await _extractor.search(
        'recommended zen today',
        filter: SearchFilter.musicVideos,
      );
      final songs = <Song>[];
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null) continue;
        songs.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
      }
      final result = songs.take(15).toList();
      if (result.isNotEmpty) _toCache(_songCache, key, result);
      return result;
    } catch (e) {
      print('getRecommendedToday failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // COLLECTION ROWS (cards)
  // ═════════════════════════════════════════════

  Future<List<Collection>> getHomeCollections() async {
    const key = 'home_collections';
    final hit = _fromCache(_collectionCache, key);
    if (hit != null) return hit;

    try {
      // Live searches — a removed / renamed playlist never leaves a
      // dead card on the home screen.
      final a = await _jiosaavn.searchPlaylists('trending playlists', limit: 8);
      final b = await _jiosaavn.searchPlaylists('popular playlists', limit: 8);
      final seen = <String>{};
      final result =
      [...a, ...b].where((c) => seen.add(c.id)).take(12).toList();
      if (result.isNotEmpty) _toCache(_collectionCache, key, result);
      return result;
    } catch (e) {
      print('getHomeCollections failed: $e');
      return [];
    }
  }

  Future<List<Collection>> getNewReleaseAlbums() async {
    const key = 'new_albums';
    final hit = _fromCache(_collectionCache, key);
    if (hit != null) return hit;

    try {
      // Year is computed at call time — never goes stale.
      final year = DateTime.now().year;
      final a =
      await _jiosaavn.searchAlbums('new hindi songs $year', limit: 8);
      final b =
      await _jiosaavn.searchAlbums('new punjabi songs $year', limit: 8);
      final seen = <String>{};
      final result =
      [...a, ...b].where((c) => seen.add(c.id)).take(12).toList();
      if (result.isNotEmpty) _toCache(_collectionCache, key, result);
      return result;
    } catch (e) {
      print('getNewReleaseAlbums failed: $e');
      return [];
    }
  }

  String? _extractVideoId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          (segments.contains('watch') ||
              segments.contains('embed') ||
              segments.contains('shorts'))) {
        return segments.last;
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    clearCache();
    _jiosaavn.dispose();
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.at);
  final T value;
  final DateTime at;
}