// ZenMusic — MOBILE APP SHELL (SP-77).
//
// The phone shell, re-modelled on the reference app's shell behaviour:
//   * a floating bottom dock (5 destinations: Home / Search / YouTube /
//     Saved / Settings) with the animated pill indicator — the selected
//     pill grows (34 -> 62) on a spring-like curve, icon + label colours
//     cross-fade with it;
//   * the mini player sits above the dock and BOTH slide away when the
//     user scrolls a feed up (scroll direction "reverse"), sliding back on
//     the first downward scroll — exactly like the reference shell;
//   * content scrolls BEHIND the dock (the dock is a floating overlay, so
//     glass mode shows the feed through it) — pages get the chrome height
//     injected into MediaQuery.padding.bottom so their SafeAreas clear it;
//   * tapping a destination always reveals the chrome again.
//
// WINDOWS IS UNTOUCHED: app_shell.dart keeps serving the desktop; this
// shell is only mounted on Android/iOS (see router.dart).

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart' show MediaItem;

import 'package:zenmusic/desktop/liquid/glass_panel.dart';
import 'package:zenmusic/desktop/screens/shell/widgets/bottom_player.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart'; // SP-82

/// Branch indexes in the router (see router.dart — SP-79 order):
/// 0=/ 1=/search 2=/youtube 3=/saved 4=/settings, i.e. exactly the dock's
/// visual order Home / Search / YouTube / Saved / Settings.
const List<int> kZenMobileBranchOrder = [0, 1, 2, 3, 4];

class ZenMobileShell extends StatefulWidget {
  const ZenMobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// True on phone platforms — the router mounts this shell there only.
  static bool applies() => Platform.isAndroid || Platform.isIOS;

  @override
  State<ZenMobileShell> createState() => _ZenMobileShellState();
}

class _ZenMobileShellState extends State<ZenMobileShell> {
  bool _chromeHidden = false;

  void _goBranch(int branch) {
    if (_chromeHidden) _show();
    widget.navigationShell.goBranch(
      branch,
      initialLocation: branch == widget.navigationShell.currentIndex,
    );
  }

  void _hide() {
    if (!_chromeHidden) setState(() => _chromeHidden = true);
  }

  void _show() {
    if (_chromeHidden) setState(() => _chromeHidden = false);
  }

  // Scroll-direction-aware chrome: scrolling a feed UP (content moves up,
  // "reverse") hides the dock + mini player; the first downward scroll
  // brings them back. Near the top the chrome always shows. Horizontal
  // carousels are ignored (only vertical feeds drive the chrome).
  //
  // SP-82: the auto-hide now lives on EVERY tab (Home / Search / YouTube /
  // Saved / Settings) — the SP-81 home-only scope was too narrow (user:
  // "I want the auto hide the nav bar in home screen search screen other
  // 5 tab also"). The dock stays hidden entirely while a full page (the
  // player) is stacked above the shell — see ShellOverlaysBus.
  bool _onUserScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.metrics.pixels <= 40) {
      _show();
      return false;
    }
    if (n.direction == ScrollDirection.reverse) {
      _hide();
    } else if (n.direction == ScrollDirection.forward) {
      _show();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = GetIt.I<SettingsManager>();
    final liquid = settings.liquidGlass;
    final m3 = settings.isMaterial3;
    final mq = MediaQuery.of(context);

    // Overlay shell (the desktop AppShell's proven pattern): the branch
    // content is full-size and the floating chrome (mini player + dock)
    // hovers over it — so hiding the chrome genuinely expands the feed.
    // Pages learn the chrome height through MediaQuery.padding.bottom so
    // their SafeAreas never underlap it.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onUserScroll,
        child: ValueListenableBuilder<bool>(
          // SP-82: a full page (the player) stacked above the shell tucks
          // the WHOLE floating chrome — dock AND mini player. LastWave
          // contract: pushed routes never carry bottom navigation
          // ("I don't want nav bar in my player page").
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
                                mq.padding.bottom + 86.0 + miniInset),
                          ),
                        ),
                        child: widget.navigationShell,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _Chrome(
                        hidden: _chromeHidden || pageAbove,
                        liquid: liquid,
                        m3: m3,
                        currentIndex: widget.navigationShell.currentIndex,
                        onSelect: _goBranch,
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

// ═══════════════════════════════════════════════════════════════════════
// Bottom chrome: mini player + dock, sliding away together.
// ═══════════════════════════════════════════════════════════════════════

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.hidden,
    required this.liquid,
    required this.m3,
    required this.currentIndex,
    required this.onSelect,
  });

  final bool hidden;
  final bool liquid;
  final bool m3;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: hidden ? const Offset(0, 1.08) : Offset.zero,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: hidden ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 260),
        child: IgnorePointer(
          ignoring: hidden,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini player (self-hides when nothing is playing).
              const BottomPlayer(),
              _ZenDock(
                liquid: liquid,
                m3: m3,
                currentIndex: currentIndex,
                onSelect: onSelect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// The floating dock — reference-style animated pill indicator.
// ═══════════════════════════════════════════════════════════════════════

class _ZenDock extends StatelessWidget {
  const _ZenDock({
    required this.liquid,
    required this.m3,
    required this.currentIndex,
    required this.onSelect,
  });

  final bool liquid;
  final bool m3;
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final Color container;
    if (m3) {
      container = cs.surfaceContainerHigh;
    } else if (liquid) {
      container = Colors.transparent; // ZenGlassPanel provides the glass
    } else {
      container = dark ? const Color(0xFF202020) : cs.surfaceContainerLowest;
    }

    Widget dock = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
        child: Material(
          color: container,
          elevation: liquid || m3 ? 0 : 8,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(30),
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                for (var i = 0; i < kZenMobileBranchOrder.length; i++)
                  _DockItem(
                    label: _labels[i],
                    icon: _icons[i],
                    activeIcon: _activeIcons[i],
                    selected: currentIndex == kZenMobileBranchOrder[i],
                    liquid: liquid,
                    m3: m3,
                    onTap: () => onSelect(kZenMobileBranchOrder[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (liquid && !m3) {
      dock = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: ZenGlassPanel(radius: 30, child: dock),
      );
    }
    return dock;
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.liquid,
    required this.m3,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final bool liquid;
  final bool m3;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final glass = liquid && !m3;

    final Color indicator = selected
        ? (glass
            ? cs.secondaryContainer.withValues(alpha: 0.35)
            : cs.secondaryContainer)
        : Colors.transparent;
    final Color iconTint = selected
        ? (glass ? Colors.black : cs.onSecondaryContainer)
        : cs.onSurfaceVariant;
    final Color labelColor = selected
        ? (glass ? Colors.black : cs.onSurface)
        : cs.onSurfaceVariant.withValues(alpha: 0.85);

    return Expanded(
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The growing pill behind the icon — reference-shell signature.
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              height: 32,
              width: selected ? 62 : 34,
              decoration: BoxDecoration(
                color: indicator,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                size: 23,
                color: iconTint,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: labelColor,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
