// ZenMusic — 22 seek-slider styles in ONE file, switchable from Settings.
//
//   ZenSlider(
//     style: ZenSliderStyle.fromName(savedName),   // persist `style.name`
//     value: progress01,
//     isPlaying: playing,
//     onChanged: (v) {},
//     onChangeEnd: (v) => player.seek(...),
//   )
//
// Original: wavy, rgbGlow, classic, pill, segments, equalizer, neon
// NEW (15): orbit, heartbeat, dna, elastic, liquid, constellation,
//           fireflies, ripple, spring, dotWave, ruler, comet,
//           lightning, glitch, bubbles
// Every style shares the same gesture / animation core.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

enum ZenSliderStyle {
  wavy('Wavy'),
  rgbGlow('RGB Glow'),
  classic('Classic'),
  pill('Pill'),
  segments('Segments'),
  equalizer('Equalizer'),
  neon('Neon'),
  orbit('Orbit'),
  heartbeat('Heartbeat'),
  dna('DNA Helix'),
  elastic('Elastic String'),
  liquid('Liquid Tube'),
  constellation('Constellation'),
  fireflies('Fireflies'),
  ripple('Ripple'),
  spring('Spring Coil'),
  dotWave('Dot Wave'),
  ruler('Ruler'),
  comet('Comet'),
  lightning('Lightning'),
  glitch('Glitch'),
  bubbles('Bubbles');

  const ZenSliderStyle(this.label);

  /// Text for the settings list.
  final String label;

  /// Safe restore from a saved `style.name` (falls back to wavy).
  static ZenSliderStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
    orElse: () => ZenSliderStyle.wavy,
  );
}

class ZenSlider extends StatefulWidget {
  const ZenSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.style = ZenSliderStyle.wavy,
    this.isPlaying = true,
    this.enabled = true,
    this.height = 36.0,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white30,
    this.thumbColor = Colors.white,
  });

  /// 0..1 normalized progress.
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final ZenSliderStyle style;
  final bool isPlaying;
  final bool enabled;
  final double height;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;

  @override
  State<ZenSlider> createState() => _ZenSliderState();
}

class _ZenSliderState extends State<ZenSlider> with TickerProviderStateMixin {
  late final AnimationController _amp; // 0 paused -> 1 playing
  late final AnimationController _drag; // 0 idle -> 1 dragging
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  Duration? _last;

  bool _dragging = false;
  double _dragValue = 0;

  double get _display => _dragging ? _dragValue : widget.value;

  @override
  void initState() {
    super.initState();
    _amp = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.isPlaying ? 1.0 : 0.0,
    )..addStatusListener((s) {
      // Fully flat -> stop the ticker, no wasted frames while paused.
      if (s == AnimationStatus.dismissed) _ticker.stop();
    });
    _drag = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _ticker = createTicker((d) {
      final dt = _last == null ? 0.0 : (d - _last!).inMicroseconds / 1e6;
      _last = d;
      _time.value += dt; // accumulated, so resume never jumps
    });
    if (widget.isPlaying) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant ZenSlider old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final on = widget.isPlaying || _dragging;
    if (on) {
      _amp.forward();
      if (!_ticker.isActive) {
        _last = null;
        _ticker.start();
      }
    } else {
      _amp.reverse();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _amp.dispose();
    _drag.dispose();
    _time.dispose();
    super.dispose();
  }

  double _fractionAt(double dx) {
    final w = (context.size?.width ?? 1.0) - _P.inset * 2;
    if (w <= 0) return 0;
    return ((dx - _P.inset) / w).clamp(0.0, 1.0);
  }

  void _startDrag(double dx) {
    setState(() {
      _dragging = true;
      _dragValue = _fractionAt(dx);
    });
    _drag.forward();
    _sync();
    widget.onChanged(_dragValue);
  }

  void _updateDrag(double dx) {
    setState(() => _dragValue = _fractionAt(dx));
    widget.onChanged(_dragValue);
  }

