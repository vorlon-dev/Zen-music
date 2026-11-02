// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT DEVIATIONS: S.of(...) l10n -> English literals; UpdateService deferred;
// rail labels made theme-correct and visible (user-approved); DEVIATION:
// Saved item carries a live download badge (DOWNLOADING/QUEUED count) via
// the DownloadManager notifier.

// SP-55.2: dart:async for the idle Timer, dart:io for the platform gate.
// SP-78 mobile shell: the phone gets the LastWave-style shell — the YouTube
// tab is back in the bottom bar, scrolling the feed up hides BOTH the nav
// bar and the mini player (glide + fade, they glide back on a downward
// scroll), and tapping the mini player expands the full player as an
// in-shell overlay sheet (slide 85% + scale 0.85 from the bottom edge +
// fade — the exact motion the LastWave player sheet uses) instead of
// pushing another route: no more double-open and no route-push jank.
// Windows keeps the SP-55.2/55.3 rail auto-hide and the /player route
// push, byte-for-byte the old behaviour.
//
// SP-81 (user report: "I can't exit from player page — only the shell
// should auto hide for only home screen. Not for player screen or
// anything else"):
//   1. The scroll auto-hide now lives ONLY on the Home tab (branch 0).
//      Search / YouTube / Saved / Settings keep the bar permanently.
//   2. The player screen NEVER auto-hides anything, and the nav bar
//      stays visible while the player sheet is open — the dock is the
//      guaranteed way out: tapping ANY destination collapses the sheet
//      first, then navigates.
//   3. The mini player still tucks behind the sheet (tapping it there
//      would double-open), but the bar itself never hides for the sheet.

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show PointerEvent; // SP-55.3: typed hover handler
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/liquid/glass_panel.dart'; // SP-54
import 'package:zenmusic/desktop/screens/player/player_page.dart'; // SP-78
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart'; // SP-54
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart'; // SP-82
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
    // SP-81: a dock tap is ALWAYS an exit from the player sheet — the
    // sheet collapses first, then the branch switches. This is the
    // fix for "I can't exit from player page": whatever state the
    // shell is in, touching the bar always gets the user out.
    if (_playerSheetOpen) _closePlayerSheet();
    _showChrome(); // SP-78: a tab switch always reveals the chrome again.
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  // ── SP-55.2: auto-hiding sidebar (4 nav buttons only, WINDOWS) ────────
  // Windows desktop only: after 3 s without pointer activity the
  // Home / Search / Saved / Settings rail glides away and the content
  // expands to fill the whole window — "full screen" WITHOUT touching
  // the OS window frame. SP-55.2 per user correction: the
  // borderless-fullscreen window toggle (Win32Fullscreen) and the mini
  // player tuck are REMOVED — only the rail hides now; the mini
  // player stays put. SP-55.3 per user correction: the hidden rail
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
  bool _railHidden = false;

  bool get _autoHideOn => kShellAutoHide && Platform.isWindows;

  // ── SP-78: mobile shell chrome (scroll auto-hide + player sheet) ──────
  // Mobile only. Scrolling the feed UP (finger up, content forward)
  // hides the nav bar and the mini player together; a downward scroll
  // brings them back. Tapping the mini player expands the full player
  // INSIDE this shell (no route push — the sheet is kept warm after the
  // first open, which is where the old double-push and open lag came
  // from). Windows never sees any of this.
  static const Duration _kSheetAnim = Duration(milliseconds: 320);
  bool _chromeHidden = false; // nav bar + mini player (scroll)
  bool _playerSheetOpen = false;
  bool _playerSheetBuilt = false; // lazy, then kept warm

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  void _hideChrome() {
    if (!_isMobile || _chromeHidden || _playerSheetOpen) return;
    setState(() => _chromeHidden = true);
  }

  void _showChrome() {
    if (!_isMobile || !_chromeHidden) return;
    setState(() => _chromeHidden = false);
  }

  void _openPlayerSheet() {
    if (!_isMobile) return;
    setState(() {
      _playerSheetBuilt = true;
      _playerSheetOpen = true;
      // SP-82: the sheet is the PLAYER PAGE — the user does not want the
      // nav bar on it ("I don't want nav bar in my player page"), so the
      // bottom bar now tucks with the sheet (it used to stay per SP-81).
      // Exit affordances: the player's own close chevron, drag-to-dismiss,
      // and system back (PopScope) — exactly the reference app.
    });
  }

  void _closePlayerSheet() {
    if (!_isMobile) return;
    setState(() => _playerSheetOpen = false);
  }

  /// SP-78: scroll-direction watcher bubbling up from every tab's feed.
  /// Reverse (content scrolling up) hides the chrome; forward reveals it.
  ///
  /// SP-82: the auto-hide lives on EVERY tab (Home / Search / YouTube /
  /// Saved / Settings) — the SP-81 home-only scope was too narrow (user:
  /// "I want the auto hide the nav bar in home screen search screen other
  /// 5 tab also"). Still mobile-only, still vertical-feeds-only, still
  /// suspended while the player sheet is open, and the chrome always
  /// comes back near the top of any feed.
  bool _onScrollNotification(ScrollNotification n) {
    if (!_isMobile || _playerSheetOpen) return false;
    if (n is! UserScrollNotification) return false;
    // SP-81: only VERTICAL feeds drive the chrome — swiping a horizontal
    // carousel must not tuck the bar away.
    if (n.metrics.axis != Axis.vertical) return false;
    // Near the top of any feed the chrome always shows.
    if (n.metrics.pixels <= 40) {
      _showChrome();
      return false;
    }
    switch (n.direction) {
      case ScrollDirection.reverse:
        _hideChrome();
      case ScrollDirection.forward:
        _showChrome();
      default:
        break;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // SP-55: the first tuck-away fires 3 s after launch if the mouse
    // stays still.
    if (_autoHideOn) {
      _idleTimer = Timer(_kIdleBeforeHide, _tuckAway);
    }
    // SP-82: rebuild when a full page (the player) stacks above the shell
    // — all floating chrome tucks while it is up (see build).
    ShellOverlaysBus.fullPageAbove.addListener(_onFullPageAboveChanged);
  }

  @override
  void dispose() {
    ShellOverlaysBus.fullPageAbove.removeListener(_onFullPageAboveChanged);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onFullPageAboveChanged() {
    if (mounted) setState(() {}); // SP-82
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
    if (_railHidden) {
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
    if (!_autoHideOn || _railHidden) return;
    _restartIdleTimer();
  }

  /// SP-55.3: glide the tucked-away rail back in (the pointer reached
  /// the left reveal band) and restart the idle timer so it does not
  /// instantly re-tuck.
  void _revealRail() {
    if (!mounted) return;
    setState(() => _railHidden = false);
    _restartIdleTimer();
  }

  /// SP-55 / SP-55.2: tuck the 4-button sidebar away; the content
  /// expands to fill the freed width. The OS window is never touched.
  void _tuckAway() {
    if (!mounted || !_autoHideOn) return;
    setState(() => _railHidden = true);
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
    // SP-82: a full page (the player) is stacked above the shell → every
    // floating chrome tucks (LastWave: "hasBottomNavigation =
    // currentRoute == MainShell.route"). On Windows the /player route
    // already covers the shell opaquely, so this is invisible there; on
    // mobile it guarantees the dock never shows on the player page no
    // matter which shell or hosting style is live. Rebuilt via the
    // initState listener.
    final pageAbove = ShellOverlaysBus.fullPageAbove.value;
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
                    // SP-78: YouTube joined the rail too (branch index 2,
                    // same order as the phone's bottom bar).
                    NavigationRailDestination(
                      icon: const Icon(Icons.smart_display_outlined),
                      selectedIcon: Icon(Icons.smart_display,
                          color: m3 ? null : Colors.black),
                      label: const Text('YouTube'),
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
          // SP-78: YouTube tab restored (Home / Search / YouTube / Saved /
          // Settings — the order the phone shows).
          NavigationDestination(
            icon: const Icon(Icons.smart_display_outlined),
            selectedIcon: Icon(Icons.smart_display,
                color: m3 ? null : Colors.black),
            label: 'YouTube',
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

    // SP-78: the phone's chrome hides by GLIDING — the bar's reserved
    // height animates away (AnimatedSize + ClipRect wipes the bar down
    // past the bottom edge, exactly the dock tuck feel) and the feed
    // expands into the freed space. Revealing runs the same motion
    // backwards.
    Widget mobileChrome(Widget bar) => ClipRect(
          child: AnimatedSize(
            duration: _kChromeAnim,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.bottomCenter,
            // SP-82: collapse for the scroll auto-hide, for the player
            // sheet, and while the full-page player is above the shell —
            // the nav bar never shows on the player screen (user request),
            // the player's own close/drag/back affordances are the way out
            // (see _goBranch for the reverse direction).
            child: (_chromeHidden || _playerSheetOpen || pageAbove)
                ? const SizedBox(width: double.infinity, height: 0)
                : bar,
          ),
        );

    Widget? bottomBar;
    if (_isMobile && screenWidth < 450) {
      // SP-78: phones always carry the bar (the old screenWidth < 450
      // gate dropped it on some narrow-window desktops too — mobile keeps
      // it); wide foldables/tablets keep the pre-existing rail layout.
      bottomBar = mobileChrome(m3
          ? navBar
          : liquid
              ? Padding(
                  // SP-54: floating glass bottom nav on phones.
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: ZenGlassPanel(radius: 22, child: navBar),
                )
              : navBar);
    } else if (screenWidth < 450) {
      // SP-82: full-page player above → no bar here either.
      bottomBar = pageAbove
          ? null
          : (m3
              ? navBar
              : liquid
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: ZenGlassPanel(radius: 22, child: navBar),
                    )
                  : navBar);
    }

    // SP-78: the mini player glides away with the chrome (scroll or
    // player sheet). Windows keeps it pinned (SP-55.2 contract).
    final bottomPlayer = BottomPlayer(
      // SP-78: mobile opens the in-shell player sheet instead of pushing
      // a route (double-push + lag fix); Windows keeps the /player push.
      onOpen: _isMobile ? _openPlayerSheet : null,
    );
    Widget miniPlayer = liquid
        ? ZenGlassPanel(radius: 20, child: bottomPlayer)
        : bottomPlayer;
    if (_isMobile) {
      // SP-82: the mini player tucks for the scroll auto-hide, the player
      // sheet, AND the full-page player — nothing of the shell floats
      // over / under the player page.
      final hidden = _chromeHidden || _playerSheetOpen || pageAbove;
      miniPlayer = IgnorePointer(
        ignoring: hidden,
        child: AnimatedSlide(
          offset: hidden ? const Offset(0, 1.35) : Offset.zero,
          duration: _kChromeAnim,
          curve: Curves.easeInOutCubic,
          child: AnimatedOpacity(
            opacity: hidden ? 0.0 : 1.0,
            duration: _kChromeAnim,
            child: miniPlayer,
          ),
        ),
      );
    }

    return PopScope(
      // SP-78: system back collapses the player sheet first.
      canPop: !_playerSheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _playerSheetOpen) _closePlayerSheet();
      },
      child: Scaffold(
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
                        tween: Tween<double>(end: _railHidden ? 0.0 : 1.0),
                        duration: _kChromeAnim,
                        curve: Curves.easeInOutCubic,
                        builder: (context, widthFactor, railChild) => Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: widthFactor,
                          child: railChild,
                        ),
                        child: AnimatedSlide(
                          offset: _railHidden
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
                                  // exactly the destinations; with the Row's
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
                    // SP-78: every tab's feed reports its scroll direction
                    // here — the mobile chrome hides/reveals with the drag.
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: widget.navigationShell,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                // SP-55.2 (Windows): the mini player STAYS PUT — only the
                // sidebar auto-hides. SP-78 (mobile): it glides away with
                // the nav bar on scroll, and hides behind the player sheet.
                // SP-54: glass mini player when liquid glass is on.
                // SP-58: in Material 3 the BottomPlayer styles itself as an
                // M3 surface (surfaceContainerHigh + wavy progress line).
                child: miniPlayer,
              ),
              // SP-78: the LastWave-style player sheet — an in-shell
              // overlay, not a route. Slide 85% + scale 0.85 anchored to
              // the bottom edge + fade, exactly the PlayerHost expand/
              // collapse motion; built lazily on first open and kept
              // warm (tickers paused while collapsed) after.
              if (_isMobile && _playerSheetBuilt)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_playerSheetOpen,
                    child: TickerMode(
                      enabled: _playerSheetOpen,
                      child: AnimatedScale(
                        scale: _playerSheetOpen ? 1.0 : 0.85,
                        alignment: Alignment.bottomCenter,
                        duration: _kSheetAnim,
                        curve: _playerSheetOpen
                            ? Curves.easeOutCubic
                            : Curves.easeInCubic,
                        child: AnimatedSlide(
                          offset: _playerSheetOpen
                              ? Offset.zero
                              : const Offset(0, 0.85),
                          duration: _kSheetAnim,
                          curve: _playerSheetOpen
                              ? Curves.easeOutCubic
                              : Curves.easeInCubic,
                          child: AnimatedOpacity(
                            opacity: _playerSheetOpen ? 1.0 : 0.0,
                            duration: _playerSheetOpen
                                ? const Duration(milliseconds: 180)
                                : const Duration(milliseconds: 150),
                            child: Material(
                              type: MaterialType.transparency,
                              child: PlayerPage(
                                onClose: _closePlayerSheet,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }
}
