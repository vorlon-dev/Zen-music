// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/appearance_prefs.dart';

class ZenLogo {
  ZenLogo._();

  /// The built-in mark (also the launcher icon source).
  static const String defaultAsset = 'assets/icon/logo.png';

  /// The asset currently shown ('' = default).
  static String get currentAsset =>
      AppearancePrefs.customLogo.value.isEmpty
          ? defaultAsset
          : AppearancePrefs.customLogo.value;
}

/// Renders the current logo (custom pick or default), live-updating when
/// the user changes it. Tint-safe on any theme — the image is shown as-is,
/// so logo files should carry their own contrast.
class ZenLogoWidget extends StatelessWidget {
  const ZenLogoWidget({super.key, this.size = 28, this.borderRadius = 6});
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppearancePrefs.customLogo,
      builder: (context, custom, _) {
        final asset =
            custom.isEmpty ? ZenLogo.defaultAsset : custom;
        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image(
            image: AssetImage(asset),
            width: size,
            height: size,
            fit: BoxFit.contain,
            // Never let a missing/odd asset break the layout.
            errorBuilder: (_, __, ___) => SizedBox(
              width: size,
              height: size,
            ),
          ),
        );
      },
    );
  }
}
