// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — PaxSenix.kt

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'lyric_doc.dart';

class _PaxCandidate {
  const _PaxCandidate(this.id, this.title, this.artist, this.durationMs);
  final String id;
  final String title;
  final String artist;
  final int durationMs;
}

/// PaxSenix: Apple Music lyrics through the keyless public proxy
/// (`lyrics.paxsenix.org/apple-music/lyrics`, the track found via Apple's own
/// catalogue search with a scraped web-player token), plus optional
/// authenticated routes (`api.paxsenix.org`: Spotify, Musixmatch, lrcget)
/// that are skipped unless [apiKey] is set.
///
/// Structured Apple payloads (per-syllable stamps) are converted into
/// karaoke rows `[start,dur](wStart,wDur)text`; TTML, karaoke, LRC and plain
/// text responses pass through as they are.
class PaxSenix {
  PaxSenix._();

  /// Optional PaxSenix API key for the authenticated routes. Leave null to
  /// use the keyless Apple route only.
  static String? apiKey;

  static const String _api = 'https://api.paxsenix.org';
  static const String _publicProxy = 'https://lyrics.paxsenix.org';
  static const String _appleSearch =
      'https://amp-api.music.apple.com/v1/catalog/us/search';
  static const int _minimumMatchScore = 10;
  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  static const List<String> _idKeys = <String>[
    'id', 'trackId', 'track_id', 'realId',
  ];
  static const List<String> _titleKeys = <String>[
    'name', 'title', 'trackName', 'track_name',
  ];
  static const List<String> _artistKeys = <String>[
    'artistName', 'artist_name',
  ];
  static const List<String> _durationKeys = <String>[
    'durationInMillis', 'durationMs', 'duration_ms', 'duration',
  ];
  static const List<String> _contentKeys = <String>[
    'ttml', 'ttmlContent', 'lyrics', 'lrc', 'content', 'text',
    'plainLyrics', 'syncedLyrics', 'line', 'lines', 'lyric',
    'data', 'result', 'response',
  ];

