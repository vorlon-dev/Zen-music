// ZenMusic — SP-68: Song DNA — the backstory of the track that is playing.
//
// A song's "DNA" is three strands of text, resolved live:
//   1. Movie / Album    — which release the track belongs to
//   2. About the Song   — what the song is about (short encyclopedia
//                         extract, disambiguation-guarded)
//   3. About the Artist — a short artist biography
//
// Resolution order (each strand degrades independently, never throws):
//   * Genius public web API (no key): /api/search/multi → /api/songs/<id>
//     → /api/artists/<id> — album name + artist description.
//   * Wikipedia API (no key): action=query&list=search →
//     action=query&prop=extracts&exsentences=4&explaintext=1 — song
//     meaning, and the artist bio when Genius has none. Results that
//     "may refer to" a disambiguation page are rejected.
//   * Local metadata (the playing card's album) is the last resort.
//
// ZERO new pubspec deps (package:http, dart:convert, dart:async — all
// present). Debug prints use the [song-dna] prefix.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/services/lyrics_service.dart';

class SongDnaInfo {
  final String album;
  final String meaning;
  final String bio;

  const SongDnaInfo({
    required this.album,
    required this.meaning,
    required this.bio,
  });
}

class SongDna {
  SongDna._();

  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  /// Tiny per-track cache so reopening the sheet for the same song does
  /// not re-hit the network. Bounded — the oldest entries fall out.
  static final Map<String, SongDnaInfo> _cache = {};
  static const int _cacheMax = 12;
  static Future<SongDnaInfo>? _inflight;

  /// Extracts (title, artist, album) from the track map shapes the app
  /// actually produces: YouTube items carry `artists` (list) + `album`
  /// (map), Spotify items carry plain `artist` / `album` strings.
  static (String, String, String) idsFromSong(Map song) {
    String album = '';
    final albumField = song['album'];
    if (albumField is Map) album = albumField['name']?.toString() ?? '';
    if (albumField is String) album = albumField;

    String artist = '';
    final artists = song['artists'];
    if (artists is List && artists.isNotEmpty) {
      final first = artists.first;
      if (first is Map) artist = first['name']?.toString() ?? '';
    }
    if (artist.isEmpty && song['artist'] is String) {
      artist = song['artist'] as String;
    }
    if (artist.isEmpty) {
      // "Artist • Album • Year" — the subtitle's first run.
      final subtitle = song['subtitle']?.toString() ?? '';
      artist = subtitle.split('•').first.trim();
    }
    return (song['title']?.toString() ?? '', artist, album);
  }

  /// Main entry. Never throws — every failure lands in a friendly
  /// placeholder the dialog can show.
  static Future<SongDnaInfo> fetch({
    required String title,
    required String artist,
    String? album,
  }) {
    final clean = MetadataCleaner.clean(title, artist);
    final key = '${clean.primaryArtist.toLowerCase()}|'
        '${clean.cleanTitle.toLowerCase()}';
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    // One flight at a time (the dialog is modal anyway).
    final existing = _inflight;
    if (existing != null) return existing;
    final fut = _fetchImpl(clean.cleanTitle, clean.primaryArtist, album)
        .whenComplete(() => _inflight = null);
    _inflight = fut;
    return fut;
  }

