import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../theme/spotify_theme.dart';

class ZenNavItem {
  const ZenNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;

  /// Kept for constructor compatibility; not rendered (icon-only bar).
  final String label;
}

/// Echo-compact floating bottom bar (raised a touch): slim stadium,
/// CIRCLE indicator behind the icon.
///
/// Hide/show = controller-driven WIPE + FADE: SizeTransition sinks the
/// bar below the bottom edge (top-pinned), FadeTransition smooths it,
/// and the slot collapses fully — hidden TOTALLY. Finger release /
/// fling settle (ScrollDirection.idle) does NOT reshow it — only an
/// actual upward scroll does (the scroll owner's job).
class ZenNavBar extends StatefulWidget {
  const ZenNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.visible = true,
  });

  final List<ZenNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// false → bar wipes down + fades out; true → wipes back up.
  final bool visible;

  @override
  State<ZenNavBar> createState() => _ZenNavBarState();
}

class _ZenNavBarState extends State<ZenNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.visible ? 1.0 : 0.0,
  );

  late final Animation<double> _wipe = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void didUpdateWidget(covariant ZenNavBar old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A hidden bar must never eat taps mid-animation.
    return IgnorePointer(
      ignoring: !widget.visible,
      child: ClipRect(
        child: SizeTransition(
          sizeFactor: _wipe,
          axis: Axis.vertical,
          // -1 pins the bar's TOP while the size shrinks — the bar
          // sinks below the bottom edge (wipe-down). Do not change.
          axisAlignment: -1,
          child: FadeTransition(
            opacity: _wipe,
            child: Padding(
              // Raised a touch (Echo placement) — was 8.
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: SpotifyColors.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.30),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      Expanded(
                        child: _ZenTab(
                          item: widget.items[i],
                          active: i == widget.currentIndex,
                          onTap: () => widget.onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One icon-only tab. Active = filled CIRCLE behind the icon; spring
/// press-scale (controller starts at 1.0 — the default 0.0 renders
/// Transform.scale(0), the invisible-button regression).
class _ZenTab extends StatefulWidget {
  const _ZenTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final ZenNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ZenTab> createState() => _ZenTabState();
}

class _ZenTabState extends State<_ZenTab>
    with SingleTickerProviderStateMixin {
  // IMPORTANT: value MUST start at 1.0 — AnimationController defaults
  // to 0.0, which renders Transform.scale(0) (invisible-but-tappable).
  late final AnimationController _scale =
  AnimationController(vsync: this, value: 1.0);

  static final _pressSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.7,
  );

  void _setPressed(bool pressed) {
    _scale.animateWith(
      SpringSimulation(_pressSpring, _scale.value, pressed ? 0.88 : 1.0, 0),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final item = widget.item;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.fastOutSlowIn,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? SpotifyColors.surfaceLight : Colors.transparent,
            ),
            child: Icon(
              active ? item.activeIcon : item.icon,
              size: 24,
              color: active
                  ? SpotifyColors.textPrimary
                  : SpotifyColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}