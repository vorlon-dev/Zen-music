// ZenMusic — SP-82: shell chrome ↔ full-page bridge.
//
// LastWave contract (MainShell.kt): bottom navigation exists ONLY on the
// main shell route — `hasBottomNavigation = currentRoute == MainShell.route`.
// Any full-screen page pushed above the shell (the player above all) never
// shows the dock, the mini player, or the bottom bar.
//
// Flutter's shells stay mounted UNDER pushed routes, so the shell cannot
// know on its own that the player is open (a pushed opaque route covers it
// on the route-hosting builds, but sheet-hosted players and translucent
// builds keep the dock visible — the user's "I don't want nav bar in my
// player page"). The player page therefore announces itself here and every
// shell tucks ALL floating chrome while the flag is up.
//
// Deliberately NOT persisted, NOT platform-gated: on Windows the route
// already covers the shell, so flipping the flag is invisible there — and
// it guarantees the rule holds no matter which shell variant hosts the
// player (ZenMobileShell, AppShell route, or AppShell sheet).

import 'package:flutter/foundation.dart';

class ShellOverlaysBus {
  ShellOverlaysBus._();

  /// True while a full-screen page (the player page) is stacked ABOVE the
  /// shell. Every shell must hide its dock / bottom bar / mini player.
  static final ValueNotifier<bool> fullPageAbove = ValueNotifier(false);
}
