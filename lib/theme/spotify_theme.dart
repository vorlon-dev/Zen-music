import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ZenMusic — Black + Oxblood dark theme (final palette).
///
/// User palette (nothing omitted):
///   Background #0C0A0B → SpotifyColors.background
///   Surface    #171113 → SpotifyColors.surface
///   Card       #211619 → SpotifyColors.surfaceLight
///   Primary    #8E3F4B → SpotifyColors.green       (accent everywhere)
///   Accent     #B9626D → SpotifyColors.highlight   (secondary accent)
///   Text       #F5EDEE → SpotifyColors.textPrimary
///   Muted      #968589 → SpotifyColors.textSecondary
///   Divider    #302124 → SpotifyColors.surfaceLighter / outlineVariant
///
/// Derived (tunable — not from the user's list):
///   greenDark    #5C262F  deep oxblood (containers, gradients)
///   textTertiary #6E5F63  faintest text
class SpotifyColors {
  static const background = Color(0xFF0C0A0B);
  static const surface = Color(0xFF171113);
  static const surfaceLight = Color(0xFF211619); // Card
  static const surfaceLighter = Color(0xFF302124); // Divider tone
  static const green = Color(0xFF8E3F4B); // Primary (oxblood)
  static const greenDark = Color(0xFF5C262F); // Deep oxblood (derived)
  static const highlight = Color(0xFFB9626D); // Accent
  static const textPrimary = Color(0xFFF5EDEE);
  static const textSecondary = Color(0xFF968589);
  static const textTertiary = Color(0xFF6E5F63);
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
        onPrimary: SpotifyColors.textPrimary,
        primaryContainer: SpotifyColors.greenDark,
        onPrimaryContainer: SpotifyColors.textPrimary,
        secondary: SpotifyColors.highlight,
        onSecondary: SpotifyColors.greenDark,
        secondaryContainer: SpotifyColors.surfaceLighter,
        onSecondaryContainer: SpotifyColors.textPrimary,
        tertiary: SpotifyColors.highlight,
        onTertiary: SpotifyColors.greenDark,
        tertiaryContainer: SpotifyColors.surfaceLighter,
        onTertiaryContainer: SpotifyColors.textPrimary,
        surface: SpotifyColors.surface,
        onSurface: SpotifyColors.textPrimary,
        onSurfaceVariant: SpotifyColors.textSecondary,
        surfaceContainerLowest: Color(0xFF080708),
        surfaceContainerLow: SpotifyColors.surface,
        surfaceContainer: SpotifyColors.surfaceLight,
        surfaceContainerHigh: SpotifyColors.surfaceLight,
        surfaceContainerHighest: SpotifyColors.surfaceLighter,
        surfaceDim: SpotifyColors.background,
        surfaceBright: SpotifyColors.surfaceLight,
        outline: SpotifyColors.textTertiary,
        outlineVariant: SpotifyColors.surfaceLighter,
        inverseSurface: SpotifyColors.textPrimary,
        onInverseSurface: Color(0xFF171113),
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
        selectedItemColor: SpotifyColors.textPrimary,
        unselectedItemColor: SpotifyColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: SpotifyColors.green,
        inactiveTrackColor: SpotifyColors.surfaceLighter,
        thumbColor: SpotifyColors.highlight,
        overlayColor: Color(0x338E3F4B),
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
        selectedColor: SpotifyColors.greenDark,
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
          foregroundColor: SpotifyColors.textPrimary,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.selected)
            ? SpotifyColors.textPrimary
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