import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';
import 'wave_spinner.dart';

/// App-standard loading spinner. Renders the same Material 3 Expressive
/// wavy ring as WaveSpinner so every loading state in the app matches.
class Spinner extends StatelessWidget {
  const Spinner({
    super.key,
    this.size = 28,
    this.strokeWidth = 2.5,
    this.color = SpotifyColors.green,
  });

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: WaveSpinner(
        size: size,
        strokeWidth: strokeWidth,
        color: color,
      ),
    );
  }
}