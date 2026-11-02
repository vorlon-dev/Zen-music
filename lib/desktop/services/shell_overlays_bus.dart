// ZenMusic · vorlon-dev

import 'package:flutter/foundation.dart';

class ShellOverlaysBus {
  ShellOverlaysBus._();

  /// True while a full-screen page (the player page) is stacked ABOVE the
  /// shell. Every shell must hide its dock / bottom bar / mini player.
  static final ValueNotifier<bool> fullPageAbove = ValueNotifier(false);
}
