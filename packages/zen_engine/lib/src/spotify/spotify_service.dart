import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song_model.dart';

/// Headless Spotify search and metadata helper.
class SpotifyService {
  SpotifyService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _anonToken;
  DateTime? _tokenExpiry;

  /// Retrieve an anonymous token from Spotify Open API
  Future<String?> getAnonymousToken() async {
    if (_anonToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _anonToken;
    }
    try {
      final res = await _client.get(Uri.parse('https://open.spotify.com/get_access_token?reason=transport&productType=web_player'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _anonToken = data['accessToken'];
        final expMs = data['accessTokenExpirationTimestampMs'] as num?;
        if (expMs != null) {
          _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expMs.toInt());
        }
        return _anonToken;
      }
    } catch (_) {}
    return null;
  }

  /// Search tracks on Spotify and map to ZenSong models
  Future<List<ZenSong>> search(String query, {int limit = 15}) async {
    try {
      final token = await getAnonymousToken();
      if (token == null) return [];

      final uri = Uri.parse('https://api.spotify.com/v1/search').replace(
        queryParameters: {
          'q': query,
          'type': 'track',
          'limit': limit.toString(),
        },
      );

      final res = await _client.get(uri, headers: {
        'Authorization': 'Bearer $token',
      });

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);
      final items = data['tracks']?['items'] as List<dynamic>? ?? [];

      return items.map((item) {
        final id = item['id'] as String? ?? '';
        final title = item['name'] as String? ?? '';
        final artistsList = item['artists'] as List<dynamic>? ?? [];
        final artist = artistsList.map((a) => a['name']).join(', ');
        final album = item['album']?['name'] as String?;
        final images = item['album']?['images'] as List<dynamic>? ?? [];
        final thumb = images.isNotEmpty ? images.first['url'] as String? : null;
        final durMs = item['duration_ms'] as num? ?? 0;

        return ZenSong(
          id: id,
          title: title,
          artist: artist,
          album: album,
          duration: Duration(milliseconds: durMs.toInt()),
          thumbnailUrl: thumb,
          source: ZenSongSource.spotify,
          raw: {
            'spotifyUri': 'spotify:track:$id',
            'id': id,
            'title': title,
            'artist': artist,
            'album': {'name': album},
            'thumbnails': [{'url': thumb}],
          },
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _client.close();
  }
}
