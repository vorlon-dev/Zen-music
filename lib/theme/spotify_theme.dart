import 'package:flutter/material.dart';

class SpotifyColors {
  static const background = Color(0xFF403600);
  static const surface = Color(0xFF4B4105);
  static const surfaceLight = Color(0xFF574B08);
  static const surfaceLighter = Color(0xFF63560C);
  static const green = Color(0xFFFFDE21);
  static const greenDark = Color(0xFFE0C41E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFD8D2BD);
  static const textTertiary = Color(0xFF9A9480);
}
class ZenFonts {
  static const String display = 'PaytoneOne';
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
        onPrimary: Colors.black,
        onSecondary: Colors.black,
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
        backgroundColor: Color(0xFF322B00),
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
        activeTrackColor: SpotifyColors.textPrimary,
        inactiveTrackColor: SpotifyColors.surfaceLighter,
        thumbColor: SpotifyColors.textPrimary,
        overlayColor: Color(0x33FFFFFF),
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