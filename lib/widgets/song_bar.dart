import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// ZenMusic port of Musify's ArtistBar: a circular-avatar row for
/// opening an artist. Data comes from the CALLER (name + image) —
/// like rank and play count, it belongs to where the artist is
/// listed, not to any global store.
class ArtistBar extends StatelessWidget {
  const ArtistBar({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.subtitle = 'Artist',
    this.borderRadius = BorderRadius.zero,
  });

  final String name;
  final String imageUrl;
  final VoidCallback onTap;
  final String subtitle;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpotifyColors.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          child: Row(
            children: [
              ClipOval(
                child: imageUrl.isNotEmpty
                    ? Image.network(
                  imageUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _fallback(),
                )
                    : _fallback(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: SpotifyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SpotifyColors.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      width: 52,
      height: 52,
      color: SpotifyColors.surfaceLight,
      child: const Icon(
        FluentIcons.person_24_filled,
        size: 26,
        color: SpotifyColors.textTertiary,
      ),
    );
  }
}