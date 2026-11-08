// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'
    show PointerEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/liquid/glass_panel.dart';
import 'package:zenmusic/desktop/screens/player/player_page.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';
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
    if (_playerSheetOpen) _closePlayerSheet();
    _showChrome();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  static const bool kShellAutoHide = true; // kill-switch
  static const Duration _kIdleBeforeHide = Duration(seconds: 3);
  static const Duration _kChromeAnim = Duration(milliseconds: 380);
  static const double _kRevealBandWidth = 48;

  Timer? _idleTimer;
  bool _railHidden = false;

  bool get _autoHideOn => kShellAutoHide && Platform.isWindows;

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
    });
  }

  void _closePlayerSheet() {
    if (!_isMobile) return;
    setState(() => _playerSheetOpen = false);
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (!_isMobile || _playerSheetOpen) return false;
    if (n is! UserScrollNotification) return false;
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
    if (_autoHideOn) {
      _idleTimer = Timer(_kIdleBeforeHide, _tuckAway);
    }
    ShellOverlaysBus.fullPageAbove.addListener(_onFullPageAboveChanged);
  }

  @override
  void dispose() {
    ShellOverlaysBus.fullPageAbove.removeListener(_onFullPageAboveChanged);
    _idleTimer?.cancel();
    super.dispose();
  }

  void _onFullPageAboveChanged() {
    if (mounted) setState(() {});
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_kIdleBeforeHide, _tuckAway);
  }

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

  void _onShellActivity() {
    if (!_autoHideOn || _railHidden) return;
    _restartIdleTimer();
  }

  void _revealRail() {
    if (!mounted) return;
    setState(() => _railHidden = false);
    _restartIdleTimer();
  }

  void _tuckAway() {
    if (!mounted || !_autoHideOn) return;
    setState(() => _railHidden = true);
  }

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
    // The on-screen keyboard (Android) covers the lower part of the screen;
    // keep the nav bar and mini player out of the way so they do not float
    // above the keyboard and squeeze the page (e.g. the Search results).
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final pageAbove = ShellOverlaysBus.fullPageAbove.value;
    final settings = GetIt.I<SettingsManager>();
    final liquid = settings.liquidGlass;
    final m3 = settings.isMaterial3;

    final Widget rail = NavigationRail(
      extended: true,
      backgroundColor: (liquid || m3)
          ? Colors.transparent
          : Theme.of(context).colorScheme.surfaceContainerLowest,
                  groupAlignment: 0.0,
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(CupertinoIcons.music_house),
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
                      icon: const Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore,
                          color: m3 ? null : Colors.black),
                      label: const Text('Discover'),
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
            icon: const Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore,
                color: m3 ? null : Colors.black),
            label: 'Discover',
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
            ? null
            : liquid
                ? Colors.transparent
                : Theme.of(context).colorScheme.surfaceContainerLowest,
        onDestinationSelected: _goBranch,
      );

    Widget mobileChrome(Widget bar) => ClipRect(
          child: AnimatedSize(
            duration: _kChromeAnim,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.bottomCenter,
            child: (_chromeHidden ||
                    _playerSheetOpen ||
                    pageAbove ||
                    keyboardOpen)
                ? const SizedBox(width: double.infinity, height: 0)
                : bar,
          ),
        );

    Widget? bottomBar;
    if (_isMobile && screenWidth < 450) {
      bottomBar = mobileChrome(m3
          ? navBar
          : liquid
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: ZenGlassPanel(radius: 22, child: navBar),
                )
              : navBar);
    } else if (screenWidth < 450) {
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

    final bottomPlayer = BottomPlayer(
      onOpen: _isMobile ? _openPlayerSheet : null,
    );
    Widget miniPlayer = liquid
        ? ZenGlassPanel(radius: 20, child: bottomPlayer)
        : bottomPlayer;
    if (_isMobile) {
      final hidden =
          _chromeHidden || _playerSheetOpen || pageAbove || keyboardOpen;
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
      canPop: !_playerSheetOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _playerSheetOpen) _closePlayerSheet();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: _wrapActivityDetector(
          Stack(
            children: [
              Row(
                children: [
                  if (screenWidth >= 450)
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
                              ? rail
                              : liquid
                                  ? IntrinsicHeight(
                                  child: ZenGlassPanel(
                                    radius: 24,
                                    margin: const EdgeInsets.all(8),
                                    child: rail,
                                  ),
                                )
                              : rail,
                        ),
                      ),
                    ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: widget.navigationShell,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: miniPlayer,
              ),
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
