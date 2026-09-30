import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// Material 3 Expressive wavy loading indicator — a full wavy ring
/// whose wave travels around while the amplitude inflates and deflates
/// once per cycle (the expressive "jelly" pulse). Compact by default;
/// place inside Center()/SizedBox as needed.
class WaveSpinner extends StatefulWidget {
  const WaveSpinner({
    super.key,
    this.size = 22,
    this.strokeWidth = 2.2,
    this.color = SpotifyColors.green,
  });

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  State<WaveSpinner> createState() => _WaveSpinnerState();
}

class _WaveSpinnerState extends State<WaveSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // Amplitude envelope: 0 -> full -> 0 once per cycle, eased —
          // the Material 3 Expressive wavy indicator behavior. The wave
          // phase also travels around the ring for the rolling motion.
          final envelope =
          Curves.easeInOut.transform(math.sin(math.pi * t));
          final maxAmp = math.max(1.0, widget.size * 0.08);
          return CustomPaint(
            size: Size(widget.size, widget.size),
            painter: WaveRingPainter(
              phase: t * 2 * math.pi,
              startAngle: t * 2 * math.pi,
              sweepAngle: 2 * math.pi, // full expressive wavy ring
              color: widget.color,
              strokeWidth: widget.strokeWidth,
              amplitude: maxAmp * envelope,
            ),
          );
        },
      ),
    );
  }
}

/// Wavy ring painter — shared with the mini player's progress ring.
/// [amplitude] is the wave height in pixels; defaults to the original
/// fixed 1.5 so existing callers render identically.
class WaveRingPainter extends CustomPainter {
  WaveRingPainter({
    required this.phase,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
    this.backgroundColor,
    this.strokeWidth = 3,
    this.amplitude = 1.5,
  });

  final double phase;
  final double startAngle;
  final double sweepAngle;
  final Color color;
  final Color? backgroundColor;
  final double strokeWidth;
  final double amplitude;

  static const _waveFrequency = 12.0;

  Path _buildWavyArcPath(Size size, double start, double sweep) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = (size.width - strokeWidth) / 2;
    final steps = (sweep.abs() * 180 / math.pi).round().clamp(6, 720);
    final path = Path();

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = start + sweep * t;
      final wave = amplitude * math.sin(_waveFrequency * angle + phase);
      final r = baseRadius + wave;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = backgroundColor;
    if (bg != null) {
      final trackPaint = Paint()
        ..color = bg
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        _buildWavyArcPath(size, -math.pi / 2, 2 * math.pi),
        trackPaint,
      );
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(_buildWavyArcPath(size, startAngle, sweepAngle), paint);
  }

  @override
  bool shouldRepaint(WaveRingPainter old) =>
      old.phase != phase ||
          old.startAngle != startAngle ||
          old.sweepAngle != sweepAngle ||
          old.amplitude != amplitude;
}