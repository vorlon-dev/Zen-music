// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — Musixmatch.kt

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'lyric_doc.dart';

/// Word timing (rich-sync) with a line-synced fallback, from Musixmatch's
/// web API (`apic.musixmatch.com`). The signing key and the user token are
/// both fetched on the fly, exactly like the web client does.
class Musixmatch {
  Musixmatch._();

  static const String _base = 'https://apic.musixmatch.com/ws/1.1';
  static const String _appId = 'mobile-app-v1.0';
  static const String _searchPage = 'https://www.musixmatch.com/search';
  static const String _browserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  // Used only if the public page serving the rotating key is unavailable.
  static const String _fallbackSigningSecret =
      'f09016176ba43a1cfd1031fbd6b3d26c';

  /// Optional: a Musixmatch user token supplied by the app. When null (the
  /// default) a token is requested from `token.get`, like the Kotlin does.
  static String? token;

  static String? _cachedSecret;
  static String? _cachedToken;
  static String? _guid;

  static final RegExp _appScriptRe = RegExp(
    r'''src=["']([^"']*/_next/static/chunks/pages/_app-[^"']+\.js)["']''',
    caseSensitive: false,
  );
  static final RegExp _encodedSecretRe =
      RegExp(r'''from\(\s*["']([^"']+)["']\s*\.split''');

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[musixmatch] $m');

  /// Never throws. Rich-sync (karaoke rows, wordSynced) when the track has
  /// it, else whole-line LRC, else null.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final title = q.title.trim();
      final artist = q.artist.trim();
      if (title.isEmpty) return null;

      final track = await _bestTrack(title, artist, q.durationSec);
      if (track == null) {
        _log('no track match for "$title"');
        return null;
      }
      final trackId = _asInt(track['track_id']);
      if (trackId == null) return null;

      // The subtitle endpoint is line-timed by design; prefer the rich-sync
      // tier so tracks with syllable data are not flattened.
      if (_asInt(track['has_richsync']) != 0) {
        final body = await _fetchRichSync(trackId);
        if (body != null) {
          final karaoke = _richSyncToKaraoke(body);
          if (karaoke != null) {
            return LyricDoc(payload: karaoke, wordSynced: true);
          }
        }
      }

      if (_asInt(track['has_subtitles']) != 0) {
        final sub = await _fetchSubtitle(trackId);
        if (sub != null) {
          final lrc = _subtitleToLrc(sub);
          if (lrc.isNotEmpty) {
            return LyricDoc(
              payload: lrc,
              wordSynced: false,
              lineSynced: true,
            );
          }
        }
      }
      return null;
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- search

  static Future<Map<String, dynamic>?> _bestTrack(
      String title, String artist, int? seconds) async {
    final tracks = await _searchTrack(title, artist);
    if (tracks == null || tracks.isEmpty) return null;
    Map<String, dynamic>? best;
    var bestScore = -1e18;
    for (final t in tracks) {
      final s = _score(t, title, artist, seconds);
      if (best == null || s > bestScore) {
        best = t;
        bestScore = s;
      }
    }
    return best;
  }

  static double _score(
      Map<String, dynamic> track, String title, String artist, int? seconds) {
    var score = 0.0;
    final name = (track['track_name'] ?? '').toString().trim().toLowerCase();
    final targetTitle = title.trim().toLowerCase();
    if (name == targetTitle) {
      score += 80.0;
    } else if (name.contains(targetTitle) || targetTitle.contains(name)) {
      score += 40.0;
    }
    final trackArtist =
        (track['artist_name'] ?? '').toString().trim().toLowerCase();
    if (trackArtist.contains(artist.trim().toLowerCase())) {
      score += 40.0;
    }
    final length = _asInt(track['track_length']);
    if (length != null && seconds != null) {
      final diff = (length - seconds).abs();
      if (diff <= 2) {
        score += 30.0;
      } else if (diff <= 5) {
        score += 15.0;
      } else if (diff <= 10) {
        score += 5.0;
      } else {
        score -= 20.0;
      }
    }
    return score;
  }

