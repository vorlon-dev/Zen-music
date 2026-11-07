// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — LyricsPlus.kt

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lyric_doc.dart';

/// Syllable-timed lyrics from LyricsPlus (the backend behind YouLy+). It runs
/// on volunteer mirrors, so every mirror is asked at once and the first real
/// answer wins; the winner is remembered for the next track.
///
/// Output: QQ-style karaoke rows (`[start,dur](start,dur)word …`) when any
/// line carries syllable timing, otherwise plain LRC.
class LyricsPlus {
  LyricsPlus._();

  static const List<String> _mirrors = <String>[
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.atomix.one',
    'https://lyricsplus.binimum.org',
    'https://lyricsplus.prjktla.workers.dev',
    'https://lyricsplus-seven.vercel.app',
    'https://lyrics-plus-backend.vercel.app',
  ];

  static const String _agent = 'BitChord (https://github.com/bitchord)';

  static String? _lastGood;
  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _agent
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[lyrics_plus] $m');

  /// Never throws; null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      if (q.title.trim().isEmpty || q.artist.trim().isEmpty) return null;
      final good = _lastGood;
      final hosts = <String>[];
      if (good != null) hosts.add(good);
      for (final m in _mirrors) {
        if (m != good) hosts.add(m);
      }
      final done = Completer<LyricDoc?>();
      var pending = hosts.length;
      for (final host in hosts) {
        _fetch(host, q).then((LyricDoc? doc) {
          pending--;
          if (done.isCompleted) return;
          if (doc != null) {
            _lastGood = host;
            done.complete(doc);
          } else if (pending <= 0) {
            done.complete(null);
          }
        });
      }
      return await done.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static Future<LyricDoc?> _fetch(String host, LyricQuery q) async {
    try {
      final params = <String, String>{
        'title': q.title.trim(),
        'artist': q.artist.trim(),
      };
      final seconds = q.durationSec;
      if (seconds != null && seconds > 0) params['duration'] = '$seconds';
      final album = q.album;
      if (album != null && album.trim().isNotEmpty) {
        params['album'] = album.trim();
      }
      final isrc = q.isrc;
      if (isrc != null && isrc.trim().isNotEmpty) params['isrc'] = isrc.trim();

      final uri =
          Uri.parse('$host/v2/lyrics/get').replace(queryParameters: params);
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
      if (body.trim().isEmpty) return null;
      return _parse(body);
    } catch (e) {
      _log('fetch failed ($host): $e');
      return null;
    }
  }

  static int? _int(dynamic v) {
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static LyricDoc? _parse(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final dynamic lyrics = decoded['lyrics'];
    if (lyrics is! List) return null;

    final lines = <_Line>[];
    for (final dynamic item in lyrics) {
      if (item is! Map) continue;
      final start = _int(item['time']);
      if (start == null) continue;
      final runs = <_Run>[];
      final dynamic syl = item['syllabus'];
      if (syl is List) {
        for (final dynamic s in syl) {
          if (s is! Map) continue;
          final text = s['text'];
          final t = _int(s['time']);
          if (text is! String || t == null) continue;
          final d = _int(s['duration']) ?? 0;
          runs.add(_Run(t, t + (d < 0 ? 0 : d), text));
        }
      }
      final words = _mergeSyllables(runs);
      if (words.isNotEmpty) {
        final first = words.first.start;
        lines.add(_Line(start < first ? start : first, words, null, 0));
      } else {
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) {
          lines.add(_Line(start, const <_Word>[], text.trim(),
              _int(item['duration']) ?? 0));
        }
      }
    }
    if (lines.isEmpty) return null;
    lines.sort((a, b) => a.time.compareTo(b.time));

    final anyWords = lines.any((l) => l.words.isNotEmpty);
    final sb = StringBuffer();
    if (anyWords) {
      for (final l in lines) {
        if (l.words.isNotEmpty) {
          final lineStart = l.time;
          var end = l.words.first.end;
          for (final w in l.words) {
            if (w.end > end) end = w.end;
          }
          final dur = end > lineStart ? end - lineStart : 0;
          sb.write('[$lineStart,$dur]');
          for (var i = 0; i < l.words.length; i++) {
            final w = l.words[i];
            final wd = w.end > w.start ? w.end - w.start : 0;
            sb.write('(${w.start},$wd)${_clean(w.text)}');
            if (i < l.words.length - 1) sb.write(' ');
          }
          sb.write('\n');
        } else {
          // Line-only entry inside a word-synced song: one span for the line.
          final d = l.duration > 0 ? l.duration : 3000;
          sb.write('[${l.time},$d](${l.time},$d)${_clean(l.text ?? '')}\n');
        }
      }
      final payload = sb.toString().trim();
      if (payload.isEmpty) return null;
      return LyricDoc(payload: payload, wordSynced: true);
    }

    for (final l in lines) {
      final text = _clean(l.text ?? '');
      if (text.isEmpty) continue;
      sb.write('${_stamp(l.time)}$text\n');
    }
    final payload = sb.toString().trim();
    if (payload.isEmpty) return null;
    return LyricDoc(payload: payload, wordSynced: false, lineSynced: true);
  }

  /// Karaoke rows cannot hold parentheses or line breaks in a word.
  static String _clean(String s) => s
      .replaceAll('(', '')
      .replaceAll(')', '')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();

  static String _stamp(int ms) {
    final total = ms < 0 ? 0 : ms;
    final m = total ~/ 60000;
    final s = (total % 60000) ~/ 1000;
    final cs = (total % 1000) ~/ 10;
    String two(int n) => n.toString().padLeft(2, '0');
    return '[${two(m)}:${two(s)}.${two(cs)}]';
  }

  static bool _unspaced(int c) =>
      (c >= 0x3400 && c <= 0x9FFF) ||
      (c >= 0x3040 && c <= 0x30FF) ||
      (c >= 0x3000 && c <= 0x303F) ||
      (c >= 0xFF00 && c <= 0xFFEF) ||
      (c >= 0x0E00 && c <= 0x0E7F);

  static bool _isSpace(String ch) => ch.trim().isEmpty;

  /// Glues syllables back into words: the API's own spacing is the word
  /// boundary (`"e"` then `"nough "` is one word). Each word spans from its
  /// first syllable's start to its last syllable's end.
  static List<_Word> _mergeSyllables(List<_Run> runs) {
    final words = <_Word>[];
    final current = StringBuffer();
    var start = 0;
    var end = 0;

    void flush() {
      if (current.isNotEmpty) {
        words.add(_Word(start, end < start ? start : end, current.toString()));
      }
      current.clear();
    }

    for (final run in runs) {
      final content = run.raw.trim();
      if (content.isEmpty) {
        flush();
        continue;
      }
      final cur = current.toString();
      final joins = cur.isNotEmpty &&
          !_isSpace(run.raw[0]) &&
          !_unspaced(cur.codeUnitAt(cur.length - 1)) &&
          !_unspaced(content.codeUnitAt(0));
      if (!joins) flush();
      if (current.isEmpty) {
        start = run.start;
        end = run.start;
      }
      current.write(content);
      final runEnd = run.end < run.start ? run.start : run.end;
      if (runEnd > end) end = runEnd;
      if (_isSpace(run.raw[run.raw.length - 1])) flush();
    }
    flush();
    return words;
  }
}

class _Run {
  _Run(this.start, this.end, this.raw);
  final int start;
  final int end;
  final String raw;
}

class _Word {
  _Word(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

class _Line {
  _Line(this.time, this.words, this.text, this.duration);
  final int time;
  final List<_Word> words;
  final String? text;
  final int duration;
}
