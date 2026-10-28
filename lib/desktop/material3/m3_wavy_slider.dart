// SP-58: Material 3 expressive WAVY seekbar.
//
// PixelMusic's player seekbar is the M3-expressive `WavySliderExpressive`:
// the active track is a sine wave whose amplitude grows while playing and
// peaks while scrubbing, the inactive remainder is a flat rounded line,
// and a 20dp thumb rides the wave. This is the Flutter port used by the
// ZenMusic mini player (and anywhere else) when the Material 3 theme is
// on. Colors come from the M3 ColorScheme:
//   active wave + thumb  = colorScheme.primary   (PixelMusic thumbColor)
//   inactive track       = colorScheme.surfaceContainerHighest
//   stop indicator       = colorScheme.onSurfaceVariant (M3 spec)

import 'dart:math' as math;

import 'package:flutter/material.dart';
// SP-64: `Ticker` lives in the scheduler library and material.dart does not
// re-export it — the bare `Ticker` field below failed to resolve on stable
// SDKs ("Type 'Ticker' not found" / "'Ticker' isn't a type").
import 'package:flutter/scheduler.dart';

import 'm3_tokens.dart';

class ZenM3WavySlider extends StatefulWidget {
  const ZenM3WavySlider({
    super.key,
    required this.value,
    required this.playing,
    this.onChanged,
    this.onChangeEnd,
    this.height = 44,
    this.compact = false, // SP-58: mini-player progress line mode
  }) : assert(value >= 0.0 && value <= 1.0);

  /// Playback position as a fraction of the duration (0..1).
  final double value;
  final bool playing;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;

  /// Compact mode: a thin, non-interactive wavy progress line pinned to
  /// the bottom edge of the mini player (PixelMusic's collapsed-bar
  /// indicator, in the expressive wavy language of the full seekbar).
  final bool compact;

  @override
  State<ZenM3WavySlider> createState() => _ZenM3WavySliderState();
}

class _ZenM3WavySliderState extends State<ZenM3WavySlider>
    with SingleTickerProviderStateMixin {
  /// Phase of the travelling wave — advances only while playing so a
  /// paused seekbar costs zero frames (same battery contract as the
  /// SP-54.3 aurora).
  late final Ticker _ticker;
  double _phase = 0;
  bool _animating = false;

  /// Scrub override while the pointer is down (dragging shows the local
  /// value, not the streaming playback position).
  double? _dragValue;
  bool _hovering = false;

  double get _effectiveValue =>
      (_dragValue ?? widget.value).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(ZenM3WavySlider old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) _syncAnimation();
  }

  void _syncAnimation() {
    final wantRun = widget.playing || _hovering;
    if (wantRun && !_animating) {
      _animating = true;
      _ticker.start();
    } else if (!wantRun && _animating) {
      _animating = false;
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    setState(() => _phase = (elapsed.inMicroseconds / 1e6) % 1000.0);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setFromLocalX(double dx, double width, {required bool commit}) {
    if (width <= 0 || widget.onChanged == null) return;
    final v = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragValue = v);
    widget.onChanged?.call(v);
    if (commit) {
      widget.onChangeEnd?.call(v);
      setState(() => _dragValue = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final interactive = widget.onChanged != null;
    final amp = _dragValue != null
        ? ZenM3SliderMetrics.waveAmpActive
        : ZenM3SliderMetrics.waveAmpRest;
    final slider = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavySliderPainter(
          value: _effectiveValue,
          amp: widget.compact ? amp * 0.55 : amp,
          phase: _phase,
          activeColor: cs.primary,
          inactiveColor: cs.surfaceContainerHighest,
          thumbColor: cs.primary,
          stopColor: cs.onSurfaceVariant,
          thumbRadius: widget.compact ? 0 : ZenM3SliderMetrics.thumbRadius,
          strokeWidth: widget.compact ? 2.5 : 4.5,
        ),
      ),
    );
    if (!interactive) return slider;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovering = true);
        _syncAnimation();
      },
      onExit: (_) {
        setState(() => _hovering = false);
        _syncAnimation();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) =>
            _setFromLocalX(d.localPosition.dx, context.size!.width, commit: false),
        onHorizontalDragUpdate: (d) =>
            _setFromLocalX(d.localPosition.dx, context.size!.width, commit: false),
        onHorizontalDragEnd: (_) {
          final v = _effectiveValue;
          widget.onChangeEnd?.call(v);
          setState(() => _dragValue = null);
        },
        onTapDown: (d) =>
            _setFromLocalX(d.localPosition.dx, context.size!.width, commit: true),
        child: slider,
      ),
    );
  }
}

class _WavySliderPainter extends CustomPainter {
  _WavySliderPainter({
    required this.value,
    required this.amp,
    required this.phase,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.stopColor,
    this.thumbRadius = ZenM3SliderMetrics.thumbRadius,
    this.strokeWidth = 4.5,
  });

  final double value;
  final double amp;
  final double phase;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color stopColor;
  final double thumbRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackRight = size.width - thumbRadius * 2;
    final activeEnd = trackRight * value;

    // Inactive remainder: flat rounded line, small 4dp gap at the thumb.
    final inactive = Paint()
      ..color = inactiveColor
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (trackRight - activeEnd > 4) {
      canvas.drawLine(Offset(activeEnd + 4, cy),
          Offset(trackRight, cy), inactive);
    }

    // Active wave: sine path of the current amplitude + phase. The wave
    // only exists where there is progress — short tracks collapse to a
    // dot gracefully.
    if (activeEnd > 2) {
      final wave = Paint()
        ..color = activeColor
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(0, cy);
      const step = 2.0;
      final k = 2 * math.pi / ZenM3SliderMetrics.waveLength;
      for (var x = 0.0; x <= activeEnd; x += step) {
        final t = x + phase * ZenM3SliderMetrics.waveLength;
        path.lineTo(x, cy + amp * math.sin(k * t));
      }
      path.lineTo(activeEnd, cy);
      canvas.drawPath(path, wave);
    }

    if (thumbRadius > 0) {
      // Stop indicator dot at the far end (M3 spec).
      canvas.drawCircle(Offset(trackRight, cy),
          ZenM3SliderMetrics.stopIndicatorRadius,
          Paint()..color = stopColor.withValues(alpha: 0.55));

      // Thumb.
      canvas.drawCircle(
          Offset(activeEnd, cy), thumbRadius, Paint()..color = thumbColor);
    }
  }

  @override
  bool shouldRepaint(_WavySliderPainter old) =>
      old.value != value ||
      old.amp != amp ||
      old.phase != phase ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.thumbColor != thumbColor ||
      old.stopColor != stopColor;
}
