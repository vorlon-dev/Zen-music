import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

class ZenNavItem {
  const ZenNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Echo-style bottom bar: 56x32 pill indicator behind the icon,
/// non-bold 12sp label below, animated icon swap on select.
/// [onTap] fires on every tap, including re-selects (reselect handling
/// is the caller's job — Echo opens the extension sheet on Home).
class ZenNavBar extends StatelessWidget {
  const ZenNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<ZenNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  // Bar = surface token; pill = one step up. Echo resolves both from
  // theme attributes — tune here if you want the pill lighter.
  static const Color _barColor = SpotifyColors.surface;
  static const Color _indicatorColor = SpotifyColors.surfaceLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _barColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++) Expanded(child: _item(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i) {
    final item = items[i];
    final active = i == currentIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.fastOutSlowIn,
            width: 56,
            height: 32,
            decoration: BoxDecoration(
              color: active ? _indicatorColor : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.fastOutSlowIn,
              switchOutCurve: Curves.fastOutSlowIn,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                active ? item.activeIcon : item.icon,
                key: ValueKey(active),
                size: 22,
                color: active
                    ? SpotifyColors.textPrimary
                    : SpotifyColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1.0,
              fontWeight: FontWeight.w400,
              color: active
                  ? SpotifyColors.textPrimary
                  : SpotifyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}