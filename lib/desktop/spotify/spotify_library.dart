// ZenMusic — Spotify account library (SP-6, Pathfinder).
//
// Data sources (all api-partner.spotify.com/pathfinder/v2/query):
//   * profileAttributes  -> display name + username + avatar
//   * libraryV3          -> user's playlists (filters:['Playlists'])
//                           user's liked songs (filters:['LikedSongs'])
//   * fetchPlaylist      -> tracks of a NORMAL playlist only. Liked Songs
//                           is rejected by the server — it's not a
//                           PLAYLIST-typed URI.
//   * home (SP-39)       -> the REAL Spotify homepage: greeting +
//                           shelves (tracks/albums/artists/playlists/
//                           promos/recents lists), ported 1:1 from
//                           Stopify's SpotifyWebClient.fetchHomeSections
//                           (Anattana-Labs/Stopify, MIT).
//   * recents (SP-39)    -> recently played tracks
//                           ("spotify:list:recents:page"), ported from
//                           Stopify's fetchSpotifyRecentlyPlayed.
//   * getAlbum (SP-39)   -> tracks of an ALBUM uri, ported from
//                           Stopify's fetchAlbumTracks.
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
    // SP-39: the profile node carries the avatar too
    // (avatar.sources[].url) — Stopify renders it in the home top bar.
    String avatar = '';
    final sources = (profile['avatar'] as Map?)?['sources'] as List?;
    if (sources != null && sources.isNotEmpty) {
      avatar = ((sources.first as Map)['url']?.toString() ?? '');
    }
    return {
      'id': profile['username']?.toString() ?? '',
      'display_name': profile['name']?.toString() ?? '',
      'avatar': avatar,
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

  // ── SP-39: the REAL Spotify homepage (Stopify port) ──────────────

  /// The exact request Stopify's SpotifyWebClient.fetchHomeSections
  /// fires. Returns {'greeting': String, 'sections': [sectionMap]} or
  /// null. Section map: {'title', 'subtitle', 'items': [itemMap]}.
  ///
  /// Item map (normalized for the home section widget):
  ///   {
  ///     'kind': 'track' | 'playlist' | 'album' | 'artist' |
  ///             'podcast' | 'episode',
  ///     'uri': full spotify uri ('' when the promo has no target),
  ///     'title': display name,
  ///     'subtitle': artist / description / type label,
  ///     'thumbnails': [{'url': cover}],
  ///     'track': {standard playable track map}   // kind == track only
  ///   }
  Future<Map<String, dynamic>?> homeSnapshot(
      {int sectionItemsLimit = 10}) async {
    final data = await _post(_op('home', SpotifyConfig.homeHash, {
      'includeHomeChapterVideoCards': false,
      'homeEndUserIntegration': 'INTEGRATION_WEB_PLAYER',
      'timeZone': 'Asia/Calcutta', // Stopify hardcodes this too
      'sp_t': '',
      'facet': '',
      'sectionItemsLimit': sectionItemsLimit,
      'includeEpisodeContentRatingsV2': true,
    }));
    if (data == null) return null;
    final home = ((data['data'] as Map?)?['home']) as Map?;
    if (home == null) {
      _log('home: no data.home. top keys: ${data.keys.toList()}');
      return null;
    }
    final greeting =
        (home['greeting'] as Map?)?['transformedLabel']?.toString() ??
            'Welcome back';
    final sections =
        (((home['sectionContainer'] as Map?)?['sections'] as Map?)?['items']
            as List?) ??
            const [];

    final out = <Map<String, dynamic>>[];
    for (final sec in sections) {
      if (sec is! Map) continue;
      final d = sec['data'];
      if (d is! Map) continue;
      final title =
          (d['title'] as Map?)?['transformedLabel']?.toString() ?? '';
      if (title.isEmpty) continue;
      final subtitle =
          (d['subtitle'] as Map?)?['transformedLabel']?.toString() ?? '';
      final items =
          ((sec['sectionItems'] as Map?)?['items']) as List? ?? const [];

      final parsed = <Map<String, dynamic>>[];
      for (final it in items) {
        final content = (it as Map?)?['content'];
        if (content is! Map) continue;
        final tn = content['__typename']?.toString() ?? '';
        if (tn == 'ListResponseWrapper') {
          // One item that EXPANDS into multiple entities (recent
          // lists) — Stopify flattens them into the shelf.
          parsed.addAll(_listWrapperItems(content['data']));
        } else {
          final m = _homeItem(content);
          if (m != null) parsed.add(m);
        }
      }
      if (parsed.isNotEmpty) {
        out.add({'title': title, 'subtitle': subtitle, 'items': parsed});
      }
    }
    _log('home: ${out.length} sections');
    return {'greeting': greeting, 'sections': out};
  }

  /// __typename → normalized item map. Ported from Stopify's five
  /// response-wrapper branches.
  Map<String, dynamic>? _homeItem(Map content) {
    final d = content['data'];
    switch (content['__typename']?.toString() ?? '') {
      case 'TrackResponseWrapper':
        if (d is! Map) return null;
        final t = _trackFromMap(d);
        if (t == null) return null;
        return {
          'kind': 'track',
          'uri': t['spotifyUri'],
          'title': t['title'],
          'subtitle': t['artist'],
          'thumbnails': t['thumbnails'],
          'track': t,
        };
      case 'PlaylistResponseWrapper':
        if (d is! Map) return null;
        final uri = d['uri']?.toString() ?? '';
        if (uri.isEmpty) return null;
        final kind = _kindFromUri(uri, 'playlist');
        final desc = d['description']?.toString() ?? '';
        return {
          'kind': kind,
          'uri': uri,
          'title': d['name']?.toString() ?? 'Playlist',
          'subtitle': desc.isNotEmpty
              ? desc
              : (kind == 'track' ? 'Track' : 'Playlist'),
          'thumbnails': [
            {'url': _playlistCover(d)},
          ],
        };
      case 'PromotionResponseWrapper':
        if (d is! Map) return null;
        final target = d['target']?.toString() ?? '';
        if (target.isEmpty) return null;
        final name = (d['titleTranslation'] as Map?)?['transformedLabel']
                ?.toString() ??
            d['name']?.toString() ??
            'Featured';
        final body =
            (d['bodyTranslation'] as Map?)?['transformedLabel']?.toString() ??
                '';
        return {
          'kind': _kindFromUri(target, 'playlist'),
          'uri': target,
          'title': name,
          'subtitle': body.isNotEmpty ? body : 'Featured',
          'thumbnails': [
            {'url': _deepFirstSourceUrl(d['background'])},
          ],
        };
      case 'AlbumResponseWrapper':
        if (d is! Map) return null;
        final uri = d['uri']?.toString() ?? '';
        if (uri.isEmpty) return null;
        return {
          'kind': uri.contains(':track:') ? 'track' : 'album',
          'uri': uri,
          'title': d['name']?.toString() ?? 'Album',
          'subtitle': _firstArtistName(d),
          'thumbnails': [
            {'url': _deepFirstSourceUrl(d['coverArt'])},
          ],
        };
    }
    return null;
  }

  /// ListResponseWrapper expansion: entity list with trait-based
  /// metadata (recently played, made-for-you lists).
  List<Map<String, dynamic>> _listWrapperItems(dynamic d) {
    final listItems =
        (((d as Map?)?['items'] as Map?)?['items']) as List? ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final li in listItems) {
      final entity = (li as Map?)?['entity'];
      if (entity is! Map) continue;
      final uri = entity['_uri']?.toString() ?? '';
      final eData = entity['data'];
      if (uri.isEmpty || eData is! Map) continue;

      final rawType =
          (eData['entityTypeTrait'] as Map?)?['type']?.toString() ?? '';
      final identity = eData['identityTrait'] as Map?;
      final name = identity?['name']?.toString() ?? 'Recent';
      final desc = identity?['description']?.toString() ?? '';

      String kind;
      if (uri.contains(':track:') || rawType.contains('TRACK')) {
        kind = 'track';
      } else if (uri.contains(':album:') || rawType.contains('ALBUM')) {
        kind = 'album';
      } else if (uri.contains(':artist:') || rawType.contains('ARTIST')) {
        kind = 'artist';
      } else if (uri.contains(':show:') ||
          uri.contains(':episode:') ||
          rawType.contains('PODCAST') ||
          rawType.contains('EPISODE')) {
        kind = 'podcast';
      } else {
        kind = 'playlist';
      }

      final cover = _deepFirstSourceUrl(
          (eData['visualIdentityTrait'] as Map?)?['squareCoverImage']);

      if (kind == 'track') {
        // Reuse the pathfinder track parser where possible: the entity
        // node in recents-style lists does NOT match TrackResponseWrapper
        // shape, so build the map directly.
        final contribs =
            (identity?['contributors'] as Map?)?['items'] as List? ?? const [];
        final artistNames = [
          for (final c in contribs)
            if (c is Map) c['name']?.toString() ?? ''
        ].where((s) => s.isNotEmpty).toList();
        out.add({
          'kind': 'track',
          'uri': uri,
          'title': name,
          'subtitle': artistNames.isEmpty ? 'Track' : artistNames.join(', '),
          'thumbnails': [
            {'url': cover},
          ],
          'track': {
            'videoId': uri.replaceFirst('spotify:track:', ''),
            'title': name,
            'artist': artistNames.isEmpty
                ? 'Unknown Artist'
                : artistNames.join(', '),
            'artists': [
              for (final n in artistNames) {'name': n},
            ],
            'thumbnails': [
              {'url': cover},
            ],
            'duration': Duration.zero,
            'album': {'name': ''},
            'spotifyUri': uri,
            'type': 'SPOTIFY',
          },
        });
      } else {
        out.add({
          'kind': kind,
          'uri': uri,
          'title': name,
          'subtitle':
              desc.isNotEmpty ? desc : _kindLabel(kind),
          'thumbnails': [
            {'url': cover},
          ],
        });
      }
    }
    return out;
  }

  String _kindFromUri(String uri, String fallback) {
    if (uri.contains(':track:')) return 'track';
    if (uri.contains(':album:')) return 'album';
    if (uri.contains(':artist:')) return 'artist';
    if (uri.contains(':show:')) return 'podcast';
    if (uri.contains(':episode:')) return 'episode';
    if (uri.contains(':playlist:') || uri.contains(':user:')) {
      return 'playlist';
    }
    return fallback;
  }

  String _kindLabel(String kind) =>
      kind.isEmpty ? 'Playlist' : kind[0].toUpperCase() + kind.substring(1);

  /// images.items[0].sources[0].url (PlaylistResponseWrapper shape).
  String _playlistCover(Map d) {
    final items = (d['images'] as Map?)?['items'] as List? ?? const [];
    if (items.isEmpty) return '';
    final sources = (items.first as Map?)?['sources'] as List? ?? const [];
    if (sources.isEmpty) return '';
    return ((sources.first as Map)['url']?.toString() ?? '');
  }

  String _firstArtistName(Map d) {
    final items = (d['artists'] as Map?)?['items'] as List? ?? const [];
    if (items.isEmpty) return 'Artist';
    return (((items.first as Map)['profile'] as Map?)?['name']?.toString() ??
            'Artist');
  }

  /// Walks node.sources / node.image.sources / node.image.data.sources —
  /// one helper for every cover-art nesting Stopify handles.
  String _deepFirstSourceUrl(dynamic node) {
    if (node is! Map) return '';
    dynamic sources = node['sources'];
    if (sources is! List) sources = (node['image'] as Map?)?['sources'];
    if (sources is! List) {
      sources = ((node['image'] as Map?)?['data'] as Map?)?['sources'];
    }
    if (sources is! List) {
      sources = (((node['squareCoverImage'] as Map?)?['image'] as Map?)?['data']
          as Map?)?['sources'];
    }
    if (sources is List && sources.isNotEmpty) {
      return ((sources.first as Map)['url']?.toString() ?? '');
    }
    return '';
  }

  /// Recently played tracks ("spotify:list:recents:page"), Stopify
  /// fetchSpotifyRecentlyPlayed port. Output = the standard track map.
  Future<List<Map<String, dynamic>>> recentlyPlayed(
      {int limit = 100}) async {
    final data = await _post(_op('recents', SpotifyConfig.recentsHash, {
      'uris': ['spotify:list:recents:page'],
      'offset': 0,
      'limit': limit,
    }));
    if (data == null) return [];
    final lists = ((data['data'] as Map?)?['lists']) as List? ?? const [];
    if (lists.isEmpty) {
      _log('recents: no lists');
      return [];
    }
    final items =
        (((lists.first as Map?)?['items'] as Map?)?['items']) as List? ??
            const [];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final it in items) {
      final entity = (it as Map?)?['entity'];
      if (entity is! Map) continue;
      final entityData = entity['data'];
      if (entityData is! Map) continue;
      final uri = entity['_uri']?.toString() ??
          entityData['uri']?.toString() ??
          '';
      // ENTITY_TYPE_TRACK check collapsed to the uri prefix (Stopify
      // accepts either).
      if (!uri.startsWith('spotify:track:')) continue;
      if (!seen.add(uri)) continue;
      final t = _trackFromRecentsEntity(entityData, uri);
      if (t != null) out.add(t);
    }
    _log('recents: ${out.length} tracks');
    return out;
  }

  Map<String, dynamic>? _trackFromRecentsEntity(Map d, String uri) {
    final identity = d['identityTrait'] as Map?;
    final name = identity?['name']?.toString() ?? '';
    if (name.isEmpty) return null;

    final contribs =
        (identity?['contributors'] as Map?)?['items'] as List? ?? const [];
    final artistNames = [
      for (final c in contribs)
        if (c is Map) c['name']?.toString() ?? ''
    ].where((s) => s.isNotEmpty).toList();

    final album = ((identity?['contentHierarchyParent'] as Map?)
                ?['identityTrait'] as Map?)
            ?['name']
        ?.toString() ??
        '';

    final visual = d['visualIdentityTrait'] as Map?;
    String cover = _deepFirstSourceUrl(visual?['squareCoverImage']);
    if (cover.isEmpty) {
      final origs =
          ((visual?['squareCoverImage'] as Map?)?['originalInstances'])
              as List? ??
              const [];
      if (origs.isNotEmpty) {
        cover =
            (((origs.first as Map)['flatFile'] as Map?)?['cdnUrl'])
                    ?.toString() ??
                '';
      }
    }

    // consumptionExperienceTrait.duration.seconds → ms
    final durationMs = ((((d['consumptionExperienceTrait'] as Map?)
                        ?['duration'] as Map?)
                    ?['seconds'] as num?)
                ?.toInt() ??
            0) *
        1000;

    return {
      'videoId': uri.replaceFirst('spotify:track:', ''),
      'title': name,
      'artist': artistNames.isEmpty
          ? 'Unknown Artist'
          : artistNames.join(', '),
      'artists': [
        for (final n in artistNames) {'name': n},
      ],
      'thumbnails': [
        {'url': cover},
      ],
      'duration': Duration(milliseconds: durationMs),
      'album': {'name': album},
      'spotifyUri': uri,
      'type': 'SPOTIFY',
    };
  }

  /// Tracks of an ALBUM uri (spotify:album:…), Stopify fetchAlbumTracks
  /// port (getAlbum persisted query). Output = the standard track map.
  Future<List<Map<String, dynamic>>> fetchAlbumTracks(String uri,
      {int limit = 50, int offset = 0}) async {
    final data = await _post(_op('getAlbum', SpotifyConfig.getAlbumHash, {
      'uri': uri,
      'locale': '',
      'offset': offset,
      'limit': limit,
    }));
    if (data == null) return [];
    final album = ((data['data'] as Map?)?['albumUnion']) as Map?;
    if (album == null) {
      _log('getAlbum $uri -> no albumUnion. root keys: '
          '${(data['data'] as Map?)?.keys?.toList() ?? 'null'}');
      return [];
    }
    final albumName = album['name']?.toString() ?? 'Album';
    final cover = _deepFirstSourceUrl(album['coverArt']);
    final tracks =
        (((album['tracksV2'] as Map?)?['items'])) as List? ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final t in tracks) {
      final track = (t as Map?)?['track'];
      if (track is! Map) continue;
      final tUri = track['uri']?.toString() ?? '';
      final name = track['name']?.toString() ?? '';
      if (tUri.isEmpty || name.isEmpty) continue;
      final artistNames = <String>[];
      for (final a
          in ((track['artists'] as Map?)?['items'] as List? ?? const [])) {
        final n =
            ((a as Map?)?['profile'] as Map?)?['name']?.toString() ?? '';
        if (n.isNotEmpty) artistNames.add(n);
      }
      final durationMs =
          ((track['duration'] as Map?)?['totalMilliseconds'] as num?)
                  ?.toInt() ??
              0;
      out.add({
        'videoId': tUri.replaceFirst('spotify:track:', ''),
        'title': name,
        'artist': artistNames.isEmpty
            ? 'Unknown Artist'
            : artistNames.join(', '),
        'artists': [
          for (final n in artistNames) {'name': n},
        ],
        'thumbnails': [
          {'url': cover},
        ],
        'duration': Duration(milliseconds: durationMs),
        'album': {'name': albumName},
        'spotifyUri': tUri,
        'type': 'SPOTIFY',
      });
    }
    _log('getAlbum $uri -> ${out.length}/${tracks.length} parsed');
    return out;
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
