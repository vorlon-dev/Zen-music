// SP-58: Material 3 — the whole-app ThemeData.
//
// Mirrors PixelMusic's PixelPlayerTheme (ui/theme/Theme.kt + Type.kt):
//   • exact ColorSchemes (dark + light, verbatim anchors),
//   • the full M3 type scale on the bundled Google Sans Flex variable
//     font (OFL — see assets/fonts/GoogleSansFlex-OFL.txt; PixelMusic's
//     "RoundedSans" is the same file with the ROND axis maxed, which is
//     how a rounded variable font reads as one family),
//   • Shapes 8 / 16 / 24 (Shape.kt),
//   • M3 expressive component theming: thick rounded sliders with the
//     stop indicator, NavigationBar / NavigationRail active-indicator
//     pills, filled buttons at M3 heights, cards at 12dp radii, surface
//     app bars — so every screen (built on Theme.of(context)) re-skins
//     itself without touching page code.

import 'package:flutter/material.dart';

import 'm3_palette.dart';
import 'm3_tokens.dart';

/// Font family declared in pubspec.yaml (assets/fonts/gflex_variable.ttf).
const String kZenM3FontFamily = 'ZenSansFlex';

const Color _darkOnSurfaceVariant = Color(0xFFCBBCF0);
const Color _lightOnPrimary = Color(0xFFFFFFFF);

TextStyle _m3Text(
    {required double size,
    required double height,
    required FontWeight weight,
    double letterSpacing = 0,
    double? wOff}) {
  return TextStyle(
    fontFamily: kZenM3FontFamily,
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: letterSpacing,
  );
}

/// Full M3 type scale — PixelMusic Typography (Type.kt, verbatim values).
TextTheme _zenM3TextTheme(TextTheme base) {
  return base.copyWith(
    displayLarge: _m3Text(
        size: 48, height: 56 / 48, weight: FontWeight.bold),
    displayMedium: _m3Text(
        size: 36, height: 44 / 36, weight: FontWeight.bold),
    displaySmall: _m3Text(
        size: 30, height: 38 / 30, weight: FontWeight.normal),
    headlineLarge: _m3Text(
        size: 32, height: 40 / 32, weight: FontWeight.w600),
    headlineMedium: _m3Text(
        size: 28, height: 36 / 28, weight: FontWeight.w600),
    headlineSmall: _m3Text(
        size: 24, height: 32 / 24, weight: FontWeight.w600),
    titleLarge: _m3Text(
        size: 22, height: 28 / 22, weight: FontWeight.normal),
    titleMedium: _m3Text(
        size: 18,
        height: 24 / 18,
        weight: FontWeight.w500,
        letterSpacing: 0.15),
    titleSmall: _m3Text(
        size: 14,
        height: 20 / 14,
        weight: FontWeight.w500,
        letterSpacing: 0.1),
    bodyLarge: _m3Text(
        size: 16,
        height: 24 / 16,
        weight: FontWeight.normal,
        letterSpacing: 0.5),
    bodyMedium: _m3Text(
        size: 14,
        height: 20 / 14,
        weight: FontWeight.normal,
        letterSpacing: 0.25),
    bodySmall: _m3Text(
        size: 12,
        height: 16 / 12,
        weight: FontWeight.normal,
        letterSpacing: 0.4),
    labelLarge: _m3Text(
        size: 16,
        height: 20 / 16,
        weight: FontWeight.w500,
        letterSpacing: 0.1),
    labelMedium: _m3Text(
        size: 14,
        height: 16 / 14,
        weight: FontWeight.w500,
        letterSpacing: 0.5),
    labelSmall: _m3Text(
        size: 11,
        height: 16 / 11,
        weight: FontWeight.w500,
        letterSpacing: 0.5),
  );
}