  static Future<List<Map<String, dynamic>>?> _searchTrack(
      String title, String artist) async {
    final response = await _signedGet((String tok) => _buildUrl(
          'track.search',
          <String, String>{
            'app_id': _appId,
            'format': 'json',
            'q_track': title,
            'q_artist': artist,
            'f_has_lyrics': '1',
            's_track_rating': 'desc',
            'quorum_factor': '1',
            'page_size': '10',
            'page': '1',
            'usertoken': tok,
          },
        ));
    if (response == null) return null;
    final body = _messageBody(response);
    if (body is! Map) return null;
    final list = body['track_list'];
    if (list is! List) return null;
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is Map && item['track'] is Map) {
        final t = Map<String, dynamic>.from(item['track'] as Map);
        if (t['track_id'] != null && t['track_name'] != null) out.add(t);
      }
    }
    return out;
  }

  static Future<String?> _fetchSubtitle(int trackId) async {
    final response = await _signedGet((String tok) => _buildUrl(
          'track.subtitle.get',
          <String, String>{
            'app_id': _appId,
            'format': 'json',
            'track_id': trackId.toString(),
            'subtitle_format': 'mxm',
            'usertoken': tok,
          },
        ));
    if (response == null) return null;
    final body = _messageBody(response);
    if (body is! Map) return null;
    final subtitle = body['subtitle'];
    if (subtitle is! Map) return null;
    final text = subtitle['subtitle_body'];
    return text is String ? text : null;
  }

  static Future<String?> _fetchRichSync(int trackId) async {
    final response = await _signedGet((String tok) => _buildUrl(
          'track.richsync.get',
          <String, String>{
            'app_id': _appId,
            'format': 'json',
            'track_id': trackId.toString(),
            'usertoken': tok,
          },
        ));
    if (response == null) return null;
    final body = _messageBody(response);
    if (body is! Map) return null;
    final rich = body['richsync'];
    if (rich is! Map) return null;
    final text = rich['richsync_body'];
    return text is String ? text : null;
  }

  /// `message.body` of an API envelope, or null.
  static dynamic _messageBody(String response) {
    try {
      final root = jsonDecode(response);
      if (root is Map && root['message'] is Map) {
        return (root['message'] as Map)['body'];
      }
    } catch (_) {}
    return null;
  }

  // ------------------------------------------------------------- converters

  /// Rich-sync JSON -> QQ karaoke rows `[lineStart,lineDur](start,dur)word`.
  /// Null when nothing usable (or no real multi-word timing) is found.
  static String? _richSyncToKaraoke(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;

    final rows = <Map<String, dynamic>>[];
    var anyWordSynced = false;

    for (final entry in decoded) {
      if (entry is! Map) continue;
      final ts = _asDouble(entry['ts']);
      final te = _asDouble(entry['te']);
      if (ts == null || te == null) continue;
      final lineStart = _secondsToMs(ts);
      final lineEnd = math.max(lineStart, _secondsToMs(te));

      final frags = <Map<String, dynamic>>[];
      final rawFrags = entry['l'];
      if (rawFrags is List) {
        for (final f in rawFrags) {
          if (f is! Map) continue;
          final o = _asDouble(f['o']);
          frags.add(<String, dynamic>{
            'c': (f['c'] ?? '').toString(),
            'o': o ?? 0.0,
          });
        }
      }

      // Timed runs (start, end, text), source order kept.
      final runStart = <int>[];
      final runEnd = <int>[];
      final runText = <String>[];
      var previousStart = lineStart;
      for (var i = 0; i < frags.length; i++) {
        final text = (frags[i]['c'] as String)
            .replaceAll('\r', ' ')
            .replaceAll('\n', ' ')
            .replaceAll('(', '')
            .replaceAll(')', '');
        if (text.isEmpty) continue;
        final start = math.max(
          lineStart,
          math.max(
              previousStart, _secondsToMs(ts + (frags[i]['o'] as double))),
        );
        final next = i + 1 < frags.length
            ? _secondsToMs(ts + (frags[i + 1]['o'] as double))
            : lineEnd;
        previousStart = start;
        runStart.add(start);
        runEnd.add(math.max(start, math.min(lineEnd, next)));
        runText.add(text);
      }

      // Group runs into words: fragments carry their own spacing, so a
      // fragment with no space after it is a syllable of a word that goes on.
      final wStart = <int>[];
      final wEnd = <int>[];
      final wText = <String>[];
      var curText = '';
      var curStart = 0;
      var curEnd = 0;
      var open = false;
      void flush() {
        if (open && curText.isNotEmpty) {
          wStart.add(curStart);
          wEnd.add(curEnd);
          wText.add(curText);
        }
        curText = '';
        open = false;
      }

      for (var i = 0; i < runText.length; i++) {
        final t = runText[i];
        if (t.trim().isEmpty) {
          flush();
          continue;
        }
        if (RegExp(r'^\s').hasMatch(t)) flush();
        if (!open) {
          curStart = runStart[i];
          open = true;
        }
        curText += t.trim();
        curEnd = runEnd[i];
        if (RegExp(r'\s$').hasMatch(t)) flush();
      }
      flush();

      final x = (entry['x'] ?? '')
          .toString()
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ')
          .replaceAll('(', '')
          .replaceAll(')', '')
          .trim();

      if (wText.isEmpty) {
        // No fragments: keep the line as one timed span.
        if (x.isEmpty) continue;
        rows.add(<String, dynamic>{
          't': lineStart,
          'row': '[$lineStart,${lineEnd - lineStart}]'
              '($lineStart,${lineEnd - lineStart})$x',
        });
        continue;
      }
      if (wText.length >= 2) anyWordSynced = true;

      final sb = StringBuffer('[$lineStart,${lineEnd - lineStart}]');
      for (var i = 0; i < wText.length; i++) {
        final dur = math.max(0, wEnd[i] - wStart[i]);
        sb.write('(${wStart[i]},$dur)${wText[i]}');
        if (i + 1 < wText.length) sb.write(' ');
      }
      rows.add(<String, dynamic>{'t': lineStart, 'row': sb.toString()});
    }

    if (!anyWordSynced || rows.isEmpty) return null;
    rows.sort((a, b) => (a['t'] as int).compareTo(b['t'] as int));
    return rows.map((r) => r['row'] as String).join('\n');
  }

  /// Musixmatch's `mxm` subtitle JSON -> plain LRC (`[mm:ss.xx] line`).
  static String _subtitleToLrc(String subtitleBody) {
    dynamic decoded;
    try {
      decoded = jsonDecode(subtitleBody);
    } catch (_) {
      return '';
    }
    if (decoded is! List) return '';
    final sb = StringBuffer();
    for (final line in decoded) {
      if (line is! Map) continue;
      final text = (line['text'] ?? '')
          .toString()
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ')
          .trim();
      if (text.isEmpty) continue;
      final time = line['time'];
      if (time is! Map) continue;
      final total = _asDouble(time['total']);
      if (total == null) continue;
      final totalMs = _secondsToMs(total);
      final minutes = totalMs ~/ 1000 ~/ 60;
      final secs = (totalMs ~/ 1000) % 60;
      final centis = (totalMs % 1000) ~/ 10;
      sb.writeln('[${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}.'
          '${centis.toString().padLeft(2, '0')}] $text');
    }
    return sb.toString().trim();
  }

  static int _secondsToMs(double seconds) => (seconds * 1000.0).toInt();

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  // ---------------------------------------------------- signing & transport

  static String _buildUrl(String endpoint, Map<String, String> params) {
    final parts = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$_base/$endpoint?$parts';
  }

  /// Signs and issues the URL from [buildUrl]; an auth failure refreshes
  /// both moving credentials once.
  static Future<String?> _signedGet(
      String Function(String token) buildUrl) async {
    final secret = await _getSecret();
    final tok = await _getToken(secret);
    if (tok == null) return null;
    final first = await _apiGet(_sign(buildUrl(tok), secret));
    if (first != null && !_looksUnauthorized(first)) return first;

    _cachedToken = null;
    _cachedSecret = null;
    final freshSecret = await _getSecret();
    final freshToken = await _getToken(freshSecret);
    if (freshToken == null) return null;
    return _apiGet(_sign(buildUrl(freshToken), freshSecret));
  }

  /// Musixmatch reports an expired token inside a successful HTTP response.
  static bool _looksUnauthorized(String body) {
    try {
      final root = jsonDecode(body);
      if (root is Map && root['message'] is Map) {
        final header = (root['message'] as Map)['header'];
        if (header is Map) {
          final code = _asInt(header['status_code']);
          return code == 401 || code == 402;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> _getToken(String secret) async {
    final preset = token;
    if (preset != null && preset.trim().isNotEmpty) return preset.trim();
    final cached = _cachedToken;
    if (cached != null) return cached;
    final fetched = await _fetchToken(secret);
    if (fetched != null) _cachedToken = fetched;
    return fetched;
  }

  static String _processGuid() {
    final existing = _guid;
    if (existing != null) return existing;
    final rnd = math.Random.secure();
    final hex = StringBuffer();
    for (var i = 0; i < 32; i++) {
      hex.write(rnd.nextInt(16).toRadixString(16));
    }
    final h = hex.toString();
    final g = '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    _guid = g;
    return g;
  }

  static Future<String?> _fetchToken(String secret) async {
    final url = _buildUrl('token.get', <String, String>{
      'app_id': _appId,
      'guid': _processGuid(),
      'format': 'json',
    });
    final body = await _apiGet(_sign(url, secret));
    if (body == null) return null;
    final data = _messageBody(body);
    if (data is Map && data['user_token'] is String) {
      final t = data['user_token'] as String;
      return t.isEmpty ? null : t;
    }
    return null;
  }

  /// Reads the rotating signing key from the JavaScript linked by the
  /// current web client; falls back to the known key.
  static Future<String> _getSecret() async {
    final cached = _cachedSecret;
    if (cached != null) return cached;
    String secret;
    try {
      final page = await _browserGet(_searchPage, 'text/html,application/xhtml+xml');
      if (page == null) throw StateError('search page unavailable');
      final scriptMatch = _appScriptRe.firstMatch(page);
      final script = scriptMatch?.group(1);
      if (script == null) throw StateError('application script not found');
      final scriptUrl = Uri.parse(_searchPage).resolve(script).toString();
      final js = await _browserGet(scriptUrl, '*/*');
      if (js == null) throw StateError('application script unavailable');
      final encMatch = _encodedSecretRe.firstMatch(js);
      final encoded = encMatch?.group(1);
      if (encoded == null) throw StateError('signing key not found');
      var b64 = String.fromCharCodes(encoded.codeUnits.reversed);
      while (b64.length % 4 != 0) {
        b64 += '=';
      }
      final decoded = utf8.decode(base64.decode(b64));
      if (decoded.trim().isEmpty) throw StateError('empty signing key');
      secret = decoded;
    } catch (e) {
      _log('signing key lookup failed, using fallback: $e');
      secret = _fallbackSigningSecret;
    }
    _cachedSecret = secret;
    return secret;
  }

  /// Signs `<url><UTC yyyyMMdd>` with HMAC-SHA256, like the web client.
  static String _sign(String url, String secret) {
    final normalized = url.replaceAll('%20', '+').replaceAll(' ', '+');
    final now = DateTime.now().toUtc();
    final date = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final digest = hmac.convert(utf8.encode('$normalized$date'));
    final signature = base64.encode(digest.bytes);
    return '$normalized&signature=${Uri.encodeQueryComponent(signature)}'
        '&signature_protocol=sha256';
  }

  static Future<String?> _apiGet(String url) =>
      _request(url, 'application/json, text/plain, */*');

  static Future<String?> _browserGet(String url, String accept) =>
      _request(url, accept, cookie: 'mxm_bab=AB');

  static Future<String?> _request(String url, String accept,
      {String? cookie}) async {
    try {
      final req = await _client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.userAgentHeader, _browserAgent);
      req.headers.set(HttpHeaders.acceptHeader, accept);
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
      if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _log('HTTP ${res.statusCode} from ${Uri.parse(url).host}');
        // Drain the error body so the socket is released.
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _log('request failed (${Uri.tryParse(url)?.host}): $e');
      return null;
    }
  }
}
