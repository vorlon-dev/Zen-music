// ZenMusic · vorlon-dev
//
// Mobile shell with a "floating button" bottom bar.
// A glowing circle rises out of a pill bar and springs to the active tab.
//
// SP-76 · Echo Nightly player sheet: the mini player IS the collapsed sheet.
// Dragging the pill up grows THE PILL into the full player — the panel's
// top edge rises 1:1 with the finger from the pill's own rect, the bottom
// edge slides down over the dock in the first half of the travel, the
// artwork morphs from the pill's thumbnail into the page's artwork, the
// pill fades with offset*2 and the player content composes in over the
// first half. Settles with a spring, exactly like the reference.
//
// Built to stay smooth on low-end phones:
//  * no BackdropFilter / blur / saveLayer / BoxShadow blur in the sheet
//  * ONE AnimationController (spring) drives dock + sheet + morph
//  * per-frame work is positioned containers only; the player page subtree
//    is a cached AnimatedBuilder child and never rebuilds mid-drag
//  * scroll-hide uses a ValueNotifier, so the page below never rebuilds

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/gestures.dart' show DragUpdateDetails, DragEndDetails;
import 'package:flutter/rendering.dart' show ScrollDirection, RenderBox;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart' show MediaItem;

import 'package:zenmusic/desktop/liquid/glass_panel.dart';
import 'package:zenmusic/desktop/screens/player/player_page.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/screens/shell/widgets/echo_bottom_player.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';
import 'package:zenmusic/desktop/utils/song_thumbnail.dart';

const List<int> kZenMobileBranchOrder = [0, 1, 2, 3, 4];
const int _kDiscoverBranch = 2; // Home, Search, Discover, Saved, Settings

// ── Dock geometry ───────────────────────────────────────────────────────────
const double _kBarHeight = 64; // pill bar
const double _kOverhang = 24; // how far the circle area sticks above the bar
const double _kDockHeight = _kBarHeight + _kOverhang;
const double _kDockBottomGap = 10;
const double _kDockSideGap = 14;

/// Space the page content must leave at the bottom for the dock.
const double _kDockExtent = _kDockHeight + _kDockBottomGap;

// Segmented Dynamic Bar: the active segment is a raised card that pops above
// the bar's top edge.
const double _kPop = 14; // how far the active card rises above the bar
const double _kCardWidthFactor = 1.14; // active card width vs. one segment
const double _kBarRadius = 24;
const double _kCardRadius = 20;

/// The mini pill's total wrapper height (64 pill + 10 internal bottom pad).
const double _kMiniWrapHeight = 74;

class ZenMobileShell extends StatefulWidget {
  const ZenMobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static bool applies() => Platform.isAndroid || Platform.isIOS;

  @override
  State<ZenMobileShell> createState() => _ZenMobileShellState();
}

