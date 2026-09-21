import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/collection.dart';

class PlaylistDetail {
  final Collection collection;
  final List<Song> songs;
  const PlaylistDetail(this.collection, this.songs);
}

class JiosaavnService {
  static const _baseUrl = 'https://jiosaavn-api.vorlon-revora.workers.dev';
  final _client = http.Client();

  // ═════════════════════════════════════════════
  // SONG SEARCH
  // ═════════════════════════════════════════════

  Future<List<Song>> search(String query, {int limit = 15}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/songs').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final songs = <Song>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        songs.add(_songFromSaavnJson(item));
      }

      return _filterRelevant(songs, query);
    } catch (e) {
      print('JiosaavnService.search error: $e');
      return [];
    }
  }

  Future<String?> fetchStreamUrl(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/songs/$songId');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final list = data['data'] as List<dynamic>? ?? [];
      if (list.isEmpty) return null;

      final dl = (list.first as Map<String, dynamic>)['downloadUrl']
      as List<dynamic>? ?? [];
      for (final d in dl) {
        final m = d as Map<String, dynamic>;
        if (m['quality'] == '320kbps') return m['url'] as String?;
      }
      return dl.isNotEmpty
          ? (dl.last as Map<String, dynamic>)['url'] as String?
          : null;
    } catch (e) {
      print('JiosaavnService.fetchStreamUrl error: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════
  // PLAYLISTS — search + detail
  // ═════════════════════════════════════════════

  Future<List<Collection>> searchPlaylists(String query,
      {int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/playlists').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );
      final response =
      await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final playlists = <Collection>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        playlists.add(Collection.fromPlaylistJson(item));
      }
      return playlists;
    } catch (e) {
      print('JiosaavnService.searchPlaylists error: $e');
      return [];
    }
  }

  Future<PlaylistDetail?> getPlaylist(String id) async {
    try {
      final uri =
      Uri.parse('$_baseUrl/api/playlists?id=$id&limit=100');
      final response =
      await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        print('JiosaavnService.getPlaylist: status ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) return null;

      final collection = Collection.fromPlaylistJson(payload);
      final songList = payload['songs'] as List<dynamic>? ?? [];
      final songs = <Song>[];
      for (final item in songList) {
        if (item is! Map<String, dynamic>) continue;
        songs.add(_songFromSaavnJson(item));
      }

      print('🎵 Playlist "${collection.title}": ${songs.length} songs loaded');
      return PlaylistDetail(collection, songs);
    } catch (e) {
      print('JiosaavnService.getPlaylist error: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════
  // ALBUMS — search + detail
  // ═════════════════════════════════════════════

  Future<List<Collection>> searchAlbums(String query,
      {int limit = 10}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/albums').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );
      final response =
      await _client.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final albums = <Collection>[];
      for (final item in results) {
        if (item is! Map<String, dynamic>) continue;
        albums.add(Collection.fromAlbumJson(item));
      }
      return albums;
    } catch (e) {
      print('JiosaavnService.searchAlbums error: $e');
      return [];
    }
  }

  Future<PlaylistDetail?> getAlbum(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/albums?id=$id&limit=100');
      final response =
      await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        print('JiosaavnService.getAlbum: status ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return null;
      final payload = data['data'];
      if (payload is! Map<String, dynamic>) return null;

      final collection = Collection.fromAlbumJson(payload);
      final songList = payload['songs'] as List<dynamic>? ?? [];
      final songs = <Song>[];
      for (final item in songList) {
        if (item is! Map<String, dynamic>) continue;
        songs.add(_songFromSaavnJson(item));
      }

      print('🎵 Album "${collection.title}": ${songs.length} songs loaded');
      return PlaylistDetail(collection, songs);
    } catch (e) {
      print('JiosaavnService.getAlbum error: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════
  // SHARED PARSERS
  // ═════════════════════════════════════════════

  Song _songFromSaavnJson(Map<String, dynamic> map) {
    // ── Thumbnail (prefer 500×500) ──
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
      thumb =
          (imageList.last as Map<String, dynamic>)['url'] as String? ?? '';
    }

    // ── 320kbps stream URL ──
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

    // ── Primary artists ──
    final artists = map['artists'] is Map
        ? (map['artists']['primary'] as List<dynamic>? ?? [])
        : (map['artists'] as List<dynamic>? ?? []);
    final artistNames = artists
        .map((a) => a is Map ? (a['name'] as String? ?? '') : '')
        .where((s) => s.isNotEmpty)
        .join(', ');

    return Song(
      id: map['id'] as String? ?? '',
      title: _decodeEntities(map['name'] as String? ?? 'Unknown'),
      artist: _decodeEntities(artistNames.isNotEmpty
          ? artistNames
          : (map['primaryArtists'] as String? ?? 'Unknown')),
      thumbnail: thumb,
      duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
      jiosaavnId: map['id'] as String?,
      jiosaavnStreamUrl: stream320,
    );
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

  // ═════════════════════════════════════════════
  // CLIENT-SIDE FILTERING (song search only)
  // ═════════════════════════════════════════════

  List<Song> _filterRelevant(List<Song> songs, String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return songs;

    final required = tokens.length >= 2 ? 2 : 1;

    return songs.where((s) {
      final text = '${s.title} ${s.artist}'.toLowerCase();
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