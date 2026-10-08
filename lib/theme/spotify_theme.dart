import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ZenMusic — Black + Brass gold theme (final palette).
///
/// User palette (nothing omitted):
///   Background #0B0A08 → SpotifyColors.background
///   Surface    #15130F → SpotifyColors.surface   (mini player, nav)
///   Card       #201C15 → SpotifyColors.surfaceLight
///   Primary    #B58A3C → SpotifyColors.green      (brass — buttons, fill)
///   Accent     #D6AD5B → SpotifyColors.highlight  (honey — active, progress)
///   Text       #F5F0E5 → SpotifyColors.textPrimary
///   Muted      #928A78 → SpotifyColors.textSecondary
///   Divider    #302A1D → SpotifyColors.surfaceLighter / outlineVariant
///
/// Derived (tunable — not from the user's list):
///   greenDark    #6B5122  deep brass (containers, gradients)
///   textTertiary #6E675A  faintest text
class SpotifyColors {
  static const background = Color(0xFF0B0A08);
  static const surface = Color(0xFF15130F);
  static const surfaceLight = Color(0xFF201C15); // Card
  static const surfaceLighter = Color(0xFF302A1D); // Divider tone
  static const green = Color(0xFFB58A3C); // Brass gold (primary)
  static const greenDark = Color(0xFF6B5122); // Deep brass (derived)
  static const highlight = Color(0xFFD6AD5B); // Honey gold (accent)
  static const textPrimary = Color(0xFFF5F0E5);
  static const textSecondary = Color(0xFF928A78);
  static const textTertiary = Color(0xFF6E675A);
}

class SpotifyTheme {
  /// Heading font — Playfair Display.
  static const headingFont = 'PlayfairDisplay';

  /// Body/UI font — Inter.
  static const bodyFont = 'Inter';

  static ThemeData dark() {
    // google_fonts: no-argument calls fetch + register both families
    // (version-proof API). Plain fontFamily strings resolve to them.
    GoogleFonts.inter();
    GoogleFonts.playfairDisplay();

    final text = ThemeData.dark(useMaterial3: true).textTheme.apply(
      bodyColor: SpotifyColors.textPrimary,
      displayColor: SpotifyColors.textPrimary,
      fontFamily: bodyFont,
    );

    final headings = text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontFamily: headingFont),
      displayMedium: text.displayMedium?.copyWith(fontFamily: headingFont),
      displaySmall: text.displaySmall?.copyWith(fontFamily: headingFont),
      headlineLarge: text.headlineLarge?.copyWith(fontFamily: headingFont),
      headlineMedium: text.headlineMedium?.copyWith(fontFamily: headingFont),
      headlineSmall: text.headlineSmall?.copyWith(fontFamily: headingFont),
      titleLarge: text.titleLarge?.copyWith(fontFamily: headingFont),
    );

    return ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: SpotifyColors.background,
      colorScheme: const ColorScheme.dark(
        primary: SpotifyColors.green,
        // Dark-on-brass — matches the reference's Play button (#0B0A08
        // text on #B58A3C).
        onPrimary: SpotifyColors.background,
        primaryContainer: Color(0xFF3A2E14),
        onPrimaryContainer: SpotifyColors.textPrimary,
        secondary: SpotifyColors.highlight,
        onSecondary: SpotifyColors.background,
        secondaryContainer: SpotifyColors.surfaceLighter,
        onSecondaryContainer: SpotifyColors.textPrimary,
        tertiary: SpotifyColors.highlight,
        onTertiary: SpotifyColors.background,
        tertiaryContainer: SpotifyColors.surfaceLighter,
        onTertiaryContainer: SpotifyColors.textPrimary,
        surface: SpotifyColors.surface,
        onSurface: SpotifyColors.textPrimary,
        onSurfaceVariant: SpotifyColors.textSecondary,
        surfaceContainerLowest: Color(0xFF080706),
        surfaceContainerLow: SpotifyColors.surface,
        surfaceContainer: SpotifyColors.surfaceLight,
        surfaceContainerHigh: SpotifyColors.surfaceLight,
        surfaceContainerHighest: SpotifyColors.surfaceLighter,
        surfaceDim: SpotifyColors.background,
        surfaceBright: SpotifyColors.surfaceLight,
        outline: SpotifyColors.textTertiary,
        outlineVariant: SpotifyColors.surfaceLighter,
        inverseSurface: SpotifyColors.textPrimary,
        onInverseSurface: SpotifyColors.background,
        inversePrimary: SpotifyColors.highlight,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      textTheme: headings,
      appBarTheme: const AppBarTheme(
        backgroundColor: SpotifyColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: SpotifyColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: headingFont,
        ),
        iconTheme: IconThemeData(color: SpotifyColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: SpotifyColors.surface,
        selectedItemColor: SpotifyColors.highlight,
        unselectedItemColor: SpotifyColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: SpotifyColors.highlight,
        inactiveTrackColor: SpotifyColors.surfaceLighter,
        thumbColor: SpotifyColors.highlight,
        overlayColor: Color(0x33B58A3C),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
      dividerColor: SpotifyColors.surfaceLighter,
      // NOTE: no const — this Flutter version's DialogThemeData
      // constructor is not const.
      dialogTheme: DialogThemeData(
        backgroundColor: SpotifyColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: SpotifyColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          fontFamily: headingFont,
        ),
        contentTextStyle: const TextStyle(
          color: SpotifyColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SpotifyColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: SpotifyColors.surface,
        modalBarrierColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: false,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: SpotifyColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        textStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 14),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: SpotifyColors.surfaceLighter,
        contentTextStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 14),
        actionTextColor: SpotifyColors.highlight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: SpotifyColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: SpotifyColors.surfaceLight,
        headerForegroundColor: SpotifyColors.textPrimary,
        dayStyle: TextStyle(color: SpotifyColors.textPrimary),
        yearStyle: TextStyle(color: SpotifyColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
      ),
      timePickerTheme: const TimePickerThemeData(
        backgroundColor: SpotifyColors.surface,
        dialBackgroundColor: SpotifyColors.surfaceLight,
        hourMinuteColor: SpotifyColors.surfaceLight,
        hourMinuteTextColor: SpotifyColors.textPrimary,
        dialHandColor: SpotifyColors.highlight,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: SpotifyColors.surface,
        selectedColor: Color(0xFF3A2E14),
        labelStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 13),
        side: BorderSide(color: SpotifyColors.surfaceLighter),
        shape: StadiumBorder(),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: SpotifyColors.surfaceLighter,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 12),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SpotifyColors.highlight,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SpotifyColors.green,
          // Dark-on-brass — the reference's Play button treatment.
          foregroundColor: SpotifyColors.background,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? SpotifyColors.background
            : SpotifyColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? SpotifyColors.green
            : SpotifyColors.surfaceLighter),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? SpotifyColors.green
            : Colors.transparent),
        side: const BorderSide(color: SpotifyColors.textTertiary, width: 1.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SpotifyColors.highlight,
        linearTrackColor: SpotifyColors.surfaceLighter,
      ),
    );
  }
}

/// A subtle vertical gradient that fades from a tinted top to the background.
class SpotifyGradient extends StatelessWidget {
  final Widget child;
  final Color tint;

  const SpotifyGradient({
    super.key,
    required this.child,
    this.tint = SpotifyColors.surface,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint,
            SpotifyColors.background,
          ],
          stops: const [0.0, 0.6],
        ),
      ),
      child: child,
    );
  }
}