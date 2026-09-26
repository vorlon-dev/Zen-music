import 'package:flutter/material.dart';
import '../theme/spotify_theme.dart';

/// ZenMusic-styled confirmation dialog. Use this everywhere instead of
/// raw AlertDialog so error/bug/confirm boxes always match the app.
/// (The theme also styles default AlertDialogs — this just makes the
/// consistent look explicit and adds the danger variant.)
Future<bool> showZenConfirm(
    BuildContext context, {
      required String title,
      String? message,
      String confirmLabel = 'Confirm',
      String cancelLabel = 'Cancel',
      bool dangerous = false,
    }) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: SpotifyColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        title,
        style: TextStyle(
          color: dangerous ? Colors.redAccent : SpotifyColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: message == null
          ? null
          : Text(message,
          style: const TextStyle(
              color: SpotifyColors.textSecondary, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel,
              style: const TextStyle(color: SpotifyColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: TextStyle(
                color: dangerous ? Colors.redAccent : SpotifyColors.green,
                fontWeight: FontWeight.w700,
              )),
        ),
      ],
    ),
  );
  return result == true;
}