// SP-54: Liquid Glass — app-wide ambient backdrop.
//
// Replaces the opaque root ColoredBox in ZenDesktopApp when the liquid
// glass theme is ON. Every page then sits on a slowly drifting aurora of
// soft colour orbs — the "liquid" that all the glass surfaces refract.
//
//   • ALL platforms → a pure-Flutter CustomPaint: 6 pre-softened
//     RadialGradient orbs on one ticker inside a RepaintBoundary.
//     No ImageFilter.blur anywhere (gradients are pre-blurred by design),
//     so it costs ~1 layer per orb and stays smooth even on iGPUs.
//
// SP-54.4 (look): the first aurora palette was muted (35-55% alphas over
// near-black) — glass panels blur whatever sits behind them, so a dim
// backdrop made every glass surface read as a flat dark slab instead of
// liquid glass. The palette is now saturated + luminous (the package demo
// floats its glass over a rich colour field for exactly this reason), the
// base is a deep blue-violet instead of pure black, the accent orb is much
// stronger, and the orbs travel wider so panels at the screen edges pick
// up colour too. Same 6 gradients, same no-blur contract — zero perf cost.
//
// SP-54.3 (Android): the backdrop used to be a FULLSCREEN Kotlin platform
// view mounted at the app root. With a second platform view in the glass
// nav bar, the Android compositor split the scene into three planes
// (backdrop PV → page content → nav PV) and on real devices the MIDDLE
// plane — every page — was never composited: the app showed aurora +
// bottom nav but blank pages. The root platform view is therefore gone;
// the aurora is painted in Dart (identical painter to Windows). The
// Kotlin glass SURFACE panels stay native — small platform views with
// content above them are the proven-safe pattern (the nav bar renders).
//
// PERFORMANCE CONTRACT (low-end mobile first):
//   • Gradient-only painting — no blur pass ever.
//   • high tier / desktop : ticker at native vsync (~60fps).
//   • mid tier            : repaints gated to ~40fps in the tick callback.
//   • low tier (Android)  : NO ticker at all — one static frame is drawn,
//     then silence (zero GPU/CPU until the theme changes). The tier is
//     re-checked every tick, so a device that resolves to "low" after the
//     bridge warms up freezes itself on the next frame.
//   • The ticker stops when the app is hidden (lifecycle observer), so
//     the aurora costs nothing while backgrounded.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:zenmusic/desktop/liquid/liquid_bridge.dart'; // SP-54.3

/// Platform-view type shared with ZenLiquidGlassViewFactory (Android).
/// Still used by the small glass SURFACE panels (glass_panel.dart).
const String kZenGlassViewType = 'zen_liquid_glass';

/// Aurora cycle length in seconds — one full orb lap (matches SP-54 v1).
const double _kAuroraCycleSeconds = 26.0;

class LiquidBackdrop extends StatefulWidget {
  const LiquidBackdrop({
    super.key,
    required this.dark,
    this.accent,
    required this.child,
  });

  final bool dark;
  final Color? accent;
  final Widget child;

  @override
  State<LiquidBackdrop> createState() => _LiquidBackdropState();
}

