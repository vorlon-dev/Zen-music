import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

class GradientBackground extends StatefulWidget {
  final String imageUrl;
  final Widget child;

  const GradientBackground({
    super.key,
    required this.imageUrl,
    required this.child,
  });

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground> {
  Color _dominant = const Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _updateColor();
  }

  @override
  void didUpdateWidget(covariant GradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _updateColor();
    }
  }

  Future<void> _updateColor() async {
    try {
      final generator = await PaletteGeneratorMaster.fromImageProvider(
        CachedNetworkImageProvider(widget.imageUrl),
        maximumColorCount: 8,          // Small palette = faster
        generateHarmony: false,        // We only need one color
        colorSpace: ColorSpace.rgb,    // Faster than LAB
        timeout: const Duration(seconds: 10),
        // Only sample a small portion of the image for speed.
        region: const Rect.fromLTWH(0, 0, 200, 200),
      );

      if (!mounted) return;

      // Prefer vibrant → darkVibrant → muted → dominant, then fall back.
      final picked =
          generator.darkVibrantColor?.color ??
              generator.vibrantColor?.color ??
              generator.darkMutedColor?.color ??
              generator.mutedColor?.color ??
              generator.dominantColor?.color ??
              const Color(0xFF1A1A1A);

      setState(() => _dominant = picked);
    } catch (e) {
      // Silently fail — keep the default dark background.
      debugPrint('GradientBackground: palette extraction failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _dominant.withOpacity(0.9),
            Color.lerp(_dominant, Colors.black, 0.6)!.withOpacity(0.95),
            const Color(0xFF0A0A0A),
          ],
          stops: const [0.0, 0.45, 0.85],
        ),
      ),
      child: widget.child,
    );
  }
}