// ZenMusic — expressive motion helpers.
// Port of the Material 3 Expressive motion language used by LastWave-Native
// (ui/common/ExpressiveMotion.kt): spatial springs overshoot slightly, effect
// springs do not. Concept port only — no code was copied; ZenMusic remains
// GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// The curve below is the closed-form response of the same underdamped spring
// Compose evaluates numerically:
//   spring(dampingRatio = 0.8, stiffness = 650)  — "spatialDefault"
// ≈ 280 ms to settle with a tiny (~1.5%) overshoot, which reads as the
// snappy-but-fluid full-player entrance. Evaluating the analytic form as a
// Curve lets go_router's CustomTransitionPage drive it from the plain
// 0→1 route animation without an extra AnimationController.

import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Analytic underdamped spring as a [Curve].
///
/// [t] is the animation progress 0→1; it is interpreted as SECONDS of spring
/// time, so pair the curve with a transition duration that covers the settle
/// window (~450 ms for the default constants; the motion is visually done at
/// ~300 ms, exactly like the Compose original).
class ExpressiveSpring extends Curve {
  const ExpressiveSpring({
    this.dampingRatio = 0.8,
    this.stiffness = 650,
  });

  /// ζ — <1 gives the small expressive overshoot, 1 is critically damped.
  final double dampingRatio;

  /// Spring stiffness (rad/s after sqrt), mirroring Compose `stiffness`.
  final double stiffness;

  @override
  double transform(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;

    final double wn = math.sqrt(stiffness);
    final double wd = wn * math.sqrt(1.0 - dampingRatio * dampingRatio);
    final double decay = math.exp(-dampingRatio * wn * t);
    final double value =
        1.0 - decay * (math.cos(wd * t) + (dampingRatio * wn / wd) * math.sin(wd * t));

    // Guard the tail: after settle the analytic form oscillates within
    // float noise of 1.0 — clamp so reverse transitions never jitter.
    if ((1.0 - value).abs() < 0.0005) return 1.0;
    return value;
  }
}