ColorScheme _darkScheme() {
  return const ColorScheme.dark(
    primary: ZenM3Palette.darkPrimary,
    onPrimary: ZenM3Palette.white,
    primaryContainer: ZenM3Palette.darkPrimaryContainer,
    onPrimaryContainer: ZenM3Palette.darkOnPrimaryContainer,
    secondary: ZenM3Palette.darkSecondary,
    onSecondary: ZenM3Palette.white,
    secondaryContainer: ZenM3Palette.darkSecondaryContainer,
    onSecondaryContainer: ZenM3Palette.darkOnSecondaryContainer,
    tertiary: ZenM3Palette.darkTertiary,
    onTertiary: ZenM3Palette.white,
    tertiaryContainer: ZenM3Palette.darkTertiaryContainer,
    onTertiaryContainer: ZenM3Palette.darkOnTertiaryContainer,
    error: ZenM3Palette.darkError,
    onError: ZenM3Palette.white,
    // PixelMusic: background = PixelPlayerPurpleDark, surface =
    // PixelPlayerSurface, onSurface = PixelPlayerLightPurple.
    background: ZenM3Palette.darkBackground,
    onBackground: ZenM3Palette.darkOnSurface,
    surface: ZenM3Palette.darkSurface,
    onSurface: ZenM3Palette.darkOnSurface,
    onSurfaceVariant: _darkOnSurfaceVariant,
    surfaceContainerLowest: ZenM3Palette.darkSurfaceLowest,
    surfaceContainerLow: ZenM3Palette.darkSurfaceLow,
    surfaceContainer: ZenM3Palette.darkSurfaceContainer,
    surfaceContainerHigh: ZenM3Palette.darkSurfaceContainerHigh,
    surfaceContainerHighest: ZenM3Palette.darkSurfaceContainerHighest,
    outline: Color(0xFF9A8FB5),
    outlineVariant: Color(0xFF4E4365),
    surfaceTint: ZenM3Palette.darkPrimary,
    scrim: ZenM3Palette.black,
  );
}

ColorScheme _lightScheme() {
  return const ColorScheme.light(
    primary: ZenM3Palette.lightPrimary,
    onPrimary: _lightOnPrimary,
    primaryContainer: ZenM3Palette.lightPrimaryContainer,
    onPrimaryContainer: ZenM3Palette.lightOnPrimaryContainer,
    secondary: ZenM3Palette.lightSecondary,
    onSecondary: ZenM3Palette.white,
    secondaryContainer: ZenM3Palette.lightSecondaryContainer,
    onSecondaryContainer: ZenM3Palette.lightOnSecondaryContainer,
    tertiary: ZenM3Palette.lightTertiary,
    onTertiary: ZenM3Palette.black,
    tertiaryContainer: ZenM3Palette.lightTertiaryContainer,
    onTertiaryContainer: ZenM3Palette.lightOnTertiaryContainer,
    error: ZenM3Palette.lightError,
    onError: ZenM3Palette.white,
    background: ZenM3Palette.lightBackground,
    onBackground: ZenM3Palette.lightOnSurface,
    surface: ZenM3Palette.lightSurface,
    onSurface: ZenM3Palette.lightOnSurface,
    surfaceVariant: ZenM3Palette.lightSurfaceVariant,
    onSurfaceVariant: ZenM3Palette.lightOnSurfaceVariant,
    surfaceContainerLowest: ZenM3Palette.lightSurfaceLowest,
    surfaceContainerLow: ZenM3Palette.lightSurfaceLow,
    surfaceContainer: ZenM3Palette.lightSurfaceContainer,
    surfaceContainerHigh: ZenM3Palette.lightSurfaceContainerHigh,
    surfaceContainerHighest: ZenM3Palette.lightSurfaceContainerHighest,
    outline: ZenM3Palette.lightOutline,
    outlineVariant: Color(0xFFCFC5E3),
    surfaceTint: ZenM3Palette.lightPrimary,
    scrim: ZenM3Palette.black,
  );
}

// SP-58: the whole-app ThemeData — PixelMusic's PixelPlayerTheme ported.
class ZenM3Theme {
  ZenM3Theme._();

  static ThemeData light({Color? primary}) =>
      _build(_lightScheme(), bright: Brightness.light, primary: primary);

  static ThemeData dark({Color? primary}) =>
      _build(_darkScheme(), bright: Brightness.dark, primary: primary);

