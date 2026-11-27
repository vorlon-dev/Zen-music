// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerSignalEvent, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Kept for source compatibility; the glide no longer restarts a timed
/// animation on every wheel notch (that restart is what made scrolling feel
/// stuttery). [kSmoothScrollDuration] is now only a hint for callers.
const Duration kSmoothScrollDuration = Duration(milliseconds: 240);
const Duration kSmoothScrollDecay = Duration(milliseconds: 220);

/// Time constant of the glide, in seconds. Smaller = snappier, larger =
/// floatier. 0.09 s finishes ~95 % of a move in ~270 ms with no restart.
const double _kGlideTau = 0.09;

/// Continuous wheel glide. Each wheel notch only moves a TARGET; one
/// per-frame loop eases the real scroll position toward it
/// (`pos += (target - pos) * (1 - e^(-dt/tau))`). Because nothing is ever
/// restarted, a flick of many notches is one smooth, frame-rate independent
/// motion, and a single notch never "teleports".
class WheelGlide {
  double? _target;
  double _expected = 0;
  int? _frameId;
  Duration? _last;
  ScrollPosition? _position;

  void push(ScrollPosition position, double delta) {
    // If something else moved the view (scrollbar drag, keyboard, jumpTo),
    // start from where it really is.
    if (_target == null || (position.pixels - _expected).abs() > 1.5) {
      _target = position.pixels;
    }
    _position = position;
    _target = (_target! + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _frameId ??= SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _tick(Duration ts) {
    _frameId = null;
    final ScrollPosition? pos = _position;
    final double? target = _target;
    if (pos == null || target == null || !pos.hasPixels) {
      _stop();
      return;
    }
    final double dt = _last == null
        ? 1 / 60
        : math.min((ts - _last!).inMicroseconds / 1e6, 0.05);
    _last = ts;

    final double diff = target - pos.pixels;
    if (diff.abs() < 0.4) {
      pos.jumpTo(target);
      _stop();
      return;
    }
    final double k = 1 - math.exp(-dt / _kGlideTau);
    final double next = pos.pixels + diff * k;
    pos.jumpTo(next);
    _expected = pos.pixels;
    _frameId = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _stop() {
    _last = null;
    _target = null;
  }

  void dispose() {
    if (_frameId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frameId!);
      _frameId = null;
    }
    _stop();
    _position = null;
  }
}

/// Vertical page scrolling: wrap the CHILD of a SingleChildScrollView
/// (i.e. deeper than the viewport) with the SAME ScrollController the
/// scroll view uses.
///
/// ```dart
/// SingleChildScrollView(
///   controller: _scrollController,
///   child: SmoothScroll(
///     controller: _scrollController,
///     child: <the original child>,
///   ),
/// )
/// ```
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({
    super.key,
    required this.child,
    required this.controller,
    this.speed = 1.0,
  });

  final Widget child;
  final ScrollController controller;

  /// Multiplier on the raw wheel delta. 1.0 = OS-native distance per notch,
  /// just animated instead of teleported.
  final double speed;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final WheelGlide _glide = WheelGlide();

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final ScrollController controller = widget.controller;
    if (!controller.hasClients) return; // nothing attached — native fallback
    final ScrollPosition position = controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;

    final double delta = event.scrollDelta.dy * widget.speed;
    if (delta == 0) return;
    _glide.push(position, delta);
  }

  @override
  Widget build(BuildContext context) {
    // Listener (not RawGestureDetector): pointer SIGNALS are dispatched to
    // every Listener on the hit path, and because this one is deeper than
    // the Scrollable's own, the resolver gives the event to US first.
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}

/// Shared glide state for ONE horizontal shelf. Lives in the shelf's State;
/// every wrapped item of that shelf contributes to the same glide.
class ShelfWheelMomentum {
  final WheelGlide _glide = WheelGlide();

  void dispose() => _glide.dispose();
}

/// Horizontal shelves: wrap EACH item of a horizontal ListView (or each page
/// of a paged shelf) with the shelf's controller. The wheel — vertical or
/// tilt — then glides the shelf smoothly, exactly like the Spotify desktop
/// shelves, instead of doing nothing on the horizontal axis.
///
/// ```dart
/// ListView.separated(
///   scrollDirection: Axis.horizontal,
///   controller: horizontalScrollController,
///   itemBuilder: (context, index) => SmoothShelfWheel(
///     controller: horizontalScrollController,
///     momentum: _shelfMomentum,
///     child: <the item>,
///   ),
/// )
/// ```
class SmoothShelfWheel extends StatefulWidget {
  const SmoothShelfWheel({
    super.key,
    required this.child,
    required this.controller,
    required this.momentum,
  });

  final Widget child;
  final ScrollController controller;
  final ShelfWheelMomentum momentum;

  @override
  State<SmoothShelfWheel> createState() => _SmoothShelfWheelState();
}

class _SmoothShelfWheelState extends State<SmoothShelfWheel> {
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final ScrollController controller = widget.controller;
    if (!controller.hasClients) return;
    final ScrollPosition position = controller.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;

    // Either axis may carry the intent: vertical wheel, tilt wheel or a
    // trackpad's diagonal two-finger pan all drive the shelf.
    final double delta = event.scrollDelta.dy + event.scrollDelta.dx;
    if (delta == 0) return;
    widget.momentum._glide.push(position, delta);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
