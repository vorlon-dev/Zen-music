// ZenMusic · vorlon-dev
//
// Look of the web player, matched to the Android / Windows app: pure black
// background, dark grey cards, pill controls and a soft rose accent.

import 'package:flutter/material.dart';

const Color kBg = Color(0xFF000000);
const Color kCard = Color(0xFF121212);
const Color kPill = Color(0xFF1E1E1E);
const Color kAccent = Color(0xFFE9B7BE);
const Color kOnAccent = Color(0xFF3A1A20);
const Color kTonal = Color(0xFF4A2A30);
const Color kMiniStart = Color(0xFF2A0D12);
const Color kMiniEnd = Color(0xFF120508);
const String kFont = 'ZenSansFlex';

ThemeData zenTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: kAccent,
          onPrimary: kOnAccent,
          surface: kBg,
          onSurface: Colors.white,
          surfaceContainerHigh: kPill,
          surfaceContainerHighest: kCard,
        )
      : ColorScheme.fromSeed(seedColor: kAccent, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kFont,
    scaffoldBackgroundColor: dark ? kBg : const Color(0xFFF8F3F4),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: dark ? kPill : const Color(0xFFEDE4E6),
      selectedColor: dark ? Colors.white : kOnAccent,
      labelStyle: TextStyle(color: dark ? Colors.white : Colors.black87),
      secondaryLabelStyle: TextStyle(color: dark ? Colors.black : Colors.white),
      checkmarkColor: dark ? Colors.black : Colors.white,
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 8,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: dark ? Colors.white24 : Colors.black12,
      thumbColor: scheme.primary,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: SliderComponentShape.noOverlay,
      trackShape: const RoundedRectSliderTrackShape(),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? kPill : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? kPill : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF0E0E0E) : null,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Round white play button used on tiles and cards.
class PlayDot extends StatelessWidget {
  const PlayDot({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.play_arrow_rounded,
            color: Colors.black, size: size * 0.65),
      );
}
