import 'dart:async';
import 'package:yt_extractor/yt_extractor.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;
import '../models/song.dart';
import 'jiosaavn_service.dart';

class YoutubeService {
  static bool videoEnabled = true;

  final _extractor = YtExtractor();
  final _yt = yt_explode.YoutubeExplode();
  final _jiosaavn = JiosaavnService();

  bool _extractorInitialized = false;

  DateTime? _lastRequestTime;
  static const _minRequestInterval = Duration(milliseconds: 1200);

  Future<void> _throttle() async {
    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (elapsed < _minRequestInterval) {
        await Future.delayed(_minRequestInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  Future<void> _ensureExtractorInit() async {
    if (_extractorInitialized) return;
    await _extractor.init();
    _extractorInitialized = true;
  }

  // ═════════════════════════════════════════════
  // SEARCH
  // ═════════════════════════════════════════════

  Future<List<Song>> search(
      String query, {
        SearchFilter filter = SearchFilter.musicSongs,
      }) async {
    await _throttle();

    if (filter == SearchFilter.videos) {
      return await _youtubeVideoSearch(query);
    }

    final combined = <Song>[];

    final jsResults = await _jiosaavn.search(query, limit: 15);
    combined.addAll(jsResults);
    print('🎧 JioSaavn: ${jsResults.length} songs');

    try {
      await _ensureExtractorInit();
      final page =
      await _extractor.search(query, filter: SearchFilter.musicSongs);
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid == null) continue;
        combined.add(Song(
          id: vid,
          title: item.name,
          artist: item.uploaderName ?? 'Unknown',
          thumbnail: 'https://i.ytimg.com/vi/$vid/maxresdefault.jpg',
          duration: Duration(seconds: item.duration ?? 0),
        ));
      }
      print('🎵 YouTube Music: added ${combined.length - jsResults.length}');
    } catch (e) {
      print('YouTube Music search failed: $e');
    }

    return _deduplicateByTitle(combined);
  }

  /// Videos tab — uses youtube_explode_dart directly (more reliable than yt_extractor for video search).
  Future<List<Song>> _youtubeVideoSearch(String query) async {
    try {
      final results = await _yt.search.search(query);
      final songs = <Song>[];
      for (final v in results) {
        songs.add(Song(
          id: v.id.value,
          title: v.title,
          artist: v.author,
          thumbnail: 'https://i.ytimg.com/vi/${v.id.value}/maxresdefault.jpg',
          duration: v.duration ?? Duration.zero,
        ));
      }
      print('📹 YouTube videos: ${songs.length}');
      return _deduplicateByTitle(songs);
    } catch (e) {
      print('YouTube video search failed: $e');
      return [];
    }
  }

  List<Song> _deduplicateByTitle(List<Song> songs) {
    final seen = <String>{};
    final result = <Song>[];
    for (final s in songs) {
      final key = _normalizeTitle(s.title);
      if (key.isEmpty) continue;
      if (seen.contains(key)) continue;
      seen.add(key);
      result.add(s);
    }
    return result;
  }

  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\s*-\s*topic.*$'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ═════════════════════════════════════════════
  // AUDIO STREAM URL
  // ═════════════════════════════════════════════

  Future<String> getAudioStreamUrl(Song song) async {
    await _throttle();

    if (song.isFromJiosaavn) {
      if (song.hasHighQuality) return song.jiosaavnStreamUrl!;
      final url = await _jiosaavn.fetchStreamUrl(song.jiosaavnId!);
      if (url != null && url.isNotEmpty) return url;
    }

    try {
      await _ensureExtractorInit();
      final info = await _extractor.getStreamInfo(
        'https://www.youtube.com/watch?v=${song.id}',
      );
      final audio = info.bestAudioStream;
      if (audio != null && audio.url.isNotEmpty) return audio.url;
    } catch (e) {
      print('yt_extractor failed: $e');
    }

    try {
      final manifest = await _yt.videos.streams.getManifest(
        song.id,
        ytClients: [yt_explode.YoutubeApiClient.androidVr],
      );
      return manifest.audioOnly.withHighestBitrate().url.toString();
    } catch (e) {
      print('youtube_explode_dart failed: $e');
    }

    throw Exception('All audio extractors failed for ${song.title}');
  }

  // ═════════════════════════════════════════════
  // VIDEO — returns just the YouTube ID for the iframe embed
  // ═════════════════════════════════════════════

  /// Returns the YouTube video ID to load in the WebView embed.
  /// For JioSaavn songs, searches YouTube Music Videos by title.
  Future<String?> getVideoId(Song song) async {
    if (!videoEnabled) return null;
    await _throttle();

    if (!song.isFromJiosaavn) return song.id;

    try {
      await _ensureExtractorInit();
      final query = '${song.title} ${song.artist}';
      final page = await _extractor.search(
        query,
        filter: SearchFilter.musicVideos,
      );
      for (final item in page.items) {
        final vid = _extractVideoId(item.url);
        if (vid != null) {
          print('🎬 Resolved to YouTube ID: $vid');
          return vid;
        }
      }
    } catch (e) {
      print('getVideoId failed: $e');
    }
    return null;
  }

  // ═════════════════════════════════════════════
  // RELATED SONGS
  // ═════════════════════════════════════════════

  Future<List<Song>> getRelatedSongs(Song seedSong) async {
    await _throttle();

    String? youtubeId;

    if (seedSong.isFromJiosaavn) {
      try {
        await _ensureExtractorInit();
        final query = '${seedSong.title} ${seedSong.artist}';
        final page =
        await _extractor.search(query, filter: SearchFilter.musicSongs);
        for (final item in page.items) {
          final vid = _extractVideoId(item.url);
          if (vid != null) {
            youtubeId = vid;
            break;
          }
        }
      } catch (e) {
        print('Seed resolution failed: $e');
      }
    } else {
      youtubeId = seedSong.id;
    }

    if (youtubeId == null) return [];

    try {
      await _ensureExtractorInit();
      final related = await _extractor.getRelatedStreams(
        'https://www.youtube.com/watch?v=$youtubeId',
      );
      final songs = <Song>[];
      for (final item in related) {
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
      return songs;
    } catch (e) {
      print('getRelatedSongs failed: $e');
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
    _yt.close();
    _jiosaavn.dispose();
  }
}