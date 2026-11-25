// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';

/// A back button that ALWAYS works, wherever it is placed.
///
/// Detail pages (Browse / Chip / Podcasts, playlist details …) can end up
/// on the navigator root when they were opened with `context.go()`
/// (stack replaced — nothing to pop), via a deep link, or after state
/// restoration. In those cases Flutter's `automaticallyImplyLeading`
/// shows NO arrow and the user is stranded. This leading widget:
///   • pops when there is something to pop (normal pushed flow), else
///   • falls back to the shell root ('/'), which restores the tabs.
///
/// Use it as the explicit `leading:` of AppBar-based pages that are
/// reachable through more than one navigation path.
class SmartBackLeading extends StatelessWidget {
  const SmartBackLeading({super.key, this.fallback = '/'});

  /// Where to go when the stack is empty (go()-opened page).
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(AdaptiveIcons.back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).maybePop();
        } else {
          context.go(fallback);
        }
      },
    );
  }
}