  void _endDrag() {
    if (!_dragging) return;
    final v = _dragValue;
    setState(() => _dragging = false);
    _drag.reverse();
    _sync();
    widget.onChangeEnd?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    Color dim(Color c) => on ? c : c.withOpacity(0.4);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
        on ? (d) => widget.onChanged(_fractionAt(d.localPosition.dx)) : null,
        onTapUp: on
            ? (d) => widget.onChangeEnd?.call(_fractionAt(d.localPosition.dx))
            : null,
        onHorizontalDragStart: on ? (d) => _startDrag(d.localPosition.dx) : null,
        onHorizontalDragUpdate:
        on ? (d) => _updateDrag(d.localPosition.dx) : null,
        onHorizontalDragEnd: on ? (_) => _endDrag() : null,
        onHorizontalDragCancel: on ? _endDrag : null,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_time, _amp, _drag]),
            builder: (context, _) => CustomPaint(
              painter: _StylePainter(
                widget.style,
                _P(
                  _display.clamp(0.0, 1.0),
                  _time.value,
                  Curves.easeInOut.transform(_amp.value),
                  _drag.value,
                  dim(widget.activeColor),
                  widget.inactiveColor,
                  dim(widget.thumbColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── paint params shared by every style ──

class _P {
  const _P(this.progress, this.time, this.amp, this.drag, this.active,
      this.inactive, this.thumb);

  static const inset = 10.0; // track starts/ends here (gesture uses it too)

  final double progress; // 0..1
  final double time; // accumulated seconds while animating
  final double amp; // 0 paused .. 1 playing (eased)
  final double drag; // 0 idle .. 1 dragging
  final Color active;
  final Color inactive;
  final Color thumb;
}

Paint _stroke(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true
  ..color = c;

Paint _fill(Color c) => Paint()
  ..isAntiAlias = true
  ..color = c;

Color _hue(double deg, [double a = 1.0]) =>
    HSVColor.fromAHSV(a, ((deg % 360) + 360) % 360, 0.9, 1).toColor();

double _smooth(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Deterministic pseudo-random 0..1 (stable between frames).
double _rnd(num i) {
  final v = math.sin(i * 12.9898) * 43758.5453;
  return v - v.floor();
}

/// (x0, x1, thumbX, midY)
(double, double, double, double) _geo(Size s, _P p) {
  final x0 = _P.inset, x1 = s.width - _P.inset;
  return (x0, x1, x0 + (x1 - x0) * p.progress, s.height / 2);
}

/// One ECG beat shape, u in 0..1 -> -1..1 (positive = up).
double _ecg(double u) {
  const us = [0.0, .30, .36, .42, .48, .54, .62, .70, 1.0];
  const vs = [0.0, 0.0, -.2, 1.0, -.6, 0.0, .25, 0.0, 0.0];
  for (var i = 1; i < us.length; i++) {
    if (u <= us[i]) {
      final t = (u - us[i - 1]) / (us[i] - us[i - 1]);
      return vs[i - 1] + (vs[i] - vs[i - 1]) * t;
    }
  }
  return 0;
}

class _StylePainter extends CustomPainter {
  _StylePainter(this.style, this.p);
  final ZenSliderStyle style;
  final _P p;

  @override
  void paint(Canvas c, Size s) {
    switch (style) {
      case ZenSliderStyle.wavy:
        _wavy(c, s, p);
      case ZenSliderStyle.rgbGlow:
        _rgbGlow(c, s, p);
      case ZenSliderStyle.classic:
        _classic(c, s, p);
      case ZenSliderStyle.pill:
        _pill(c, s, p);
      case ZenSliderStyle.segments:
        _segments(c, s, p);
      case ZenSliderStyle.equalizer:
        _equalizer(c, s, p);
      case ZenSliderStyle.neon:
        _neon(c, s, p);
      case ZenSliderStyle.orbit:
        _orbit(c, s, p);
      case ZenSliderStyle.heartbeat:
        _heartbeat(c, s, p);
      case ZenSliderStyle.dna:
        _dna(c, s, p);
      case ZenSliderStyle.elastic:
        _elastic(c, s, p);
      case ZenSliderStyle.liquid:
        _liquid(c, s, p);
      case ZenSliderStyle.constellation:
        _constellation(c, s, p);
      case ZenSliderStyle.fireflies:
        _fireflies(c, s, p);
      case ZenSliderStyle.ripple:
        _ripple(c, s, p);
      case ZenSliderStyle.spring:
        _spring(c, s, p);
      case ZenSliderStyle.dotWave:
        _dotWave(c, s, p);
      case ZenSliderStyle.ruler:
        _ruler(c, s, p);
      case ZenSliderStyle.comet:
        _comet(c, s, p);
      case ZenSliderStyle.lightning:
        _lightning(c, s, p);
      case ZenSliderStyle.glitch:
        _glitch(c, s, p);
      case ZenSliderStyle.bubbles:
        _bubbles(c, s, p);
    }
  }

  @override
  bool shouldRepaint(_StylePainter old) => true; // repainted by animations

  // ── 1. WAVY — animated wave that settles into the thumb, flat after it ──
  static void _wavy(Canvas c, Size s, _P p) {
    const sw = 3.0, wavelength = 26.0, speed = 12.0, maxAmp = 4.0;
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final thumbR = 5.0 * (1 + 0.2 * p.drag);
    final amp = math.min(maxAmp * p.amp, midY - sw / 2);
    final phasePx = p.time * speed; // wave travels left

    if (tx < x1) {
      c.drawLine(Offset(tx, midY), Offset(x1, midY), _stroke(p.inactive, sw));
    }
    final len = tx - x0;
    if (len > 0.5) {
      final settle = math.min(wavelength * 0.5, len);
      final path = Path();
      for (double x = x0;; x += 1.5) {
        final px = math.min(x, tx);
        final env = _smooth((tx - px) / settle);
        final y = midY +
            math.sin(((px - x0 + phasePx) / wavelength) * 2 * math.pi) *
                amp *
                env;
        px == x0 ? path.moveTo(px, y) : path.lineTo(px, y);
        if (px >= tx) break;
      }
      c.drawPath(path, _stroke(p.active, sw));
    }
    c.drawCircle(Offset(tx, midY), thumbR, _fill(p.thumb));
  }

  // ── 2. RGB GLOW ──
  static void _rgbGlow(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final hue = p.time * 70; // flowing colours
    final thumbR = 4.5 * (1 + 0.25 * p.drag);

    c.drawLine(Offset(x0, midY), Offset(x1, midY), _stroke(p.inactive, 3));

    if (tx - x0 > 1) {
      final rect = Rect.fromLTRB(x0, 0, tx, s.height);
      Shader grad(double a) => LinearGradient(
        colors: [for (var i = 0; i < 6; i++) _hue(hue + i * 60.0, a)],
      ).createShader(rect);
      c.drawLine(
        Offset(x0, midY),
        Offset(tx, midY),
        _stroke(Colors.white, 9)
          ..shader = grad(0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      c.drawLine(Offset(x0, midY), Offset(tx, midY),
          _stroke(Colors.white, 3)..shader = grad(1));
    }

    c.drawCircle(
      Offset(tx, midY),
      thumbR + 4,
      _fill(_hue(hue, 0.8))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    c.drawCircle(Offset(tx, midY), thumbR, _fill(p.thumb));
  }

  // ── 3. CLASSIC ──
  static void _classic(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    c.drawLine(Offset(x0, midY), Offset(x1, midY), _stroke(p.inactive, 3));
    c.drawLine(Offset(x0, midY), Offset(tx, midY), _stroke(p.active, 3));
    c.drawCircle(Offset(tx, midY), 6 + 3 * p.drag, _fill(p.thumb));
  }

  // ── 4. PILL ──
  static void _pill(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    const h = 10.0, gap = 6.0;
    final r = const Radius.circular(h / 2);
    RRect bar(double l, double rt) =>
        RRect.fromLTRBR(l, midY - h / 2, rt, midY + h / 2, r);

    if (tx - gap > x0) c.drawRRect(bar(x0, tx - gap), _fill(p.active));
    if (tx + gap < x1) c.drawRRect(bar(tx + gap, x1), _fill(p.inactive));
    final hw = 4.0 + 2 * p.drag;
    final hh = math.min(s.height - 4, 22.0 + 4 * p.drag);
    c.drawRRect(
      RRect.fromLTRBR(tx - hw / 2, midY - hh / 2, tx + hw / 2, midY + hh / 2,
          Radius.circular(hw / 2)),
      _fill(p.thumb),
    );
  }

  // ── 5. SEGMENTS ──
  static void _segments(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final n = math.max(1, ((x1 - x0) / 7).floor());
    final step = (x1 - x0) / n;
    final maxH = s.height - 4;
    for (var i = 0; i < n; i++) {
      final cx = x0 + step * (i + 0.5);
      final d = (cx - tx) / 22;
      final bump = math.exp(-d * d) * (1 + 0.3 * p.drag);
      final h = math.min(maxH, 8 + 14 * bump);
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, midY), width: 4, height: h),
          const Radius.circular(2),
        ),
        _fill(cx <= tx ? p.active : p.inactive),
      );
    }
  }

  // ── 6. EQUALIZER ──
  static void _equalizer(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final n = math.max(1, ((x1 - x0) / 5).floor());
    final step = (x1 - x0) / n;
    final maxH = s.height - 4;
    for (var i = 0; i < n; i++) {
      final cx = x0 + step * (i + 0.5);
      final base = 0.25 + 0.75 * (math.sin(i * 1.7) * math.cos(i * 0.73 + 1)).abs();
      final dyn = 0.25 * p.amp * math.sin(p.time * 4 + i * 0.9);
      final h = (base + dyn).clamp(0.15, 1.0) * maxH;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, midY), width: 3, height: h),
          const Radius.circular(1.5),
        ),
        _fill(cx <= tx ? p.active : p.inactive),
      );
    }
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(tx, midY), width: 2 + p.drag, height: s.height - 2),
        const Radius.circular(1.5),
      ),
      _fill(p.thumb),
    );
  }

  // ── 7. NEON ──
  static void _neon(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final pulse = 0.85 + 0.15 * math.sin(p.time * 3) * p.amp;

    c.drawLine(Offset(x0, midY), Offset(x1, midY), _stroke(p.inactive, 2));
    if (tx - x0 > 1) {
      c.drawLine(
        Offset(x0, midY),
        Offset(tx, midY),
        _stroke(p.active.withOpacity(0.55 * pulse), 9)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      c.drawLine(Offset(x0, midY), Offset(tx, midY), _stroke(p.active, 3));
    }
    final r = 5.0 * (1 + 0.25 * p.drag);
    c.drawCircle(
      Offset(tx, midY),
      (r + 6) * pulse,
      _fill(p.active.withOpacity(0.7))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    c.drawCircle(Offset(tx, midY), r, _fill(p.thumb));
  }

  // ════════════════ NEW STYLES ════════════════

  // ── 8. ORBIT — thumb is a planet with a tilted ring and a moon ──
  static void _orbit(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 2));
    c.drawLine(Offset(x0, my), Offset(tx, my), _stroke(p.active, 2));
    final r = 4.5 * (1 + 0.25 * p.drag);
    final or = r + 8 + 2 * p.drag;
    final ring = Rect.fromCenter(
        center: Offset(tx, my), width: or * 2, height: or * 0.9);
    final a = p.time * 3;
    final moon = Offset(tx + math.cos(a) * or, my + math.sin(a) * or * 0.45);
    final front = math.sin(a) > 0;
    c.drawOval(ring, _stroke(p.active.withOpacity(0.5), 1));
    if (!front) c.drawCircle(moon, 2, _fill(p.active));
    c.drawCircle(Offset(tx, my), r, _fill(p.thumb));
    if (front) c.drawCircle(moon, 2.6, _fill(p.active));
  }

  // ── 9. HEARTBEAT — scrolling ECG trace that flattens into the thumb ──
  static void _heartbeat(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    if (tx < x1) {
      c.drawLine(Offset(tx, my), Offset(x1, my), _stroke(p.inactive, 2));
    }
    if (tx - x0 > 0.5) {
      final a = (s.height / 2 - 3) * (0.3 + 0.7 * p.amp);
      final path = Path();
      for (double x = x0;; x += 1.5) {
        final px = math.min(x, tx);
        final env = _smooth((tx - px) / 14);
        final u = ((px - x0) / 46 + p.time * 0.8) % 1.0;
        final y = my - _ecg(u) * a * env;
        px == x0 ? path.moveTo(px, y) : path.lineTo(px, y);
        if (px >= tx) break;
      }
      c.drawPath(path, _stroke(p.active, 2));
    }
    final beat = 1 + 0.3 * math.max(0, math.sin(p.time * 5)) * p.amp;
    c.drawCircle(Offset(tx, my), 4.5 * beat * (1 + 0.2 * p.drag), _fill(p.thumb));
  }

  // ── 10. DNA — rotating double helix with rungs, converges at thumb ──
  static void _dna(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 2));
    if (tx - x0 > 1) {
      final a = math.min(9.0, s.height / 2 - 3);
      double k(double x) => (x - x0) / 18 * 2 * math.pi - p.time * 3;
      for (double x = x0 + 3; x < tx; x += 6) {
        final e = _smooth((tx - x) / 20) * a * math.sin(k(x));
        c.drawLine(Offset(x, my - e), Offset(x, my + e),
            _stroke(p.inactive, 1.2));
      }
      final pa = Path(), pb = Path();
      for (double x = x0;; x += 1.5) {
        final px = math.min(x, tx);
        final e = math.sin(k(px)) * a * _smooth((tx - px) / 20);
        if (px == x0) {
          pa.moveTo(px, my + e);
          pb.moveTo(px, my - e);
        } else {
          pa.lineTo(px, my + e);
          pb.lineTo(px, my - e);
        }
        if (px >= tx) break;
      }
      c.drawPath(pb, _stroke(p.active.withOpacity(0.5), 2));
      c.drawPath(pa, _stroke(p.active, 2));
    }
    c.drawCircle(Offset(tx, my), 4.5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 11. ELASTIC — string pulled down by the thumb, wobbles on release ──
  static void _elastic(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    final pull = 3 + 9 * p.drag;
    final wob = math.sin(p.time * 6) * 1.5 * p.amp * (1 - p.drag);
    final ty = math.min(s.height - 5, my + pull + wob);
    final l = Path()
      ..moveTo(x0, my)
      ..lineTo(tx, ty);
    final r = Path()
      ..moveTo(tx, ty)
      ..lineTo(x1, my);
    c.drawPath(l, _stroke(p.active, 2.5));
    c.drawPath(r, _stroke(p.inactive, 2.5));
    c.drawCircle(Offset(x0, my), 2.5, _fill(p.active));
    c.drawCircle(Offset(x1, my), 2.5, _fill(p.inactive));
    c.drawCircle(Offset(tx, ty), 5 * (1 + 0.2 * p.drag), _fill(p.thumb));
  }

  // ── 12. LIQUID — glass tube filled with liquid, rippling front edge ──
  static void _liquid(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    const h = 16.0;
    final rr = RRect.fromLTRBR(
        x0, my - h / 2, x1, my + h / 2, const Radius.circular(h / 2));
    c.drawRRect(rr, _stroke(p.inactive, 1.5));
    if (tx - x0 > 1) {
      c.save();
      c.clipRRect(rr);
      final path = Path()..moveTo(x0, my - h / 2);
      for (double y = my - h / 2; y <= my + h / 2; y += 1) {
        path.lineTo(tx + math.sin(y * 0.5 + p.time * 4) * 2.5 * p.amp, y);
      }
      path
        ..lineTo(x0, my + h / 2)
        ..close();
      c.drawPath(path, _fill(p.active.withOpacity(0.85)));
      for (var i = 0; i < 5; i++) {
        final bx = x0 + (tx - x0) * _rnd(i + 1);
        final by = my + h / 2 -
            ((p.time * 0.4 * (0.5 + _rnd(i + 7)) + _rnd(i + 3)) % 1) * h;
        c.drawCircle(Offset(bx, by), 1.5, _fill(Colors.white.withOpacity(0.5)));
      }
      c.restore();
    }
    c.drawCircle(Offset(tx, my), h / 2 + 1 + 2 * p.drag, _stroke(p.thumb, 2));
  }

  // ── 13. CONSTELLATION — stars light up and connect as you progress ──
  static void _constellation(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    const n = 14;
    final amp = s.height / 2 - 6;
    final pts = [
      for (var i = 0; i < n; i++)
        Offset(x0 + (x1 - x0) * i / (n - 1), my + (_rnd(i + 1) - 0.5) * 2 * amp)
    ];
    Offset? prev;
    for (var i = 0; i < n; i++) {
      final o = pts[i];
      if (o.dx <= tx) {
        if (prev != null) {
          c.drawLine(prev, o, _stroke(p.active.withOpacity(0.6), 1));
        }
        prev = o;
        final tw = 1 + 0.4 * math.sin(p.time * 3 + i * 2) * p.amp;
        c.drawCircle(o, 3.5 * tw,
            _fill(p.active.withOpacity(0.5))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        c.drawCircle(o, 1.8 * tw, _fill(p.active));
      } else {
        c.drawCircle(o, 1.3, _fill(p.inactive));
      }
    }
    if (prev != null) {
      c.drawLine(prev, Offset(tx, my), _stroke(p.active.withOpacity(0.6), 1));
    }
    final r = 5.0 * (1 + 0.3 * p.drag);
    final t = _stroke(p.thumb, 1.5);
    c.drawLine(Offset(tx - r - 2, my), Offset(tx + r + 2, my), t);
    c.drawLine(Offset(tx, my - r - 2), Offset(tx, my + r + 2), t);
    c.drawCircle(Offset(tx, my), r * 0.6, _fill(p.thumb));
  }

  // ── 14. FIREFLIES — glowing specks drifting above the played line ──
  static void _fireflies(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 1.5));
    c.drawLine(Offset(x0, my), Offset(tx, my),
        _stroke(p.active.withOpacity(0.4), 1.5));
    for (var i = 0; i < 18; i++) {
      final fx = x0 + (tx - x0) * _rnd(i + 1) + math.sin(p.time * 0.7 + i) * 4;
      if (fx < x0 || fx > tx) continue;
      final fy = my +
          math.sin(p.time * (0.8 + _rnd(i + 9)) + i * 1.3) * (s.height / 2 - 6);
      final tw = 0.5 + 0.5 * math.sin(p.time * 3 + i * 1.7);
      final a = 0.35 + 0.65 * tw * (0.4 + 0.6 * p.amp);
      c.drawCircle(Offset(fx, fy), 4,
          _fill(p.active.withOpacity(a * 0.6))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      c.drawCircle(Offset(fx, fy), 1.4, _fill(p.active.withOpacity(a)));
    }
    c.drawCircle(Offset(tx, my), 9,
        _fill(p.active.withOpacity(0.6))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(Offset(tx, my), 4.5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 15. RIPPLE — water rings radiate from the thumb ──
  static void _ripple(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 2));
    c.drawLine(Offset(x0, my), Offset(tx, my), _stroke(p.active, 2));
    final strength = math.max(p.amp, p.drag);
    for (var k = 0; k < 3; k++) {
      final t = (p.time * 0.7 + k / 3) % 1.0;
      c.drawCircle(Offset(tx, my), 5 + t * (s.height / 2 - 6),
          _stroke(p.active.withOpacity((1 - t) * 0.8 * strength), 1.5));
    }
    c.drawCircle(Offset(tx, my), 5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 16. SPRING — looping coil for played part, straight wire after ──
  static void _spring(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    if (tx < x1) {
      c.drawLine(Offset(tx, my), Offset(x1, my), _stroke(p.inactive, 2));
    }
    if (tx - x0 > 1) {
      final a = math.min(8.0, s.height / 2 - 3);
      final path = Path();
      for (double x = x0;; x += 1) {
        final px = math.min(x, tx);
        final e = _smooth((tx - px) / 10);
        final k = (px - x0) / 9 * 2 * math.pi - p.time * 6 * p.amp;
        final X = px + math.cos(k) * 3.5 * e;
        final Y = my + math.sin(k) * a * e;
        px == x0 ? path.moveTo(X, Y) : path.lineTo(X, Y);
        if (px >= tx) break;
      }
      c.drawPath(path, _stroke(p.active, 2));
    }
    c.drawCircle(Offset(tx, my), 4.5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 17. DOT WAVE — matrix of dots that swell in a travelling wave ──
  static void _dotWave(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    final n = math.max(1, ((x1 - x0) / 6).floor());
    final step = (x1 - x0) / n;
    final rowGap = math.min(8.0, (s.height - 6) / 2);
    for (var i = 0; i <= n; i++) {
      final x = x0 + step * i;
      final on = x <= tx;
      final near = math.exp(-math.pow((x - tx) / 20, 2).toDouble());
      for (var r = -1; r <= 1; r++) {
        final w = 0.5 + 0.5 * math.sin(p.time * 3 - i * 0.35 + r * 0.9);
        final rad = (1 + 1.3 * w * p.amp + 0.8 * near) * (on ? 1 : 0.7);
        c.drawCircle(Offset(x, my + r * rowGap), rad,
            _fill(on ? p.active : p.inactive));
      }
    }
    c.drawCircle(Offset(tx, my), 5 * (1 + 0.25 * p.drag), _stroke(p.thumb, 2));
  }

  // ── 18. RULER — measuring-tape ticks with a pointer ──
  static void _ruler(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    final n = math.max(1, ((x1 - x0) / 5).floor());
    final step = (x1 - x0) / n;
    final base = my + 10;
    for (var i = 0; i <= n; i++) {
      final x = x0 + step * i;
      final major = i % 10 == 0, mid = i % 5 == 0;
      final h = major ? 16.0 : (mid ? 11.0 : 6.0);
      c.drawLine(Offset(x, base), Offset(x, base - h),
          _stroke(x <= tx ? p.active : p.inactive, major ? 2 : 1.2));
    }
    final w = 4.0 + 1.5 * p.drag;
    c.drawPath(
      Path()
        ..moveTo(tx - w, my - 15)
        ..lineTo(tx + w, my - 15)
        ..lineTo(tx, my - 7)
        ..close(),
      _fill(p.thumb),
    );
    c.drawLine(Offset(tx, my - 8), Offset(tx, base), _stroke(p.thumb, 1.5));
  }

  // ── 19. COMET — tapered glowing tail with sparks ──
  static void _comet(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 1.5));
    c.drawLine(Offset(x0, my), Offset(tx, my),
        _stroke(p.active.withOpacity(0.3), 1.5));
    final tail = math.max(x0, tx - 90);
    if (tx - tail > 2) {
      final hw = 4.0 * (1 + 0.3 * p.drag);
      final shader = LinearGradient(
          colors: [p.active.withOpacity(0), p.active])
          .createShader(Rect.fromLTRB(tail, 0, tx, s.height));
      c.drawPath(
        Path()
          ..moveTo(tail, my)
          ..lineTo(tx, my - hw)
          ..lineTo(tx, my + hw)
          ..close(),
        Paint()
          ..shader = shader
          ..isAntiAlias = true,
      );
    }
    for (var i = 0; i < 7; i++) {
      final d = ((p.time * 25 * (0.5 + _rnd(i + 1)) + _rnd(i + 20) * 70) % 70);
      final sx = tx - d;
      if (sx < x0) continue;
      final sy = my + (_rnd(i + 40) - 0.5) * 2 * (d / 70) * (s.height / 2 - 4);
      c.drawCircle(Offset(sx, sy), 1.2,
          _fill(p.active.withOpacity((1 - d / 70) * p.amp)));
    }
    c.drawCircle(Offset(tx, my), 10,
        _fill(p.active.withOpacity(0.7))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(Offset(tx, my), 4.5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 20. LIGHTNING — crackling electric arc, flickers while playing ──
  static void _lightning(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 1.5));
    if (tx - x0 > 1) {
      final frame = (p.time * 14).floor();
      final jag = (1.5 + 5.5 * p.amp).clamp(0.0, s.height / 2 - 3);
      final path = Path()..moveTo(x0, my);
      var i = 0;
      for (double x = x0 + 4; x < tx; x += 4, i++) {
        final env = _smooth((tx - x) / 12);
        path.lineTo(x, my + (_rnd(i + frame * 97) - 0.5) * 2 * jag * env);
      }
      path.lineTo(tx, my);
      c.drawPath(
        path,
        _stroke(p.active.withOpacity(0.7), 6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      c.drawPath(path, _stroke(p.active, 1.8));
      c.drawPath(path, _stroke(Colors.white.withOpacity(0.8), 0.8));
    }
    final flick = 0.7 + 0.3 * _rnd((p.time * 20).floor());
    c.drawCircle(Offset(tx, my), 9 * flick,
        _fill(p.active.withOpacity(0.7))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(Offset(tx, my), 4.5 * (1 + 0.25 * p.drag), _fill(p.thumb));
  }

  // ── 21. GLITCH — RGB-split line with random digital displacement ──
  static void _glitch(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    // dashed unplayed track
    for (double x = tx; x < x1; x += 8) {
      c.drawLine(Offset(x, my), Offset(math.min(x + 4, x1), my),
          _stroke(p.inactive, 2));
    }
    final slot = (p.time * 10).floor();
    final burst = _rnd(slot) > 0.7 && p.amp > 0.05;
    void layer(Color col, double dx, double dy) {
      var i = 0;
      for (double x = x0; x < tx; x += 8, i++) {
        var y = my + dy;
        if (burst && _rnd(i + slot * 31) > 0.6) {
          y += (_rnd(i + slot * 17) - 0.5) * 12;
        }
        c.drawLine(Offset(x + dx, y), Offset(math.min(x + 8, tx) + dx, y),
            _stroke(col, 2.5));
      }
    }

    layer(const Color(0xFFFF2D55).withOpacity(0.8), -1.5, -1);
    layer(const Color(0xFF00E5FF).withOpacity(0.8), 1.5, 1);
    layer(p.active, 0, 0);
    final w = 9.0 + 3 * p.drag;
    c.drawRect(Rect.fromCenter(center: Offset(tx - 1.5, my), width: w, height: w),
        _fill(const Color(0xFFFF2D55).withOpacity(0.8)));
    c.drawRect(Rect.fromCenter(center: Offset(tx + 1.5, my), width: w, height: w),
        _fill(const Color(0xFF00E5FF).withOpacity(0.8)));
    c.drawRect(Rect.fromCenter(center: Offset(tx, my), width: w, height: w),
        _fill(p.thumb));
  }

  // ── 22. BUBBLES — glossy liquid line with bubbles rising and popping ──
  static void _bubbles(Canvas c, Size s, _P p) {
    final (x0, x1, tx, my) = _geo(s, p);
    c.drawLine(Offset(x0, my), Offset(x1, my), _stroke(p.inactive, 3));
    if (tx - x0 > 1) {
      c.drawLine(Offset(x0, my), Offset(tx, my), _stroke(p.active, 5));
      c.drawLine(Offset(x0, my - 1), Offset(tx, my - 1),
          _stroke(Colors.white.withOpacity(0.35), 1.2));
      for (var i = 0; i < 16; i++) {
        final t = (p.time * 0.5 * (0.5 + _rnd(i + 9)) + _rnd(i + 3)) % 1.0;
        final bx = x0 + (tx - x0) * _rnd(i + 1) + math.sin(t * 9 + i) * 3;
        final by = my - 3 - t * (s.height / 2 - 4);
        final r = 1.5 + 2.2 * _rnd(i + 5);
        final a = (1 - t) * (0.3 + 0.7 * p.amp);
        c.drawCircle(Offset(bx, by), r, _stroke(p.active.withOpacity(a), 1));
        c.drawCircle(Offset(bx - r * 0.3, by - r * 0.3), r * 0.25,
            _fill(Colors.white.withOpacity(a)));
      }
    }
    final r = 6.0 * (1 + 0.25 * p.drag);
    c.drawCircle(Offset(tx, my), r, _fill(p.thumb.withOpacity(0.25)));
    c.drawCircle(Offset(tx, my), r, _stroke(p.thumb, 1.5));
    c.drawCircle(Offset(tx - r * 0.35, my - r * 0.35), r * 0.22,
        _fill(Colors.white));
  }
}

// ── OPTIONAL: quick preview of all styles (use it to test / for the
//    Settings picker UI) ──

class ZenSliderGallery extends StatefulWidget {
  const ZenSliderGallery({super.key});

  @override
  State<ZenSliderGallery> createState() => _ZenSliderGalleryState();
}

class _ZenSliderGalleryState extends State<ZenSliderGallery> {
  double _v = 0.4;
  bool _playing = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          SwitchListTile(
            title: const Text('Playing', style: TextStyle(color: Colors.white)),
            value: _playing,
            onChanged: (b) => setState(() => _playing = b),
          ),
          for (final s in ZenSliderStyle.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Text(s.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
            ZenSlider(
              style: s,
              value: _v,
              isPlaying: _playing,
              onChanged: (v) => setState(() => _v = v),
            ),
          ],
        ],
      ),
    );
  }
}