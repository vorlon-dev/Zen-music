import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsResult {
  final String? plainLyrics;
  final String? syncedLyrics;
  final bool found;

  const LyricsResult({
    this.plainLyrics,
    this.syncedLyrics,
    this.found = false,
  });

  static const empty = LyricsResult(found: false);
}

class LyricsService {
  static const _userAgent = 'ZenMusic v1.0.0 (https://github.com/zenmusic)';

  Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    try {
      final cleanTitle = _cleanTitle(title);
      final cleanArtist = _cleanArtist(artist);

      final params = <String, String>{
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      };
      if (duration != null && duration.inSeconds > 0) {
        params['duration'] = duration.inSeconds.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', params);

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final plain = data['plainLyrics'] as String?;
        final synced = data['syncedLyrics'] as String?;

        if ((synced != null && synced.trim().isNotEmpty) ||
            (plain != null && plain.trim().isNotEmpty)) {
          return LyricsResult(
            plainLyrics: plain?.trim(),
            syncedLyrics: synced?.trim(),
            found: true,
          );
        }
      }

      return await _searchFallback(cleanTitle, cleanArtist);
    } catch (e) {
      print('LyricsService LRCLIB error: $e');
      return LyricsResult.empty;
    }
  }

  Future<LyricsResult> _searchFallback(String title, String artist) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {
        'track_name': title,
        'artist_name': artist,
      });

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        if (list.isNotEmpty) {
          Map<String, dynamic>? best;
          for (final item in list) {
            final map = item as Map<String, dynamic>;
            if (map['syncedLyrics'] != null &&
                (map['syncedLyrics'] as String).trim().isNotEmpty) {
              best = map;
              break;
            }
          }
          best ??= list.first as Map<String, dynamic>;

          final plain = best['plainLyrics'] as String?;
          final synced = best['syncedLyrics'] as String?;

          if ((synced != null && synced.trim().isNotEmpty) ||
              (plain != null && plain.trim().isNotEmpty)) {
            return LyricsResult(
              plainLyrics: plain?.trim(),
              syncedLyrics: synced?.trim(),
              found: true,
            );
          }
        }
      }
    } catch (e) {
      print('LyricsService search fallback error: $e');
    }
    return LyricsResult.empty;
  }

  String _cleanTitle(String raw) {
    var t = raw;
    final patterns = [
      RegExp(
          r'\s*[\(\[]\s*(official|lyric|audio|video|hd|4k|mv|music video)[^\)\]]*[\)\]]',
          caseSensitive: false),
      RegExp(
          r'\s*[\(\[]\s*(remix|extended|edit|version)[^\)\]]*[\)\]]',
          caseSensitive: false),
      RegExp(r'\s*-\s*topic$', caseSensitive: false),
    ];
    for (final p in patterns) {
      t = t.replaceAll(p, '');
    }
    return t.trim();
  }

  String _cleanArtist(String raw) {
    var a = raw;
    a = a.replaceAll(RegExp(r'\s*-\s*topic$', caseSensitive: false), '');
    a = a.replaceAll(RegExp(r'\s*vevo$', caseSensitive: false), '');
    return a.trim();
  }
}