import 'package:flutter/material.dart';

class SpotifyColors {
  static const background = Color(0xFF0D0E0F);
  static const surface = Color(0xFF151617);
  static const surfaceLight = Color(0xFF1C1D1F);
  static const surfaceLighter = Color(0xFF232527);
  static const green = Color(0xFFA8C69F);
  static const greenDark = Color(0xFF8FAE86);
  static const textPrimary = Color(0xFFF2F0EA);
  static const textSecondary = Color(0xFF9A9B9B);
  static const textTertiary = Color(0xFF6C6D6D);
}

class SpotifyTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: SpotifyColors.background,
      // ── Full M3 color scheme: every container/tonal color pinned so
      // dialogs, sheets, menus, pickers and chips can never fall back
      // to the light baseline.
      colorScheme: const ColorScheme.dark(
        primary: SpotifyColors.green,
        onPrimary: SpotifyColors.background,
        primaryContainer: SpotifyColors.greenDark,
        onPrimaryContainer: SpotifyColors.background,
        secondary: SpotifyColors.green,
        onSecondary: SpotifyColors.background,
        secondaryContainer: SpotifyColors.surfaceLighter,
        onSecondaryContainer: SpotifyColors.textPrimary,
        tertiary: SpotifyColors.green,
        onTertiary: SpotifyColors.background,
        tertiaryContainer: SpotifyColors.surfaceLighter,
        onTertiaryContainer: SpotifyColors.textPrimary,
        surface: SpotifyColors.surface,
        onSurface: SpotifyColors.textPrimary,
        onSurfaceVariant: SpotifyColors.textSecondary,
        // M3 tonal containers — this is what dialogs/sheets/menus use.
        surfaceContainerLowest: SpotifyColors.background,
        surfaceContainerLow: SpotifyColors.surface,
        surfaceContainer: SpotifyColors.surfaceLight,
        surfaceContainerHigh: SpotifyColors.surfaceLight,
        surfaceContainerHighest: SpotifyColors.surfaceLighter,
        surfaceDim: SpotifyColors.background,
        surfaceBright: SpotifyColors.surfaceLighter,
        outline: SpotifyColors.textTertiary,
        outlineVariant: Color(0xFF2C2E30),
        inverseSurface: SpotifyColors.textPrimary,
        onInverseSurface: SpotifyColors.background,
        inversePrimary: SpotifyColors.greenDark,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SpotifyColors.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: SpotifyColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
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
      textTheme: base.textTheme.apply(
        bodyColor: SpotifyColors.textPrimary,
        displayColor: SpotifyColors.textPrimary,
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: SpotifyColors.green,
        inactiveTrackColor: SpotifyColors.surfaceLighter,
        thumbColor: SpotifyColors.green,
        overlayColor: Color(0x33A8C69F),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
      iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
      dividerColor: Colors.transparent,
      // ── Dialogs (AlertDialog, Dialog) ──
      // ── Dialogs (AlertDialog, Dialog) ──
      dialogTheme: DialogThemeData(
        backgroundColor: SpotifyColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: const TextStyle(
          color: SpotifyColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: SpotifyColors.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      // ── Bottom sheets ──
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
      // ── Popup menus / dropdowns ──
      popupMenuTheme: const PopupMenuThemeData(
        color: SpotifyColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        textStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 14),
      ),
      // ── SnackBars ──
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: SpotifyColors.surfaceLighter,
        contentTextStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 14),
        actionTextColor: SpotifyColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      ),
      // ── Date/time pickers ──
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
        dialHandColor: SpotifyColors.green,
      ),
      // ── Chips (InputChip etc.) ──
      chipTheme: const ChipThemeData(
        backgroundColor: SpotifyColors.surface,
        selectedColor: SpotifyColors.greenDark,
        labelStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 13),
        side: BorderSide(color: Color(0xFF2C2E30)),
        shape: StadiumBorder(),
      ),
      // ── Tooltips ──
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: SpotifyColors.surfaceLighter,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        textStyle: TextStyle(color: SpotifyColors.textPrimary, fontSize: 12),
      ),
      // ── Buttons inside themed surfaces ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SpotifyColors.green,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SpotifyColors.green,
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
        color: SpotifyColors.green,
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