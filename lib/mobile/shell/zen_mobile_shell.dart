// ZenMusic · vorlon-dev

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart' show MediaItem;

import 'package:zenmusic/desktop/liquid/glass_panel.dart';
import 'package:zenmusic/mobile/diwali/diwali_welcome_dialog.dart';
import 'package:zenmusic/desktop/screens/shell/widgets/bottom_player.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';
import 'package:zenmusic/desktop/utils/expressive_motion.dart';

const List<int> kZenMobileBranchOrder = [0, 1, 2, 3, 4];

class ZenMobileShell extends StatefulWidget {
  const ZenMobileShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static bool applies() => Platform.isAndroid || Platform.isIOS;

  @override
  State<ZenMobileShell> createState() => _ZenMobileShellState();
}

class _ZenMobileShellState extends State<ZenMobileShell> {
  bool _chromeHidden = false;

  @override
  void initState() {
    super.initState();
    // Diwali welcome dialog: shows only once (first launch around Diwali).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showDiwaliWelcomeIfFirstTime(context);
    });
  }

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

class _ZenDock extends StatefulWidget {
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
  State<_ZenDock> createState() => _ZenDockState();
}

class _ZenDockState extends State<_ZenDock> {
  final GlobalKey _dockKey = GlobalKey();
  final List<GlobalKey> _itemKeys =
      List.generate(kZenMobileBranchOrder.length, (_) => GlobalKey());

  void _selectAt(Offset local) {
    final ctx = _dockKey.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    const bridge = 8.0;
    for (var i = 0; i < _itemKeys.length; i++) {
      final ictx = _itemKeys[i].currentContext;
      if (ictx == null) continue;
      final item = ictx.findRenderObject();
      if (item is! RenderBox || !item.attached) continue;
      final topLeft = item.localToGlobal(Offset.zero, ancestor: box);
      final bounds = topLeft & item.size;
      if (bounds.inflate(bridge).contains(local)) {
        final branch = kZenMobileBranchOrder[i];
        if (branch != widget.currentIndex) widget.onSelect(branch);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = widget.liquid && !widget.m3;

    final Color container;
    if (widget.m3) {
      container = cs.surfaceContainerHigh;
    } else if (glass) {
      container = Colors.transparent;
    } else {
      container = dark ? const Color(0xFF202020) : cs.surfaceContainerLowest;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < kZenMobileBranchOrder.length; i++)
          _DockItem(
            key: _itemKeys[i],
            label: _ZenDock._labels[i],
            icon: _ZenDock._icons[i],
            activeIcon: _ZenDock._activeIcons[i],
            selected: widget.currentIndex == kZenMobileBranchOrder[i],
            glass: glass,
            onTap: () => widget.onSelect(kZenMobileBranchOrder[i]),
          ),
      ],
    );

    Widget dock = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
        child: Listener(
          key: _dockKey,
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _selectAt(e.localPosition),
          onPointerMove: (e) => _selectAt(e.localPosition),
          child: Material(
            color: container,
            elevation: glass || widget.m3 ? 0 : 6,
            shadowColor: Colors.black45,
            borderRadius: BorderRadius.circular(32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: row,
            ),
          ),
        ),
      ),
    );

    if (glass) {
      dock = Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
        child: ZenGlassPanel(radius: 32, child: dock),
      );
    }
    return dock;
  }
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    super.key,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.glass,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final bool glass;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color indicator = widget.selected
        ? (widget.glass
            ? cs.primaryContainer.withValues(alpha: 0.28)
            : cs.primaryContainer)
        : Colors.transparent;
    final Color content = widget.selected
        ? cs.onPrimaryContainer
        : cs.onSurfaceVariant;

    final icon = Icon(
      widget.selected ? widget.activeIcon : widget.icon,
      size: 24,
      color: content,
    );

    final label = AnimatedOpacity(
      opacity: widget.selected ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: const ExpressiveSpring(),
        alignment: Alignment.centerLeft,
        child: widget.selected
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: content,
                  ),
                ),
              )
            : const SizedBox(width: 0, height: 0),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 12, end: widget.selected ? 18 : 12),
      duration: const Duration(milliseconds: 280),
      curve: const ExpressiveSpring(),
      builder: (context, pad, child) => Container(
        height: 48,
        padding: EdgeInsets.symmetric(horizontal: pad),
        decoration: BoxDecoration(
          color: indicator,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(24),
        ),
        child: child,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [icon, label],
      ),
    );
  }
}
