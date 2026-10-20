// ZenMusic — Spotify Color Lyrics (SP-10).
// Fetches native Spotify lyrics (including custom background/highlight colors)
// from the color-lyrics/v2 endpoint. Ported from Stopify's SpotifyLyricsService.
// Reuses the web-player access token and client-token.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyLyricLine {
  final int startTimeMs;
  final String words;
  final int endTimeMs;

  SpotifyLyricLine({
    required this.startTimeMs,
    required this.words,
    required this.endTimeMs,
  });
}

class SpotifyColorLyrics {
  final String syncType; // e.g., "LINE_SYNCED" or "UNSYNCED"
  final List<SpotifyLyricLine> lines;
  final int backgroundColor;
  final int textColor;
  final int highlightTextColor;
  final String providerDisplayName;

  SpotifyColorLyrics({
    required this.syncType,
    required this.lines,
    required this.backgroundColor,
    required this.textColor,
    required this.highlightTextColor,
    required this.providerDisplayName,
  });
}

class SpotifyLyricsService {
  SpotifyLyricsService._();
  static final SpotifyLyricsService instance = SpotifyLyricsService._();

  final Map<String, SpotifyColorLyrics> _cache = {};

  SpotifyColorLyrics? getCachedLyrics(String trackIdOrUri) {
    final cleanId = trackIdOrUri.split(':').last;
    return _cache[cleanId];
  }

  Future<SpotifyColorLyrics?> fetchColorLyrics(
      String trackIdOrUri, {
        String? coverUrl,
      }) async {
    final cleanId = trackIdOrUri.split(':').last;
    if (_cache.containsKey(cleanId)) return _cache[cleanId];

    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      debugPrint('[spotify-lyrics] no access token');
      return null;
    }
    final clientToken = await SpotifyAuth.instance.getClientToken();

    try {
      final encodedCover = coverUrl != null && coverUrl.isNotEmpty
          ? Uri.encodeComponent(coverUrl)
          : '';

      final String urlStr;
      if (encodedCover.isNotEmpty) {
        urlStr =
        'https://spclient.wg.spotify.com/color-lyrics/v2/track/$cleanId/image/$encodedCover?format=json&vocalRemoval=false&market=from_token';
      } else {
        urlStr =
        'https://spclient.wg.spotify.com/color-lyrics/v2/track/$cleanId?format=json&vocalRemoval=false&market=from_token';
      }

      debugPrint('[spotify-lyrics] fetching $urlStr');

      final r = await http.get(
        Uri.parse(urlStr),
        headers: {
          'authorization': 'Bearer $token',
          'client-token': clientToken,
          'accept': 'application/json',
          'accept-language': 'en',
          'app-platform': SpotifyConfig.appPlatform,
          'spotify-app-version': SpotifyConfig.spotifyAppVersion,
          'referer': 'https://open.spotify.com/',
          'origin': 'https://open.spotify.com',
          'user-agent': SpotifyConfig.userAgent,
        },
      ).timeout(const Duration(seconds: 12));

      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('[spotify-lyrics] HTTP ${r.statusCode}: ${r.body}');
        return null;
      }

      final json = jsonDecode(r.body) as Map<String, dynamic>;
      final lyricsObj = json['lyrics'] as Map<String, dynamic>?;
      final colorsObj = json['colors'] as Map<String, dynamic>?;

      if (lyricsObj == null) return null;

      final syncType = lyricsObj['syncType']?.toString() ?? 'UNSYNCED';
      final linesArray = lyricsObj['lines'] as List<dynamic>?;
      final linesList = <SpotifyLyricLine>[];

      if (linesArray != null) {
        for (final item in linesArray) {
          final lineItem = item as Map<String, dynamic>;
          final startTimeMs = int.tryParse(lineItem['startTimeMs']?.toString() ?? '0') ?? 0;
          final endTimeMs = int.tryParse(lineItem['endTimeMs']?.toString() ?? '0') ?? 0;
          final words = lineItem['words']?.toString() ?? '';
          linesList.add(SpotifyLyricLine(
            startTimeMs: startTimeMs,
            words: words,
            endTimeMs: endTimeMs,
          ));
        }
      }

      final colorLyrics = SpotifyColorLyrics(
        syncType: syncType,
        lines: linesList,
        backgroundColor: colorsObj?['background'] as int? ?? 0xFF000000,
        textColor: colorsObj?['text'] as int? ?? 0xFFFFFFFF,
        highlightTextColor: colorsObj?['highlightText'] as int? ?? 0xFF1DB954, // Spotify Green fallback
        providerDisplayName: lyricsObj['providerDisplayName']?.toString() ?? 'Musixmatch',
      );

      debugPrint(
          '[spotify-lyrics] fetched ${linesList.length} lines, syncType: $syncType');
      _cache[cleanId] = colorLyrics;
      return colorLyrics;
    } catch (e) {
      debugPrint('[spotify-lyrics] error: $e');
      return null;
    }
  }
}