class _ZenMobileShellState extends State<ZenMobileShell>
    with SingleTickerProviderStateMixin {
  // Only the chrome listens to this; the page below is never rebuilt by it.
  final ValueNotifier<bool> _chromeHidden = ValueNotifier<bool>(false);

  // Player sheet: 0 = closed (mini player), 1 = fully open. Dragged by the
  // finger, so the sheet, the mini player and the dock all follow it.
  // Settles with a spring (Echo Nightly feel): slightly under-damped so it
  // glides into place without a visible bounce. Overshoot past 0/1 is
  // harmless — every consumer clamps the value before painting.
  static final SpringDescription _sheetSpring =
  SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    // Critically damped: the sheet eases into place with NO overshoot, so it
    // never turns around at the end (the "snap back" hitch) — butter smooth.
    ratio: 1.0,
  );

  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool _sheetBuilt = false;

  /// SP-76 rev3.4: mini pill generation — bumped on every settle-closed so
  /// the pill subtree remounts fresh over the normal page. No stale element
  /// or render state can keep it invisible after an open/close cycle.
  int _pillGen = 0;

  /// The mini pill's wrapper box — measured live so the sheet and the
  /// artwork morph always start from exactly the pill's on-screen rect.
  final GlobalKey _miniKey = GlobalKey();

  /// The player page's artwork box — measured live so the morph lands the
  /// artwork exactly where the page will show it (classic AND every skin).
  final GlobalKey _pageArtKey = GlobalKey();

  // True while a finger owns the sheet (pointer down .. drag end/cancel).
  // While a drag is live the player page must NEVER unmount, even when the
  // drag clamps at an edge — unmounting mid-gesture disposes the very
  // GestureDetector that is driving the drag and leaves the shell stuck.
  bool _sheetDragging = false;

  /// Fling speeds above this (in sheet-heights per second) win over position.
  static const double _kSheetFlingVelocity = 0.8;

  @override
  void initState() {
    super.initState();
    // Everything is derived from the sheet VALUE per frame — never from
    // AnimationStatus. animateWith(SpringSimulation) reports `completed`
    // even when it settles on 0 (never `dismissed`), so a status-based
    // listener silently never fired and the dock stayed hidden forever
    // (the stuck-shell bug). The plain value listener below always fires.
    _sheet.addListener(_onSheetTick);
  }

  void _onSheetTick() {
    if (!mounted) return;
    final open = _sheet.value > 0;
    if (open && !_sheetBuilt) {
      setState(() => _sheetBuilt = true);
    } else if (!open &&
        !_sheet.isAnimating &&
        !_sheetDragging &&
        _sheetBuilt) {
      // Settled closed: unmount the player and restore the chrome no matter
      // what hid it — scroll-hide, a stale overlay flag, an interrupted
      // settle. This is the "shell always pops back up" guarantee.
      _settleClosedCleanup();
    }
  }

  /// SP-76 rev3.3: the "mini player lives over the page, never inside the
  /// player" state — runs whenever the sheet has settled closed, no matter
  /// WHICH path landed it there (spring, edge-clamped drag, canceled
  /// gesture). The player layer unmounts, the chrome flags are restored and
  /// the mini pill is rebuilt FRESH (generation bump) at v = 0, so the
  /// normal page always gets its chrome — and a full-opacity mini player —
  /// back. SP-76 rev3.4: the rebuild is UNCONDITIONAL. The pill's alpha is
  /// derived from the sheet value at build time, so a rebuild at v = 0
  /// restores it at full opacity no matter which path landed here.
  void _settleClosedCleanup() {
    if (!mounted) return;
    setState(() {
      _sheetBuilt = false;
      _pillGen++;
    });
    if (ShellOverlaysBus.fullPageAbove.value) {
      ShellOverlaysBus.fullPageAbove.value = false;
    }
    if (_chromeHidden.value) _chromeHidden.value = false;
  }

  @override
  void dispose() {
    _sheet.dispose();
    _chromeHidden.dispose();
    if (ShellOverlaysBus.fullPageAbove.value) {
      ShellOverlaysBus.fullPageAbove.value = false;
    }
    super.dispose();
  }

  void _springSheetTo(double target, [double velocity = 0]) {
    // animateWith forces the direction to forward, so when the spring
    // finishes Flutter reports AnimationStatus.completed — even when it
    // lands on 0 — and physics tolerance can stop it a hair off the target.
    // Either way `dismissed` would never fire and the dock would stay hidden
    // forever. Landing exactly on the target re-derives the status from the
    // value (0 -> dismissed), so the player unmounts and the chrome returns.
    _sheet
        .animateWith(SpringSimulation(
      _sheetSpring,
      _sheet.value,
      target,
      velocity.clamp(-3.0, 3.0), // sheet-heights per second
    ))
        .whenComplete(() {
      if (!mounted || _sheet.isAnimating) return;
      // Only land if nothing grabbed the sheet in between (a new drag or
      // another settle). A mid-range value means a new gesture owns it.
      if ((_sheet.value - target).abs() > 0.05) return;
      _sheet.value = target;
      // SP-76 rev3.3: landing exactly on 0 can be a no-op (no value change,
      // no listener tick) — run the closed-state cleanup here as well so
      // EVERY path that settles closed unmounts the player layer and
      // restores the mini player + dock over the normal page.
      if (target == 0) _settleClosedCleanup();
    });
  }

  void _openSheet() => _springSheetTo(1);

  void _closeSheet() => _springSheetTo(0);

  /// SP-76 rev3 (smoothness): mount the sheet layer the moment the finger
  /// lands on the pill — the player page's one-time build happens while the
  /// pointer is down (stationary) instead of on the first frame of the drag.
  /// Pointer-down-only; the settle-closed unmount in _onSheetTick and the
  /// shell pop-back guarantee are untouched.
  void _preWarmSheet() {
    if (!mounted) return;
    if (_sheet.value > 0) return; // already open / already warm
    if (!_sheetBuilt) setState(() => _sheetBuilt = true);
  }

  // Drag released mid-way (pointer lost): settle to the nearest edge.
  void _settleSheet() {
    _sheetDragging = false;
    _springSheetTo(_sheet.value > 0.5 ? 1 : 0);
  }

  void _dragSheet(DragUpdateDetails d, double travel) {
    _sheetDragging = true;
    // Kill any in-flight settle so the finger takes over instantly (Echo
    // Nightly grabs the sheet mid-animation the same way).
    if (_sheet.isAnimating) _sheet.stop();
    // 1:1 finger tracking: travel = pill top → screen top, so the sheet's
    // top edge moves exactly as many pixels as the finger.
    _sheet.value = (_sheet.value - d.delta.dy / travel).clamp(0.0, 1.0);
  }

  void _endDragSheet(DragEndDetails d, double travel) {
    _sheetDragging = false;
    final v = -d.velocity.pixelsPerSecond.dy / travel; // + = flinging up
    final wasMostlyOpen = _sheet.value > 0.5;
    final double target;
    if (v.abs() > _kSheetFlingVelocity) {
      target = v > 0 ? 1 : 0;
    } else {
      target = wasMostlyOpen ? 1 : 0;
    }
    // Already resting on the target edge (the drag clamped there)? Land at
    // once — springing from the edge would bounce a sliver of the page back
    // onto the screen. The setter re-derives the boundary status, so the
    // sheet unmounts and the dock + mini player come back immediately.
    if ((_sheet.value - target).abs() < 0.002) {
      _sheet.value = target;
      // SP-76 rev3.3: the setter above is a NO-OP when the drag already
      // clamped at the edge — that swallows the listener tick which unmounts
      // the player. Land the closed state here too (the open edge is already
      // correct: the sheet stays mounted while it is open).
      if (target == 0) _settleClosedCleanup();
      return;
    }
    // Same tap the reference gives when the sheet snaps away under the
    // finger.
    if (target == 0 && wasMostlyOpen) HapticFeedback.mediumImpact();
    _springSheetTo(target, v);
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
    // While the keyboard is open the dock + mini player are hidden and add no
    // bottom padding; otherwise they float above the keyboard and leave a big
    // empty bar (Search screen).
    final keyboardOpen = mq.viewInsets.bottom > 0;

    // AnimatedBuilder keeps PopScope's canPop in sync with the sheet value
    // every frame — a stale canPop let the system back gesture pop the whole
    // app route instead of closing the sheet.
    return AnimatedBuilder(
      animation: _sheet,
      builder: (context, child) => PopScope(
        canPop: _sheet.value == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _sheet.value > 0) _closeSheet();
        },
        child: child!,
      ),
      child: Scaffold(
        // The inner pages' own Scaffolds handle the keyboard; the shell must not
        // shrink the whole stack as well.
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        body: NotificationListener<UserScrollNotification>(
          onNotification: _onUserScroll,
          child: ValueListenableBuilder<bool>(
            valueListenable: ShellOverlaysBus.fullPageAbove,
            builder: (context, pageAboveRaw, _) {
              // The "page above" flag hides the chrome only on the Discover
              // tab; while the player sheet is up the mini pill fades with
              // the sheet value itself (the sheet grows out of the pill) and
              // the dock is simply covered by the panel. Anywhere else a
              // stale flag is ignored, so it can never leave the dock hidden.
              final pageAbove = pageAboveRaw &&
                  widget.navigationShell.currentIndex == _kDiscoverBranch;
              return ValueListenableBuilder<MediaItem?>(
                valueListenable: GetIt.I<MediaPlayer>().currentSongNotifier,
                builder: (context, currentSong, _) {
                  final miniInset =
                  (currentSong == null || pageAbove || keyboardOpen) ? 0.0 : 82.0;
                  final pill = _pillRect(mq);
                  // 1:1 finger mapping uses the pill-top travel: the sheet's
                  // top edge moves exactly as many pixels as the finger —
                  // like the reference.
                  final travel = math.max(pill.top, 220.0);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: MediaQuery(
                          data: mq.copyWith(
                            padding: mq.padding.copyWith(
                              bottom: keyboardOpen
                                  ? mq.padding.bottom
                                  : math.max(mq.padding.bottom,
                                  mq.padding.bottom + _kDockExtent + miniInset),
                            ),
                          ),
                          child: widget.navigationShell,
                        ),
                      ),
                      // Chrome + sheet. Layer order IS the reference's
                      // behaviour: the dock sits UNDER the sheet (the growing
                      // panel slides over it), the mini pill sits ON TOP of
                      // it (the sheet grows out from behind the pill, which
                      // fades with the reference's offset*2 curve), and the
                      // morphing artwork is topmost so it can take over the
                      // pill's thumbnail 1:1 while it grows.
                      Positioned.fill(
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _chromeHidden,
                          builder: (context, scrollHidden, _) {
                            final chromeHidden =
                                scrollHidden || pageAbove || keyboardOpen;
                            return Stack(
                              children: [
                                // 1) Dock — under the sheet, never moves.
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: _chromeSlide(
                                    chromeHidden,
                                    _ZenDock(
                                      currentIndex:
                                      widget.navigationShell.currentIndex,
                                      onSelect: _goBranch,
                                    ),
                                  ),
                                ),
                                // 2) The player sheet — the mini pill's
                                //    grown-up self. Top edge tracks the
                                //    finger 1:1 from the pill's own rect.
                                if (_sheetBuilt)
                                  _buildSheet(mq, pill, travel),
                                // 3) Mini player — the sheet's collapsed
                                //    state. Fades with offset*2 while the
                                //    sheet grows out from behind it.
                                //    Rev3.4: the alpha is VALUE-DERIVED —
                                //    computed in the builder from the sheet
                                //    value (the pre-SP-76 chrome's proven
                                //    recipe), not a compositor FadeTransition
                                //    layer, so a rebuild can never leave the
                                //    pill stale-invisible over the home page.
                                //    At rest the controller is idle (zero
                                //    per-frame cost); in travel only this
                                //    small strip repaints inside its own
                                //    RepaintBoundary (cookie spin never
                                //    dirties the shell stack).
                                //    Listener pre-warms the sheet on
                                //    pointer-down: the player page builds
                                //    while the finger is still down, never
                                //    mid-drag — the first drag frames are
                                //    already warm.
                                if (currentSong != null)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: _chromeSlide(
                                      chromeHidden,
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom:
                                          mq.padding.bottom + _kDockExtent,
                                        ),
                                        child: Listener(
                                          onPointerDown: (_) =>
                                              _preWarmSheet(),
                                          child: AnimatedBuilder(
                                            animation: _sheet,
                                            child: RepaintBoundary(
                                              child: _buildMiniPill(travel),
                                            ),
                                            builder: (context, child) {
                                              // SP-76 rev3.4: the pill's
                                              // alpha is computed HERE, at
                                              // build time, from the sheet
                                              // value — the same synchronous
                                              // recipe the pre-SP-76 chrome
                                              // used (the version that always
                                              // showed the mini player on
                                              // this device). A compositor
                                              // FadeTransition layer could
                                              // go stale across the rev3.3
                                              // structural drop/remount; a
                                              // value-derived Opacity cannot
                                              // — every rebuild paints
                                              // exactly offset*2, so the
                                              // mini player always comes
                                              // back over the home page at
                                              // full opacity.
                                              // SP-76 rev3.3: once the sheet
                                              // is fully open the mini
                                              // player is removed
                                              // STRUCTURALLY — the open
                                              // player page can never contain
                                              // it. The gate drops the
                                              // subtree only once it is
                                              // already invisible (no pop).
                                              final v =
                                              _sheet.value.clamp(0.0, 1.0);
                                              if (v >= 0.999) {
                                                return const SizedBox
                                                    .shrink();
                                              }
                                              return Opacity(
                                                // Fades over the first ~45 % of
                                                // travel (smooth, no 2x ramp).
                                                opacity: 1 - _smoothstep(0.02, 0.25, v),
                                                child: IgnorePointer(
                                                  ignoring: v > 0.05,
                                                  child: child!,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                // 4) Morphing artwork: pill thumb → page
                                //    artwork, topmost.
                                if (_sheetBuilt && currentSong != null)
                                  _buildMorphArt(mq, currentSong, pill),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

// ═══════════════════════════════════════════════════════════════════════════
//  SP-76 · Echo Nightly sheet — the mini player IS the collapsed sheet
// ═══════════════════════════════════════════════════════════════════════════

  /// The mini pill's on-screen rect (measured live; constants as fallback).
  /// The sheet's collapsed rect and the artwork morph both derive from it, so
  /// the panel always grows out of the pill itself — never from the screen
  /// edge (that was the SP-75 behaviour the reference does not do).
  Rect _pillRect(MediaQueryData mq) {
    final ctx = _miniKey.currentContext;
    if (ctx != null) {
      final ro = ctx.findRenderObject();
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        final tl = ro.localToGlobal(Offset.zero);
        return Rect.fromLTWH(tl.dx, tl.dy, ro.size.width, ro.size.height);
      }
    }
    // Fallback = the Echo pill layout: ≤380 wide, centred, 74 tall (64 pill
    // + 10 internal bottom pad), dock extent above the safe area.
    final w = math.min(380.0, mq.size.width);
    final left = (mq.size.width - w) / 2;
    final bottom = mq.size.height - mq.padding.bottom - _kDockExtent;
    return Rect.fromLTWH(left, bottom - _kMiniWrapHeight, w, _kMiniWrapHeight);
  }

  /// The classic page's full-screen artwork rect — the morph target fallback
  /// when the live measurement has not laid out yet. Mirrors
  /// _buildPlayerColumnMobile's math: SafeArea + 58 top bar + 4 top pad,
  /// 20 h-pad, media side = (inner height - 344 controls/gap) clamped to
  /// [150, min(inner width, 520)].
  Rect _classicArtRect(MediaQueryData mq) {
    final safeTop = mq.padding.top;
    final innerH = mq.size.height - safeTop - 78;
    final innerW = mq.size.width - 40;
    final room = innerH - 344;
    final side =
    room.clamp(150.0, math.min(innerW, 520.0)).toDouble();
    final columnH = side + 344;
    final columnTop = safeTop + 62 + (innerH - columnH) / 2;
    return Rect.fromCenter(
      center: Offset(mq.size.width / 2, columnTop + side / 2),
      width: side,
      height: side,
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// Scroll/keyboard/discover-hide wrapper for the chrome layers (same slide
  /// recipe the old _Chrome used).
  Widget _chromeSlide(bool hidden, Widget child) => AnimatedSlide(
    offset: hidden ? const Offset(0, 1.25) : Offset.zero,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    child: IgnorePointer(ignoring: hidden, child: child),
  );

  /// The mini pill — the sheet's collapsed state. Vertical drags feed the
  /// sheet (1:1 finger tracking) via [EchoSheetDragSink]; taps spring it open.
  Widget _buildMiniPill(double travel) {
    final sink = EchoSheetDragSink(
      update: (d) => _dragSheet(d, travel),
      end: (d) => _endDragSheet(d, travel),
      cancel: _settleSheet,
    );
    Widget pill = EchoBottomPlayer(
      onOpen: _openSheet,
      sheetDrag: sink,
    );
    if (GetIt.I<SettingsManager>().liquidGlass) {
      // Liquid theme colours are see-through by design; without a frosted
      // slab behind them the page bleeds through (unchanged from SP-73).
      pill = ZenGlassPanel(
        radius: 20,
        margin: const EdgeInsets.fromLTRB(
            _kDockSideGap, 0, _kDockSideGap, 6),
        child: pill,
      );
    }
    // rev3.4: the generation key forces a fresh subtree after every
    // settle-closed — clean State, clean render objects; the pill comes back
    // exactly as it was at app start.
    return KeyedSubtree(key: _miniKey, child: KeyedSubtree(key: ValueKey<int>(_pillGen), child: pill));
  }

  /// The player sheet. Its collapsed rect IS the mini pill's rect; the top
  /// edge rises 1:1 with the finger, the bottom edge slides down over the
  /// dock during the first half of the travel, and the side insets close
  /// early — the reference's BottomSheetBehaviour with peek = mini player.
  /// The surface is a translucent dark gradient (no blur — this shell targets
  /// low-end phones), the pill fades out over it, and the player page
  /// composes in during the second third.
  ///
  /// Perf model (the difference between Echo Nightly tracking and jank):
  /// the layer is laid out ONCE at full screen; every frame only changes
  /// paint/compositor state — the moving clip path, the gradient alpha and
  /// the page's layer opacity. The player page sits in its own
  /// RepaintBoundary, so its cached raster is re-composited, never redrawn.
  Widget _buildSheet(MediaQueryData mq, Rect pill, double travel) {
    final liquid = GetIt.I<SettingsManager>().liquidGlass;
    // NOTE: no Positioned wrapper here. This subtree is consumed inside
    // Opacity(opacity: pageA, ...) below, and a Positioned is only legal as a
    // DIRECT Stack child — nesting one under a render proxy (Opacity /
    // IgnorePointer) throws `type 'ParentData' is not a subtype of type
    // 'StackParentData'` on the sheet's first mount, which blanked the whole
    // page when the player opened. The builder's own Positioned.fill (around
    // ClipPath) is what fills the sheet Stack; the page just lives inside it.
    final pageSub = Material(
      type: MaterialType.transparency,
      child: RepaintBoundary(
        child: PlayerPage(
          onClose: _closeSheet,
          artKey: _pageArtKey,
          sheetOffset: _sheet,
          // Whole-body drags (any skin) drive the sheet: the page follows
          // the finger 1:1 and settles with the shell's spring.
          bodyDragSink: PlayerBodyDragSink(
            update: (d) => _dragSheet(d, travel),
            end: (d) => _endDragSheet(d, travel),
            cancel: _settleSheet,
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _sheet,
      child: pageSub,
      builder: (context, page) {
        final v = _sheet.value.clamp(0.0, 1.0);
        final screenH = mq.size.height;
        final screenW = mq.size.width;
        final top = _lerp(pill.top, 0, v);
        final sideT = _smoothstep(0, 0.35, v);
        final left = _lerp(pill.left, 0, sideT);
        final right = _lerp(screenW - pill.right, 0, sideT);
        final bottomInset =
        _lerp(screenH - pill.bottom, 0, _smoothstep(0, 0.55, v));
        // Corners: the pill's own rounding at rest, Echo's ~26 rounded top
        // corners while it follows the finger, flat when fully open.
        final startRadius = liquid ? 20.0 : 32.0;
        final topRadius =
            _lerp(startRadius, 26, (v * 3).clamp(0.0, 1.0)) * (1 - v);
        final bottomRadius = topRadius * (1 - _smoothstep(0.55, 0.85, v));
        // Translucent dark surface fades in as the pill fades out; the player
        // content composes over it in the second third (reference crossfade).
        // The player content starts appearing early and overlaps the pill
        // fading out, so there is never a near-empty dark panel mid-travel.
        // The pill fades out and the page fades in over the SAME short window
        // (first quarter of travel), so their alphas always add up to ~1 and
        // the sheet never shows an empty dark panel mid-travel (the hollow
        // frame seen while closing). It also keeps the full-screen Opacity
        // layer (a saveLayer) alive for only a handful of frames.
        final surfaceA = _smoothstep(0.0, 0.25, v);
        final pageA = _smoothstep(0.02, 0.25, v);

        return Positioned.fill(
          child: ClipPath(
            clipper: _SheetRectClipper(
              Rect.fromLTRB(left, top, screenW - right, screenH - bottomInset),
              topRadius,
              bottomRadius,
            ),
            child: Stack(
              children: [
                // Surface: full-screen gradient, alpha-only per frame (the
                // moving clip keeps it to the sheet rect). Hit-testing is
                // clipped to the sheet rect as well.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.fromRGBO(12, 12, 16, 0.88 * surfaceA),
                          Color.fromRGBO(8, 8, 12, 0.94 * surfaceA),
                        ],
                      ),
                    ),
                  ),
                ),
                // Page content: laid out once at full screen, revealed by the
                // moving clip; alpha is compositor-only (RepaintBoundary
                // above). Never interactive until fully open — same as the
                // reference, where mid-travel taps keep driving the sheet.
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: v < 0.98,
                    child: Opacity(opacity: pageA, child: page!),
                  ),
                ),
                // Grab area at the top: drag down to close. Translated per
                // frame (paint-only) so it hugs the sheet's top edge. Only
                // vertical drags are captured — taps fall through to the
                // page's own top-bar buttons. Dormant while the sheet rests at
                // 0 (pointer-down pre-warm mounts the layer early; without
                // this gate the strip would steal vertical scrolls in the
                // band above the mini pill).
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 96,
                  child: Transform.translate(
                    offset: Offset(0, top),
                    child: IgnorePointer(
                      ignoring: v <= 0.0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragUpdate: (d) => _dragSheet(d, travel),
                        onVerticalDragEnd: (d) => _endDragSheet(d, travel),
                        onVerticalDragCancel: _settleSheet,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The morphing artwork: the pill's 40 dp round thumb grows into the page's
  /// full artwork — the reference's signature container transform. The target
  /// is the page's own artwork rect (the page is laid out at full screen, so
  /// the rect does not move during the morph), keeping the handoff at 0.985
  /// pixel-exact for the classic page AND every skin (the page hides its own
  /// artwork until then via PlayerPage.sheetOffset). Topmost layer, so it
  /// covers the pill's thumbnail 1:1 as it starts growing.
  ///
  /// Perf model: the artwork is laid out ONCE at the target size and every
  /// frame only transforms + clips it (paint-only, GPU texture sample). The
  /// old version rebuilt SongThumbnail at a new size every tick — per-frame
  /// image re-layout + re-raster was the morph's stutter on low-end phones.
  Widget _buildMorphArt(MediaQueryData mq, MediaItem song, Rect pill) {
    final extras = song.extras;
    if (extras == null) return const SizedBox.shrink();
    final thumb = Rect.fromCenter(
      center: Offset(pill.left + 32, pill.top + 32), // 8 pad + 24 ring centre
      width: 40,
      height: 40,
    );
    // Morph target: measured once per shell build (song / scroll / keyboard
    // changes), with the page's live artwork rect preferred over the classic
    // fallback. Live measurement per tick is no longer needed because the
    // page no longer re-layouts during the morph.
    Rect end = _classicArtRect(mq);
    final ctx = _pageArtKey.currentContext;
    if (ctx != null) {
      final ro = ctx.findRenderObject();
      if (ro is RenderBox && ro.attached && ro.hasSize) {
        final tl = ro.localToGlobal(Offset.zero);
        final live = tl & ro.size;
        if (live.width >= 8 && live.height >= 8) end = live;
      }
    }
    final endW = math.max(end.width, 1.0);
    final endH = math.max(end.height, 1.0);
    // AnimatedBuilder sits directly under the shell's Stack so the builder can
    // return Positioned.fromRect itself (a Positioned must be a Stack child).
    return AnimatedBuilder(
      animation: _sheet,
      child: RepaintBoundary(
        child: SongThumbnail(
          song: extras,
          dp: mq.devicePixelRatio,
          width: endW,
          height: endH,
          fit: BoxFit.cover,
        ),
      ),
      builder: (context, img) {
        final v = _sheet.value.clamp(0.0, 1.0);
        final opacity = 1 - _smoothstep(0.88, 0.985, v);
        if (opacity <= 0.002) return const SizedBox.shrink();
        final p = (v / 0.9).clamp(0.0, 1.0);
        final rect = Rect.lerp(thumb, end, p)!;
        final sx = rect.width / endW;
        final sy = rect.height / endH;
        return Positioned.fromRect(
          rect: end,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.topLeft,
                transform: Matrix4.identity()
                  ..translate(rect.left - end.left, rect.top - end.top)
                  ..scale(sx, sy),
                child: ClipRRect(
                  // Radius in pre-transform units so the SCREEN radius matches
                  // the reference (20 → 36) as the image scales up.
                  borderRadius:
                  BorderRadius.circular(_lerp(20, 36, p) / sx),
                  child: img!,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Per-frame clip of the sheet: the interpolated sheet rect (pill rect →
/// full screen) with the interpolated corner radii. Changing the rect per
/// frame is a PAINT-only operation — everything inside stays laid out at
/// full screen ONCE, so following the finger never re-layouts (or
/// re-rasterises) the player page. This is what keeps the sheet 1:1 smooth
/// on low-end phones (the old per-frame Positioned insets re-laid-out the
/// entire PlayerPage every tick — that was the lag).
class _SheetRectClipper extends CustomClipper<Path> {
  const _SheetRectClipper(this.rect, this.topRadius, this.bottomRadius);
  final Rect rect;
  final double topRadius;
  final double bottomRadius;

  @override
  Path getClip(Size size) {
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(topRadius),
      topRight: Radius.circular(topRadius),
      bottomLeft: Radius.circular(bottomRadius),
      bottomRight: Radius.circular(bottomRadius),
    );
    return Path()..addRRect(rrect);
  }

  @override
  bool shouldReclip(_SheetRectClipper old) =>
      old.rect != rect ||
          old.topRadius != topRadius ||
          old.bottomRadius != bottomRadius;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Segmented Dynamic Bar
//
//  A rounded bar split into equal segments. The active segment is a raised
//  card that lifts above the bar and glides between tabs on a spring.
//
//  Built to stay smooth on 1 GB phones:
//   * no BackdropFilter / blur layer, no shader, no saveLayer (icons fade by
//     colour alpha, not Opacity);
//   * the bar, its dividers and the card's shadow are STATIC layers inside
//     RepaintBoundaries — they are rasterised once;
//   * per frame only two small widgets translate (Transform) and at most two
//     icon/label pairs change colour alpha.
// ═══════════════════════════════════════════════════════════════════════════

class _ZenDock extends StatefulWidget {
  const _ZenDock({required this.currentIndex, required this.onSelect});

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const _labels = ['Home', 'Search', 'Discover', 'Saved', 'Settings'];
  static const _icons = [
    Icons.home_outlined,
    Icons.search,
    Icons.explore_outlined,
    Icons.bookmark_border_rounded,
    Icons.settings_outlined,
  ];
  static const _activeIcons = [
    Icons.home_rounded,
    Icons.search,
    Icons.explore_rounded,
    Icons.bookmark_rounded,
    Icons.settings_rounded,
  ];

  @override
  State<_ZenDock> createState() => _ZenDockState();
}

class _ZenDockState extends State<_ZenDock>
    with SingleTickerProviderStateMixin {
  // Close to critically damped (zeta ~0.83): a soft landing with a hint of
  // life, never a wobble.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 34,
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
      _pos.animateWith(
          SpringSimulation(_spring, _pos.value, target, _pos.velocity));
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

    final liquid = GetIt.I<SettingsManager>().liquidGlass;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Liquid theme keeps its frosted-slab colour, but WITHOUT a live blur
    // layer (that is the expensive part on low-end GPUs).
    final barFill = liquid ? ZenFrost.slab(isDark) : cs.surfaceContainerHigh;
    final line = cs.outlineVariant.withValues(alpha: isDark ? 0.45 : 0.65);
    final cardFill = Color.alphaBlend(
      cs.primary.withValues(alpha: isDark ? 0.16 : 0.08),
      isDark ? cs.surfaceContainerHighest : cs.surface,
    );
    final shadow = Colors.black.withValues(alpha: isDark ? 0.5 : 0.18);

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
              final cardW = itemW * _kCardWidthFactor;
              const cardH = _kBarHeight + _kPop;
              const cardTop = _kOverhang - _kPop;

              double cardLeft(double pos) =>
                  ((pos + 0.5) * itemW - cardW / 2)
                      .clamp(0.0, width - cardW)
                      .toDouble();

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
                      // 1) Bar + dividers (static, rasterised once).
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _kOverhang,
                        height: _kBarHeight,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _SegBarPainter(
                              segments: n,
                              fill: barFill,
                              line: line,
                              shadow: shadow,
                            ),
                          ),
                        ),
                      ),

                      // 2) Idle icons + labels (static).
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _kOverhang,
                        height: _kBarHeight,
                        child: Row(
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: _SegItem(
                                  label: _ZenDock._labels[i],
                                  icon: _ZenDock._icons[i],
                                  color: cs.onSurfaceVariant,
                                  selected: i == slot,
                                  onTap: () => widget
                                      .onSelect(kZenMobileBranchOrder[i]),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 3) The raised card: its decoration is built ONCE and
                      //    cached as a layer; only a translate runs per frame.
                      Positioned(
                        left: 0,
                        top: cardTop,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _pos,
                            child: RepaintBoundary(
                              child: Container(
                                width: cardW,
                                height: cardH,
                                decoration: BoxDecoration(
                                  color: cardFill,
                                  borderRadius:
                                      BorderRadius.circular(_kCardRadius),
                                  border: Border.all(
                                    color:
                                        cs.primary.withValues(alpha: 0.28),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: shadow,
                                      blurRadius: 14,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            builder: (context, child) => Transform.translate(
                              offset: Offset(cardLeft(_pos.value), 0),
                              child: child,
                            ),
                          ),
                        ),
                      ),

                      // 4) The card's icon + label. They ride with the card
                      //    and cross-fade by COLOUR alpha between segments.
                      Positioned(
                        left: 0,
                        top: cardTop,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _pos,
                            builder: (context, _) {
                              final pos = _pos.value;
                              return Transform.translate(
                                offset: Offset(cardLeft(pos), 0),
                                child: SizedBox(
                                  width: cardW,
                                  height: cardH,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      for (var i = 0; i < n; i++)
                                        if ((1 - (pos - i).abs()) > 0.01)
                                          _CardContent(
                                            icon: _ZenDock._activeIcons[i],
                                            label: _ZenDock._labels[i],
                                            color: cs.onSurface.withValues(
                                              alpha: (1 - (pos - i).abs())
                                                  .clamp(0.0, 1.0),
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

/// One idle segment: icon over a small label.
class _SegItem extends StatelessWidget {
  const _SegItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.1,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// The active segment's icon + bold label (lives inside the raised card).
class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 26, color: color),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Bar body: rounded slab, soft drop shadow, thin segment dividers.
class _SegBarPainter extends CustomPainter {
  const _SegBarPainter({
    required this.segments,
    required this.fill,
    required this.line,
    required this.shadow,
  });

  final int segments;
  final Color fill;
  final Color line;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(_kBarRadius),
    );
    canvas.drawShadow(Path()..addRRect(rrect), shadow, 6, false);
    canvas.drawRRect(rrect, Paint()..color = fill);

    final p = Paint()
      ..color = line
      ..strokeWidth = 1;
    final w = size.width / segments;
    for (var i = 1; i < segments; i++) {
      final x = (w * i).roundToDouble() + 0.5;
      canvas.drawLine(Offset(x, 16), Offset(x, size.height - 16), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SegBarPainter old) =>
      old.segments != segments ||
      old.fill != fill ||
      old.line != line ||
      old.shadow != shadow;
}
