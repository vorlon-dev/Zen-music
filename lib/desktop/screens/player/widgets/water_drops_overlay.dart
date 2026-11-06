// ZenMusic · vorlon-dev

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Highly optimized ambient water drops & condensation overlay widget.
/// Simulates raindrops falling and sliding down wet glass / window pane,
/// with scattered stationary condensation micro-drops and moving trickling drops.
class WaterDropsOverlay extends StatefulWidget {
  const WaterDropsOverlay({
    super.key,
    this.intensity = 1.0,
    this.staticDropCount = 45,
    this.movingDropCount = 18,
    this.dropletColor = const Color(0xFFFFFFFF),
  });

  final double intensity;
  final int staticDropCount;
  final int movingDropCount;
  final Color dropletColor;

  @override
  State<WaterDropsOverlay> createState() => _WaterDropsOverlayState();
}

class _WaterDropsOverlayState extends State<WaterDropsOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  late List<_StaticDrop> _staticDrops;
  late List<_MovingDrop> _movingDrops;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _initDroplets();
    _ticker = createTicker(_onTick)..start();
  }

  void _initDroplets() {
    _staticDrops = List.generate(widget.staticDropCount, (i) {
      return _StaticDrop(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        radius: 1.0 + _rng.nextDouble() * 3.5,
        opacity: 0.25 + _rng.nextDouble() * 0.45,
        aspectRatio: 0.8 + _rng.nextDouble() * 0.4,
      );
    });

    _movingDrops = List.generate(widget.movingDropCount, (i) {
      return _spawnMovingDrop(initialY: _rng.nextDouble());
    });
  }

  _MovingDrop _spawnMovingDrop({double? initialY}) {
    final speed = 0.08 + _rng.nextDouble() * 0.22; // fraction of height per sec
    return _MovingDrop(
      x: _rng.nextDouble(),
      y: initialY ?? (-0.05 - _rng.nextDouble() * 0.2),
      radius: 1.8 + _rng.nextDouble() * 3.2,
      speed: speed,
      opacity: 0.35 + _rng.nextDouble() * 0.5,
      trailLength: 12.0 + _rng.nextDouble() * 26.0,
      jitter: (_rng.nextDouble() - 0.5) * 0.0003,
      delay: initialY == null ? _rng.nextDouble() * 1.5 : 0.0,
    );
  }

  void _onTick(Duration elapsed) {
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    // Cap dt in case of backgrounding or lag spike
    final clampedDt = dt.clamp(0.0, 0.1);

    var needsUpdate = false;
    for (var i = 0; i < _movingDrops.length; i++) {
      final drop = _movingDrops[i];
      if (drop.delay > 0) {
        drop.delay -= clampedDt;
        continue;
      }

      drop.y += drop.speed * clampedDt;
      drop.x = (drop.x + drop.jitter).clamp(0.01, 0.99);

      // Drops leave tiny condensation or accelerate slightly
      if (drop.y > 1.1) {
        _movingDrops[i] = _spawnMovingDrop();
      }
      needsUpdate = true;
    }

    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _WaterDropsPainter(
            staticDrops: _staticDrops,
            movingDrops: _movingDrops,
            color: widget.dropletColor,
          ),
        ),
      ),
    );
  }
}

class _StaticDrop {
  _StaticDrop({
    required this.x,
    required this.y,
    required this.radius,
    required this.opacity,
    required this.aspectRatio,
  });

  final double x;
  final double y;
  final double radius;
  final double opacity;
  final double aspectRatio;
}

class _MovingDrop {
  _MovingDrop({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.trailLength,
    required this.jitter,
    required this.delay,
  });

  double x;
  double y;
  final double radius;
  final double speed;
  final double opacity;
  final double trailLength;
  final double jitter;
  double delay;
}

class _WaterDropsPainter extends CustomPainter {
  _WaterDropsPainter({
    required this.staticDrops,
    required this.movingDrops,
    required this.color,
  });

  final List<_StaticDrop> staticDrops;
  final List<_MovingDrop> movingDrops;
  final Color color;

  static final Paint _highlightPaint = Paint()..isAntiAlias = true;
  static final Paint _bodyPaint = Paint()..isAntiAlias = true;
  static final Paint _shadowPaint = Paint()..isAntiAlias = true;
  static final Paint _trailPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;

    // 1. Draw static condensation drops
    for (final drop in staticDrops) {
      final cx = drop.x * w;
      final cy = drop.y * h;
      final r = drop.radius;
      final rx = r;
      final ry = r * drop.aspectRatio;

      final rect = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2);

      // Drop shadow (bottom-right edge)
      _shadowPaint.color = Colors.black.withValues(alpha: drop.opacity * 0.45);
      canvas.drawOval(
        rect.shift(const Offset(0.6, 0.8)),
        _shadowPaint,
      );

      // Glass droplet refraction / body
      _bodyPaint.color = color.withValues(alpha: drop.opacity * 0.35);
      canvas.drawOval(rect, _bodyPaint);

      // Top specular highlight (tiny glint of light)
      _highlightPaint.color = Colors.white.withValues(alpha: (drop.opacity * 1.2).clamp(0.0, 0.95));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - rx * 0.28, cy - ry * 0.3),
          width: rx * 0.7,
          height: ry * 0.6,
        ),
        _highlightPaint,
      );
    }

    // 2. Draw moving trickling drops with wet trail
    for (final drop in movingDrops) {
      if (drop.delay > 0 || drop.y < -0.05 || drop.y > 1.05) continue;

      final cx = drop.x * w;
      final cy = drop.y * h;
      final r = drop.radius;

      // Wet trail behind the sliding drop
      final trailStartY = (cy - drop.trailLength).clamp(0.0, h);
      if (trailStartY < cy) {
        _trailPaint.strokeWidth = r * 0.65;
        _trailPaint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: drop.opacity * 0.3),
          ],
        ).createShader(Rect.fromLTRB(cx - 2, trailStartY, cx + 2, cy));

        canvas.drawLine(
          Offset(cx, trailStartY),
          Offset(cx, cy - r * 0.5),
          _trailPaint,
        );
        _trailPaint.shader = null;
      }

      // Drop shadow
      _shadowPaint.color = Colors.black.withValues(alpha: drop.opacity * 0.5);
      canvas.drawCircle(Offset(cx + 0.8, cy + 1.0), r, _shadowPaint);

      // Drop body
      _bodyPaint.color = color.withValues(alpha: drop.opacity * 0.4);
      canvas.drawCircle(Offset(cx, cy), r, _bodyPaint);

      // Top-left specular glint
      _highlightPaint.color = Colors.white.withValues(alpha: (drop.opacity * 1.3).clamp(0.0, 0.95));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx - r * 0.3, cy - r * 0.3),
          width: r * 0.75,
          height: r * 0.65,
        ),
        _highlightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaterDropsPainter oldDelegate) => true;
}
