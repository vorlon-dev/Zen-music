import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fw;
import 'lyrics_model.dart';

/// LRCLIB (lrclib.net) lyrics client.
class LrcNetService {
  LrcNetService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _baseUrl = 'https://lrclib.net';

  Future<Lyrics?> getLyrics({
    required String title,
    String? artist,
    String? album,
    String? duration,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/get').replace(
        queryParameters: {
          'track_name': title,
          if (artist != null && artist.isNotEmpty) 'artist_name': artist,
          if (album != null && album.isNotEmpty) 'album_name': album,
          if (duration != null && duration.isNotEmpty) 'duration': duration,
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return Lyrics(
          id: data['id']?.toString() ?? '',
          artist: data['artistName'] ?? artist ?? '',
          title: data['trackName'] ?? title,
          lyricsPlain: data['plainLyrics'] ?? '',
          lyricsSynced: data['syncedLyrics'],
          album: data['albumName'] ?? album,
          duration: data['duration']?.toString() ?? duration,
          provider: LyricsProvider.lrcnet,
        );
      }
    } catch (_) {}

    // Fallback: search query
    return await searchSingle(title: title, artist: artist, album: album);
  }

  Future<Lyrics?> searchSingle({
    required String title,
    String? artist,
    String? album,
  }) async {
    try {
      final q = [title, if (artist != null) artist, if (album != null) album].join(' ');
      final uri = Uri.parse('$_baseUrl/api/search').replace(
        queryParameters: {
          'q': q,
          'track_name': title,
          if (artist != null) 'artist_name': artist,
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final list = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>? ?? [];
      if (list.isEmpty) return null;

      final candidates = list.map((item) {
        final data = item as Map<String, dynamic>;
        return Lyrics(
          id: data['id']?.toString() ?? '',
          artist: data['artistName'] ?? '',
          title: data['trackName'] ?? '',
          lyricsPlain: data['plainLyrics'] ?? '',
          lyricsSynced: data['syncedLyrics'],
          album: data['albumName'],
          duration: data['duration']?.toString(),
          provider: LyricsProvider.lrcnet,
        );
      }).toList();

      final syncedList = candidates.where((c) => c.lyricsSynced != null).toList();
      if (syncedList.isNotEmpty) {
        final match = fw.extractOne(
          query: '$title $artist',
          choices: syncedList.map((e) => '${e.title} ${e.artist} ${e.album ?? ''}').toList(),
        );
        return syncedList[match.index];
      }

      final match = fw.extractOne(
        query: '$title $artist',
        choices: candidates.map((e) => '${e.title} ${e.artist} ${e.album ?? ''}').toList(),
      );
      return candidates[match.index];
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
