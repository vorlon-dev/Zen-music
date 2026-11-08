// ZenMusic · vorlon-dev
//
// Mobile shell with a "floating button" bottom bar.
// A glowing circle rises out of a pill bar and springs to the active tab.
//
// Built to stay smooth on low-end phones:
//  * no BackdropFilter / blur / saveLayer / BoxShadow blur
//  * ONE AnimationController (spring) drives the whole dock
//  * the circle only moves through a Transform (compositor, no repaint)
//  * only the small bar outline is repainted per frame
//  * scroll-hide uses a ValueNotifier, so the page below never rebuilds

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart' show MediaItem;

import 'package:zenmusic/desktop/screens/shell/widgets/bottom_player.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';

const List<int> kZenMobileBranchOrder = [0, 1, 2, 3, 4];

// ── Dock geometry ───────────────────────────────────────────────────────────
const double _kBarHeight = 64; // pill bar
const double _kOverhang = 24; // how far the circle area sticks above the bar
const double _kDockHeight = _kBarHeight + _kOverhang;
const double _kDockBottomGap = 10;
const double _kDockSideGap = 14;

/// Space the page content must leave at the bottom for the dock.
const double _kDockExtent = _kDockHeight + _kDockBottomGap;

const double _kBubble = 50; // glowing circle diameter
const double _kGlow = 76; // soft glow around it (gradient, not blur)
const double _kBubbleCenterY = _kOverhang + 6; // circle centre, from dock top

const double _kNotchHalf = 40;
const double _kNotchDepth = 13;

class ZenMobileShell extends StatefulWidget {
  const ZenMobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static bool applies() => Platform.isAndroid || Platform.isIOS;

  @override
  State<ZenMobileShell> createState() => _ZenMobileShellState();
}

