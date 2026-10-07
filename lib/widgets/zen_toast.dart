import 'package:flutter/material.dart';

import '../main.dart';
import '../theme/spotify_theme.dart';

/// Mini-player-aware toast (Musify's flutter_toast concept): snackbars
/// float ABOVE the mini player instead of colliding with it.
///
/// ADOPTION NOTE: available now; existing ScaffoldMessenger calls
/// migrate one-by-one on request — new screens use this directly.
class ZenToast {
  ZenToast._();

  /// Mini player height (72) + its vertical padding (8 + 8).
  /// Keep in sync with MiniPlayer in home_screen.dart.
  static const double _miniPlayerFootprint = 88;

  static void show(
      BuildContext context,
      String text, {
        IconData? icon,
        Duration duration = const Duration(seconds: 2),
        String? actionLabel,
        VoidCallback? onAction,
      }) {
    final hasMini = audioHandler.mediaItem.value != null;
    final bottom = 12.0 + (hasMini ? _miniPlayerFootprint : 0.0);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        margin: EdgeInsets.fromLTRB(16, 12, 16, bottom),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: SpotifyColors.surfaceLighter,
        content: Row(
          children: [
            Icon(icon ?? Icons.check_rounded,
                size: 20, color: SpotifyColors.highlight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    color: SpotifyColors.textPrimary, fontSize: 14),
              ),
            ),
          ],
        ),
        action: actionLabel == null
            ? null
            : SnackBarAction(
          label: actionLabel,
          onPressed: () => onAction?.call(),
        ),
        duration: duration,
      ),
    );
  }
}