  static ThemeData _build(ColorScheme scheme,
      {required Brightness bright, Color? primary}) {
    // Accent override (SettingsManager.accentColor) — same contract the
    // glass theme honours: user accent becomes the primary.
    var cs = scheme;
    if (primary != null && primary != cs.primary) {
      cs = scheme.copyWith(primary: primary, surfaceTint: primary);
    }

    final isDark = bright == Brightness.dark;
    final textTheme = _zenM3TextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      // ── App bars: M3 surface style with headline headers ──
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: cs.surfaceTint,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge!.copyWith(color: cs.onSurface),
        iconTheme: IconThemeData(color: cs.onSurfaceVariant),
      ),
      // ── Buttons (M3 specs, exact heights/radii) ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 40),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, 40),
          elevation: 1,
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
          backgroundColor: cs.surfaceContainerLow,
          foregroundColor: cs.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 40),
          side: BorderSide(color: cs.outline),
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
          foregroundColor: cs.primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge,
          foregroundColor: cs.primary,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
      ),
      // SP-64: `fabTheme` only exists on the Flutter master channel — stable
      // SDKs reject it ("No named parameter with the name 'fabTheme'").
      // floatingActionButtonTheme carries the same data on every version.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        elevation: 3,
        shape: const StadiumBorder(),
      ),
      // ── Navigation: M3 active-indicator pills ──
      navigationBarTheme: NavigationBarThemeData(
        height: ZenM3Nav.barHeight,
        backgroundColor: cs.surfaceContainer,
        indicatorColor: cs.secondaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium!.copyWith(color: cs.onSurfaceVariant),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? cs.onSecondaryContainer
                  : cs.onSurfaceVariant,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: cs.secondaryContainer,
        elevation: 0,
        selectedLabelTextStyle:
            textTheme.labelLarge!.copyWith(color: cs.onSurface),
        unselectedLabelTextStyle:
            textTheme.labelLarge!.copyWith(color: cs.onSurfaceVariant),
      ),
      // ── Slider / seek bar: thick rounded M3 track + stop indicator ──
      sliderTheme: SliderThemeData(
        trackHeight: ZenM3SliderMetrics.trackHeight,
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withValues(alpha: 0.12),
        valueIndicatorColor: cs.inverseSurface,
        valueIndicatorTextStyle:
            textTheme.labelMedium!.copyWith(color: cs.onInverseSurface),
        // SP-64: dropped `rangeThumbColor` / `inactiveSliderTrackColor` —
        // stable SliderThemeData has neither parameter. Both were exact
        // duplicates of values already set above (RangeSlider thumbs follow
        // `thumbColor`; the inactive track is `inactiveTrackColor`), so the
        // look is unchanged.
        showValueIndicator: ShowValueIndicator.always,
      ),
      // ── Cards / lists / sheets / dialogs ──
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.medium),
        ),
        iconColor: cs.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.secondaryContainer,
        labelStyle: textTheme.labelLarge!.copyWith(color: cs.onSurface),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.large),
        ),
        titleTextStyle: textTheme.headlineSmall!.copyWith(color: cs.onSurface),
        contentTextStyle: textTheme.bodyMedium!.copyWith(
            color: cs.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        modalBackgroundColor: cs.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(ZenM3Shapes.large)),
        ),
        showDragHandle: true,
        dragHandleColor: cs.onSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle:
            textTheme.bodyMedium!.copyWith(color: cs.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.small),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        hintStyle: textTheme.bodyLarge!.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.small + 4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.small + 4),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: cs.surfaceContainerHighest,
        circularTrackColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant,
        indicatorColor: cs.primary,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        dividerColor: Colors.transparent,
      ),
      dividerTheme:
          DividerThemeData(color: cs.outlineVariant.withValues(alpha: 0.4)),
      popupMenuTheme: PopupMenuThemeData(
        color: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZenM3Shapes.medium),
        ),
        textStyle: textTheme.bodyLarge!.copyWith(color: cs.onSurface),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor:
              WidgetStatePropertyAll(cs.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(ZenM3Shapes.medium))),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.onPrimary;
          return cs.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.surfaceContainerHighest;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? cs.primary
                : Colors.transparent),
        side: BorderSide(color: cs.outline, width: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(cs.primary)),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: cs.inverseSurface,
          borderRadius: BorderRadius.circular(ZenM3Shapes.small),
        ),
        textStyle: textTheme.labelMedium!.copyWith(color: cs.onInverseSurface),
      ),
      // Horizontal hairlines between M3 panels get the outline variant.
      dividerColor: cs.outlineVariant.withValues(alpha: 0.4),
      disabledColor: cs.onSurface.withValues(alpha: 0.38),
      hoverColor: cs.onSurface.withValues(alpha: 0.06),
      focusColor: cs.primary.withValues(alpha: 0.12),
      highlightColor: cs.onSurface.withValues(alpha: 0.08),
      splashColor: cs.onSurface.withValues(alpha: 0.10),
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
      // SP-64: dropped `borderSide:` — ThemeData has no such parameter on any
      // stable channel (master-only). Panel hairlines are already covered by
      // dividerTheme / dividerColor above, which is what they actually read.
    );
  }
}
