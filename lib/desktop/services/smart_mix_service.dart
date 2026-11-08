// Smart Mix, Genre DNA, weekly recap, discovery. Reads local Hive history;
// heavy math runs in an isolate so the UI thread is never blocked.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:zenmusic/desktop/services/lastfm_service.dart' show kLastfmApiKey;

String _artistOf(Map s) {
  final a = s['artists'] ?? s['artist'] ?? s['subtitle'];
  if (a is List && a.isNotEmpty) {
    final f = a.first;
    return (f is Map ? f['name'] : f).toString();
  }
  if (a is Map) return (a['name'] ?? '').toString();
  return (a ?? '').toString().split(RegExp(r'[,•&]')).first.trim();
}

// ---- isolate workers: only plain data in / out ----
List<Map> _rankWorker(Map args) {
  final hist = (args['hist'] as List).cast<Map>();
  final favs = (args['favs'] as List).cast<String>().toSet();
  final n = args['n'] as int;
  final now = DateTime.now().millisecondsSinceEpoch;
  final scored = <MapEntry<Map, double>>[];
  for (final s in hist) {
    final plays = (s['plays'] as num?)?.toDouble() ?? 1;
    final ageDays = (now - ((s['updatedAt'] as num?)?.toInt() ?? now)) / 86400000;
    final recency = 1 / (1 + ageDays / 14); // half-weight after ~2 weeks
    final love = favs.contains(s['videoId']) ? 2.5 : 1.0;
    scored.add(MapEntry(s, plays * (0.4 + recency) * love));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  // limit 2 songs per artist so the mix stays varied
  final perArtist = <String, int>{};
  final out = <Map>[];
  for (final e in scored) {
    final a = _artistOf(e.key);
    if ((perArtist[a] = (perArtist[a] ?? 0) + 1) > 2) continue;
    out.add(e.key);
    if (out.length >= n) break;
  }
  return out;
}

Map _recapWorker(Map args) {
  final hist = (args['hist'] as List).cast<Map>();
  final since = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
  final artists = <String, int>{};
  var songs = 0;
  for (final s in hist) {
    if (((s['updatedAt'] as num?)?.toInt() ?? 0) < since) continue;
    songs++;
    final a = _artistOf(s);
    if (a.isNotEmpty) artists[a] = (artists[a] ?? 0) + ((s['plays'] as num?)?.toInt() ?? 1);
  }
  final top = artists.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {'songs': songs, 'topArtists': top.take(5).map((e) => {'name': e.key, 'plays': e.value}).toList()};
}

class SmartMixService {
  SmartMixService._();
  static final SmartMixService instance = SmartMixService._();

  List<Map> _history() => Hive.box('SONG_HISTORY')
      .values
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();

  /// Ranked playable songs (same maps the player already understands).
  Future<List<Map>> smartMix({int size = 40}) {
    final favs = Hive.box('FAVOURITES').keys.map((e) => e.toString()).toList();
    return compute(_rankWorker, {'hist': _history(), 'favs': favs, 'n': size});
  }

  /// Weekly listening recap: song count + top artists.
  Future<Map> weeklyRecap() => compute(_recapWorker, {'hist': _history()});

  // ---- Last.fm read-only calls (public data, no login needed) ----
  Future<Map?> _lfm(String method, Map<String, String> p) async {
    try {
      final r = await http
          .get(Uri.https('ws.audioscrobbler.com', '/2.0/',
              {'method': method, 'api_key': kLastfmApiKey, 'format': 'json', ...p}))
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 200 ? jsonDecode(r.body) as Map : null;
    } catch (_) {
      return null;
    }
  }

  /// Genre DNA: tag share across the user's top artists. Cached in Hive.
  Future<Map<String, double>> genreDna({int artistCount = 8}) async {
    final box = await Hive.openBox('genre_dna_cache');
    final recap = await weeklyRecap();
    final tops = (recap['topArtists'] as List).take(artistCount).cast<Map>();
    final counts = <String, double>{};
    for (final a in tops) {
      final name = a['name'] as String;
      List<String>? tags = (box.get(name) as List?)?.cast<String>();
      if (tags == null) {
        final r = await _lfm('artist.getTopTags', {'artist': name});
        final list = (r?['toptags']?['tag'] as List?) ?? const [];
        tags = list.take(4).map((t) => (t['name'] as String).toLowerCase()).toList();
        if (tags.isNotEmpty) await box.put(name, tags);
      }
      for (final t in tags) {
        counts[t] = (counts[t] ?? 0) + (a['plays'] as int);
      }
    }
    final total = counts.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return {};
    return {for (final e in counts.entries) e.key: e.value / total};
  }

  /// Discovery: similar artists to the user's top ones, minus ones already heard.
  Future<List<String>> discoverArtists({int limit = 15}) async {
    final recap = await weeklyRecap();
    final known = _history().map(_artistOf).toSet();
    final out = <String>{};
    for (final a in (recap['topArtists'] as List).take(3).cast<Map>()) {
      final r = await _lfm('artist.getSimilar', {'artist': a['name'] as String, 'limit': '10'});
      for (final s in (r?['similarartists']?['artist'] as List? ?? const [])) {
        final n = s['name'] as String;
        if (!known.contains(n)) out.add(n);
      }
    }
    return out.take(limit).toList();
  }

  /// Your Last.fm friends and what each one played last (max [limit] friends).
  Future<List<Map<String, dynamic>>> friendsFeed(String user, {int limit = 20}) async {
    final r = await _lfm('user.getFriends', {'user': user, 'limit': '$limit', 'recenttracks': '1'});
    final friends = (r?['friends']?['user'] as List?) ?? const [];
    return friends.map<Map<String, dynamic>>((f) {
      final rt = f['recenttrack'];
      final t = rt is List ? (rt.isEmpty ? null : rt.first) : rt;
      final images = (f['image'] as List?) ?? const [];
      return {
        'name': (f['name'] ?? '').toString(),
        'url': (f['url'] ?? '').toString(),
        'image': images.isEmpty ? '' : (images.last['#text'] ?? '').toString(),
        'artist': (t?['artist']?['#text'] ?? '').toString(),
        'track': (t?['name'] ?? '').toString(),
        'nowPlaying': t?['@attr']?['nowplaying'] == 'true',
      };
    }).toList();
  }

  /// Friend feed (Last.fm). Returns [{artist, track}]
  Future<List<Map>> friendRecent(String user) async {
    final r = await _lfm('user.getRecentTracks', {'user': user, 'limit': '10'});
    final tracks = (r?['recenttracks']?['track'] as List?) ?? const [];
    return tracks
        .map((t) => {'artist': t['artist']?['#text'] ?? '', 'track': t['name'] ?? ''})
        .toList();
  }
}
