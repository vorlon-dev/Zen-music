// Parses a PUBLIC Apple Music playlist/album page into [{title, artist}].
import 'dart:convert';
import 'package:http/http.dart' as http;

class AppleMusicPlaylist {
  static Future<({String name, List<Map<String, String>> tracks})> fetch(String url) async {
    final r = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('Apple Music returned ${r.statusCode}');

    // Public pages embed schema.org JSON-LD with the track list.
    final re = RegExp(r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', dotAll: true);
    for (final m in re.allMatches(r.body)) {
      try {
        final j = jsonDecode(m.group(1)!);
        final obj = j is List ? j.firstWhere((e) => e is Map && e['track'] != null, orElse: () => null) : j;
        if (obj is! Map || obj['track'] is! List) continue;
        final tracks = <Map<String, String>>[];
        for (final t in obj['track'] as List) {
          if (t is! Map) continue;
          final by = t['byArtist'];
          final artist = by is List && by.isNotEmpty ? (by.first['name'] ?? '') : (by is Map ? (by['name'] ?? '') : '');
          if ((t['name'] ?? '').toString().isEmpty) continue;
          tracks.add({'title': t['name'].toString(), 'artist': artist.toString()});
        }
        if (tracks.isNotEmpty) {
          return (name: (obj['name'] ?? 'Apple Music Import').toString(), tracks: tracks);
        }
      } catch (_) {}
    }
    throw Exception('No tracks found. Is the playlist public?');
  }
}
