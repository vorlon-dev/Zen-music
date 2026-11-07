// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — Megalobiz.kt

import 'dart:convert';
import 'dart:io';

import 'lyric_doc.dart';

/// Line-synced community LRC scraped from Megalobiz (search page, then the
/// first LRC entry's detail page). Output: plain line-stamped LRC.
class Megalobiz {
  Megalobiz._();

  static const String _host = 'www.megalobiz.com';
  static const String _base = 'https://www.megalobiz.com';
  static const String _agent = 'BitChord (https://github.com/bitchord)';

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _agent
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[megalobiz] $m');

  static final RegExp _lrcLink = RegExp(
    r'''href=["'](/lrc/maker/download/[^"']+)["']''',
    caseSensitive: false,
  );
  static final RegExp _lrcBody = RegExp(
    r'''id=["']lrc_[^"']*_details["'][^>]*>(.*?)</span>''',
    caseSensitive: false,
    dotAll: true,
  );
  static final RegExp _br = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final RegExp _tag = RegExp(r'<[^>]+>');
  static final RegExp _stamped =
      RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]\s*\S');

  static Future<String?> _get(Uri uri) async {
    final req = await _client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      await res.drain<void>().timeout(const Duration(seconds: 5));
      return null;
    }
    return res
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 12));
  }

  /// Never throws; null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final qry = '${q.artist} ${q.title}'.trim();
      if (q.title.trim().isEmpty || qry.isEmpty) return null;

      final search = Uri.https(_host, '/searchall', <String, String>{'qry': qry});
      final results = await _get(search);
      if (results == null) return null;
      final link = _lrcLink.firstMatch(results);
      final path = link?.group(1);
      if (path == null) return null;

      final page = await _get(Uri.parse(_base + path.replaceAll('&amp;', '&')));
      if (page == null) return null;
      final raw = _lrcBody.firstMatch(page)?.group(1);
      if (raw == null) return null;

      final lrc = _decodeEntities(
        raw.replaceAll(_br, '\n').replaceAll(_tag, ''),
      ).replaceAll('\r', '').trim();
      if (!_stamped.hasMatch(lrc)) return null;
      return LyricDoc(payload: lrc, wordSynced: false, lineSynced: true);
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static String _decodeEntities(String text) {
    if (!text.contains('&')) return text;
    var out = text.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}
