// 8 selectable lyric motion presets. Persisted in Hive 'SETTINGS'.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum LyricMotion { smooth, spring, bounce, fade, slide, zoom, elastic, snap }

extension LyricMotionX on LyricMotion {
  Curve get curve => const [
        Curves.easeInOutCubic, Curves.elasticOut, Curves.bounceOut, Curves.easeIn,
        Curves.easeOutQuart, Curves.easeOutBack, Curves.elasticInOut, Curves.linear,
      ][index];
  Duration get duration => Duration(milliseconds: this == LyricMotion.snap ? 120 : 380);
  static LyricMotion load() {
    final i = Hive.box('SETTINGS').get('LYRIC_MOTION', defaultValue: 0) as int;
    return LyricMotion.values[i.clamp(0, LyricMotion.values.length - 1)];
  }
  Future<void> save() => Hive.box('SETTINGS').put('LYRIC_MOTION', index);
}

/// Wrap a lyric line's Text with this. One RepaintBoundary per line keeps
/// scrolling lyrics at full frame rate.
class MotionLyricLine extends StatelessWidget {
  const MotionLyricLine({super.key, required this.child, required this.active, required this.motion});
  final Widget child;
  final bool active;
  final LyricMotion motion;

  @override
  Widget build(BuildContext context) {
    final slide = motion == LyricMotion.slide;
    return RepaintBoundary(
      child: AnimatedSlide(
        offset: slide && active ? Offset.zero : (slide ? const Offset(-0.03, 0) : Offset.zero),
        duration: motion.duration,
        curve: motion.curve,
        child: AnimatedScale(
          scale: active ? 1.06 : 1.0,
          alignment: Alignment.centerLeft,
          duration: motion.duration,
          curve: motion.curve,
          child: AnimatedOpacity(
            opacity: active ? 1 : 0.45,
            duration: motion.duration,
            child: child,
          ),
        ),
      ),
    );
  }
}

extension LyricMotionLabel on LyricMotion {
  String get label => name[0].toUpperCase() + name.substring(1);
}

class LyricMotionPrefs {
  static final ValueNotifier<LyricMotion> motion = ValueNotifier(LyricMotion.smooth);

  static void load() => motion.value = LyricMotionX.load();

  static Future<void> set(LyricMotion m) async {
    motion.value = m;
    await m.save();
  }
}

/// Everything a preset changes: line transitions, auto-scroll and the
/// spring "trail" of the lines below. `smooth` equals the original look.
class LyricMotionSpec {
  const LyricMotionSpec({
    required this.curve,
    required this.fxMs,
    this.scrollCurve,
    this.scrollMs,
    this.inactiveScale = 0.98,
    this.dy = 3.5,
    this.alphaMul = 1.0,
    this.trailMul = 1.0,
  });
  final Curve curve;
  final int fxMs;
  final Curve? scrollCurve; // null = original curve
  final int? scrollMs; // null = original duration
  final double inactiveScale;
  final double dy;
  final double alphaMul;
  final double trailMul;
}

extension LyricMotionSpecX on LyricMotion {
  LyricMotionSpec get spec {
    switch (this) {
      case LyricMotion.smooth:
        return const LyricMotionSpec(curve: Cubic(0.41, 0.0, 0.12, 0.99), fxMs: 420);
      case LyricMotion.spring:
        return const LyricMotionSpec(
            curve: Curves.easeOutBack, fxMs: 600, scrollCurve: Curves.easeOutBack,
            scrollMs: 600, inactiveScale: 0.94, dy: 8, trailMul: 1.6);
      case LyricMotion.bounce:
        return const LyricMotionSpec(
            curve: Curves.bounceOut, fxMs: 700, scrollCurve: Curves.easeOutBack,
            scrollMs: 650, inactiveScale: 0.92, dy: 10, trailMul: 1.8);
      case LyricMotion.fade:
        return const LyricMotionSpec(
            curve: Curves.easeInOut, fxMs: 700, scrollCurve: Curves.easeInOut,
            scrollMs: 550, inactiveScale: 1.0, dy: 0, alphaMul: 0.55, trailMul: 0);
      case LyricMotion.slide:
        return const LyricMotionSpec(
            curve: Curves.easeOutQuart, fxMs: 380, scrollCurve: Curves.easeOutQuart,
            scrollMs: 380, inactiveScale: 1.0, dy: 16, trailMul: 0);
      case LyricMotion.zoom:
        return const LyricMotionSpec(
            curve: Curves.easeOutBack, fxMs: 450, scrollCurve: Curves.easeOutCubic,
            scrollMs: 450, inactiveScale: 0.82, dy: 0, trailMul: 0.5);
      case LyricMotion.elastic:
        return const LyricMotionSpec(
            curve: Curves.elasticOut, fxMs: 950, scrollCurve: Curves.easeOutBack,
            scrollMs: 800, inactiveScale: 0.88, dy: 6, trailMul: 2.4);
      case LyricMotion.snap:
        return const LyricMotionSpec(
            curve: Curves.linear, fxMs: 120, scrollCurve: Curves.linear,
            scrollMs: 120, inactiveScale: 0.98, dy: 0, trailMul: 0);
    }
  }
}
