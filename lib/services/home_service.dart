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
  // PINNED EDITORIAL PLAYLISTS
  // ═════════════════════════════════════════════

  static const _plTop50 = '1134543272';
  static const _plDumdaar = '49';
  static const _plMostSearched = '946682072';
  static const _plLoveHindi = '1139074020';

  Future<List<Song>> _pinnedPlaylist({
    required String id,
    required String fallbackQuery,
    int max = 20,
  }) async {
    try {
      final detail = await _jiosaavn.getPlaylist(id);
      final songs = detail?.songs ?? [];
      if (songs.isNotEmpty) return songs.take(max).toList();
    } catch (e) {
      print('pinned playlist $id failed: $e');
    }
    return _jiosaavn.search(fallbackQuery, limit: 15);
  }

  // ═════════════════════════════════════════════
  // YT MUSIC — artist top songs (real YouTube ranking)
  // ═════════════════════════════════════════════

  static const _ytArtists = [
    'Arijit Singh',
    'Shreya Ghoshal',
    'Pritam',
    'Ed Sheeran',
    'A.R. Rahman',
    'Dua Lipa',
    'Anirudh Ravichander',
    'The Weeknd',
  ];

  Future<List<Song>> getYtTrendingSongs() async {
    try {
      final day = DateTime.now().weekday;
      final picks = [
        _ytArtists[day % _ytArtists.length],
        _ytArtists[(day + 3) % _ytArtists.length],
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
      return out.take(15).toList();
    } catch (e) {
      print('getYtTrendingSongs failed: $e');
      return [];
    }
  }

  /// YT Music songs-shelf search — real track rows from YouTube Music
  /// for editorial-style queries ("top hits", "new music"...).
  Future<List<Song>> getYtmShelf(String query, {int limit = 12}) async {
    try {
      return await _ytm.searchSongs(query, limit: limit);
    } catch (e) {
      print('getYtmShelf failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // CHART SHELF ROTATION (infinite home append)
  // ═════════════════════════════════════════════

  /// Chart-query pool for infinite home append. Ordered so adjacent
  /// rounds feel varied (decade → mood → genre → region rotation).
  static const chartQueries = [
    'top hits 2010s',
    'romantic hits',
    'punjabi hits',
    'top hits 2000s',
    'party hits',
    'tamil hits',
    'top hits 2020s',
    'workout hits',
    'telugu hits',
    'top hits 90s',
    'chill hits',
    'marathi hits',
    'top hits 80s',
    'sad songs',
    'bhojpuri hits',
    'top hits this month',
    'dance hits',
    'kannada hits',
    'top hits 2010s bollywood',
    'lofi hits',
    'malayalam hits',
    'top hits 2000s bollywood',
    'feel good hits',
    'bengali hits',
  ];

  int _chartCursor = 0;

  /// Next chart shelf from the rotation pool. Cycles forever; callers
  /// dedupe against already-shown content.
  Future<List<Song>> getNextChartShelf() {
    final q = chartQueries[_chartCursor % chartQueries.length];
    _chartCursor++;
    return getYtmShelf(q, limit: 15);
  }

  // ═════════════════════════════════════════════
  // PERSONALIZED VIDEOS — seeded from listening history
  // ═════════════════════════════════════════════

  /// Related YouTube videos for the songs the user actually plays.
  /// Seeds = recently played (most recent first). Falls back to a
  /// generic trending-video search when there's no history yet.
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
        'trending music videos',
        filter: SearchFilter.musicVideos,
      );
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null || !seen.add(vid)) continue;
        out.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
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
  // SECTIONS
  // ═════════════════════════════════════════════

  Future<List<Song>> getTrendingNow() => _pinnedPlaylist(
    id: _plTop50,
    fallbackQuery: 'top hits 2025',
  );

  Future<List<Song>> getBiggestHits() => _pinnedPlaylist(
    id: _plDumdaar,
    fallbackQuery: 'top songs this week',
  );

  Future<List<Song>> getTopCharts() => _pinnedPlaylist(
    id: _plMostSearched,
    fallbackQuery: 'billboard hot 100',
  );

  Future<List<Song>> getStartListening() => _pinnedPlaylist(
    id: _plLoveHindi,
    fallbackQuery: 'popular songs',
    max: 6,
  );

  Future<List<Song>> getRecommendedToday() async {
    await _ensureExtractorInit();
    try {
      final page = await _extractor.search(
        'recommended music today',
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
      return songs.take(15).toList();
    } catch (e) {
      print('getRecommendedToday failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // COLLECTION ROWS (cards)
  // ═════════════════════════════════════════════

  Future<List<Collection>> getHomeCollections() async {
    try {
      final a = await _jiosaavn.searchPlaylists('superhit hits', limit: 8);
      final b = await _jiosaavn.searchPlaylists('love songs', limit: 8);
      final seen = <String>{};
      return [...a, ...b].where((c) => seen.add(c.id)).take(12).toList();
    } catch (e) {
      print('getHomeCollections failed: $e');
      return [];
    }
  }

  Future<List<Collection>> getNewReleaseAlbums() async {
    try {
      final a =
      await _jiosaavn.searchAlbums('new hindi songs 2025', limit: 8);
      final b =
      await _jiosaavn.searchAlbums('new punjabi songs 2025', limit: 8);
      final seen = <String>{};
      return [...a, ...b].where((c) => seen.add(c.id)).take(12).toList();
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
    _jiosaavn.dispose();
  }
}