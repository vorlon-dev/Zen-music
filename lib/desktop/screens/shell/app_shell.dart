// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT DEVIATIONS: S.of(...) l10n -> English literals; UpdateService deferred;
// rail labels made theme-correct and visible (user-approved); DEVIATION:
// Saved item carries a live download badge (DOWNLOADING/QUEUED count) via
// the DownloadManager notifier.

// SP-55.2: dart:async for the idle Timer, dart:io for the platform gate.
import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show PointerEvent; // SP-55.3: typed hover handler
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/liquid/glass_panel.dart'; // SP-54
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart'; // SP-54
import 'widgets/bottom_player.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    Key? key,
    required this.navigationShell,
  }) : super(key: key ?? const ValueKey('AppShell'));
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  // ── SP-55.2: auto-hiding sidebar (4 nav buttons only) ─────────────────────────────────────────
  // Windows desktop only: after 3 s without pointer activity the
  // Home / Search / Saved / Settings rail glides away and the content
  // expands to fill the whole window — "full screen" WITHOUT touching
  // the OS window frame. SP-55.2 per user correction: the
  // borderless-fullscreen window toggle (Win32Fullscreen) and the mini
  // player tuck are REMOVED — only the 4-button rail hides now; the
  // mini player stays put. SP-55.3 per user correction: the hidden rail
  // does NOT glide back on ANY mouse move — it only re-appears when the
  // pointer moves into a narrow reveal band along the LEFT edge of the
  // window (i.e. near the rail itself). While visible, pointer activity
  // still resets the 3 s idle timer as before.
  static const bool kShellAutoHide = true; // kill-switch
  static const Duration _kIdleBeforeHide = Duration(seconds: 3);
  static const Duration _kChromeAnim = Duration(milliseconds: 380);
  // SP-55.3: how close (logical px) to the window's left edge the
  // pointer must come for the tucked-away rail to glide back in.
  static const double _kRevealBandWidth = 48;

  Timer? _idleTimer;
  bool _chromeHidden = false;

  bool get _autoHideOn => kShellAutoHide && Platform.isWindows;

  @override
  void initState() {
    super.initState();
    // SP-55: the first tuck-away fires 3 s after launch if the mouse
    // stays still.
    if (_autoHideOn) {
      _idleTimer = Timer(_kIdleBeforeHide, _tuckAway);
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  /// SP-55.3: shared idle-timer reset — arms the next tuck-away.
  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleBeforeHide, _tuckAway);
  }

  /// SP-55.3: hover handler for the whole body. While the rail is
  /// visible, any hover just resets the idle timer. While it is tucked
  /// away, hover outside the left reveal band is deliberately ignored —
  /// only entering the band glides the rail back in.
  void _onShellHover(PointerEvent e) {
    if (!_autoHideOn) return;
    if (_chromeHidden) {
      if (e.position.dx <= _kRevealBandWidth) {
        _revealRail();
      }
      return;
    }
    _restartIdleTimer();
  }

  /// SP-55.3: clicks / drags / wheel keep the visible rail awake, but
  /// they NEVER reveal a hidden rail on their own — moving or clicking
  /// anywhere else must not open the sidebar.
  void _onShellActivity() {
    if (!_autoHideOn || _chromeHidden) return;
    _restartIdleTimer();
  }

  /// SP-55.3: glide the tucked-away rail back in (the pointer reached
  /// the left reveal band) and restart the idle timer so it does not
  /// instantly re-tuck.
  void _revealRail() {
    if (!mounted) return;
    setState(() => _chromeHidden = false);
    _restartIdleTimer();
  }

  /// SP-55 / SP-55.2: tuck the 4-button sidebar away; the content
  /// expands to fill the freed width. The OS window is never touched.
  void _tuckAway() {
    if (!mounted || !_autoHideOn) return;
    setState(() => _chromeHidden = true);
  }

  /// SP-55: catches every pointer activity over the whole body — hover
  /// moves (MouseRegion), clicks/drags/wheel (Listener). Translucent so
  /// empty gutters count too. SP-55.3: the reveal policy lives in the
  /// handlers — while tucked away the body stays inert except for the
  /// left reveal band, so the sidebar only wakes when the pointer
  /// actually comes near it.
  Widget _wrapActivityDetector(Widget child) {
    if (!_autoHideOn) return child;
    return MouseRegion(
      onHover: _onShellHover,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onShellActivity(),
        onPointerMove: (_) => _onShellActivity(),
        onPointerSignal: (_) => _onShellActivity(),
        child: child,
      ),
    );
  }

  /// Saved icon with a live download-count badge (DOWNLOADING + QUEUED).
  Widget _savedIcon({required bool selected}) {
    final icon = selected
        ? const Icon(Icons.library_music, color: Colors.black)
        : const Icon(Icons.library_music_outlined);
    return ValueListenableBuilder<List<Map>>(
      valueListenable: GetIt.I<DownloadManager>().downloads,
      builder: (context, downloads, _) {
        final active = downloads
            .where((d) =>
        d['status'] == 'DOWNLOADING' || d['status'] == 'QUEUED')
            .length;
        if (active == 0) return icon;
        return Badge(
          label: Text('$active'),
          isLabelVisible: true,
          child: icon,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    // SP-54: Liquid Glass — when ON, the rail / bottom nav / mini player
    // become glass surfaces (shader glass on Windows, Dart frost on
    // Android since SP-57, static frost on low-tier devices).
    // SP-58: Material 3 — the PixelMusic design system as a THIRD whole-
    // app theme: M3 ColorScheme/type/shapes via ZenM3Theme, M3 indicator
    // pills on the rail/nav bar, M3 mini player with the wavy progress
    // line. No platform views anywhere (SP-57 contract) → the theme
    // switch is a pure Dart rebuild, blank-page-proof on every device.
    final settings = GetIt.I<SettingsManager>();
    final liquid = settings.liquidGlass;
    final m3 = settings.isMaterial3; // SP-58

    final Widget rail = NavigationRail(
      extended: true,
      backgroundColor: (liquid || m3)
          ? Colors.transparent // SP-54: glass panel above / SP-58: M3 bg
          : Theme.of(context).colorScheme.surfaceContainerLowest,
                  groupAlignment: 0.0,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.music_house),
                      // SP-58: null colour → M3 onSecondaryContainer pill
                      // look; glass keeps its black-on-frost look.
                      selectedIcon: Icon(CupertinoIcons.music_house_fill,
                          color: m3 ? null : Colors.black),
                      label: const Text('Home'),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.search),
                      selectedIcon: Icon(CupertinoIcons.search,
                          color: m3 ? null : Colors.black),
                      label: const Text('Search'),
                    ),
                    NavigationRailDestination(
                      icon: _savedIcon(selected: false),
                      selectedIcon: _savedIcon(selected: true),
                      label: const Text('Saved'),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.gear_alt),
                      selectedIcon: Icon(CupertinoIcons.gear_alt_fill,
                          color: m3 ? null : Colors.black),
                      label: const Text('Settings'),
                    )
                  ],
                  selectedIndex: widget.navigationShell.currentIndex,
                  onDestinationSelected: _goBranch,
                );

    final Widget navBar = NavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        destinations: [
          NavigationDestination(
            icon: const Icon(CupertinoIcons.music_house),
            selectedIcon: Icon(CupertinoIcons.music_house_fill,
                color: m3 ? null : Colors.black),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.search),
            selectedIcon: const Icon(CupertinoIcons.search, color: Colors.black),
            label: 'Search',
          ),
          NavigationDestination(
            icon: _savedIcon(selected: false),
            selectedIcon: _savedIcon(selected: true),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: const Icon(CupertinoIcons.settings),
            selectedIcon: Icon(CupertinoIcons.settings_solid,
                color: m3 ? null : Colors.black),
            label: 'Settings',
          ),
        ],
        backgroundColor: m3
            ? null // SP-58: M3 theme's navigationBarTheme (surfaceContainer)
            : liquid
                ? Colors.transparent // SP-54: ZenGlassPanel provides the glass
                : Theme.of(context).colorScheme.surfaceContainerLowest,
        onDestinationSelected: _goBranch,
      );

    return Scaffold(
      backgroundColor: Colors.transparent,
      // SP-55: the whole body is the activity surface for the auto-hiding
      // shell.
      body: _wrapActivityDetector(
        Stack(
          children: [
            Row(
              // SP-54.5: keep the Row's DEFAULT center alignment. Classic mode
              // centers the rail destinations vertically (groupAlignment: 0.0)
              // and the glass capsule must sit in that same centered spot.
              // (SP-54.1 had docked the capsule to the top; center restored.)
              children: [
                // SP-54: floating glass sidebar when liquid glass is on.
                if (screenWidth >= 450)
                  // SP-55 / SP-55.2: ONLY the rail tucks away smoothly —
                  // the Align's widthFactor animates 1 -> 0 (the content
                  // expands to fill the freed width) while ClipRect wipes
                  // the capsule out and the slight slide adds a parallax
                  // feel. The OS window frame is never touched.
                  ClipRect(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: _chromeHidden ? 0.0 : 1.0),
                      duration: _kChromeAnim,
                      curve: Curves.easeInOutCubic,
                      builder: (context, widthFactor, railChild) => Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: widthFactor,
                        child: railChild,
                      ),
                      child: AnimatedSlide(
                        offset: _chromeHidden
                            ? const Offset(-0.25, 0)
                            : Offset.zero,
                        duration: _kChromeAnim,
                        curve: Curves.easeInOutCubic,
                        child: m3
                            // SP-58: standard M3 rail — active-indicator
                            // pills from the M3 theme, full-height, no
                            // glass hug (that look belongs to glass mode).
                            ? rail
                            : liquid
                                ? IntrinsicHeight(
                                // SP-54.1: NavigationRail always stretches to
                                // full height (its destination block lives in an
                                // Expanded). Classic mode hides that behind a
                                // solid full-height background, but in glass mode
                                // it painted a huge empty glass slab under
                                // "Settings". IntrinsicHeight caps the panel to
                                // exactly the 4 destinations; with the Row's
                                // default center alignment (SP-54.5) the hugged
                                // capsule is then vertically centered like the
                                // default UI.
                                child: ZenGlassPanel(
                                  radius: 24,
                                  // SP-54.5: symmetric margin — the old
                                  // bottom-88 guard tilted the centered capsule
                                  // upwards.
                                  margin: const EdgeInsets.all(8),
                                  child: rail,
                                ),
                              )
                            : rail,
                      ),
                    ),
                  ),
                Expanded(
                  child: widget.navigationShell,
                ),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              // SP-55.2: the mini player STAYS PUT — only the 4-button
              // sidebar auto-hides (user correction over SP-55).
              // SP-54: glass mini player when liquid glass is on.
              // SP-58: in Material 3 the BottomPlayer styles itself as an
              // M3 surface (surfaceContainerHigh + wavy progress line).
              child: liquid
                  ? ZenGlassPanel(radius: 20, child: BottomPlayer())
                  : const BottomPlayer(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: screenWidth < 450
          ? (m3
              // SP-58: standard M3 NavigationBar (surface container,
              // active-indicator pill) — no glass padding, per spec.
              ? navBar
              : liquid
                  ? Padding(
                      // SP-54: floating glass bottom nav on phones.
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: ZenGlassPanel(radius: 22, child: navBar),
                    )
                  : navBar)
          : null,
    );
  }
}