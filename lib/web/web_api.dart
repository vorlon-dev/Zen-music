// ZenMusic · vorlon-dev
//
// Network client for the web player. Requests go to the same origin
// (`/api/...`), where the Cloudflare Pages Function in `functions/api`
// forwards them, so the browser never needs CORS access to a third party.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zenmusic/web/web_models.dart';

class WebApi {
  WebApi({http.Client? client, String? apiBase, String? lyricsBase})
      : _client = client ?? http.Client(),
        _api = apiBase ?? _defaultApi,
        _lyrics = lyricsBase ?? 'https://lrclib.net/api';

  /// Override with `--dart-define=API_BASE=https://...` for local runs.
  static const String _defaultApi =
      String.fromEnvironment('API_BASE', defaultValue: '/api');

  final http.Client _client;
  final String _api;
  final String _lyrics;

  Future<List<WebSong>> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse('$_api/search/songs').replace(queryParameters: {
      'query': q,
      'limit': '$limit',
      'page': '0',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('Search failed (${res.statusCode})', uri);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    Object? results;
    if (data is Map && data['data'] is Map) {
      results = (data['data'] as Map)['results'];
    }
    return [
      if (results is List)
        for (final item in results)
          if (item is Map<String, dynamic>) WebSong.fromJson(item),
    ].where((s) => s.id.isNotEmpty && s.playable).toList();
  }

  /// Synced lyrics from LRCLIB (it allows browser requests). Empty if none.
  Future<List<LyricLine>> lyrics(WebSong song) async {
    try {
      final uri = Uri.parse('$_lyrics/get').replace(queryParameters: {
        'track_name': song.title,
        'artist_name': song.artist.split(',').first.trim(),
        if (song.album.isNotEmpty) 'album_name': song.album,
        if (song.duration.inSeconds > 0)
          'duration': '${song.duration.inSeconds}',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final synced = data is Map ? data['syncedLyrics'] : null;
      if (synced is String && synced.isNotEmpty) return parseLrc(synced);
      return const [];
    } catch (_) {
      return const [];
    }
  }

  void close() => _client.close();
}
