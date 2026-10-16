// ZenMusic — Tinder-style swipeable artwork stack for the player page.
// Drop in: lib/desktop/screens/player/widgets/swipe_artwork_stack.dart
//
// Swipe the artwork LEFT  -> next song     (card flies off, next card is
// Swipe the artwork RIGHT -> previous song  already waiting underneath)
// Short / slow drags spring back. If there is no next/previous song that
// way, the card resists and snaps back. The skip buttons can trigger the
// same animation through swipeNext() / swipePrev() on the state (GlobalKey).
//
// Songs that change from outside (auto-advance, notification, queue tap)
// get a soft pop-in instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

typedef SwipeCardBuilder = Widget Function(
    BuildContext context, MediaItem item, bool isFront);

class SwipeArtworkStack extends StatefulWidget {
  const SwipeArtworkStack({
    super.key,
    required this.current,
    required this.next,
    required this.previous,
    required this.cardBuilder,
    required this.onSwipeNext,
    required this.onSwipePrevious,
    this.active = true,
  });

  final MediaItem current;
  final MediaItem? next;
  final MediaItem? previous;

  /// Builds one square card. `isFront` is true only for the top card, so
  /// palette extraction etc. should run only for it.
  final SwipeCardBuilder cardBuilder;
  final VoidCallback onSwipeNext;
  final VoidCallback onSwipePrevious;

  /// Playing -> full size, paused -> slightly smaller ("breathing").
  final bool active;

  @override
  State<SwipeArtworkStack> createState() => SwipeArtworkStackState();
}

