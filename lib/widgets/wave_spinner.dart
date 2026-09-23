import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// Small wavy spinner — mini-player ring style. Compact by default;
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
      duration: const Duration(milliseconds: 1600),
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
        builder: (context, _) => CustomPaint(
          size: Size(widget.size, widget.size),
          painter: WaveRingPainter(
            phase: _controller.value * 2 * math.pi,
            startAngle: _controller.value * 2 * math.pi,
            sweepAngle: math.pi / 2, // rotating quarter-arc
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

/// Wavy ring painter — shared with the mini player's progress ring.
class WaveRingPainter extends CustomPainter {
  WaveRingPainter({
    required this.phase,
    required this.startAngle,
    required this.sweepAngle,
    required this.color,
    this.backgroundColor,
    this.strokeWidth = 3,
  });

  final double phase;
  final double startAngle;
  final double sweepAngle;
  final Color color;
  final Color? backgroundColor;
  final double strokeWidth;

  static const _waveAmplitude = 1.5;
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
      final wave = _waveAmplitude * math.sin(_waveFrequency * angle + phase);
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
          old.sweepAngle != sweepAngle;
}