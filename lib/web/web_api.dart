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

  /// Base of the YouTube Music search proxy (`functions/yt/search.js`).
  static const String _ytBase =
      String.fromEnvironment('YT_BASE', defaultValue: '/yt');

  final http.Client _client;
  final String _api;
  final String _lyrics;

  Future<Object?> _getJson(String path, Map<String, String> query) async {
    final uri = Uri.parse('$_api$path').replace(queryParameters: query);
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('Request failed (${res.statusCode})', uri);
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  static Object? _data(Object? json) {
    if (json is Map) return json['data'];
    return null;
  }

  static List<Object?> _results(Object? json) {
    final data = _data(json);
    if (data is Map) {
      final r = data['results'];
      if (r is List) return r;
    }
    return const [];
  }

  static List<WebSong> _songs(Object? list) {
    final out = <WebSong>[];
    if (list is List) {
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final s = WebSong.fromJson(item);
          if (s.id.isNotEmpty && s.playable) out.add(s);
        }
      }
    }
    return out;
  }

  /// Songs from YouTube Music, via the same-origin proxy.
  Future<List<WebSong>> searchYtm(String query) => _searchYt(query, false);

  /// Plain YouTube videos (played as audio), via the same-origin proxy.
  Future<List<WebSong>> searchYoutube(String query) => _searchYt(query, true);

  Future<List<WebSong>> _searchYt(String query, bool video) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final uri = Uri.parse('$_ytBase/search').replace(queryParameters: {
      'q': q,
      if (video) 'type': 'video',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw http.ClientException('YouTube Music search failed', uri);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final out = <WebSong>[];
    if (data is Map && data['results'] is List) {
      for (final item in data['results'] as List) {
        final s = WebSong.fromYtJson(item);
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  Future<List<WebSong>> search(String query, {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _getJson(
      '/search/songs',
      {'query': q, 'limit': '$limit', 'page': '0'},
    );
    return _songs(_results(json));
  }

  Future<List<WebCollection>> searchCollections(
    String query, {
    required bool albums,
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _getJson(
      albums ? '/search/albums' : '/search/playlists',
      {'query': q, 'limit': '$limit', 'page': '0'},
    );
    final out = <WebCollection>[];
    for (final item in _results(json)) {
      if (item is Map<String, dynamic>) {
        final c = WebCollection.fromJson(item, isAlbum: albums);
        if (c.id.isNotEmpty) out.add(c);
      }
    }
    return out;
  }

  Future<WebDetail?> collection(WebCollection c) async {
    final json = await _getJson(
      c.isAlbum ? '/albums' : '/playlists',
      {'id': c.id, 'limit': '100'},
    );
    final data = _data(json);
    if (data is! Map<String, dynamic>) return null;
    final full = WebCollection.fromJson(data, isAlbum: c.isAlbum);
    return WebDetail(
      WebCollection(
        id: c.id,
        title: full.title.isEmpty ? c.title : full.title,
        subtitle: full.subtitle.isEmpty ? c.subtitle : full.subtitle,
        image: full.image.isEmpty ? c.image : full.image,
        isAlbum: c.isAlbum,
      ),
      _songs(data['songs']),
    );
  }

  /// Fetches a song again, to get a fresh stream link.
  Future<WebSong?> song(String id) async {
    try {
      final json = await _getJson('/songs/$id', {});
      final list = _songs(_data(json));
      return list.isEmpty ? null : list.first;
    } catch (_) {
      return null;
    }
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
