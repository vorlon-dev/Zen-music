// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — Unison.kt

import 'dart:convert';
import 'dart:io';

import 'lyric_doc.dart';

/// Community-submitted lyrics (unison.boidu.dev). The entry says whether it is
/// TTML, line-stamped / enhanced LRC or plain text; the text is passed through
/// as-is for the app's parsers, with the timing kind worked out here.
class Unison {
  Unison._();

  static const String _base = 'https://unison.boidu.dev/lyrics';
  static const String _agent = 'BitChord (https://github.com/bitchord)';

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _agent
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[unison] $m');

  static final RegExp _wordStamp = RegExp(r'<\d{1,3}:\d{2}[.:]\d{2,3}>');
  static final RegExp _lineStamp = RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]');
  static final RegExp _timedSpan =
      RegExp(r'<span\b[^>]*\bbegin\s*=', caseSensitive: false);
  static final RegExp _timedPara =
      RegExp(r'<p\b[^>]*\bbegin\s*=', caseSensitive: false);

  /// Never throws; null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      if (q.title.trim().isEmpty || q.artist.trim().isEmpty) return null;
      final params = <String, String>{
        'song': q.title.trim(),
        'artist': q.artist.trim(),
      };
      final album = q.album;
      if (album != null && album.trim().isNotEmpty) {
        params['album'] = album.trim();
      }
      final seconds = q.durationSec;
      if (seconds != null && seconds > 0) params['duration'] = '$seconds';

      final uri = Uri.parse(_base).replace(queryParameters: params);
      final req = await _client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      if (decoded['success'] != true) return null;
      final dynamic data = decoded['data'];
      if (data is! Map) return null;
      final dynamic lyrics = data['lyrics'];
      if (lyrics is! String || lyrics.trim().isEmpty) return null;
      final text = lyrics.trim();
      final format = (data['format'] is String)
          ? (data['format'] as String).toLowerCase()
          : '';
      final syncType = (data['syncType'] is String)
          ? (data['syncType'] as String).toLowerCase()
          : '';

      if (format == 'ttml') {
        if (_timedSpan.hasMatch(text)) {
          return LyricDoc(payload: text, wordSynced: true);
        }
        if (_timedPara.hasMatch(text)) {
          return LyricDoc(
              payload: text, wordSynced: false, lineSynced: true);
        }
        return null;
      }
      if (syncType == 'plain') return _plain(text);
      if (_wordStamp.hasMatch(text) && _lineStamp.hasMatch(text)) {
        return LyricDoc(payload: text, wordSynced: true);
      }
      if (_lineStamp.hasMatch(text)) {
        return LyricDoc(payload: text, wordSynced: false, lineSynced: true);
      }
      return _plain(text);
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static LyricDoc? _plain(String text) {
    final lines = <String>[];
    for (final l in text.split('\n')) {
      final t = l.trim();
      if (t.isNotEmpty) lines.add(t);
    }
    if (lines.isEmpty) return null;
    return LyricDoc(
        payload: lines.join('\n'), wordSynced: false, isPlain: true);
  }
}