class _ZenMobileShellState extends State<ZenMobileShell> {
  // Only the chrome listens to this; the page below is never rebuilt by it.
  final ValueNotifier<bool> _chromeHidden = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _chromeHidden.dispose();
    super.dispose();
  }

  void _goBranch(int branch) {
    _chromeHidden.value = false;
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
  }

  bool _onUserScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.pixels <= 40) {
      _chromeHidden.value = false;
      return false;
    }
    if (n.direction == ScrollDirection.reverse) {
      _chromeHidden.value = true;
    } else if (n.direction == ScrollDirection.forward) {
      _chromeHidden.value = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: ValueListenableBuilder<bool>(
          valueListenable: ShellOverlaysBus.fullPageAbove,
          builder: (context, pageAbove, _) {
            return ValueListenableBuilder<MediaItem?>(
              valueListenable: GetIt.I<MediaPlayer>().currentSongNotifier,
              builder: (context, currentSong, _) {
                final miniInset =
                (currentSong == null || pageAbove) ? 0.0 : 82.0;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: MediaQuery(
                        data: mq.copyWith(
                          padding: mq.padding.copyWith(
                            bottom: math.max(mq.padding.bottom,
                                mq.padding.bottom + _kDockExtent + miniInset),
                          ),
                        ),
                        child: widget.navigationShell,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _chromeHidden,
                        builder: (context, hidden, _) => _Chrome(
                          hidden: hidden || pageAbove,
                          currentIndex: widget.navigationShell.currentIndex,
                          onSelect: _goBranch,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.hidden,
    required this.currentIndex,
    required this.onSelect,
  });

  final bool hidden;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    // Slide only (no AnimatedOpacity): opacity animation forces an offscreen
    // layer, which is slow on weak GPUs. The chrome slides fully off-screen.
    return AnimatedSlide(
      offset: hidden ? const Offset(0, 1.25) : Offset.zero,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: hidden,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BottomPlayer(),
            _ZenDock(currentIndex: currentIndex, onSelect: onSelect),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Floating-button dock
// ═══════════════════════════════════════════════════════════════════════════

class _ZenDock extends StatefulWidget {
  const _ZenDock({required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _labels = ['Home', 'Search', 'YouTube', 'Saved', 'Settings'];
  static const _icons = [
    Icons.home_outlined,
    Icons.search,
    Icons.play_circle_outline_rounded,
    Icons.bookmark_border_rounded,
    Icons.settings_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search,
    Icons.play_circle_fill_rounded,
    Icons.bookmark_rounded,
    Icons.settings_rounded,
  ];

  @override
  State<_ZenDock> createState() => _ZenDockState();
}

class _ZenDockState extends State<_ZenDock>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 30,
  );

  late final AnimationController _pos; // value = tab position (0..n-1)
  int? _downBranch;
  bool _changedWhileDown = false;

  int _slotOf(int branch) {
    final i = kZenMobileBranchOrder.indexOf(branch);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    _pos = AnimationController.unbounded(
      vsync: this,
      value: _slotOf(widget.currentIndex).toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant _ZenDock old) {
    super.didUpdateWidget(old);
    if (old.currentIndex == widget.currentIndex) return;
    final target = _slotOf(widget.currentIndex).toDouble();
    if (MediaQuery.of(context).disableAnimations) {
      _pos.value = target;
    } else {
      _pos.animateWith(SpringSimulation(_spring, _pos.value, target, _pos.velocity));
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  // ── Touch handling: plain pointer math, no render-object lookups ─────────
  int _branchAt(double dx, double width) {
    final n = kZenMobileBranchOrder.length;
    final slot = (dx / (width / n)).floor().clamp(0, n - 1).toInt();
    return kZenMobileBranchOrder[slot];
  }

  void _pick(double dx, double width) {
    final branch = _branchAt(dx, width);
    if (branch == widget.currentIndex) return;
    _changedWhileDown = true;
    HapticFeedback.selectionClick();
    widget.onSelect(branch);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = kZenMobileBranchOrder.length;
    final slot = _slotOf(widget.currentIndex);

    final barFill = cs.surfaceContainerHigh;
    final barStroke = cs.primary.withValues(alpha: 0.32);

    // Built once per selection change, then only translated while animating.
    final bubble = _Bubble(
      icon: _ZenDock._activeIcons[slot],
      slot: slot,
      color: cs.primary,
      iconColor: cs.onPrimary,
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              _kDockSideGap, 0, _kDockSideGap, _kDockBottomGap),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              final itemW = width / n;

              return SizedBox(
                height: _kDockHeight,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    _changedWhileDown = false;
                    _downBranch = _branchAt(e.localPosition.dx, width);
                    _pick(e.localPosition.dx, width);
                  },
                  onPointerMove: (e) => _pick(e.localPosition.dx, width),
                  onPointerUp: (e) {
                    // Re-tap on the active tab → pop to its root.
                    if (!_changedWhileDown &&
                        _downBranch == widget.currentIndex) {
                      widget.onSelect(widget.currentIndex);
                    }
                    _downBranch = null;
                  },
                  onPointerCancel: (_) => _downBranch = null,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1) Bar outline with the moving notch.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _kOverhang,
                        height: _kBarHeight,
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _pos,
                            builder: (context, _) => CustomPaint(
                              painter: _BarPainter(
                                pos: _pos.value,
                                itemWidth: itemW,
                                fill: barFill,
                                stroke: barStroke,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 2) Icons + labels (static; no per-frame work).
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _kOverhang,
                        height: _kBarHeight,
                        child: Row(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: _DockItem(
                                  label: _ZenDock._labels[i],
                                  icon: _ZenDock._icons[i],
                                  selected: i == slot,
                                  activeColor: cs.onSurface,
                                  idleColor: cs.onSurfaceVariant,
                                  onTap: () => widget
                                      .onSelect(kZenMobileBranchOrder[i]),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 3) Glowing circle: Transform only → no repaint.
                      Positioned(
                        left: 0,
                        top: _kBubbleCenterY - _kGlow / 2,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _pos,
                              child: bubble,
                              builder: (context, child) =>
                                  Transform.translate(
                                    offset: Offset(
                                      (_pos.value + 0.5) * itemW - _kGlow / 2,
                                      0,
                                    ),
                                    child: child,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Glowing circle ──────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.icon,
    required this.slot,
    required this.color,
    required this.iconColor,
  });

  final IconData icon;
  final int slot;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.28)!;
    return SizedBox(
      width: _kGlow,
      height: _kGlow,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft glow = plain radial gradient (much cheaper than a blur).
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.34),
                  color.withValues(alpha: 0.0),
                ],
                stops: const [0.6, 1.0],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [light, color],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: SizedBox(
              width: _kBubble,
              height: _kBubble,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.7, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: Icon(
                  icon,
                  key: ValueKey<int>(slot),
                  size: 24,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One tab: icon + label ───────────────────────────────────────────────────
class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.idleColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final Color idleColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? activeColor : idleColor;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The active icon lives inside the circle, so hide it here.
          AnimatedOpacity(
            opacity: selected ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 140),
            child: Icon(icon, size: 24, color: idleColor),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.1,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pill bar with a notch that follows the circle ───────────────────────────
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.pos,
    required this.itemWidth,
    required this.fill,
    required this.stroke,
  });

  final double pos;
  final double itemWidth;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rc = h / 2; // full pill
    final cx = (pos + 0.5) * itemWidth;

    // Notch limits, kept inside the straight part of the top edge.
    final a = math.max(rc, cx - _kNotchHalf);
    final b = math.min(w - rc, cx + _kNotchHalf);
    final nw = b - a;

    final path = Path()..moveTo(rc, 0);

    if (nw > 6) {
      final depth =
          _kNotchDepth * (nw / (2 * _kNotchHalf)).clamp(0.35, 1.0).toDouble();
      path
        ..lineTo(a, 0)
        ..cubicTo(a + nw * 0.28, 0, a + nw * 0.18, depth, a + nw * 0.5, depth)
        ..cubicTo(b - nw * 0.18, depth, b - nw * 0.28, 0, b, 0);
    }

    path
      ..lineTo(w - rc, 0)
      ..arcToPoint(Offset(w, rc), radius: Radius.circular(rc))
      ..lineTo(w, h - rc)
      ..arcToPoint(Offset(w - rc, h), radius: Radius.circular(rc))
      ..lineTo(rc, h)
      ..arcToPoint(Offset(0, h - rc), radius: Radius.circular(rc))
      ..lineTo(0, rc)
      ..arcToPoint(Offset(rc, 0), radius: Radius.circular(rc))
      ..close();

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) =>
      o.pos != pos ||
          o.itemWidth != itemWidth ||
          o.fill != fill ||
          o.stroke != stroke;
}