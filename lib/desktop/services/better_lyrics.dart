// ZenMusic · vorlon-dev

import 'dart:convert';
import 'dart:io';

/// A fetched lyric document: the unwrapped payload text plus whether it
/// carries REAL word timing (timed TTML spans / QQ karaoke rows /
/// enhanced-LRC stamps — interpolation never counts).
class BetterLyricsDoc {
  const BetterLyricsDoc({required this.payload, required this.wordSynced});

  /// The lyric document text (TTML XML, karaoke rows, or LRC).
  final String payload;

  /// True only for real timing provenance: TTML with timed word spans,
  /// the karaoke millisecond format, or enhanced-LRC word stamps.
  final bool wordSynced;
}

class BetterLyrics {
  BetterLyrics._();

  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  static const List<String> _bases = <String>[
    'https://lyrics-api.boidu.dev/getLyrics',
    'https://lyrics-api.boidu.dev/ttml/getLyrics',
    'https://lyrics-api.boidu.dev/qq/getLyrics',
  ];

  /// Envelope keys the lyric document hides under, searched breadth-first.
  static const List<String> _envelopeKeys = <String>[
    'ttml', 'ttmlContent', 'lyrics', 'lrc', 'content', 'text',
    'plainLyrics', 'syncedLyrics', 'line', 'lines', 'lyric', 'data',
    'result', 'response',
  ];

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[better_lyrics] $m');

  /// Main entry. Returns the best document across the three endpoints
  /// (first word-synced hit wins; a line-synced hit is kept as fallback),
  /// or null when every endpoint fails. Never throws.
  static Future<BetterLyricsDoc?> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    if (title.trim().isEmpty || artist.trim().isEmpty) return null;
    final d = durationMs != null && durationMs > 0
        ? (durationMs ~/ 1000).toString()
        : null;
    BetterLyricsDoc? lineSynced;
    for (final base in _bases) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: <String, String>{
          's': title.trim(),
          'a': artist.trim(),
          if (d != null) 'd': d,
          if (album != null && album.trim().isNotEmpty) 'al': album.trim(),
        });
        final req = await _client.getUrl(uri);
        final res = await req.close().timeout(const Duration(seconds: 12));
        if (res.statusCode != 200) {
          _log('HTTP ${res.statusCode} from ${Uri.parse(base).host}'
              '${Uri.parse(base).path}');
          // Drain the error body — an undrained response pins the socket
          // for the whole session (misses are routine here).
          await res.drain<void>().timeout(const Duration(seconds: 5));
          continue;
        }
        final body = await res.transform(utf8.decoder).join();
        if (body.trim().isEmpty) continue;
        final payload = _unwrap(body);
        if (payload == null || payload.trim().isEmpty) continue;
        final wordSynced = hasWordTiming(payload);
        final doc = BetterLyricsDoc(payload: payload, wordSynced: wordSynced);
        if (wordSynced) return doc; // best case — stop racing
        lineSynced ??= doc; // remember first line-synced fallback
      } catch (e) {
        _log('fetch failed ($base): $e');
      }
    }
    if (lineSynced != null) {
      _log('line-synced fallback document kept (no word timing)');
    }
    return lineSynced;
  }

  /// Strip the JSON envelope (recursively — the doc may be double-encoded)
  /// down to the lyric document text. Non-JSON payloads pass through.
  static String? _unwrap(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      return trimmed;
    }
    final element = _decode(trimmed);
    if (element == null) return trimmed;
    final found = _extractContent(element)?.trim();
    if (found == null || found.isEmpty) return trimmed;
    return found;
  }

  static dynamic _decode(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static String? _extractContent(dynamic element) {
    if (element == null) return null;
    if (element is String) {
      final text = element.trim();
      if (text.isEmpty) return null;
      if ((text.startsWith('{') || text.startsWith('['))) {
        final inner = _decode(text);
        if (inner != null) return _extractContent(inner) ?? text;
      }
      return text;
    }
    if (element is List) {
      final texts = <String>[];
      for (final item in element) {
        final t = _extractContent(item);
        if (t != null && t.isNotEmpty) texts.add(t);
      }
      final joined = texts.join('\n');
      return joined.isEmpty ? null : joined;
    }
    if (element is Map) {
      if (element['isError']?.toString() == 'true' ||
          element['ok']?.toString() == 'false') {
        return null;
      }
      for (final key in _envelopeKeys) {
        if (element.containsKey(key)) {
          final found = _extractContent(element[key]);
          if (found != null && found.isNotEmpty) return found;
        }
      }
      return null;
    }
    return null;
  }

  /// True only for REAL timing provenance — timed TTML word spans
  /// (`<span begin=… end=…>`), QQ karaoke rows (`[start,dur](w,d)word`),
  /// or enhanced-LRC inline stamps (`<mm:ss.xx>`). Plain line LRC and
  /// span-less TTML must NOT count (their syllables are interpolated
  /// later for the wipe, which is display sugar, not word sync).
  static bool hasWordTiming(String payload) {
    final lower = payload.toLowerCase();
    final looksTtml = lower.contains('<tt') ||
        lower.contains('<p') ||
        lower.contains('http://www.w3.org/ns/ttml');
    if (looksTtml &&
        RegExp(r'<(?:[a-zA-Z0-9_-]+:)?span\b[^>]*\bbegin\s*=',
                caseSensitive: false)
            .hasMatch(payload)) {
      return true;
    }
    if (RegExp(r'^\s*\[\d{1,8},\d{1,8}\]', multiLine: true)
        .hasMatch(payload)) {
      return true; // QQ karaoke rows
    }
    if (RegExp(r'<\d{1,3}:\d{2}[.:]\d{2,3}>').hasMatch(payload)) {
      return true; // enhanced-LRC word stamps
    }
    return false;
  }
}
