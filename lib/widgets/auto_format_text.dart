import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// Shared inline-formatter text: renders **bold** spans and converts
/// "* " list markers to bullets. Used by welcome/update/info dialogs
/// wherever a plain string may carry light markdown.
///
/// ZenMusic port of Musify's AutoFormatText (which arrived duplicated
/// in their source — this is the single shared copy, per the
/// one-class-one-file rule). Same API: [AutoFormatText(text: ...)].
///
/// FIX vs Musify's version: the plain runs used the ambient
/// DefaultTextStyle (via TextSpan without a style), which silently
/// drops our theme's Inter family and colors wherever the surrounding
/// DefaultTextStyle is weak (dialogs render bodyMedium anyway, but
/// call sites pass no guaranteed parent) — and bold runs duplicated
/// the same problem. Here the base style is pinned to the theme's
/// bodyMedium in OUR palette, bold derived from it; call sites can
/// still override via [style].
class AutoFormatText extends StatelessWidget {
  AutoFormatText({super.key, required this.text, this.style});

  final String text;

  /// Optional override for the base (non-bold) runs.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];

    final boldExp = RegExp(r'\*\*(.*?)\*\*');
    final matches = boldExp.allMatches(text);
    final base = style ??
        const TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: SpotifyColors.textSecondary,
        );

    var currentTextIndex = 0;

    for (final match in matches) {
      spans
        ..add(
          TextSpan(
            text: text
                .substring(currentTextIndex, match.start)
                .replaceAll('* ', '• '),
            style: base,
          ),
        )
        ..add(
          TextSpan(
            text: match.group(1),
            style: base.copyWith(fontWeight: FontWeight.bold),
          ),
        );

      currentTextIndex = match.end;
    }

    spans.add(
      TextSpan(
        text: text.substring(currentTextIndex).replaceAll('* ', '• '),
        style: base,
      ),
    );

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(children: spans),
    );
  }
}