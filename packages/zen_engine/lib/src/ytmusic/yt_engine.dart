import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';

/// YouTube Music extractor engine powered by youtube_explode_dart.
class YouTubeEngine {
  YouTubeEngine({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  final YoutubeExplode _yt;

  /// Search YouTube songs / videos
  Future<List<ZenSong>> search(String query, {int limit = 20}) async {
    try {
      final searchResults = await _yt.search.search(query);
      final songs = <ZenSong>[];

      for (final video in searchResults) {
        if (songs.length >= limit) break;
        songs.add(ZenSong(
          id: video.id.value,
          title: video.title,
          artist: video.author,
          duration: video.duration ?? Duration.zero,
          thumbnailUrl: video.thumbnails.highResUrl,
          source: ZenSongSource.youtube,
          raw: {
            'videoId': video.id.value,
            'title': video.title,
            'artist': video.author,
            'duration': video.duration?.inSeconds,
            'thumbnails': [{'url': video.thumbnails.highResUrl}],
          },
        ));
      }
      return songs;
    } catch (_) {
      return [];
    }
  }

  /// Get direct audio stream URL (highest bitrate audio only stream)
  Future<String?> getAudioStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioOnlyStreams = manifest.audioOnly.sortByBitrate();
      if (audioOnlyStreams.isNotEmpty) {
        return audioOnlyStreams.last.url.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Get video details
  Future<ZenSong?> getVideoDetails(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      return ZenSong(
        id: video.id.value,
        title: video.title,
        artist: video.author,
        duration: video.duration ?? Duration.zero,
        thumbnailUrl: video.thumbnails.highResUrl,
        source: ZenSongSource.youtube,
        raw: {
          'videoId': video.id.value,
          'title': video.title,
          'artist': video.author,
          'duration': video.duration?.inSeconds,
          'thumbnails': [{'url': video.thumbnails.highResUrl}],
        },
      );
    } catch (_) {
      return null;
    }
  }

  /// Get related / next songs
  Future<List<ZenSong>> getRelatedSongs(String videoId) async {
    try {
      final video = await _yt.videos.get(videoId);
      final related = await _yt.videos.getRelatedVideos(video);
      if (related == null) return [];

      return related.map((v) => ZenSong(
        id: v.id.value,
        title: v.title,
        artist: v.author,
        duration: v.duration ?? Duration.zero,
        thumbnailUrl: v.thumbnails.highResUrl,
        source: ZenSongSource.youtube,
        raw: {
          'videoId': v.id.value,
          'title': v.title,
          'artist': v.author,
          'duration': v.duration?.inSeconds,
          'thumbnails': [{'url': v.thumbnails.highResUrl}],
        },
      )).toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _yt.close();
  }
}
