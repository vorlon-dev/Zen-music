// ZenMusic · "Romanize lyrics" setting: shows Hindi, Tamil, Telugu, Kannada,
// Malayalam, Bengali, Gujarati, Punjabi, Japanese kana, Korean and Russian
// lyrics in Latin letters. Works offline. Lines that are already in Latin
// letters are never touched.
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'lyrics_service.dart';
import 'romanizer.dart';

class LyricsRomanizer {
  LyricsRomanizer._();
  static final LyricsRomanizer instance = LyricsRomanizer._();

  /// 0 = off, 1 = show under the original line, 2 = replace the original line.
  final ValueNotifier<int> mode = ValueNotifier(0);

  final Map<String, String> _cache = {};

  void load() {
    final v = Hive.box('SETTINGS').get('LYRICS_ROMAN', defaultValue: 0) as int;
    mode.value = v.clamp(0, 2).toInt();
  }

  Future<void> set(int m) async {
    mode.value = m.clamp(0, 2).toInt();
    await Hive.box('SETTINGS').put('LYRICS_ROMAN', mode.value);
  }

  /// Romanized text, or null when [text] has nothing to convert.
  String? roman(String text) {
    if (!Romanizer.needs(text)) return null;
    if (_cache.length > 4000) _cache.clear();
    return _cache.putIfAbsent(text, () => Romanizer.romanize(text));
  }

  /// For "show under the line" mode.
  String? below(String text) => mode.value == 1 ? roman(text) : null;

  /// For "replace the line" mode (keeps word timing for the karaoke fill).
  LyricLine apply(LyricLine l) {
    if (mode.value != 2) return l;
    final r = roman(l.text);
    if (r == null) return l;
    return LyricLine(
      l.timeMs,
      r,
      durationMs: l.durationMs,
      words: [
        for (final w in l.words)
          LyricWord(timeMs: w.timeMs, durationMs: w.durationMs, text: roman(w.text) ?? w.text),
      ],
    );
  }
}
