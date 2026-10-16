// ZenMusic — spotify listening history (recents Pathfinder query).
// Ported from Stopify's SpotifyWebClient.fetchSpotifyRecentlyPlayed (MIT)
// — Copyright (c) Shashwat. ZenMusic remains GPL-3.0.
//
// Port contract: returns desktop song maps in the JioSaavn shape (videoId =
// spotify track id; 'spotifyUri' carries spotify:track:...; type 'SPOTIFY')
// so rows render and tap-play through the same paths as the Spotify search
// section (DRM on Android, YT-fallback on desktop).
// DEVIATIONS: Stopify's Web API /me/player/recently-played fallback dropped
// (needs a scope the web-player token may not carry — Pathfinder is the
// proven primary). No local persistence (Stopify's manager is remote-only
// by design). Dedupe by uri, like Stopify. Duration = seconds x 1000,
// verbatim from Stopify's recents parser.
// STYLE NOTE: parsing uses flat is-checked if-blocks on purpose — no nested
// ternaries or cast chains (paste-mangling immunity).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyHistory {
  SpotifyHistory._();
  static final SpotifyHistory instance = SpotifyHistory._();

  final _client = http.Client();

  void _log(String m) => debugPrint('[spotify-history] $m');

  String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  Future<List<Map<String, dynamic>>> recentlyPlayed({int limit = 50}) async {
    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      _log('skipped: ${SpotifyAuth.instance.lastError}');
      return [];
    }
    final clientToken = await SpotifyAuth.instance.getClientToken();

    // Variables verbatim from Stopify fetchSpotifyRecentlyPlayed.
    final payload = {
      'variables': {
        'uris': ['spotify:list:recents:page'],
        'offset': 0,
        'limit': 100,
      },
      'operationName': 'recents',
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash': SpotifyConfig.recentsHash,
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
          'Spotify recents HTTP ${resp.statusCode}: ${_short(resp.body)}');
    }

    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final lists = root['data']?['lists'] as List?;
    if (lists == null || lists.isEmpty) return [];
    final firstList = lists.first;
    if (firstList is! Map) return [];
    final itemsWrap = firstList['items'];
    if (itemsWrap is! Map) return [];
    final items = itemsWrap['items'];
    if (items is! List) return [];

    final songs = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final item in items) {
      if (item is! Map) continue;
      final entity = item['entity'];
      if (entity is! Map) continue;
      final entityData = entity['data'];
      if (entityData is! Map) continue;

      dynamic rawUri = entity['_uri'];
      if (rawUri == null) {
        rawUri = entityData['uri'];
      }
      final uri = rawUri?.toString() ?? '';
      if (!uri.startsWith('spotify:track:')) continue;

      String entityType = '';
      final ett = entityData['entityTypeTrait'];
      if (ett is Map) {
        entityType = ett['type']?.toString() ?? '';
      }
      if (entityType != 'ENTITY_TYPE_TRACK') continue;

      // Dedupe by uri (Stopify: pathfinderTracks.none { it.uri == uri }).
      if (!seen.add(uri)) continue;

      // Identity: name + contributors.
      final identity = entityData['identityTrait'];
      String name = 'Unknown Track';
      final artistNames = <String>[];
      if (identity is Map) {
        final n = identity['name']?.toString() ?? '';
        if (n.isNotEmpty) name = n;
        final contributors = identity['contributors'];
        if (contributors is Map) {
          final contribItems = contributors['items'];
          if (contribItems is List) {
            for (final c in contribItems) {
              if (c is Map) {
                final cn = c['name']?.toString() ?? '';
                if (cn.isNotEmpty) artistNames.add(cn);
              }
            }
          }
        }
      }

      // Album: contentHierarchyParent.identityTrait.name.
      String albumName = '';
      if (identity is Map) {
        final parent = identity['contentHierarchyParent'];
        if (parent is Map) {
          final parentIdentity = parent['identityTrait'];
          if (parentIdentity is Map) {
            albumName = parentIdentity['name']?.toString() ?? '';
          }
        }
      }

      // Duration: consumptionExperienceTrait.duration.seconds x 1000
      // (Stopify recents parser, verbatim).
      int totalMs = 0;
      final consumption = entityData['consumptionExperienceTrait'];
      if (consumption is Map) {
        final duration = consumption['duration'];
        if (duration is Map) {
          final seconds = duration['seconds'];
          if (seconds is num) {
            totalMs = (seconds * 1000).round();
          }
        }
      }

      // Cover: squareCoverImage.image.data.sources[0], then
      // squareCoverImage.originalInstances[0].flatFile.cdnUrl.
      String cover = '';
      final vit = entityData['visualIdentityTrait'];
      if (vit is Map) {
        final square = vit['squareCoverImage'];
        if (square is Map) {
          final image = square['image'];
          if (image is Map) {
            final data = image['data'];
            if (data is Map) {
              final sources = data['sources'];
              if (sources is List && sources.isNotEmpty) {
                final first = sources.first;
                if (first is Map) {
                  cover = first['url']?.toString() ?? '';
                }
              }
            }
          }
          if (cover.isEmpty) {
            final originals = square['originalInstances'];
            if (originals is List && originals.isNotEmpty) {
              final first = originals.first;
              if (first is Map) {
                final flat = first['flatFile'];
                if (flat is Map) {
                  cover = flat['cdnUrl']?.toString() ?? '';
                }
              }
            }
          }
        }
      }

      final id = uri.replaceAll('spotify:track:', '');
      songs.add({
        'videoId': id,
        'title': name,
        'artist': artistNames.isEmpty ? 'Unknown Artist' : artistNames.join(', '),
        'artists': [
          for (final n in artistNames) {'name': n},
        ],
        'thumbnails': [
          {'url': cover},
        ],
        'duration': Duration(milliseconds: totalMs),
        'album': {'name': albumName},
        'spotifyUri': uri,
        'type': 'SPOTIFY',
      });
    }

    _log('${songs.length} recents');
    return songs.take(limit).toList();
  }

  void dispose() => _client.close();
}