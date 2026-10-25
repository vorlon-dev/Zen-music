// ZenMusic Desktop — SP-42: smooth wheel scrolling for Windows.
// Ported from Echo Music (GPL-3.0) project conventions. ZenMusic remains
// GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// FIELD REPORT this fixes:
//   "when we scroll up it go directly down ... on home page and almost
//    wherever needed scroll all side should be smooth scroll"
//
// WHY IT HAPPENED
// Flutter desktop applies every mouse-wheel notch as an INSTANT
// `position.pointerScroll()` jump — there is no animation at all. On long
// feeds the page teleports notch by notch, and when a jump lands exactly on
// the bottom edge the pagination listener fires and the feed grows under the
// cursor, so the view can even read as "it jumped the wrong way". Every page
// (home, search, browse) shares this, hence "almost wherever".
//
// HOW THE FIX WORKS (one mechanism, two widgets)
// A PointerScrollEvent is offered to every Listener along the hit-test path,
// and the PointerSignalResolver hands the event to the FIRST listener that
// registered (documented: "the first registered callback is called").
// RenderObjects register children-first, so an INNER Listener beats the
// Scrollable's own instant-jump handler. Both widgets below therefore sit
// INSIDE a scrollable (wrapping its content), register first, suppress the
// native teleport and drive the same ScrollPosition with a short
// easeOutCubic `animateTo` — one smooth glide per wheel burst, correct
// direction guaranteed, deltas accumulated while the wheel keeps rolling.
//
//   - SmoothScroll      vertical pages (home / search / browse):
//                       wrap the SingleChildScrollView's CHILD.
//   - SmoothShelfWheel  horizontal shelves (ItemList / SongList):
//                       wrap each item; the wheel glides the SHELF
//                       horizontally (Spotify-like) instead of the wheel
//                       dying on the horizontal axis.
//
// Trackpad two-finger pan and touch drags do NOT travel through here —
// PointerPanZoom/drag gestures stay on the native ballistic path, untouched.
// If the controller is not attached yet (or the page cannot scroll), the
// listener quietly declines to register and the native behaviour runs.

import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerSignalEvent, PointerScrollEvent;
import 'package:flutter/material.dart';

/// How long one wheel glide eases for. Short enough to feel responsive,
/// long enough to erase the notch-to-notch teleporting.
const Duration kSmoothScrollDuration = Duration(milliseconds: 240);

/// Wheel events arriving faster than this keep accumulating onto the same
/// glide target; after the last event the accumulator resets and the next
/// burst starts from wherever the view has settled.
const Duration kSmoothScrollDecay = Duration(milliseconds: 220);

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
  double? _target;
  Timer? _decay;

  @override
  void dispose() {
    _decay?.cancel();
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

    // While the wheel keeps rolling, accumulate onto the pending glide
    // target so a fast flick travels the full distance in ONE eased run
    // instead of restarting the curve on every notch.
    final double base = _target ?? position.pixels;
    final double next = (base + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _target = next;

    _decay?.cancel();
    _decay = Timer(kSmoothScrollDecay, () => _target = null);

    // Replaces any in-flight activity on the same position — no stacking.
    position.animateTo(
      next,
      duration: kSmoothScrollDuration,
      curve: Curves.easeOutCubic,
    );
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
  double? _target;
  Timer? _decay;

  void dispose() {
    _decay?.cancel();
    _decay = null;
    _target = null;
  }
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

    final ShelfWheelMomentum m = widget.momentum;
    final double base = m._target ?? position.pixels;
    final double next = (base + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    m._target = next;

    m._decay?.cancel();
    m._decay = Timer(kSmoothScrollDecay, () => m._target = null);

    position.animateTo(
      next,
      duration: kSmoothScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: widget.child,
    );
  }
}