class _LiquidBackdropState extends State<LiquidBackdrop>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Aurora phase in [0, 1) — one lap per [_kAuroraCycleSeconds]. Repaints
  /// only the CustomPaint (it sits alone inside a RepaintBoundary).
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  late final Ticker _ticker;
  Duration _lastPaint = Duration.zero;
  bool _animating = false;

  /// Low-end Android: static aurora, zero per-frame cost (SP-54 contract).
  bool get _lowTier =>
      Platform.isAndroid &&
      LiquidGlassBridge.instance.tier == ZenGlassTier.low;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _startIfAllowed();
  }

  void _startIfAllowed() {
    if (_lowTier) {
      if (_animating) {
        _ticker.stop();
        _animating = false;
      }
      return; // static frame stays on screen
    }
    if (!_animating) {
      _animating = true;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    // Self-correcting: the bridge tier resolves asynchronously after boot;
    // if the device turned out to be low-end, freeze on the next frame.
    if (_lowTier) {
      _ticker.stop();
      _animating = false;
      return;
    }
    // Mid tier: gate repaints to ~40fps (same policy as the SP-54 Kotlin
    // animator had). High tier / desktop / still-unknown: every vsync.
    if (Platform.isAndroid &&
        LiquidGlassBridge.instance.tier == ZenGlassTier.mid &&
        elapsed - _lastPaint < const Duration(milliseconds: 24)) {
      return;
    }
    _lastPaint = elapsed;
    _phase.value =
        (elapsed.inMicroseconds / 1e6) / _kAuroraCycleSeconds % 1.0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Battery/CPU courtesy: freeze the aurora while the app is hidden.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_animating) {
        _ticker.stop();
        _animating = false;
      }
    } else if (state == AppLifecycleState.resumed) {
      _startIfAllowed();
    }
  }

  @override
  void didUpdateWidget(LiquidBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dark != oldWidget.dark ||
        widget.accent != oldWidget.accent) {
      // Epsilon bump so even a STATIC (low-tier) frame repaints with the
      // new colours — the painter's shouldRepaint compares t.
      _phase.value = _phase.value + 1e-6;
    }
    // Tier may have resolved (or the theme toggled) since the last check.
    _startIfAllowed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SP-54.3: one code path for every platform — Dart aurora BELOW, the
    // app ABOVE. No fullscreen platform view anywhere near the root.
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: IgnorePointer(
            child: ValueListenableBuilder<double>(
              valueListenable: _phase,
              builder: (context, t, _) => CustomPaint(
                painter: _AuroraPainter(
                  t: t * 2 * math.pi,
                  dark: widget.dark,
                  accent: widget.accent,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.t,
    required this.dark,
    required this.accent,
  });

  final double t;
  final bool dark;
  final Color? accent;

  static const List<double> _radius = [0.62, 0.55, 0.50, 0.58, 0.45];
  static const List<double> _speed = [0.11, 0.16, 0.08, 0.13, 0.19];
  static const List<double> _phase = [0.0, 1.4, 2.6, 4.1, 5.3];

  // SP-54.4: raised from [0.55, 0.50, 0.45, 0.40, 0.35] — the old orbs
  // vanished into the near-black base and the glass had nothing to show.
  static const List<double> _alpha = [0.78, 0.70, 0.62, 0.56, 0.48];

  // SP-54.4: saturated replacements for the muted v1 palette.
  static const List<Color> _darkColors = [
    Color(0xFF7C5CFF), // electric violet
    Color(0xFF0FA3C4), // vivid teal
    Color(0xFFE0559F), // hot rose
    Color(0xFF4C5EF0), // vivid indigo
    Color(0xFF27B07A), // emerald
  ];

  static const List<Color> _lightColors = [
    Color(0xFFF2C4CE), // blush
    Color(0xFFBFD8F2), // sky
    Color(0xFFCDEBD8), // mint
    Color(0xFFD8CCF2), // lilac
    Color(0xFFF2E4C0), // sand
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // SP-54.4: deep blue-violet base (was #07070C) — tinted, like the
    // package demo's background gradient, so the gaps between orbs are not
    // dead black.
    final base = dark ? const Color(0xFF0B0B18) : const Color(0xFFF4F5FB);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final colors = dark ? _darkColors : _lightColors;
    final w = size.width;
    final h = size.height;

    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < colors.length; i++) {
      // SP-54.4: travel amplitude widened (0.36/0.34 → 0.42/0.38) so the
      // orbs actually reach the screen edges where the glass rail, nav bar
      // and mini player sit.
      final cx = w * (0.5 + 0.42 * math.cos(t * _speed[i] * 6 + _phase[i]));
      final cy = h * (0.5 + 0.38 * math.sin(t * _speed[i] * 4.5 + _phase[i] * 1.7));
      final r = math.max(w, h) * _radius[i];
      final a = (dark ? _alpha[i] : _alpha[i] * 0.9);
      final c = colors[i];
      paint.shader = RadialGradient(
        colors: [
          c.withValues(alpha: a),
          c.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawRect(Offset.zero & size, paint);
    }

    // Accent orb — follows the user's accent colour when one is set.
    // SP-54.4: much stronger (0.34 → 0.55 in dark, radius 0.40 → 0.46) —
    // this is the glow the glass rail and mini player tint with; the
    // reference look is built on a dominant accent glow.
    final ac = accent;
    if (ac != null) {
      final cx = w * (0.5 + 0.36 * math.cos(t * 0.09 * 6 + 2.2));
      final cy = h * (0.5 + 0.36 * math.sin(t * 0.12 * 4.5 + 3.4));
      final r = math.max(w, h) * 0.46;
      paint.shader = RadialGradient(
        colors: [
          ac.withValues(alpha: dark ? 0.55 : 0.38),
          ac.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.dark != dark || old.accent != accent;
}
