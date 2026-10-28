// SP-54: Liquid Glass — whole-app glass ThemeData.
//
// When SettingsManager.liquidGlass is ON, ZenDesktopApp swaps AppTheme for
// ZenLiquidTheme so the ENTIRE app (every page, card, rail and bar built on
// colorScheme surfaces) turns into translucent glass sitting over the
// LiquidBackdrop aurora:
//   • Windows — shader glass via liquid_glass_widgets (ZenGlassPanel).
//   • Android — the glass surfaces themselves are rendered natively in
//     Kotlin (android/app/src/main/kotlin/com/zen/music/zenmusic/liquid/)
//     and bridged in as platform views.
//
// Surface colors are intentionally TRANSLUCENT (alpha over the aurora) —
// that is what makes the whole app read as liquid glass without touching
// every screen. Keep them translucent; opaque values break the illusion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/typography.dart';

class ZenLiquidTheme {
  static ThemeData light({Color? primary}) {
    const onGlass = Color(0xFF14151A);
    final accent = primary ?? const Color(0xFF5B5BD6);

    final colorScheme = ColorScheme.light(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      surface: Colors.white.withValues(alpha: 0.38),
      onSurface: onGlass,
      onSurfaceVariant: onGlass.withValues(alpha: 0.66),
      surfaceContainerLowest: Colors.white.withValues(alpha: 0.22),
      surfaceContainerLow: Colors.white.withValues(alpha: 0.30),
      surfaceContainer: Colors.white.withValues(alpha: 0.38),
      surfaceContainerHigh: Colors.white.withValues(alpha: 0.46),
      surfaceContainerHighest: Colors.white.withValues(alpha: 0.56),
      surfaceTint: Colors.transparent,
      primaryContainer: Colors.white.withValues(alpha: 0.45),
      onPrimaryContainer: onGlass,
      outlineVariant: Colors.black.withValues(alpha: 0.10),
      error: const Color(0xFFB3261E),
      onError: Colors.white,
    );

    return ThemeData.light(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: appTextTheme(ThemeData.light().textTheme),
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        unselectedIconTheme: const IconThemeData(color: onGlass),
        selectedIconTheme: IconThemeData(color: accent),
        indicatorColor: accent.withValues(alpha: 0.20),
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: TextStyle(
            color: accent, fontSize: 11, fontWeight: FontWeight.bold),
        unselectedLabelTextStyle:
            TextStyle(color: onGlass.withValues(alpha: 0.6), fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.08),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.30),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.72),
        surfaceTintColor: Colors.transparent,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: Map<TargetPlatform, PageTransitionsBuilder>.fromIterable(
          TargetPlatform.values,
          value: (_) => const FadeForwardsPageTransitionsBuilder(),
        ),
      ),
    );
  }

  static ThemeData dark({Color? primary}) {
    const onGlass = Colors.white;
    final accent = primary ?? const Color(0xFF9DA8FF);

    final colorScheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.black,
      secondary: accent,
      onSecondary: Colors.black,
      surface: Colors.black.withValues(alpha: 0.34),
      onSurface: onGlass,
      onSurfaceVariant: Colors.white.withValues(alpha: 0.70),
      surfaceContainerLowest: Colors.black.withValues(alpha: 0.18),
      surfaceContainerLow: Colors.black.withValues(alpha: 0.26),
      surfaceContainer: Colors.black.withValues(alpha: 0.34),
      surfaceContainerHigh: Colors.black.withValues(alpha: 0.44),
      surfaceContainerHighest: Colors.black.withValues(alpha: 0.55),
      surfaceTint: Colors.transparent,
      primaryContainer: Colors.white.withValues(alpha: 0.14),
      onPrimaryContainer: Colors.white,
      outlineVariant: Colors.white.withValues(alpha: 0.12),
      error: const Color(0xFFFF6B6B),
      onError: Colors.black,
    );

    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: appTextTheme(ThemeData.dark().textTheme),
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        unselectedIconTheme: const IconThemeData(color: Colors.white),
        selectedIconTheme: IconThemeData(color: accent),
        indicatorColor: Colors.white.withValues(alpha: 0.16),
        labelType: NavigationRailLabelType.all,
        selectedLabelTextStyle: TextStyle(
            color: accent, fontSize: 11, fontWeight: FontWeight.bold),
        unselectedLabelTextStyle:
            TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.10),
      ),
      cardTheme: CardThemeData(
        color: Colors.black.withValues(alpha: 0.30),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.black.withValues(alpha: 0.62),
        surfaceTintColor: Colors.transparent,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: Map<TargetPlatform, PageTransitionsBuilder>.fromIterable(
          TargetPlatform.values,
          value: (_) => const FadeForwardsPageTransitionsBuilder(),
        ),
      ),
    );
  }
}