  static final RegExp _appleIndexScript = RegExp(r'/assets/index~[^"]+\.js');
  static final RegExp _appleToken = RegExp(
      r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
  static final RegExp _ttmlRoot = RegExp(r'<tt(?:\s|>)', caseSensitive: false);
  static final RegExp _spanBegin = RegExp(
    r'<(?:[a-zA-Z0-9_-]+:)?span\b[^>]*\bbegin\s*=',
    caseSensitive: false,
  );
  static final RegExp _karaokeRow = RegExp(
      r'^\s*\[\d{1,8},\d{1,8}\].*\(\d{1,8},\d{1,8}(?:,\d{1,8})?\)',
      multiLine: true);
  static final RegExp _wordStamp = RegExp(r'<\d{1,3}:\d{2}[.:]\d{2,3}>');
  static final RegExp _lineStamp =
      RegExp(r'^\s*\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]', multiLine: true);
  static final RegExp _metaTag = RegExp(r'^\[[A-Za-z]+:.*\]$');
  static final RegExp _errorWords = RegExp(
      r'\b(?:lyrics? (?:not found|unavailable)|error)\b',
      caseSensitive: false);

  static String? _cachedAppleToken;

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[paxsenix] $m');

  /// Never throws. Null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final title = q.title.trim();
      final artist = q.artist.trim();
      if (title.isEmpty) return null;
      final dur = q.durationMs ?? 0;

      LyricDoc? fallback;

      LyricDoc? consider(LyricDoc? doc) {
        if (doc == null) return null;
        if (doc.wordSynced) return doc;
        final f = fallback;
        if (f == null || (f.isPlain && !doc.isPlain)) fallback = doc;
        return null;
      }

      // 1. Keyless Apple Music route.
      final apple = consider(await _appleLyrics(title, artist, dur));
      if (apple != null) return apple;

      // 2. Authenticated routes, only with a key.
      if (_key() != null) {
        final spotify = consider(await _spotifyLyrics(title, artist, dur));
        if (spotify != null) return spotify;
        final mxm = consider(await _musixmatchLyrics(title, artist, dur));
        if (mxm != null) return mxm;
      }
      return fallback;
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static String? _key() {
    final k = apiKey?.trim() ?? '';
    if (k.isEmpty) return null;
    if (k.toLowerCase().startsWith('bearer ')) {
      final stripped = k.substring(7).trim();
      return stripped.isEmpty ? null : stripped;
    }
    return k;
  }

  // ---------------------------------------------------------------------
  // Routes
  // ---------------------------------------------------------------------

  static Future<LyricDoc?> _appleLyrics(
      String title, String artist, int durationMs) async {
    final id = await _searchPublicAppleTrackId(title, artist, durationMs);
    if (id == null) return null;
    final uri = Uri.parse('$_publicProxy/apple-music/lyrics').replace(
      queryParameters: <String, String>{'id': id, 'ttml': 'true'},
    );
    final body = await _get(uri.toString());
    if (body == null) return null;
    return _parseResponse(body);
  }

  static Future<LyricDoc?> _spotifyLyrics(
      String title, String artist, int durationMs) async {
    final id = await _searchTrackId('spotify/search', title, artist, durationMs);
    if (id != null) {
      final body = await _apiBody(
          _apiUrl('lyrics/spotify', <String, String>{'id': id}));
      if (body != null) {
        final doc = _parseResponse(body);
        if (doc != null) return doc;
      }
    }
    return _genericAuthenticatedLyrics(title, artist, durationMs);
  }

  static Future<LyricDoc?> _musixmatchLyrics(
      String title, String artist, int durationMs) async {
    final body = await _apiBody(_apiUrl('lyrics/musixmatch', <String, String>{
      't': title,
      'a': artist,
      'd': (durationMs ~/ 1000).toString(),
    }));
    if (body != null) {
      final doc = _parseResponse(body);
      if (doc != null) return doc;
    }
    return _genericAuthenticatedLyrics(title, artist, durationMs);
  }

  static Future<String?> _searchPublicAppleTrackId(
      String title, String artist, int durationMs) async {
    final token = await _appleToken_();
    if (token == null) return null;
    final uri = Uri.parse(_appleSearch).replace(queryParameters: <String, String>{
      'term': '$title $artist',
      'types': 'songs',
      'limit': '10',
      'l': 'en-US',
    });
    final body = await _get(uri.toString(), headers: <String, String>{
      'Authorization': 'Bearer $token',
      'Origin': 'https://music.apple.com',
      'Referer': 'https://music.apple.com/',
    });
    if (body == null) return null;
    final root = _decode(body);
    if (root == null) return null;
    return _bestCandidate(root, title, artist, durationMs)?.id;
  }

  static Future<String?> _appleToken_() async {
    final cached = _cachedAppleToken;
    if (cached != null) return cached;
    final page = await _get('https://music.apple.com/us/new');
    if (page == null) return null;
    final scriptPath = _appleIndexScript.firstMatch(page)?.group(0);
    if (scriptPath == null) return null;
    final script = await _get('https://music.apple.com$scriptPath');
    if (script == null) return null;
    final token = _appleToken.firstMatch(script)?.group(0);
    if (token != null) _cachedAppleToken = token;
    return token;
  }

  static Future<String?> _searchTrackId(
      String path, String title, String artist, int durationMs) async {
    final body = await _apiBody(
        _apiUrl(path, <String, String>{'q': '$title $artist'}));
    if (body == null) return null;
    final root = _decode(body);
    if (root == null) return null;
    return _bestCandidate(root, title, artist, durationMs)?.id;
  }

  static Future<LyricDoc?> _genericAuthenticatedLyrics(
      String title, String artist, int durationMs) async {
    final body = await _apiBody(
        _apiUrl('lyrics/lrcget', <String, String>{'q': '$title $artist'}));
    if (body == null) return null;
    return _parseLrcGet(body, title, artist, durationMs);
  }

  /// The general endpoint returns search candidates, not lyric lines.
  /// Select one recording before taking its lyrics.
  static LyricDoc? _parseLrcGet(
      String raw, String title, String artist, int durationMs) {
    final root = _decode(raw);
    if (root == null) return null;
    final payload = root is Map ? root['lyrics'] : null;
    if (payload is! List || payload.isEmpty) return _parseResponse(raw);

    LyricDoc? best;
    var bestScore = -1;
    for (final document in payload) {
      final doc = _parseResponse(jsonEncode(document));
      if (doc == null) continue;
      final score = document is Map
          ? _candidateScoreOf(document, title, artist, durationMs)
          : 0;
      var better = false;
      final b = best;
      if (b == null || score > bestScore) {
        better = true;
      } else if (score == bestScore) {
        if (doc.wordSynced && !b.wordSynced) {
          better = true;
        } else if (doc.wordSynced == b.wordSynced &&
            doc.lineSynced &&
            !b.lineSynced &&
            !b.wordSynced) {
          better = true;
        }
      }
      if (better) {
        best = doc;
        bestScore = score;
      }
    }
    return best;
  }

  static int _candidateScoreOf(
      Map<dynamic, dynamic> doc, String title, String artist, int durationMs) {
    final attrs = doc['attributes'];
    final Map<dynamic, dynamic> details = attrs is Map ? attrs : doc;
    final cand = _PaxCandidate(
      _firstString(doc, _idKeys) ?? '',
      _firstString(details, _titleKeys) ?? '',
      _firstString(details, _artistKeys) ?? _artistNames(details) ?? '',
      _toDurationMs(_firstLong(details, _durationKeys)),
    );
    return _score(cand, title, artist, durationMs);
  }

  // ---------------------------------------------------------------------
  // Candidate matching
  // ---------------------------------------------------------------------

  static _PaxCandidate? _bestCandidate(
      dynamic root, String title, String artist, int durationMs) {
    final candidates = <_PaxCandidate>[];
    _collectCandidates(root, candidates);
    _PaxCandidate? best;
    var bestScore = -1;
    for (final c in candidates) {
      final s = _score(c, title, artist, durationMs);
      if (s > bestScore) {
        best = c;
        bestScore = s;
      }
    }
    if (best == null || bestScore < _minimumMatchScore) return null;
    return best;
  }

  static void _collectCandidates(dynamic node, List<_PaxCandidate> into) {
    if (node is List) {
      for (final e in node) {
        _collectCandidates(e, into);
      }
    } else if (node is Map) {
      final c = _toCandidate(node);
      if (c != null) into.add(c);
      for (final v in node.values) {
        _collectCandidates(v, into);
      }
    }
  }

  static _PaxCandidate? _toCandidate(Map<dynamic, dynamic> m) {
    final attrs = m['attributes'];
    final Map<dynamic, dynamic> details = attrs is Map ? attrs : m;
    final id = _firstString(m, _idKeys) ?? _firstString(details, _idKeys);
    if (id == null) return null;
    final title = _firstString(details, _titleKeys);
    if (title == null) return null;
    final artist =
        _firstString(details, _artistKeys) ?? _artistNames(details) ?? '';
    return _PaxCandidate(
        id, title, artist, _toDurationMs(_firstLong(details, _durationKeys)));
  }

  static String? _artistNames(Map<dynamic, dynamic> m) {
    final artists = m['artists'] ?? m['artist'];
    const nameKeys = <String>['name', 'artistName', 'title'];
    if (artists is String) return artists;
    if (artists is Map) return _firstString(artists, nameKeys);
    if (artists is List) {
      final names = <String>[];
      for (final a in artists) {
        if (a is String) {
          names.add(a);
        } else if (a is Map) {
          final n = _firstString(a, nameKeys);
          if (n != null) names.add(n);
        }
      }
      return names.isEmpty ? null : names.join(', ');
    }
    return null;
  }

  static int _score(
      _PaxCandidate c, String wantedTitle, String wantedArtist, int wantedMs) {
    var score = _textScore(c.title, wantedTitle, 20, 10) +
        _textScore(c.artist, wantedArtist, 15, 5);
    if (wantedMs > 0 && c.durationMs > 0) {
      final diff = (c.durationMs - wantedMs).abs();
      if (diff < 3000) {
        score += 10;
      } else if (diff < 10000) {
        score += 5;
      }
    }
    return score;
  }

  static int _textScore(String candidate, String wanted, int exact, int partial) {
    if (candidate.trim().isEmpty || wanted.trim().isEmpty) return 0;
    final a = candidate.toLowerCase();
    final b = wanted.toLowerCase();
    if (a == b) return exact;
    if (a.contains(b) || b.contains(a)) return partial;
    return 0;
  }

  static int _toDurationMs(int? v) {
    if (v == null || v <= 0) return 0;
    if (v < 10000) return v * 1000;
    return v;
  }

  // ---------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------

  static LyricDoc? _parseResponse(String raw) {
    final timed = _parseTimedApple(raw);
    if (timed != null) return LyricDoc(payload: timed, wordSynced: true);
    final unwrapped = _unwrap(raw);
    if (unwrapped == null) return null;
    return _classify(_unescapeTtml(unwrapped));
  }

  /// Structured Apple payload (`content: [{timestamp, text: [{text,
  /// timestamp, endtime, part}]}]`) -> karaoke rows, or null when the
  /// payload is not of that shape.
  static String? _parseTimedApple(String raw) {
    final root = _decode(raw);
    if (root == null) return null;
    final content = _findTimedContent(root);
    if (content == null) return null;

    final rows = <Map<dynamic, dynamic>>[];
    for (final e in content) {
      if (e is Map) rows.add(e);
    }

    final out = StringBuffer();
    var any = false;
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final start = _toInt(row['timestamp']);
      if (start == null) continue;
      final wordRows = row['text'];
      if (wordRows is! List) continue;

      final texts = <String>[];
      for (final w in wordRows) {
        if (w is Map) {
          final t = _string(w, 'text');
          if (t != null) texts.add(t);
        }
      }
      if (texts.isEmpty) continue;
      final nonBlank = texts.where((t) => t.trim().isNotEmpty).length;

      final int? nextLine = index + 1 < rows.length
          ? _toInt(rows[index + 1]['timestamp'])
          : null;

      final body = StringBuffer();
      var timedCount = 0;
      var firstStart = start;
      var lastEnd = start;
      for (var i = 0; i < wordRows.length; i++) {
        final w = wordRows[i];
        if (w is! Map) continue;
        final text = _cleanText(_string(w, 'text') ?? '');
        if (text.isEmpty) continue;
        final wordStart = _toInt(w['timestamp']);
        if (wordStart == null) continue;
        int? wordEnd = _toInt(w['endtime']);
        if (wordEnd == null && i + 1 < wordRows.length) {
          final nx = wordRows[i + 1];
          if (nx is Map) wordEnd = _toInt(nx['timestamp']);
        }
        wordEnd ??= nextLine ?? (wordStart + 800);
        final dur = math.max(0, wordEnd - wordStart);
        final joinsNext = w['part'] == true;
        body.write('($wordStart,$dur)$text${joinsNext ? '' : ' '}');
        if (timedCount == 0) firstStart = wordStart;
        timedCount++;
        lastEnd = math.max(lastEnd, wordStart + dur);
      }

      var lineStart = math.min(start, timedCount > 0 ? firstStart : start);
      String rowBody;
      int lineEnd;
      if (timedCount == 0 || timedCount != nonBlank) {
        // A syllable with no stamp leaves nothing to time the words by: keep
        // the text, stamped as one span over the line.
        final full = texts
            .map(_cleanText)
            .where((t) => t.isNotEmpty)
            .join(' ');
        if (full.isEmpty) continue;
        lineStart = start;
        lineEnd = nextLine != null && nextLine > start ? nextLine : start + 4000;
        rowBody = '($start,${lineEnd - start})$full';
      } else {
        rowBody = body.toString().trim();
        lineEnd = nextLine != null && nextLine > lineStart ? nextLine : lastEnd;
      }
      if (lineStart < 0) lineStart = 0;
      final lineDur = math.max(0, lineEnd - lineStart);
      out.write('[$lineStart,$lineDur]$rowBody\n');
      any = true;
    }
    if (!any) return null;
    return out.toString().trim();
  }

