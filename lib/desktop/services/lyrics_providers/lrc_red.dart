// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — LrcRed.kt

import 'dart:convert';
import 'dart:io';

import 'lyric_doc.dart';

/// lrc.red: Apple Music TTML (per syllable), filed by ISRC at
/// `https://lrc.red/s/{ISRC}.ttml`. Without an ISRC the free-text search
/// (`/search.json?q=`) is asked and the hits are matched strictly (title,
/// version words, artist, duration) rather than trusted in order.
class LrcRed {
  LrcRed._();

  static const String _base = 'https://lrc.red/';
  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  /// How far a hit's length may be from the playing track's, in seconds.
  static const double _durationTolerance = 3.0;

  static final RegExp _isrcRe = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$');
  static final RegExp _bracketed = RegExp(r'[(\[][^)\]]*[)\]]');
  static final RegExp _combining = RegExp(r'[̀-ͯ]+');
  static final RegExp _nonAlnum = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _artistSeparators = RegExp(
    r'\s*(?:,|&|;|/|\s+and\s+|\s+x\s+|\s+with\s+|\s+feat\.?\s+|\s+ft\.?\s+)\s*',
    caseSensitive: false,
  );
  static final RegExp _spanBegin = RegExp(
    r'<(?:[a-zA-Z0-9_-]+:)?span\b[^>]*\bbegin\s*=',
    caseSensitive: false,
  );

  /// Bracket words that make it a different recording, not a different label.
  static const Set<String> _versionWords = <String>{
    'live', 'remix', 'remixed', 'mix', 'acoustic', 'unplugged',
    'instrumental', 'karaoke', 'cappella', 'acapella', 'demo', 'edit',
    'version', 'cover', 'sped', 'slowed', 'reverb', 'nightcore', 'lofi',
    'orchestral', 'extended',
  };

  static const List<String> _foldFrom = <String>[
    'àáâãäåāăą', 'çćĉċč', 'ďđ', 'èéêëēĕėęě', 'ĝğġģ', 'ĥħ', 'ìíîïĩīĭįı',
    'ĵ', 'ķ', 'ĺļľŀł', 'ñńņňŉ', 'òóôõöøōŏő', 'ŕŗř', 'śŝşš', 'ţťŧ',
    'ùúûüũūŭůűų', 'ŵ', 'ýÿŷ', 'źżž',
  ];
  static const List<String> _foldTo = <String>[
    'a', 'c', 'd', 'e', 'g', 'h', 'i', 'j', 'k', 'l', 'n', 'o', 'r', 's', 't',
    'u', 'w', 'y', 'z',
  ];
  static Map<String, String>? _foldMap;

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[lrc_red] $m');

  /// Never throws. Null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final known = documentUrl(q.isrc ?? '');
      if (known != null) {
        final doc = await _document(known);
        if (doc != null) return doc;
      }
      if (q.title.trim().isEmpty) return null;

      // A known recording lrc.red doesn't have still gets a search: the same
      // song is often catalogued under a sibling release's code.
      final hit = await _search(q.title, q.artist, q.durationMs ?? 0);
      if (hit == null) return null;
      final found = documentUrl(hit['isrc']?.toString() ?? '');
      if (found == null || found == known) return null;
      return await _document(found);
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  /// `https://lrc.red/s/{ISRC}.ttml`, or null when [isrc] is not an ISRC.
  static String? documentUrl(String isrc) {
    final s = isrc.trim().replaceAll('-', '').toUpperCase();
    if (!_isrcRe.hasMatch(s)) return null;
    return '${_base}s/$s.ttml';
  }

  static Future<LyricDoc?> _document(String url) async {
    final body = await _get(url);
    if (body == null) return null;
    final text = body.replaceAll('﻿', '').trim();
    final lower = text.toLowerCase();
    if (!lower.contains('<tt') && !lower.contains('<p')) return null;
    if (!RegExp(r'<(?:[a-zA-Z0-9_-]+:)?p\b[^>]*\bbegin\s*=',
            caseSensitive: false)
        .hasMatch(text)) {
      return null;
    }
    final word = _spanBegin.hasMatch(text);
    return LyricDoc(payload: text, wordSynced: word, lineSynced: !word);
  }

