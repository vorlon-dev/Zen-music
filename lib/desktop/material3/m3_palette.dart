// SP-58: Material 3 theme — exact PixelMusic palette.
//
// Extracted 1:1 from PixelMusic (github.com/ianshulyadav/PixelMusic),
// ui/theme/Color.kt + Theme.kt. ZenMusic keeps its own name/branding;
// only the DESIGN SYSTEM is adopted. Single source of truth on Android is
// res/values/material3_tokens.xml (read by Material3Tokens.kt and fetched
// over the zen/material3_tokens channel — see m3_bridge.dart); the values
// below are the identical Dart fallback so Windows and pre-rebuild builds
// render the same theme.

import 'package:flutter/material.dart';

/// PixelMusic brand colors (Color.kt, verbatim).
class ZenM3Palette {
  ZenM3Palette._();

  // Dark scheme anchors.
  static const Color darkPrimary = Color(0xFFAB47BC); // PixelPlayerPurplePrimary
  static const Color darkSecondary = Color(0xFFF06292); // PixelPlayerPink
  static const Color darkTertiary = Color(0xFFFF8A65); // PixelPlayerOrange
  static const Color darkBackground = Color(0xFF1E1234); // PixelPlayerPurpleDark
  static const Color darkSurface = Color(0xFF2A1F40); // PixelPlayerSurface
  static const Color darkOnSurface = Color(0xFFE1BEE7); // PixelPlayerLightPurple
  static const Color darkError = Color(0xFFFF5252);

  // Light scheme anchors.
  static const Color lightPrimary = Color(0xFF6C4FF5); // LightPrimary
  static const Color lightPrimaryContainer = Color(0xFFE3DBFF);
  static const Color lightOnPrimaryContainer = Color(0xFF23005C);
  static const Color lightSecondary = Color(0xFFF06292); // PixelPlayerPink
  static const Color lightTertiary = Color(0xFFFF8A65); // PixelPlayerOrange
  static const Color lightBackground = Color(0xFFF7F2FF);
  static const Color lightSurface = Color(0xFFFBF8FF);
  static const Color lightSurfaceVariant = Color(0xFFE8DEF9);
  static const Color lightOnSurface = Color(0xFF1E1237); // LightOnSurface
  static const Color lightOnSurfaceVariant = Color(0xFF4D4165);
  static const Color lightOutline = Color(0xFF78659A);
  static const Color lightError = Color(0xFFD32F2F);

  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  /// Derived M3 dark containers (PixelMusic relies on MaterialTheme's
  /// defaults blended over the anchors — reproduced here so Windows and
  /// pre-channel builds match Android exactly).
  static const Color darkPrimaryContainer = Color(0xFF3D2350);
  static const Color darkOnPrimaryContainer = Color(0xFFF6D9FF);
  static const Color darkSecondaryContainer = Color(0xFF4A2540);
  static const Color darkOnSecondaryContainer = Color(0xFFFFD9E6);
  static const Color darkTertiaryContainer = Color(0xFF57321E);
  static const Color darkOnTertiaryContainer = Color(0xFFFFDBD1);

  /// M3 surface container ladder over the dark surface (PixelMusic lets
  /// the M3 defaults derive these; the ladder is tuned to sit on
  /// #2A1F40 without washing out).
  static const Color darkSurfaceLowest = Color(0xFF150C27);
  static const Color darkSurfaceLow = Color(0xFF241A38);
  static const Color darkSurfaceContainer = Color(0xFF2E2244);
  static const Color darkSurfaceContainerHigh = Color(0xFF392C4F);
  static const Color darkSurfaceContainerHighest = Color(0xFF44375B);

  /// Light M3 container ladder.
  static const Color lightSecondaryContainer = Color(0xFFFFD9E6);
  static const Color lightOnSecondaryContainer = Color(0xFF5C1140);
  static const Color lightTertiaryContainer = Color(0xFFFFDBD1);
  static const Color lightOnTertiaryContainer = Color(0xFF3A0B00);
  static const Color lightSurfaceLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceLow = Color(0xFFFAF5FF);
  static const Color lightSurfaceContainer = Color(0xFFF2ECFA);
  static const Color lightSurfaceContainerHigh = Color(0xFFECE6F5);
  static const Color lightSurfaceContainerHighest = Color(0xFFE6E1EF);
}
