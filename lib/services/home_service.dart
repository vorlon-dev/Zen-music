import 'package:yt_extractor/yt_extractor.dart';
import '../models/song.dart';
import 'jiosaavn_service.dart';

class HomeService {
  final _extractor = YtExtractor();
  final _jiosaavn = JiosaavnService();

  bool _extractorInitialized = false;

  Future<void> _ensureExtractorInit() async {
    if (_extractorInitialized) return;
    await _extractor.init();
    _extractorInitialized = true;
  }

  // ═════════════════════════════════════════════
  // SECTION 1: Trending Now (JioSaavn)
  // ═════════════════════════════════════════════
  Future<List<Song>> getTrendingNow() async {
    try {
      return await _jiosaavn.search('top hits 2024', limit: 15);
    } catch (e) {
      print('getTrendingNow failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // SECTION 2: Today's Biggest Hits (YouTube Music)
  // ═════════════════════════════════════════════
  Future<List<Song>> getBiggestHits() async {
    await _ensureExtractorInit();
    try {
      final page = await _extractor.search(
        'top songs this week',
        filter: SearchFilter.musicSongs,
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
      print('getBiggestHits failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // SECTION 3: New Releases (JioSaavn)
  // ═════════════════════════════════════════════
  Future<List<Song>> getNewReleases() async {
    try {
      return await _jiosaavn.search('new songs 2024', limit: 15);
    } catch (e) {
      print('getNewReleases failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // SECTION 4: Recommended for Today (YouTube Trending)
  // ═════════════════════════════════════════════
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
  // SECTION 5: Top Charts (JioSaavn)
  // ═════════════════════════════════════════════
  Future<List<Song>> getTopCharts() async {
    try {
      return await _jiosaavn.search('billboard hot 100', limit: 15);
    } catch (e) {
      print('getTopCharts failed: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // SECTION 6: Start Listening (Mixed vertical list)
  // ═════════════════════════════════════════════
  Future<List<Song>> getStartListening() async {
    try {
      final results = await _jiosaavn.search('popular songs', limit: 6);
      return results;
    } catch (e) {
      print('getStartListening failed: $e');
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