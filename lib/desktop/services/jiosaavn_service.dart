// ZenMusic Desktop — ported from the retired mobile stack's
// jiosaavn_service.dart. ZenMusic remains GPL-3.0.
// PORT: Song/Collection models -> desktop song maps (videoId = JioSaavn id,
// jiosaavnStreamUrl carries the 320kbps URL — the player's JioSaavn branch
// plays it directly). Playlists/albums emit maps for a future browse round.

import 'dart:convert';
import 'package:http/http.dart' as http;

class JioSaavnService {
  JioSaavnService._();
  static final JioSaavnService instance = JioSaavnService._();

  static const _baseUrl = 'https://jiosaavn-api.vorlon-revora.workers.dev';
  final _client = http.Client();

  // ── SONG SEARCH ──

  Future<List<Map<String, dynamic>>> search(String query,
      {int limit = 15}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/songs').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final songs = <Map<String, dynamic>>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        songs.add(_songFromSaavnJson(item));
      }
      return _filterRelevant(songs, query);
    } catch (_) {
      return [];
    }
  }

  Future<String?> fetchStreamUrl(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/songs/$songId');
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final list = data['data'] as List<dynamic>? ?? [];
      if (list.isEmpty) return null;

      final dl = (list.first as Map<String, dynamic>)['downloadUrl']
      as List<dynamic>? ??
          [];
      for (final d in dl) {
        final m = d as Map<String, dynamic>;
        if (m['quality'] == '320kbps') return m['url'] as String?;
      }
      return dl.isNotEmpty
          ? (dl.last as Map<String, dynamic>)['url'] as String?
          : null;
    } catch (_) {
      return null;
    }
  }

  // ── PLAYLISTS ──

  Future<List<Map<String, dynamic>>> searchPlaylists(String query,
      {int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/playlists').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final playlists = <Map<String, dynamic>>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        playlists.add(_collectionFromJson(item, isAlbum: false));
      }
      return playlists;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getPlaylist(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/playlists?id=$id&limit=100');
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) return null;

      return {
        'collection': _collectionFromJson(payload, isAlbum: false),
        'songs': [
          for (final item in payload['songs'] as List<dynamic>? ?? [])
            if (item is Map<String, dynamic>) _songFromSaavnJson(item),
        ],
      };
    } catch (_) {
      return null;
    }
  }

  // ── ALBUMS ──

  Future<List<Map<String, dynamic>>> searchAlbums(String query,
      {int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/albums').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final albums = <Map<String, dynamic>>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        albums.add(_collectionFromJson(item, isAlbum: true));
      }
      return albums;
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getAlbum(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/albums?id=$id&limit=100');
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) return null;

      return {
        'collection': _collectionFromJson(payload, isAlbum: true),
        'songs': [
          for (final item in payload['songs'] as List<dynamic>? ?? [])
            if (item is Map<String, dynamic>) _songFromSaavnJson(item),
        ],
      };
    } catch (_) {
      return null;
    }
  }

  // ── PARSERS ──

  /// Desktop-shape song map. videoId carries the JioSaavn id (opaque queue
  /// key for the whole UI); jiosaavnStreamUrl routes the player's
  /// JioSaavn branch. Thumbnails normalized to the list shape so
  /// SongThumbnail/SquareArtwork work unchanged.
  Map<String, dynamic> _songFromSaavnJson(Map<String, dynamic> map) {
    String thumb = '';
    final imageList = map['image'] as List<dynamic>? ?? [];
    for (final img in imageList) {
      final m = img as Map<String, dynamic>;
      if (m['quality'] == '500x500') {
        thumb = m['url'] as String? ?? '';
        break;
      }
    }
    if (thumb.isEmpty && imageList.isNotEmpty) {
      thumb = (imageList.last as Map<String, dynamic>)['url'] as String? ?? '';
    }

    String? stream320;
    final downloadUrls = map['downloadUrl'] as List<dynamic>? ?? [];
    for (final dl in downloadUrls) {
      final m = dl as Map<String, dynamic>;
      if (m['quality'] == '320kbps') {
        stream320 = m['url'] as String?;
        break;
      }
    }
    if (stream320 == null && downloadUrls.isNotEmpty) {
      int bestBitrate = 0;
      for (final dl in downloadUrls) {
        final m = dl as Map<String, dynamic>;
        final q = m['quality'] as String? ?? '';
        final br = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (br > bestBitrate) {
          bestBitrate = br;
          stream320 = m['url'] as String?;
        }
      }
    }

    final artists = map['artists'] is Map
        ? (map['artists']['primary'] as List<dynamic>? ?? [])
        : (map['artists'] as List<dynamic>? ?? []);
    final artistNames = artists
        .map((a) => a is Map ? (a['name'] as String? ?? '') : '')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final id = map['id'] as String? ?? '';

    return {
      'videoId': id,
      'title': _decodeEntities(map['name'] as String? ?? 'Unknown'),
      'artist': _decodeEntities(artistNames.isNotEmpty
          ? artistNames
          : (map['primaryArtists'] as String? ?? 'Unknown')),
      'artists': [
        for (final a in artistNames.split(', '))
          if (a.isNotEmpty) {'name': a},
      ],
      'thumbnails': [
        {'url': thumb},
      ],
      'duration': Duration(
          seconds: (map['duration'] as num?)?.toInt() ?? 0),
      'jiosaavnStreamUrl': stream320,
      'type': 'JIOSAAVN',
    };
  }

  Map<String, dynamic> _collectionFromJson(Map<String, dynamic> map,
      {required bool isAlbum}) {
    String thumb = '';
    final imageList = map['image'] as List<dynamic>? ?? [];
    for (final img in imageList) {
      final m = img as Map<String, dynamic>;
      if (m['quality'] == '500x500') {
        thumb = m['url'] as String? ?? '';
        break;
      }
    }
    if (thumb.isEmpty && imageList.isNotEmpty) {
      thumb = (imageList.last as Map<String, dynamic>)['url'] as String? ?? '';
    }
    final id = map['id'] as String? ?? '';
    return {
      'title': _decodeEntities(map['name'] as String? ?? 'Unknown'),
      'subtitle': _decodeEntities(map['subtitle'] as String? ?? ''),
      'thumbnails': [
        {'url': thumb},
      ],
      'endpoint': {
        if (isAlbum) 'jiosaavnAlbumId': id else 'jiosaavnPlaylistId': id,
      },
      'type': isAlbum ? 'JIOSAAVN_ALBUM' : 'JIOSAAVN_PLAYLIST',
    };
  }

  static const _entities = {
    '&quot;': '"',
    '&amp;': '&',
    '&#039;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
  };

  String _decodeEntities(String input) {
    var out = input;
    _entities.forEach((entity, char) {
      out = out.replaceAll(entity, char);
    });
    return out;
  }

  // ── CLIENT-SIDE FILTERING (song search only) ──

  List<Map<String, dynamic>> _filterRelevant(
      List<Map<String, dynamic>> songs, String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return songs;

    final required = tokens.length >= 2 ? 2 : 1;

    return songs.where((s) {
      final text =
      '${s['title']} ${s['artist']}'.toLowerCase();
      int matches = 0;
      for (final t in tokens) {
        if (text.contains(t)) matches++;
      }
      return matches >= required;
    }).toList();
  }

  List<String> _tokens(String query) {
    const stopWords = {
      'the', 'and', 'for', 'from', 'with', 'feat', 'ft', 'of', 'a', 'an',
      'song', 'video', 'audio', 'lyrics', 'lyric',
    };
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !stopWords.contains(t))
        .toList();
  }

  void dispose() {
    _client.close();
  }
}