// ZenMusic — 7 seek-slider styles in ONE file, switchable from Settings.
//
//   ZenSlider(
//     style: ZenSliderStyle.fromName(savedName),   // persist `style.name`
//     value: progress01,
//     isPlaying: playing,
//     onChanged: (v) {},
//     onChangeEnd: (v) => player.seek(...),
//   )
//
// Styles: wavy (our wave slider), rgbGlow, classic, pill, segments,
//         equalizer, neon.
// Every style shares the same gesture / animation core, so behaviour
// (tap, drag, play/pause animation) is identical across all of them.

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
  neon('Neon');

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

  // ── 2. RGB GLOW — flowing RGB line BEHIND the dot with a Gaussian glow,
  //       RGB halo on the dot, plain dim line in front ──
  static void _rgbGlow(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    final hue = p.time * 70; // flowing colours
    final thumbR = 4.5 * (1 + 0.25 * p.drag);

    // dim base track
    c.drawLine(Offset(x0, midY), Offset(x1, midY), _stroke(p.inactive, 3));

    // played part: RGB gradient + Gaussian glow
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
      c.drawLine(
          Offset(x0, midY), Offset(tx, midY), _stroke(Colors.white, 3)..shader = grad(1));
    }

    // dot with RGB halo
    c.drawCircle(
      Offset(tx, midY),
      thumbR + 4,
      _fill(_hue(hue, 0.8))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    c.drawCircle(Offset(tx, midY), thumbR, _fill(p.thumb));
  }

  // ── 3. CLASSIC — thin line, round thumb that grows while dragging ──
  static void _classic(Canvas c, Size s, _P p) {
    final midY = s.height / 2;
    final x0 = _P.inset, x1 = s.width - _P.inset;
    final tx = x0 + (x1 - x0) * p.progress;
    c.drawLine(Offset(x0, midY), Offset(x1, midY), _stroke(p.inactive, 3));
    c.drawLine(Offset(x0, midY), Offset(tx, midY), _stroke(p.active, 3));
    c.drawCircle(Offset(tx, midY), 6 + 3 * p.drag, _fill(p.thumb));
  }

  // ── 4. PILL — thick rounded bar with a gap + vertical handle ──
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

  // ── 5. SEGMENTS — rounded ticks, magnified around the thumb ──
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

  // ── 6. EQUALIZER — bouncing bars while playing, played bars lit ──
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

  // ── 7. NEON — single colour glow line with a pulsing halo ──
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
}

// ── OPTIONAL: quick preview of all 7 styles (use it to test / for the
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