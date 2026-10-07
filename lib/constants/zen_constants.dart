import 'package:flutter/material.dart';

/// ZenMusic shared layout constants.
///
/// Centralized versions of values that previously lived inline across
/// screens. Keep in sync:
///   - [_miniPlayerFootprint] mirrors MiniPlayer in home_screen.dart
///     (height 72 + vertical padding 8 + 8).
class ZenConstants {
  ZenConstants._();

  // ── Mini player ──
  /// Height (72) + vertical padding (8 top + 8 bottom). Used by
  /// toast offsets and any bottom overlay that must clear it.
  static const double miniPlayerFootprint = 88;

  // ── List-block corners (getItemBorderRadius users) ──
  static const double barRadiusValue = 12.0;
  static final BorderRadius barRadius = BorderRadius.circular(barRadiusValue);
  static final BorderRadius barRadiusFirst =
  BorderRadius.vertical(top: Radius.circular(barRadiusValue));
  static final BorderRadius barRadiusLast =
  BorderRadius.vertical(bottom: Radius.circular(barRadiusValue));

  // ── Scroll paddings ──
  /// Home/search bottom padding that clears the floating mini player
  /// + nav bar (extendBody).
  static const EdgeInsets bottomClearPadding =
  EdgeInsets.only(bottom: 170);

  /// Standard horizontal gutter for shelf rows and collection rows.
  static const EdgeInsets shelfHorizontalPadding =
  EdgeInsets.symmetric(horizontal: 20);
}