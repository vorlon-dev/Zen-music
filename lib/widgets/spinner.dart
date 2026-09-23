import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

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
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }
}