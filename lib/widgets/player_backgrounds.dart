import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator_master/palette_generator_master.dart' as pg;

/// Player background styles ported from the reference Compose player:
/// GlowBackground (animated palette glow), MeshBackground (rotating
/// saturated artwork mesh), AppleArtworkBackground (blurred backdrop +
/// sharp top artwork with fade mask).
///
/// NOTE: the palette package is imported with a prefix on purpose —
/// its exports must never shadow Flutter types (Alignment et al).

// ═════════════════════════════════════════════
// GLOW — 6 palette-colored radial blobs drifting on near-black,
// 20s loop. Colors rotate through the list; positions/radii
// oscillate — exact port of the reference parameters.
// ═════════════════════════════════════════════

class GlowBackground extends StatefulWidget {
  const GlowBackground({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  List<Color> _colors = const [];

  @override
  void initState() {
    super.initState();
    _extract();
  }

  @override
  void didUpdateWidget(covariant GlowBackground old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _extract();
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    try {
      final g = await pg.PaletteGeneratorMaster.fromImageProvider(
        CachedNetworkImageProvider(widget.imageUrl),
        maximumColorCount: 16,
        generateHarmony: false,
        colorSpace: pg.ColorSpace.rgb,
        timeout: const Duration(seconds: 10),
        region: const Rect.fromLTWH(0, 0, 200, 200),
      );
      if (!mounted) return;

      // Reference extraction order: vibrant, darkVibrant, muted,
      // darkMuted, dominant — light variants are synthesized below
      // instead of relying on unverified palette accessors.
      // Palette accessors are nullable, so the literal is List<Color?>
      // and nulls are filtered out before use.
      final base = (<Color?>[
        g.vibrantColor?.color,
        g.darkVibrantColor?.color,
        g.mutedColor?.color,
        g.darkMutedColor?.color,
        g.dominantColor?.color,
      ]).whereType<Color>().toSet().toList();

      if (base.isEmpty) {
        base.addAll([const Color(0xFF2E2E2E), const Color(0xFF1B1B1B)]);
      }

      // Build six working colors; with few base colors, alternate
      // light/dark tints so adjacent blobs stay distinct.
      final six = <Color>[];
      for (var i = 0; i < 6; i++) {
        final c = base[i % base.length];
        six.add(base.length <= 2
            ? Color.lerp(c, i.isEven ? Colors.white : Colors.black, 0.15)!
            : c);
      }
      setState(() => _colors = six);
    } catch (_) {
      // Keep defaults — painter falls back to neutral grays.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      child: KeyedSubtree(
        key: ValueKey(widget.imageUrl),
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, _) => CustomPaint(
              painter: _GlowPainter(progress: _t.value, colors: _colors),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  // Per-blob oscillation ranges and phases — ported 1:1.
  static const List<
      ({
      double xMin, double xMax, double xP,
      double yMin, double yMax, double yP,
      double rMin, double rMax, double rP,
      double a1, double a2,
      })> _blobs = [
    (xMin: 0.0, xMax: 1.0, xP: 0.00, yMin: 0.0, yMax: 0.5, yP: 0.07, rMin: 0.8, rMax: 1.6, rP: 0.12, a1: 0.85, a2: 0.50),
    (xMin: 1.0, xMax: 0.0, xP: 0.20, yMin: 0.5, yMax: 1.0, yP: 0.25, rMin: 0.7, rMax: 1.5, rP: 0.18, a1: 0.80, a2: 0.45),
    (xMin: 0.2, xMax: 0.8, xP: 0.33, yMin: 0.8, yMax: 0.2, yP: 0.36, rMin: 0.6, rMax: 1.4, rP: 0.29, a1: 0.75, a2: 0.40),
    (xMin: 0.3, xMax: 0.7, xP: 0.44, yMin: 0.2, yMax: 0.8, yP: 0.41, rMin: 0.9, rMax: 1.7, rP: 0.47, a1: 0.70, a2: 0.35),
    (xMin: 0.4, xMax: 0.6, xP: 0.55, yMin: 0.0, yMax: 1.0, yP: 0.51, rMin: 0.7, rMax: 1.5, rP: 0.58, a1: 0.65, a2: 0.30),
    (xMin: 0.0, xMax: 1.0, xP: 0.66, yMin: 0.5, yMax: 0.7, yP: 0.62, rMin: 0.8, rMax: 1.8, rP: 0.69, a1: 0.60, a2: 0.25),
  ];

  Color _colorAt(List<Color> c, int i) {
    final n = c.length;
    final idx = i.toDouble() + progress * n;
    final a = idx.floor() % n;
    final b = (a + 1) % n;
    final frac = idx - idx.floor();
    return Color.lerp(c[a], c[b], frac)!;
  }

  double _osc(double min, double max, double phase) {
    final v = math.sin(2 * math.pi * (progress + phase));
    return min + (max - min) * ((v + 1) / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = colors.isEmpty
        ? const [Color(0xFF262626), Color(0xFF1A1A1A)]
        : colors;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF050505),
    );

    for (var i = 0; i < _blobs.length; i++) {
      final b = _blobs[i];
      final color = _colorAt(c, i);
      final center = Offset(
        size.width * _osc(b.xMin, b.xMax, b.xP),
        size.height * _osc(b.yMin, b.yMax, b.yP),
      );
      final radius = size.width * _osc(b.rMin, b.rMax, b.rP);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(center, radius, [
            color.withOpacity(b.a1),
            color.withOpacity(b.a2),
            color.withOpacity(0),
          ], const [0.0, 0.5, 1.0]),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.progress != progress || old.colors != colors;
}

// ═════════════════════════════════════════════
// MESH — three artwork layers (128px decode, 1.8x saturation,
// heavy blur) scaled 1.7x and rotating at 80s / 40s / 60s, under
// dark scrims. Layer anchoring uses FractionalOffset (identical
// result to topStart/bottomEnd, immune to Alignment name clashes).
// ═════════════════════════════════════════════

class MeshBackground extends StatefulWidget {
  const MeshBackground({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground>
    with TickerProviderStateMixin {
  late final AnimationController _anchor =
  AnimationController(vsync: this, duration: const Duration(seconds: 80))
    ..repeat();
  late final AnimationController _fast =
  AnimationController(vsync: this, duration: const Duration(seconds: 40))
    ..repeat();
  late final AnimationController _slow =
  AnimationController(vsync: this, duration: const Duration(seconds: 60))
    ..repeat();

  late final ColorFilter _saturationFilter = _saturationFilterOf(1.8);

  static ColorFilter _saturationFilterOf(double s) {
    // Same constants as the reference saturation matrix.
    const rR = 0.213, rG = 0.715, rB = 0.072;
    final sr = 1 - s;
    return ColorFilter.matrix([
      rR * sr + s, rG * sr,      rB * sr,      0, 0,
      rR * sr,     rG * sr + s,  rB * sr,      0, 0,
      rR * sr,     rG * sr,      rB * sr + s,  0, 0,
      0,           0,            0,            1, 0,
    ]);
  }

  @override
  void dispose() {
    _anchor.dispose();
    _fast.dispose();
    _slow.dispose();
    super.dispose();
  }

  Widget _layer({
    required double angle,
    required FractionalOffset anchor,
    required double blur,
    required double alpha,
    bool saturated = true,
  }) {
    Widget img = Image.network(
      widget.imageUrl,
      fit: BoxFit.cover,
      alignment: anchor,
      cacheWidth: 128,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
    if (saturated) {
      img = ColorFiltered(colorFilter: _saturationFilter, child: img);
    }
    img = ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: img,
    );
    return Opacity(
      opacity: alpha,
      child: Transform.scale(
        scale: 1.7,
        child: Transform.rotate(angle: angle, child: img),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      child: KeyedSubtree(
        key: ValueKey(widget.imageUrl),
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: Listenable.merge([_anchor, _fast, _slow]),
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                _layer(
                  angle: -2 * math.pi * _anchor.value,
                  anchor: const FractionalOffset(0.5, 0.5),
                  blur: 60,
                  alpha: 1,
                ),
                _layer(
                  angle: 2 * math.pi * _fast.value,
                  anchor: const FractionalOffset(0.0, 0.0),
                  blur: 80,
                  alpha: 0.6,
                ),
                _layer(
                  angle: 2 * math.pi * _slow.value,
                  anchor: const FractionalOffset(1.0, 1.0),
                  blur: 80,
                  alpha: 0.5,
                ),
                ColoredBox(color: Colors.black.withOpacity(0.2)),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.25),
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// APPLE ARTWORK STACK — blurred backdrop + sharp artwork across the
// top 65%, fading out via an alpha mask, under a bottom scrim.
// (When a canvas video is available, the player replaces this whole
// background with the canvas — existing precedence.)
// ═════════════════════════════════════════════

class AppleArtworkBackground extends StatelessWidget {
  const AppleArtworkBackground({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred backdrop (small decode — it is only ever blurred).
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            cacheWidth: 128,
            errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Colors.black),
          ),
        ),
        // Sharp artwork, top 65%, fading to transparent at its bottom.
        Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.65,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1200),
              child: KeyedSubtree(
                key: ValueKey(imageUrl),
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFFFFFFF),
                      Color(0x66FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                    stops: [0.0, 0.75, 0.92, 1.0],
                  ).createShader(
                    Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                  ),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Colors.black),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Bottom scrim.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.05),
                  Colors.black.withOpacity(0.4),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}