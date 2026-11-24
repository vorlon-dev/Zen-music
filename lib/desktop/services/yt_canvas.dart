// ZenMusic · vorlon-dev
//
// YouTube canvas: when Spotify has no canvas for a song (or the user is not
// signed in to Spotify), the song's own YouTube / YouTube Music VIDEO plays
// behind the player as a muted 20-second loop, in up to 1080p.

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class YtCanvasResult {
  const YtCanvasResult({
    required this.url,
    required this.headers,
    required this.clipStart,
    required this.videoId,
  });
  final String url;
  final Map<String, String> headers;
  final Duration clipStart;
  final String videoId;
}

class YtCanvas {
  YtCanvas._();
  static final YtCanvas instance = YtCanvas._();

  /// Length of the looping window.
  static const clipLength = Duration(seconds: 20);

  /// Highest quality asked for. The resolver picks the closest height at or
  /// below this, so 1080 means "1080p when the video has it".
  static const maxHeight = 1080;

  // songId -> videoId of the music video ('' = none found)
  final Map<String, String> _videoIds = {};
  // songId -> duration of that video, when the search told us
  final Map<String, Duration?> _durations = {};

  Future<YtCanvasResult?> resolve(MediaItem song) async {
    try {
      var videoId = _videoIds[song.id];
      if (videoId == null) {
        videoId = await _findVideoId(song) ?? '';
        _videoIds[song.id] = videoId;
        if (_videoIds.length > 200) _videoIds.remove(_videoIds.keys.first);
      }
      if (videoId.isEmpty) return null;

      final streams =
          await InnertubexBridge.extractVideo(videoId, maxHeight: maxHeight);
      final url = streams?.videoUrl;
      if (streams == null || url == null || url.isEmpty) return null;

      final total = _durations[song.id] ?? song.duration;
      return YtCanvasResult(
        url: url,
        headers: streams.headers,
        clipStart: _clipStartFor(total),
        videoId: videoId,
      );
    } catch (e) {
      debugPrint('[yt-canvas] ${song.title}: $e');
      return null;
    }
  }

  /// A window that skips the intro and stays clear of the outro; the middle
  /// of a music video is almost always the busiest part.
  static Duration _clipStartFor(Duration? total) {
    if (total == null || total.inSeconds < 60) {
      return const Duration(seconds: 20);
    }
    final target = (total.inMilliseconds * 0.3).round();
    final latest = total.inMilliseconds - (clipLength.inMilliseconds + 5000);
    final ms = target.clamp(15000, latest < 15000 ? 15000 : latest);
    return Duration(milliseconds: ms);
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\u0080-￿ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Duration? _parseDuration(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.contains(null)) return null;
    var s = 0;
    for (final p in parts) {
      s = s * 60 + p!;
    }
    return s > 0 ? Duration(seconds: s) : null;
  }

  /// The best VIDEO for the song: an official music video if one exists,
  /// otherwise the first video whose title carries the song's title. The
  /// song's own id is the last resort (it is a video too, just often a
  /// static-art one).
  Future<String?> _findVideoId(MediaItem song) async {
    final title = _norm(song.title);
    final artist =
        (song.artist ?? song.album ?? song.extras?['subtitle'] ?? '')
            .toString();
    if (title.isEmpty) return song.id.length == 11 ? song.id : null;

    try {
      final result = await GetIt.I<YTMusic>()
          .search('${song.title} $artist'.trim(), filter: 'videos');
      final sections = result['sections'] as List?;
      final contents = (sections != null && sections.isNotEmpty)
          ? sections[0]['contents'] as List?
          : null;
      String? best;
      Duration? bestDuration;
      var bestScore = -1;
      for (final raw in (contents ?? const []).take(8)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['videoId'] as String?;
        if (id == null || id.length != 11) continue;
        final t = _norm('${m['title'] ?? ''}');
        var score = 0;
        if (t.contains(title)) score += 4;
        if (artist.isNotEmpty && t.contains(_norm(artist))) score += 1;
        final full = '${m['title'] ?? ''}'.toLowerCase();
        if (full.contains('official')) score += 2;
        if (full.contains('video')) score += 1;
        if (full.contains('lyric') ||
            full.contains('audio') ||
            full.contains('visualizer') ||
            full.contains('reaction') ||
            full.contains('cover') ||
            full.contains('live')) {
          score -= 3;
        }
        if (score > bestScore) {
          bestScore = score;
          best = id;
          bestDuration = _parseDuration(m['duration']);
        }
      }
      // Require at least the title match; a loose guess would show some
      // other song's video.
      if (best != null && bestScore >= 4) {
        _durations[song.id] = bestDuration;
        return best;
      }
    } catch (e) {
      debugPrint('[yt-canvas] video search failed: $e');
    }
    return song.id.length == 11 ? song.id : null;
  }
}
