import 'dart:convert';

import 'package:http/http.dart' as http;

/// Artwork upgrades: converts YouTube video thumbnails (16:9) into
/// proper square album covers and raises resolution.
///
/// YouTube serves square crops of any thumbnail by swapping the filename
/// (hq720 → hq1200 etc. keeps aspect, but the music catalog exposes
/// square crops through the "maxresdefault"-style names). For songs
/// resolved from YTMusic, the thumbnails already carry the square crop
/// in the "w1200-h1200"-style URLs — this service rewrites those, and
/// probes candidates so a broken variant never ships to the UI.
class ArtworkService {
  ArtworkService._();
  static final ArtworkService instance = ArtworkService._();

  final http.Client _client = http.Client();
  final Map<String, String> _cache = {};

  /// Returns the best square, high-quality artwork URL for a song.
  /// [rawUrl] is whatever thumbnail the catalog entry carried.
  Future<String> squareArt(String rawUrl, String songId) async {
    final key = '$rawUrl|$songId';
    final hit = _cache[key];
    if (hit != null) return hit;

    String candidate = rawUrl;

    // YTMusic catalog URLs sometimes embed a rectangle size — rewrite
    // to the square variant YouTube generates for music covers.
    candidate = candidate
        .replaceAll(RegExp(r'w\d+-h\d+'), 'w1200-h1200')
        .replaceAll(RegExp(r'=w\d+-h\d+.*$'), '=w1200-h1200');

    // Generic YouTube thumbnail upgrade: use maxres for quality.
    if (candidate.contains('i.ytimg.com')) {
      candidate = 'https://i.ytimg.com/vi/$songId/maxresdefault.jpg';
    }

    // Probe: the square/maxres variant may not exist. Fall back down a
    // quality ladder until one answers 200.
    final url = await _firstWorking([
      candidate,
      if (candidate.contains('i.ytimg.com')) ...[
        'https://i.ytimg.com/vi/$songId/sddefault.jpg',
        'https://i.ytimg.com/vi/$songId/hq720.jpg',
      ],
      rawUrl,
    ]);

    _cache[key] = url;
    return url;
  }

  Future<String> _firstWorking(List<String> urls) async {
    for (final url in urls) {
      if (url.isEmpty) continue;
      try {
        final resp = await _client
            .head(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) return url;
      } catch (_) {}
    }
    return urls.isNotEmpty ? urls.last : '';
  }

  void dispose() => _client.close();
}