  /// Keeps the karaoke row syntax safe: no brackets of its own, no newlines.
  static String _cleanText(String s) => s
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .replaceAll('(', '')
      .replaceAll(')', '')
      .trim();

  static List<dynamic>? _findTimedContent(dynamic node) {
    if (node is Map) {
      final c = node['content'];
      if (c is List) {
        for (final e in c) {
          if (e is Map && e['timestamp'] != null) return c;
        }
      }
      for (final v in node.values) {
        final r = _findTimedContent(v);
        if (r != null) return r;
      }
      return null;
    }
    if (node is List) {
      for (final e in node) {
        final r = _findTimedContent(e);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Decides what kind of document [content] is.
  static LyricDoc? _classify(String content) {
    final lower = content.toLowerCase();
    if (_ttmlRoot.hasMatch(content) ||
        lower.contains('http://www.w3.org/ns/ttml')) {
      if (!lower.contains('<p')) return null;
      final word = _spanBegin.hasMatch(content);
      return LyricDoc(payload: content, wordSynced: word, lineSynced: !word);
    }
    if (_karaokeRow.hasMatch(content)) {
      return LyricDoc(payload: content, wordSynced: true);
    }
    if (content.trimLeft().startsWith('<')) return null;
    if (_wordStamp.hasMatch(content) && _lineStamp.hasMatch(content)) {
      return LyricDoc(payload: content, wordSynced: true);
    }
    if (_lineStamp.hasMatch(content)) {
      return LyricDoc(
          payload: content, wordSynced: false, lineSynced: true);
    }
    if (_errorWords.hasMatch(content)) return null;
    final kept = <String>[];
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || _metaTag.hasMatch(t)) continue;
      kept.add(t);
    }
    if (kept.isEmpty) return null;
    return LyricDoc(
        payload: kept.join('\n'), wordSynced: false, isPlain: true);
  }

  static String _unescapeTtml(String value) {
    if (!value.toLowerCase().contains('&lt;tt')) return value;
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  /// Providers sometimes wrap the same lyric string in one or two JSON
  /// envelopes. Returns the inner text, or null for an error / empty body.
  static String? _unwrap(String raw) {
    var value = raw.replaceAll('﻿', '').trim();
    if (value.startsWith('```')) {
      final lines = value.split('\n');
      var rest = lines.skip(1).toList();
      if (rest.isNotEmpty && rest.last.trim() == '```') {
        rest = rest.sublist(0, rest.length - 1);
      }
      value = rest.join('\n').trim();
    }
    if (value.isEmpty) return null;
    final json = _decode(value);
    if (json == null) return value;
    final found = _extract(json)?.trim();
    if (found == null || found.isEmpty) return null;
    return found;
  }

  static String? _extract(dynamic element) {
    if (element == null) return null;
    if (element is String) {
      final text = element.trim();
      final nested = _decode(text);
      if (nested is Map || nested is List) return _extract(nested);
      return text;
    }
    if (element is List) {
      final parts = <String>[];
      for (final e in element) {
        final t = _extract(e);
        if (t != null) parts.add(t);
      }
      final joined = parts.join('\n');
      return joined.trim().isEmpty ? null : joined;
    }
    if (element is Map) {
      if (element['isError']?.toString() == 'true' ||
          element['ok']?.toString() == 'false') {
        return null;
      }
      final err = element['error'];
      if (err != null && err != false && err != '') return null;
      for (final key in _contentKeys) {
        final v = element[key];
        if (v == null) continue;
        final t = _extract(v);
        if (t != null) return t;
      }
      final meta = element['metadata'];
      if (meta is Map) {
        final t = _extract(meta);
        if (t != null) return t;
      }
      final words = element['words'];
      if (words != null) return _extract(words);
      return null;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // JSON helpers
  // ---------------------------------------------------------------------

  static dynamic _decode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static String? _string(Map<dynamic, dynamic> m, String key) {
    final v = m[key];
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    return null;
  }

  static String? _firstString(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final s = _string(m, k)?.trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static int? _firstLong(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = _toInt(m[k]);
      if (v != null) return v;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // HTTP
  // ---------------------------------------------------------------------

  static Uri _apiUrl(String path, Map<String, String> query) =>
      Uri.parse('$_api/$path').replace(queryParameters: query);

  static Future<String?> _apiBody(Uri url) {
    final key = _key();
    if (key == null) return Future<String?>.value(null);
    return _get(url.toString(), bearer: key, seconds: 15);
  }

  static Future<String?> _get(
    String url, {
    String? bearer,
    Map<String, String>? headers,
    int seconds = 12,
  }) async {
    try {
      final req = await _client
          .getUrl(Uri.parse(url))
          .timeout(Duration(seconds: seconds));
      req.headers.set(HttpHeaders.acceptHeader,
          'application/json, text/plain, */*');
      if (bearer != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
      }
      if (headers != null) {
        headers.forEach((k, v) => req.headers.set(k, v));
      }
      final res = await req.close().timeout(Duration(seconds: seconds));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Drain the error body so the socket is not pinned.
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(Duration(seconds: seconds));
    } catch (e) {
      _log('GET failed (${Uri.parse(url).host}): $e');
      return null;
    }
  }
}