  static Future<SongDnaInfo> _fetchImpl(
      String title, String artist, String? album) async {
    // Placeholders — the exact strings the dialog renders while a strand
    // is unresolved.
    var dnaAlbum = album?.trim().isNotEmpty == true ? album!.trim() : '';
    var meaning = '';
    var bio = '';

    String geniusSongId = '';
    String geniusArtistId = '';

    // ── 1. Genius: search → song → artist ─────────────────────────────
    try {
      final q = Uri.encodeQueryComponent('$artist $title');
      final searchBody = await _getJson('https://genius.com/api/search'
          '/multi?q=$q');
      final sections = (searchBody?['response']?['sections'] as List?) ??
          const [];
      for (final section in sections) {
        if (section is! Map) continue;
        final type = section['type']?.toString();
        if (type != 'song' && type != 'top_hit') continue;
        final hits = (section['hits'] as List?) ?? const [];
        for (final hit in hits) {
          final result = (hit as Map?)?['result'];
          if (result is Map && result['id'] != null) {
            geniusSongId = result['id'].toString();
            break;
          }
        }
        if (geniusSongId.isNotEmpty) break;
      }
    } catch (e) {
      debugPrint('[song-dna] genius search failed: $e');
    }

    if (geniusSongId.isNotEmpty) {
      try {
        final songBody =
            await _getJson('https://genius.com/api/songs/$geniusSongId'
                '?text_format=plain');
        final song = songBody?['response']?['song'];
        if (song is Map) {
          final gAlbum = song['album'];
          if (gAlbum is Map && (gAlbum['name']?.toString() ?? '').isNotEmpty) {
            dnaAlbum = gAlbum['name'].toString();
          }
          final gArtist = song['primary_artist'];
          if (gArtist is Map && gArtist['id'] != null) {
            geniusArtistId = gArtist['id'].toString();
          }
        }
      } catch (e) {
        debugPrint('[song-dna] genius song failed: $e');
      }
      if (geniusArtistId.isNotEmpty) {
        try {
          final artistBody = await _getJson(
              'https://genius.com/api/artists/$geniusArtistId'
              '?text_format=plain');
          final desc = ((artistBody?['response']?['artist']
                      as Map?)?['description'] as Map?)?['plain'] ??
              '';
          final text = desc.toString().trim();
          if (text.isNotEmpty && text != '?') bio = text;
        } catch (e) {
          debugPrint('[song-dna] genius artist failed: $e');
        }
      }
    }

    // ── 2. Wikipedia: song meaning (always attempted) ─────────────────
    try {
      final extract = await _wikiExtract('$title $dnaAlbum');
      if (extract != null) meaning = extract;
    } catch (e) {
      debugPrint('[song-dna] wiki song failed: $e');
    }

    // ── 3. Wikipedia: artist bio fallback ─────────────────────────────
    if (bio.isEmpty && artist.trim().isNotEmpty) {
      try {
        final extract = await _wikiExtract(artist);
        if (extract != null) bio = extract;
      } catch (e) {
        debugPrint('[song-dna] wiki artist failed: $e');
      }
    }

    final info = SongDnaInfo(
      album: dnaAlbum,
      meaning: meaning,
      bio: bio,
    );
    if (_cache.length >= _cacheMax) _cache.remove(_cache.keys.first);
    _cache['${artist.toLowerCase()}|$title'] = info;
    return info;
  }

  /// Wikipedia search → 4-sentence plain extract of the top hit. Returns
  /// null when the hit is a disambiguation page ("may refer to") or the
  /// extract is empty.
  static Future<String?> _wikiExtract(String query) async {
    final searchUri = Uri.parse('https://en.wikipedia.org/w/api.php')
        .replace(queryParameters: {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'utf8': '1',
      'format': 'json',
    });
    final search = await _getJson(searchUri.toString());
    final hits = ((search?['query']?['search'] as List?) ?? const []);
    if (hits.isEmpty) return null;
    final pageTitle = ((hits.first as Map)['title'] as String?) ?? '';
    if (pageTitle.isEmpty) return null;

    final extractUri = Uri.parse('https://en.wikipedia.org/w/api.php')
        .replace(queryParameters: {
      'action': 'query',
      'prop': 'extracts',
      'exsentences': '4',
      'exlimit': '1',
      'titles': pageTitle,
      'explaintext': '1',
      'format': 'json',
    });
    final page = await _getJson(extractUri.toString());
    final pages = (page?['query']?['pages'] as Map?) ?? const {};
    if (pages.isEmpty) return null;
    final extract = ((pages.values.first as Map)['extract'] as String?) ?? '';
    final text = extract.trim();
    if (text.isEmpty || text.contains('may refer to')) return null;
    return text;
  }

  static Future<Map?> _getJson(String url) async {
    try {
      final resp = await http.get(Uri.parse(url), headers: {
        'User-Agent': _ua,
        'accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[song-dna] HTTP ${resp.statusCode} from '
            '${Uri.parse(url).host}');
        return null;
      }
      return jsonDecode(resp.body) as Map;
    } catch (e) {
      debugPrint('[song-dna] $url failed: $e');
      return null;
    }
  }
}
