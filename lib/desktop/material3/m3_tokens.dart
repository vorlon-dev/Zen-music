// SP-58: Material 3 — design tokens extracted from PixelMusic
// (ui/theme/Shape.kt, Type.kt, and the M3 expressive component metrics its
// screens rely on). Values here are the Dart fallback of
// android/app/src/main/res/values/material3_tokens.xml.

/// PixelMusic Shapes (Shape.kt, verbatim).
class ZenM3Shapes {
  ZenM3Shapes._();
  static const double small = 8;
  static const double medium = 16;
  static const double large = 24;
}

/// M3 NavigationBar metrics (PixelMusic nav bar + CustomNavigationBarItem).
class ZenM3Nav {
  ZenM3Nav._();
  /// M3 NavigationBar height (standard).
  static const double barHeight = 80;
  /// Active indicator pill: 64×32, fully rounded.
  static const double indicatorHeight = 32;
  static const double indicatorWidth = 64;
  static const double indicatorRadius = 16;
  /// Label typography = M3 labelMedium (PixelMusic nav labels).
  static const double labelSize = 14;
}

/// M3 slider / seek bar metrics (PixelMusic EfficientSlider +
/// WavySliderExpressive).
class ZenM3SliderMetrics {
  ZenM3SliderMetrics._();
  /// Expressive wave: rest amplitude, active amplitude, wavelength.
  static const double waveAmpRest = 2.0;
  static const double waveAmpActive = 5.0;
  static const double waveLength = 14.0;
  /// Straight-track fallback thickness.
  static const double trackHeight = 16;
  static const double trackHeightSlim = 4;
  static const double thumbRadius = 10;
  /// Stop indicator dot at the track end (M3 spec).
  static const double stopIndicatorRadius = 2;
}

/// Mini player metrics (PixelMusic UnifiedPlayerSheetShared collapsed bar).
class ZenM3MiniPlayer {
  ZenM3MiniPlayer._();
  static const double height = 64;
  static const double radius = 16;
  static const double artRadius = 12;
  static const double progressLineHeight = 3;
}
