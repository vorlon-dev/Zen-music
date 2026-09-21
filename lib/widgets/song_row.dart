import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/spotify_theme.dart';
import 'youtube_thumbnail.dart';

class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.onTap,
    this.trailing,
    this.borderRadius = 6,
    this.barPadding = EdgeInsets.zero,
  });

  final Song song;
  final VoidCallback onTap;

  /// Optional right-side widget (add button, play icon, menu...).
  final Widget? trailing;
  final double borderRadius;
  final EdgeInsetsGeometry barPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: barPadding,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              children: [
                YoutubeThumbnail(
                  videoId: song.id,
                  imageUrl: song.thumbnail,
                  width: 52,
                  height: 52,
                  borderRadius: borderRadius,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First row = more rounded top, last row = more rounded bottom —
/// the grouped-list look.
BorderRadius songRowRadius(int index, int total) {
  const base = 6.0;
  const group = 14.0;
  if (total <= 1) return BorderRadius.circular(group);
  if (index == 0) {
    return BorderRadius.vertical(
        top: Radius.circular(group), bottom: Radius.circular(base));
  }
  if (index == total - 1) {
    return BorderRadius.vertical(
        top: Radius.circular(base), bottom: Radius.circular(group));
  }
  return BorderRadius.circular(base);
}