  static Future<Map<dynamic, dynamic>?> _search(
      String title, String artist, int durationMs) async {
    final uri = Uri.parse('${_base}search.json').replace(
      queryParameters: <String, String>{'q': '$title $artist'.trim()},
    );
    final body = await _get(uri.toString());
    if (body == null) return null;
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final hits = json['hits'];
    if (hits is! List) return null;
    final list = <Map<dynamic, dynamic>>[];
    for (final h in hits) {
      if (h is Map) list.add(h);
    }
    return _best(list, title, artist, durationMs);
  }

  /// The hit that is this recording, or null if none of them is sure to be.
  static Map<dynamic, dynamic>? _best(
    List<Map<dynamic, dynamic>> hits,
    String title,
    String artist,
    int durationMs,
  ) {
    final wantedTitle = _coreOf(title);
    final wantedVersion = _versionOf(title);
    final wantedArtists = _artistsOf(artist);
    final seconds = durationMs / 1000.0;

    double distance(Map<dynamic, dynamic> hit) {
      final d = _toDouble(hit['duration']);
      if (durationMs > 0 && d != null) return (d - seconds).abs();
      return 0.0;
    }

    Map<dynamic, dynamic>? best;
    var bestDistance = 0.0;
    for (final hit in hits) {
      final name = hit['title'];
      if (name is! String) continue;
      if (documentUrl(hit['isrc']?.toString() ?? '') == null) continue;
      if (_coreOf(name) != wantedTitle) continue;
      if (!_sameSet(_versionOf(name), wantedVersion)) continue;
      if (wantedArtists.isNotEmpty) {
        final theirs = _artistsOf(hit['artist']?.toString() ?? '');
        if (!theirs.any((a) => wantedArtists.contains(a))) continue;
      }
      final d = distance(hit);
      if (d > _durationTolerance) continue;
      if (best == null || d < bestDistance) {
        best = hit;
        bestDistance = d;
      }
    }
    return best;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// "Song (Live) - 2011 Remaster" -> "song".
  static String _coreOf(String title) {
    var head = title.replaceAll(_bracketed, ' ');
    final dash = head.indexOf(' - ');
    if (dash >= 0) head = head.substring(0, dash);
    final n = _normalized(head);
    return n.isEmpty ? _normalized(title) : n;
  }

  /// The version words in the parts [_coreOf] throws away.
  static Set<String> _versionOf(String title) {
    final extras = StringBuffer();
    for (final m in _bracketed.allMatches(title)) {
      extras.write(m.group(0));
      extras.write(' ');
    }
    final dash = title.indexOf(' - ');
    if (dash >= 0) extras.write(title.substring(dash + 3));
    final out = <String>{};
    for (final w in _normalized(extras.toString()).split(' ')) {
      if (_versionWords.contains(w)) out.add(w);
    }
    return out;
  }

  static Set<String> _artistsOf(String artist) {
    final out = <String>{};
    for (final part in artist.split(_artistSeparators)) {
      final n = _normalized(part);
      if (n.isNotEmpty) out.add(n);
    }
    return out;
  }

  /// Lower case, accents off ("ROSE" with an acute is "rose"), and only
  /// letters and digits.
  static String _normalized(String value) {
    var map = _foldMap;
    if (map == null) {
      map = <String, String>{};
      for (var i = 0; i < _foldFrom.length; i++) {
        for (final rune in _foldFrom[i].runes) {
          map[String.fromCharCode(rune)] = _foldTo[i];
        }
      }
      _foldMap = map;
    }
    final lowered = value.replaceAll(_combining, '').toLowerCase();
    final buf = StringBuffer();
    for (final rune in lowered.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(map[ch] ?? ch);
    }
    return buf
        .toString()
        .replaceAll(_nonAlnum, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  static Future<String?> _get(String url) async {
    try {
      final req = await _client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.acceptHeader,
          'application/json, application/xml, text/plain, */*');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Drain the error body so the socket is not pinned.
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _log('GET failed ($url): $e');
      return null;
    }
  }
}
