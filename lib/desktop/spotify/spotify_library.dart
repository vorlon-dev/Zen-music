// ZenMusic — Spotify account library (SP-6, Pathfinder).
//
// Data sources (all api-partner.spotify.com/pathfinder/v2/query):
//   * profileAttributes  -> display name + username
//   * libraryV3          -> user's playlists (filters:['Playlists'])
//                           user's liked songs (filters:['LikedSongs'])
//   * fetchPlaylist      -> tracks of a NORMAL playlist only. Liked Songs
//                           is rejected by the server — it's not a
//                           PLAYLIST-typed URI.
//
// Track parsing: fetchPlaylist wraps tracks as
//   wrap.itemV2.data   (TrackResponseWrapper → Track)
// The parser tries that direct path, then a wrap-level try, then a deep
// search that returns the first map whose 'uri' starts with 'spotify:track:'.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyLibrary {
  SpotifyLibrary._();
  static final SpotifyLibrary instance = SpotifyLibrary._();

  final _client = http.Client();

  void _log(String m) => debugPrint('[spotify-lib] $m');

  String _short(String s, [int n = 240]) =>
      s.length > n ? '${s.substring(0, n)}…' : s;

  Future<Map<String, dynamic>?> _post(
      Map<String, dynamic> payload) async {
    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      _log('no session: ${SpotifyAuth.instance.lastError}');
      return null;
    }
    final clientToken = await SpotifyAuth.instance.getClientToken();
    try {
      final r = await _client
          .post(Uri.parse(SpotifyConfig.pathfinderUrl),
          headers: {
            'authorization': 'Bearer $token',
            'client-token': clientToken,
            'content-type': 'application/json;charset=UTF-8',
            'app-platform': SpotifyConfig.appPlatform,
            'spotify-app-version': SpotifyConfig.spotifyAppVersion,
            'origin': 'https://open.spotify.com',
            'referer': 'https://open.spotify.com/',
            'user-agent': SpotifyConfig.userAgent,
          },
          body: jsonEncode(payload))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        _log('pathfinder HTTP ${r.statusCode}: ${_short(r.body)}');
        return null;
      }
      final root = jsonDecode(r.body) as Map<String, dynamic>;
      final errs = root['errors'];
      if (errs is List && errs.isNotEmpty) {
        _log('errors: ${_short(jsonEncode(errs), 400)}');
      }
      return root;
    } catch (e) {
      _log('pathfinder error $e');
      return null;
    }
  }

  Map<String, dynamic> _op(String operationName, String hash,
      [Map<String, dynamic> variables = const {}]) =>
      {
        'variables': variables,
        'operationName': operationName,
        'extensions': {
          'persistedQuery': {'version': 1, 'sha256Hash': hash},
        },
      };

  // ── PUBLIC ──

  Future<Map<String, dynamic>?> me() async {
    final data = await _post(_op(
        'profileAttributes', SpotifyConfig.profileAttributesHash));
    if (data == null) return null;
    final profile = data['data']?['me']?['profile'];
    if (profile is! Map) {
      _log('profileAttributes missing profile — data keys: '
          '${(data['data'] as Map?)?.keys?.toList() ?? 'null'}');
      return null;
    }
    return {
      'id': profile['username']?.toString() ?? '',
      'display_name': profile['name']?.toString() ?? '',
    };
  }

  Future<List<Map<String, dynamic>>> userPlaylists(
      {int limit = 50, int offset = 0}) async {
    final data = await _post(_op('libraryV3', SpotifyConfig.libraryHash, {
      'filters': ['Playlists'],
      'order': null,
      'textFilter': '',
      'features': ['LIKED_SONGS', 'YOUR_EPISODES'],
      'limit': limit,
      'offset': offset,
    }));
    if (data == null) return [];
    final items = data['data']?['me']?['libraryV3']?['items'] as List? ?? [];
    if (items.isEmpty) {
      _log('libraryV3 zero playlists');
      return [];
    }

    final out = <Map<String, dynamic>>[];
    for (final wrap in items) {
      if (wrap is! Map) continue;
      final item = wrap['item'];
      if (item is! Map) continue;
      final d = item['data'];
      if (d is! Map) continue;
      if (d['__typename'] != 'Playlist') continue;
      final uri = d['uri']?.toString() ?? '';
      if (uri.isEmpty) continue;

      final name = d['name']?.toString() ?? 'Playlist';

      String thumb = '';
      final imgs = (d['images'] as Map?)?['items'] as List?;
      if (imgs != null && imgs.isNotEmpty) {
        final sources = (imgs.first as Map?)?['sources'] as List? ?? [];
        for (final s in sources) {
          if (s is Map && (s['width'] as num?)?.toInt() == 300) {
            thumb = s['url']?.toString() ?? '';
            break;
          }
        }
        if (thumb.isEmpty && sources.isNotEmpty) {
          thumb = (sources.first as Map)['url']?.toString() ?? '';
        }
      }

      out.add({
        'id': uri,
        'title': name,
        'subtitle': '',
        'thumbnails': [{'url': thumb}],
        'type': 'SPOTIFY_PLAYLIST',
      });
    }
    return out;
  }

  /// User's liked songs via libraryV3 with the LikedSongs filter.
  /// Diagnostic build: dumps the first item so we can pin the exact wrapper
  /// shape (the LikedSongs node is a Playlist wrapper, not a normal one).
  Future<List<Map<String, dynamic>>> userLikedSongs(
      {int limit = 100, int offset = 0}) async {
    final data = await _post(_op('libraryV3', SpotifyConfig.libraryHash, {
      'filters': ['LikedSongs'],
      'order': null,
      'textFilter': '',
      'features': ['LIKED_SONGS'],
      'limit': limit,
      'offset': offset,
    }));
    if (data == null) return [];
    final items = data['data']?['me']?['libraryV3']?['items'] as List? ?? [];
    _log('userLikedSongs: ${items.length} items from libraryV3');
    if (items.isNotEmpty) {
      _log('userLikedSongs first wrap raw (1400 chars): '
          '${_short(jsonEncode(items.first), 1400)}');
    }
    // For now, return whatever we can extract as tracks from the response.
    // If the LikedSongs node embeds a playlist with items, we'll get them.
    final songs = <Map<String, dynamic>>[];
    for (final wrap in items) {
      final s = _trackFromPathfinder(wrap);
      if (s != null) songs.add(s);
    }
    _log('userLikedSongs: ${songs.length} parsed');
    return songs;
  }

  /// Fetches tracks of a NORMAL playlist. Pass the full uri
  /// ("spotify:playlist:...").
  Future<List<Map<String, dynamic>>> fetchPlaylistTracks(String uri,
      {int limit = 100, int offset = 0}) async {
    final data =
    await _post(_op('fetchPlaylist', SpotifyConfig.fetchPlaylistHash, {
      'uri': uri,
      'offset': offset,
      'limit': limit,
      'enableWatchFeedEntrypoint': false,
    }));
    if (data == null) return [];

    final root = data['data'];
    if (root is! Map) {
      _log('fetchPlaylist $uri -> no data. top keys: ${data.keys.toList()}');
      return [];
    }

    final candidateLists = <List?>[
      ((root['playlistV2'] as Map?)?['content'] as Map?)?['items'] as List?,
      (root['playlistV2'] as Map?)?['items'] as List?,
      ((root['collection'] as Map?)?['content'] as Map?)?['items'] as List?,
      ((root['me'] as Map?)?['collection'] as Map?)?['items'] as List?,
    ];

    List items = const [];
    for (final c in candidateLists) {
      if (c != null && c.isNotEmpty) {
        items = c;
        break;
      }
    }

    if (items.isEmpty) {
      _log('fetchPlaylist $uri -> 0 items. root keys: '
          '${root.keys.toList()}');
      return [];
    }

    final songs = <Map<String, dynamic>>[];
    for (final wrap in items) {
      final song = _trackFromPathfinder(wrap);
      if (song != null) songs.add(song);
    }
    _log('fetchPlaylist $uri -> ${songs.length}/${items.length} parsed');
    return songs;
  }

  // ── PARSERS ──

  /// Three-tier track extraction:
  ///   1. Known shape: wrap.itemV2.data (or item / track), then check
  ///      the deepest node is a track.
  ///   2. The wrap itself might be a track (in some contexts).
  ///   3. Deep-search every value for the first map whose uri starts with
  ///      'spotify:track:'.
  Map<String, dynamic>? _trackFromPathfinder(dynamic wrap) {
    if (wrap is! Map) return null;

    // Tier 1: known wrapper chain.
    final wrapper = wrap['itemV2'] ?? wrap['item'] ?? wrap['track'];
    if (wrapper is Map) {
      final inner = wrapper['data'] ?? wrapper;
      final parsed = _tryTrack(inner);
      if (parsed != null) return parsed;
    }

    // Tier 2: wrap itself.
    final direct = _tryTrack(wrap);
    if (direct != null) return direct;

    // Tier 3: deep search.
    return _walkForTrack(wrap, 0);
  }

  Map<String, dynamic>? _tryTrack(dynamic node) {
    if (node is! Map) return null;
    final uri = node['uri']?.toString() ?? '';
    if (!uri.startsWith('spotify:track:')) return null;
    return _trackFromMap(node);
  }

  Map<String, dynamic>? _walkForTrack(dynamic node, int depth) {
    if (depth > 8) return null;
    if (node is Map) {
      final parsed = _tryTrack(node);
      if (parsed != null) return parsed;
      for (final v in node.values) {
        final r = _walkForTrack(v, depth + 1);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _walkForTrack(v, depth + 1);
        if (r != null) return r;
      }
    }
    return null;
  }

  Map<String, dynamic>? _trackFromMap(Map d) {
    final uri = d['uri']?.toString() ?? '';
    final name = d['name']?.toString() ?? '';
    if (uri.isEmpty || name.isEmpty) return null;

    // Derive display id from the uri if 'id' isn't present.
    var id = d['id']?.toString() ?? '';
    if (id.isEmpty) {
      id = uri.replaceFirst('spotify:track:', '');
    }
    if (id.isEmpty) return null;

    final artistNames = <String>[];
    final artists = d['artists'] as Map?;
    final items = artists?['items'] as List?;
    if (items != null) {
      for (final a in items) {
        final n =
            ((a as Map?)?['profile'] as Map?)?['name']?.toString() ?? '';
        if (n.isNotEmpty) artistNames.add(n);
      }
    }

    final album = d['albumOfTrack'] as Map?;
    final albumName = album?['name']?.toString() ?? '';

    String cover = '';
    final sources = (album?['coverArt'] as Map?)?['sources'] as List?;
    if (sources != null) {
      for (final s in sources) {
        if (s is Map && (s['height'] as num?)?.toInt() == 300) {
          cover = s['url']?.toString() ?? '';
          break;
        }
      }
      if (cover.isEmpty && sources.isNotEmpty) {
        cover = (sources.first as Map)['url']?.toString() ?? '';
      }
    }

    final durationMs =
        ((d['duration'] as Map?)?['totalMilliseconds'] as num?)?.toInt() ??
            0;

    return {
      'videoId': id,
      'title': name,
      'artist': artistNames.isEmpty ? 'Unknown Artist' : artistNames.join(', '),
      'artists': [for (final n in artistNames) {'name': n}],
      'thumbnails': [{'url': cover}],
      'duration': Duration(milliseconds: durationMs),
      'album': {'name': albumName},
      'spotifyUri': uri,
      'type': 'SPOTIFY',
    };
  }

  void dispose() => _client.close();
}