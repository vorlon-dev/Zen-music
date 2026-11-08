// ZenMusic · six lyric styles: Prism (default), Classic karaoke, Bold card,
// Glow, Typewriter, Calm. Persisted in Hive 'SETTINGS' (LYRIC_STYLE).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'lyrics_service.dart';

enum LyricStyle { prism, classic, boldCard, glow, typewriter, calm }

extension LyricStyleName on LyricStyle {
  String get label => const [
        'Prism', 'Classic karaoke', 'Bold card', 'Glow', 'Typewriter', 'Calm'
      ][index];
}

class LyricStylePrefs {
  static final ValueNotifier<LyricStyle> style = ValueNotifier(LyricStyle.prism);

  /// Call once after Hive is open.
  static void load() {
    final i = Hive.box('SETTINGS').get('LYRIC_STYLE', defaultValue: 0) as int;
    style.value = LyricStyle.values[i.clamp(0, LyricStyle.values.length - 1)];
  }

  static Future<void> set(LyricStyle s) async {
    style.value = s;
    await Hive.box('SETTINGS').put('LYRIC_STYLE', s.index);
  }
}

class LyricStyleKit {
  static TextStyle textStyle(LyricStyle s, TextStyle b) {
    switch (s) {
      case LyricStyle.prism:
        return b;
      case LyricStyle.classic:
        return b.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0);
      case LyricStyle.boldCard:
        return b.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.4);
      case LyricStyle.glow:
        return b.copyWith(fontWeight: FontWeight.w800);
      case LyricStyle.typewriter:
        return b.copyWith(
            fontFamily: 'monospace', fontWeight: FontWeight.w600, letterSpacing: 0);
      case LyricStyle.calm:
        return b.copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.2);
    }
  }

  /// Returns null when the built-in Prism rendering should be used.
  static Widget? body({
    required LyricStyle s,
    required LyricLine line,
    required bool active,
    required TextStyle style,
    required Color accent,
    required Color dim,
    required ValueListenable<int> pos,
  }) {
    final text = line.text.trim().isEmpty ? '♪' : line.text;
    switch (s) {
      case LyricStyle.prism:
        return null;
      case LyricStyle.classic:
        if (active && line.hasWords) return null; // keep word-by-word fill
        return Text(text, style: style.copyWith(color: active ? accent : dim));
      case LyricStyle.boldCard:
        if (!active) return Text(text, style: style.copyWith(color: dim));
        final fg = accent.computeLuminance() > 0.5 ? Colors.black : Colors.white;
        return DecoratedBox(
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(text, style: style.copyWith(color: fg)),
          ),
        );
      case LyricStyle.glow:
        return Text(
          text,
          style: style.copyWith(
            color: active ? Colors.white : dim,
            shadows: active
                ? [
                    Shadow(color: accent.withOpacity(0.9), blurRadius: 14),
                    Shadow(color: accent.withOpacity(0.6), blurRadius: 32),
                  ]
                : null,
          ),
        );
      case LyricStyle.typewriter:
        if (!active) return Text(text, style: style.copyWith(color: dim));
        return ValueListenableBuilder<int>(
          valueListenable: pos,
          builder: (context, ms, _) {
            final start = line.timeMs;
            final end = line.endMs > start ? line.endMs : start + 3000;
            final t = ((ms - start) / ((end - start) * 0.85)).clamp(0.0, 1.0);
            final runes = text.runes.toList();
            final n = (runes.length * t).ceil();
            return RichText(
              text: TextSpan(children: [
                TextSpan(
                    text: String.fromCharCodes(runes.take(n)),
                    style: style.copyWith(color: accent)),
                TextSpan(
                    text: String.fromCharCodes(runes.skip(n)),
                    style: style.copyWith(color: Colors.transparent)),
              ]),
            );
          },
        );
      case LyricStyle.calm:
        return Text(text,
            style: style.copyWith(color: active ? Colors.white.withOpacity(0.92) : dim));
    }
  }
}

/// Drop into a settings page.
class LyricStylePicker extends StatelessWidget {
  const LyricStylePicker({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LyricStyle>(
        valueListenable: LyricStylePrefs.style,
        builder: (context, cur, _) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in LyricStyle.values)
              ChoiceChip(
                label: Text(s.label),
                selected: s == cur,
                onSelected: (_) => LyricStylePrefs.set(s),
              ),
          ],
        ),
      );
}