class SwipeArtworkStackState extends State<SwipeArtworkStack>
    with TickerProviderStateMixin {
  final ValueNotifier<Offset> _offset = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _anim; // drives fly-out / spring-back
  late final AnimationController _enter; // soft pop-in for external changes

  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  Curve _curve = Curves.linear;
  VoidCallback? _done;

  double _w = 300; // card width, measured in build
  bool _awaiting = false; // card is flying out, waiting for the new song
  bool _changed = false; // the new song arrived during the fly-out
  int _dir = 0; // -1 left (next), 1 right (previous)
  MediaItem? _frontItem; // frozen while flying, so visuals never mismatch
  MediaItem? _behindItem;
  Timer? _fallback;

  bool get _canNext => widget.next != null;
  bool get _canPrev => widget.previous != null;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this)
      ..addListener(() {
        _offset.value =
        Offset.lerp(_from, _to, _curve.transform(_anim.value))!;
      })
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          final cb = _done;
          _done = null;
          cb?.call();
        }
      });
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant SwipeArtworkStack old) {
    super.didUpdateWidget(old);
    if (old.current.id == widget.current.id) return;
    if (_awaiting) {
      // Our own swipe: let the fly-out finish, then swap invisibly.
      _changed = true;
      if (!_anim.isAnimating) _finishSwap();
    } else {
      // Changed from outside (auto-advance, queue tap, notification).
      _anim.stop();
      _offset.value = Offset.zero;
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fallback?.cancel();
    _anim.dispose();
    _enter.dispose();
    _offset.dispose();
    super.dispose();
  }

  // ── public: trigger the same animation from the skip buttons ──

  bool swipeNext() {
    if (_awaiting || !_canNext) return false;
    _fly(-1);
    return true;
  }

  bool swipePrev() {
    if (_awaiting || !_canPrev) return false;
    _fly(1);
    return true;
  }

  // ── animation helpers ──

  void _animateTo(Offset to, Duration d, Curve curve, [VoidCallback? done]) {
    _from = _offset.value;
    _to = to;
    _curve = curve;
    _done = done;
    _anim
      ..duration = d
      ..forward(from: 0);
  }

  void _springBack() =>
      _animateTo(Offset.zero, const Duration(milliseconds: 380), Curves.easeOutBack);

  void _fly(int dir) {
    _awaiting = true;
    _changed = false;
    _dir = dir;
    _frontItem = widget.current;
    _behindItem = dir < 0 ? widget.next : widget.previous;
    HapticFeedback.lightImpact();

    // Start the audio switch immediately, the card animates while it loads.
    dir < 0 ? widget.onSwipeNext() : widget.onSwipePrevious();

    final y = _offset.value.dy + 24;
    _animateTo(
      Offset(dir * _w * 1.7, y),
      const Duration(milliseconds: 260),
      Curves.easeOutCubic,
          () {
        if (_changed) _finishSwap();
      },
    );

    // Song never changed (e.g. repeat-one): bring the card back.
    _fallback?.cancel();
    _fallback = Timer(const Duration(milliseconds: 1100), () {
      if (mounted && _awaiting && !_anim.isAnimating) {
        _finishSwap(fade: true);
      }
    });
  }

  void _finishSwap({bool fade = false}) {
    _fallback?.cancel();
    _awaiting = false;
    _changed = false;
    _frontItem = null;
    _behindItem = null;
    if (fade) {
      _enter.forward(from: 0);
    } else {
      _enter.value = 1;
    }
    _offset.value = Offset.zero;
  }

  // ── gestures ──

  void _onStart(DragStartDetails _) {
    if (_awaiting) return;
    _anim.stop();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_awaiting) return;
    final cur = _offset.value;
    var dx = d.delta.dx;
    final target = cur.dx + dx;
    final blocked = (target < 0 && !_canNext) || (target > 0 && !_canPrev);
    if (blocked) dx *= 0.3; // rubber band when there is nothing that way
    _offset.value = Offset(
      cur.dx + dx,
      (cur.dy + d.delta.dy * 0.35).clamp(-60.0, 60.0),
    );
  }

  void _onEnd(DragEndDetails d) {
    if (_awaiting) return;
    final dx = _offset.value.dx;
    final vx = d.velocity.pixelsPerSecond.dx;
    final thr = _w * 0.28;
    if (_canNext && (dx < -thr || (vx < -800 && dx < -16))) {
      _fly(-1);
    } else if (_canPrev && (dx > thr || (vx > 800 && dx > 16))) {
      _fly(1);
    } else {
      _springBack();
    }
  }

  // ── build ──

  Widget _card(MediaItem item, bool isFront) {
    return KeyedSubtree(
      key: ValueKey('${isFront ? 'f' : 'b'}-${item.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: widget.active ? 0.5 : 0.3),
              blurRadius: widget.active ? 36 : 20,
              spreadRadius: 2,
              offset: Offset(0, widget.active ? 18 : 10),
            ),
          ],
        ),
        child: widget.cardBuilder(context, item, isFront),
      ),
    );
  }

  Widget _stack(BuildContext context, Widget? _) {
    final o = _offset.value;
    final dx = o.dx;
    final progress = (dx.abs() / (_w * 0.9)).clamp(0.0, 1.0);

    // While flying, use the frozen items so nothing changes mid-animation.
    final front = _awaiting ? (_frontItem ?? widget.current) : widget.current;
    final nextItem = _awaiting ? (_dir < 0 ? _behindItem : null) : widget.next;
    final prevItem =
    _awaiting ? (_dir > 0 ? _behindItem : null) : widget.previous;

    // Both neighbours stay built (images preloaded) but only the one in
    // the swipe direction is shown.
    Widget behind(MediaItem? item, bool show) {
      if (item == null) return const SizedBox.shrink();
      return Offstage(
        offstage: !show,
        child: Transform.scale(
          scale: 0.9 + 0.1 * progress,
          child: Opacity(
            opacity: 0.55 + 0.45 * progress,
            child: _card(item, false),
          ),
        ),
      );
    }

    final e = Curves.easeOut.transform(_enter.value);
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        behind(prevItem, dx > 0.5),
        behind(nextItem, dx < -0.5),
        Transform.translate(
          offset: o,
          child: Transform.rotate(
            angle: (dx / _w) * 0.3,
            alignment: Alignment.bottomCenter,
            child: Transform.scale(
              scale: 0.94 + 0.06 * e,
              child: Opacity(opacity: e, child: _card(front, true)),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: widget.active ? 1.0 : 0.88,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, c) {
            _w = c.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _onStart,
              onPanUpdate: _onUpdate,
              onPanEnd: _onEnd,
              onPanCancel: () {
                if (!_awaiting) _springBack();
              },
              child: AnimatedBuilder(
                animation: Listenable.merge([_offset, _enter]),
                builder: _stack,
              ),
            );
          },
        ),
      ),
    );
  }
}