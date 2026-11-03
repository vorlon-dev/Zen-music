// ZenMusic · vorlon-dev
//
// LastWave-style top bar: a tinted surface with rounded bottom corners, a
// bold left-aligned title and round icon buttons on the right.

import 'package:flutter/material.dart';

class ZenTopBarAction {
  const ZenTopBarAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
}

class ZenTopBar extends StatelessWidget implements PreferredSizeWidget {
  const ZenTopBar({
    super.key,
    required this.title,
    this.actions = const [],
  });

  final String title;
  final List<ZenTopBarAction> actions;

  static const double _barHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top;

    return Container(
      height: _barHeight + top,
      padding: EdgeInsets.only(top: top, left: 20, right: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: scheme.onSurface,
                // fontFamily: 'GoogleSans', // ← LastWave look; add font to pubspec
              ),
            ),
          ),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: a.tooltip ?? '',
                child: Material(
                  color: scheme.surface.withAlpha(150),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: a.onTap,
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(a.icon, size: 22, color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}