// ZenMusic — spotify search (searchTopResultsList Pathfinder query).
// Ported from Stopify's SpotifyWebClient.searchTracks (MIT License) —
// Copyright (c) Shashwat. ZenMusic remains GPL-3.0.
//
// Port contract: returns desktop song maps in the JioSaavn shape (videoId =
// spotify track id; 'spotifyUri' carries spotify:track:... for the player's
// future Spotify branch; type 'SPOTIFY'). Requires a Spotify session (sp_dc
// or token-only); returns [] with a console marker when logged out, so the
// search page is unaffected for non-Spotify users.
// DEVIATION: unplayable tracks (playability.playable == false) are dropped
// (Stopify keeps them; they would just error on tap here).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifySearch {
  SpotifySearch._();
  static final SpotifySearch instance = SpotifySearch._();

  final _client = http.Client();

  void _log(String m) => debugPrint('[spotify-search] $m');

  String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  Future<List<Map<String, dynamic>>> search(String query,
      {int limit = 10}) async {
    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      _log('skipped: ${SpotifyAuth.instance.lastError}');
      return [];
    }
    final clientToken = await SpotifyAuth.instance.getClientToken();

    // Variables verbatim from Stopify searchTracks (limit/numberOfTopResults
    // stay 50 — known-good request; we slice client-side).
    final payload = {
      'variables': {
        'query': query,
        'limit': 50,
        'offset': 0,
        'numberOfTopResults': 50,
        'includeArtistHasConcertsField': false,
        'includeAudiobooks': true,
        'includeAuthors': true,
        'includePreReleases': true,
        'includeAlbumPreReleases': false,
        'includeEpisodeContentRatingsV2': true,
        'isPrefix': null,
        'sectionFilters': ['GENERIC', 'VIDEO_CONTENT'],
      },
      'operationName': 'searchTopResultsList',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash': SpotifyConfig.searchTopResultsHash,
        },
      },
    };

    final resp = await _client
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
        .timeout(const Duration(seconds: 15));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
          'Spotify search HTTP ${resp.statusCode}: ${_short(resp.body)}');
    }

    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final itemsV2 =
    root['data']?['searchV2']?['topResultsV2']?['itemsV2'] as List?;
    if (itemsV2 == null) return [];

    final songs = <Map<String, dynamic>>[];
    for (final hit in itemsV2) {
      final item = (hit as Map<String, dynamic>?)?['item'];
      if (item is! Map<String, dynamic>) continue;
      if (item['__typename'] != 'TrackResponseWrapper') continue;
      final data = item['data'];
      if (data is! Map<String, dynamic>) continue;

      // DEVIATION: drop unplayable rows.
      if (data['playability']?['playable'] == false) continue;

      final id = data['id']?.toString() ?? '';
      final uri = data['uri']?.toString() ?? '';
      final name = data['name']?.toString() ?? '';
      if (id.isEmpty || uri.isEmpty || name.isEmpty) continue;

      final durationMs =
          ((data['duration'] as Map<String, dynamic>?)?['totalMilliseconds']
          as num?)
              ?.toInt() ??
              0;

      final artistNames = <String>[];
      final artistItems =
      (data['artists'] as Map<String, dynamic>?)?['items'] as List?;
      if (artistItems != null) {
        for (final a in artistItems) {
          final n = ((a as Map<String, dynamic>?)?['profile']
          as Map<String, dynamic>?)?['name']
              ?.toString();
          if (n != null && n.isNotEmpty) artistNames.add(n);
        }
      }
      final artist = artistNames.join(', ');

      final album = data['albumOfTrack'] as Map<String, dynamic>?;
      final albumName = album?['name']?.toString() ?? '';

      // Cover: prefer the 300px source (Stopify's pick), else first.
      String cover = '';
      final sources = album?['coverArt']?['sources'] as List?;
      if (sources != null) {
        for (final s in sources) {
          final m = s as Map<String, dynamic>?;
          if (m == null) continue;
          if ((m['height'] as num?)?.toInt() == 300) {
            cover = m['url']?.toString() ?? '';
            break;
          }
        }
        if (cover.isEmpty && sources.isNotEmpty) {
          cover = (sources.first as Map<String, dynamic>)['url']?.toString() ?? '';
        }
      }

      songs.add({
        'videoId': id,
        'title': name,
        'artist': artist.isEmpty ? 'Unknown Artist' : artist,
        'artists': [
          for (final n in artistNames) {'name': n},
        ],
        'thumbnails': [
          {'url': cover},
        ],
        'duration': Duration(milliseconds: durationMs),
        'album': {'name': albumName},
        'spotifyUri': uri,
        'type': 'SPOTIFY',
      });
    }

    _log('${songs.length} tracks for "$query"');
    return songs.take(limit).toList();
  }

  void dispose() => _client.close();
}