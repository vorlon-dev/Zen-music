import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'wave_spinner.dart';

/// Echo-style "cookie" play/pause button: a 9-bump wavy circle that
/// morphs in while playing, rotates continuously, and springs on press.
///
/// Shape math matches the reference implementation exactly:
///   r(theta) = 1 - indent + indent * cos(sides * (theta - rotation))
/// indent 0 = perfect circle (paused), indent 0.08 = cookie (playing).
class CookiePlayButton extends StatefulWidget {
  const CookiePlayButton({
    super.key,
    required this.playing,
    required this.onToggle,
    this.loading = false,
    this.size = 84,
    this.background = Colors.white,
    this.iconColor = Colors.black,
    this.iconSize = 36,
    this.sides = 9,
    this.maxIndent = 0.08,
  });

  final bool playing;
  final VoidCallback onToggle;

  /// When true the icon area shows the wavy spinner instead of
  /// play/pause (buffering state); the shape keeps morphing as usual.
  final bool loading;
  final double size;
  final Color background;
  final Color iconColor;
  final double iconSize;
  final int sides;
  final double maxIndent;

  @override
  State<CookiePlayButton> createState() => _CookiePlayButtonState();
}

class _CookiePlayButtonState extends State<CookiePlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _morph;   // indent 0 -> maxIndent
  late final AnimationController _rotation; // 360deg / 8s while playing
  late final AnimationController _scale;    // press spring

  static final _pressSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.6,
  );

  @override
  void initState() {
    super.initState();
    _morph = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: widget.playing ? 1.0 : 0.0,
    );
    _rotation = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    // IMPORTANT: value MUST start at 1.0. AnimationController defaults
    // to 0.0, which renders Transform.scale(0) — an invisible (but
    // tappable) button until the first tap springs it into view.
    _scale = AnimationController(vsync: this, value: 1.0);
    if (widget.playing) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant CookiePlayButton old) {
    super.didUpdateWidget(old);
    if (widget.playing != old.playing) {
      widget.playing ? _morph.forward() : _morph.reverse();
      if (widget.playing) {
        _rotation.repeat(); // continues from current angle
      } else {
        _rotation.stop();
      }
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    _rotation.dispose();
    _scale.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    final target = pressed ? 0.9 : 1.0;
    _scale.animateWith(
      SpringSimulation(_pressSpring, _scale.value, target, 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_morph, _rotation, _scale]),
      builder: (context, _) {
        final indent = widget.maxIndent * _morph.value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: widget.onToggle,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Transform.scale(
              scale: _scale.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _CookiePainter(
                      indent: indent,
                      rotation: _rotation.value * 2 * math.pi,
                      sides: widget.sides,
                      color: widget.background,
                    ),
                  ),
                  if (widget.loading)
                    SizedBox(
                      width: widget.iconSize * 0.82,
                      height: widget.iconSize * 0.82,
                      child: WaveSpinner(
                        size: widget.iconSize * 0.82,
                        strokeWidth: 2.6,
                        color: widget.iconColor,
                      ),
                    )
                  else
                    Icon(
                      widget.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: widget.iconSize,
                      color: widget.iconColor,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CookiePainter extends CustomPainter {
  _CookiePainter({
    required this.indent,
    required this.rotation,
    required this.sides,
    required this.color,
  });

  final double indent;
  final double rotation;
  final int sides;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width / 2;
    final ry = size.height / 2;

    const steps = 120;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final angle = i * math.pi * 2 / steps;
      final bumpAngle = angle - rotation;
      final r = 1 - indent + indent * math.cos(sides * bumpAngle);
      final x = cx + rx * r * math.cos(angle);
      final y = cy + ry * r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CookiePainter old) =>
      old.indent != indent ||
          old.rotation != rotation ||
          old.sides != sides ||
          old.color != color;
}