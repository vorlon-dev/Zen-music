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
      colorScheme: const ColorScheme.dark(
        primary: SpotifyColors.green,
        secondary: SpotifyColors.green,
        surface: SpotifyColors.surface,
        onPrimary: SpotifyColors.background,
        onSecondary: SpotifyColors.background,
        onSurface: SpotifyColors.textPrimary,
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