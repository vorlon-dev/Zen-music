// ZenMusic · vorlon-dev
//
// Spring physics + timing for the "Apple" lyric animation: line spring,
// word rise, per-letter swell on long held words, and the breathing dots
// shown during long instrumental gaps.
//
// The motion design is modelled on the open-source am-lyrics web component
// by uimaxbai (MPL-2.0, https://github.com/binimum/am-lyrics). This file is
// an independent Dart implementation of the same published behaviour.

import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curve;

/// Displacement of a damped spring released at [x0] with velocity [v0],
/// [t] seconds later (decays towards 0).
double springPosition(
    double x0, double v0, double t, double frequency, double damping) {
  final omega =
      math.sqrt(math.max(1e-6, frequency * frequency - damping * damping));
  final decay = math.exp(-damping * t);
  return decay *
      (x0 * math.cos(omega * t) + ((v0 + damping * x0) / omega) * math.sin(omega * t));
}

/// 0 -> 1 progress of a lightly damped spring (frequency 10, damping ratio
/// 0.9) stretched over 1.2 s: the quick, soft settle of Apple-style lyric
/// scrolling. Use as a scroll / transition curve.
class SpringCurve extends Curve {
  const SpringCurve({this.frequency = 10, this.spanSeconds = 1.2});

  final double frequency;
  final double spanSeconds;

  @override
  double transformInternal(double t) =>
      1 - springPosition(1, 0, spanSeconds * t, frequency, 0.9 * frequency);
}

/// Per-letter effect of one character of a long held word.
class CharFx {
  const CharFx(this.rise, this.dxEm, this.lift, this.scale);

  /// 0..1 rise progress (multiply by the word rise in px).
  final double rise;

  /// Horizontal spread in em.
  final double dxEm;

  /// Extra upward lift in px.
  final double lift;

  final double scale;
}

class AppleMotion {
  AppleMotion._();

  /// Words held longer than this get the per-letter swell.
  static const int emphasisMinMs = 1100;

  /// Base rise of a sung word in px.
  static const double wordRisePx = 3.0;

  /// Whole-word rise: spring (stiffness 14, damping 7), settles in ~2 s.
  static double wordRise(double tSec) {
    if (tSec <= 0) return 0;
    if (tSec >= 2.0) return 1;
    return 1 - springPosition(1, 0, tSec, math.sqrt(14), 3.5);
  }

  // Critically damped spring step response.
  static double _response(double t, double response) {
    if (t <= 0) return 0;
    final phase = 2 * math.pi * t / math.max(0.001, response);
    return 1 - (1 + phase) * math.exp(-phase);
  }

  /// Effect of character [index] of [count], [tSec] seconds into a word
  /// that lasts [durationSec].
  static CharFx charFx({
    required double tSec,
    required double durationSec,
    required int index,
    required int count,
  }) {
    if (tSec <= 0 || count <= 0) return const CharFx(0, 0, 0, 1);
    final hold = 2 * durationSec / count;
    final response = math.min(3.0, durationSec);
    final emphasis = (durationSec - 1).clamp(0.0, 1.0).toDouble();
    final rise = _response(tSec, response);
    final env = _response(tSec, response) * (1 - _response(tSec - hold, response));
    return CharFx(
      rise,
      (index - (count - 1) / 2) * 0.05 * emphasis * env,
      2.25 * emphasis * env,
      1 + 0.1 * emphasis * env,
    );
  }

  // ------------------------------------------------ instrumental gap

  static const double _entryFadeMs = 160;
  static const double _entryScaleMs = 400;
  static const double _collapseLeadMs = 500;
  static const double _exitLeadMs = 350;
  static const double _pulseMs = 4000;

  static double _easeOutExpo(double p) =>
      p <= 0 ? 0 : (p >= 1 ? 1 : 1 - math.pow(2, -10 * p).toDouble());

  /// Gap start of the dots' sequential fade-in (ms into the gap).
  static double exitStart(double durationMs) =>
      math.max(_entryScaleMs, durationMs - _collapseLeadMs - _exitLeadMs);

  /// (scale, opacity) of the dots layer [tMs] into a gap of [durationMs].
  static (double, double) gapLayer(double tMs, double durationMs) {
    final exit = exitStart(durationMs);
    final end = math.min(durationMs, exit + _exitLeadMs);
    final time = tMs.clamp(0.0, end).toDouble();
    final cycle = _pulseMs * 2;
    final phase = (time + _pulseMs - (exit % cycle) + cycle) % cycle;
    final mix = (1 - math.cos(math.pi * phase / _pulseMs)) / 2;
    var scale = (1.12 + (0.85 - 1.12) * mix) * _easeOutExpo(time / _entryScaleMs);
    var opacity = math.min(1.0, time / _entryFadeMs);
    if (time >= exit) {
      final progress = (time - exit) / math.max(1.0, end - exit);
      final popping = progress <= 0.35;
      final pp = popping ? progress / 0.35 : (progress - 0.35) / 0.65;
      final ease = pp * pp * (3 - 2 * pp);
      scale = popping ? 0.85 + (1.2 - 0.85) * ease : 1.2 * (1 - ease);
      opacity = popping ? 1.0 : 1 - ease;
    }
    return (scale, opacity);
  }

  /// Opacity of dot [i] of [n]: they light up one after another.
  static double dotOpacity(int i, int n, double tMs, double durationMs) {
    final span = exitStart(durationMs) / n;
    final p = ((tMs - i * span) / span).clamp(0.0, 1.0).toDouble();
    return 0.25 + 0.75 * p;
  }
}
