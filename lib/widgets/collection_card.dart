import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/collection.dart';
import '../theme/spotify_theme.dart';

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
    this.size = 150,
  });

  final Collection collection;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: collection.imageUrl.isEmpty
                  ? Container(
                width: size,
                height: size,
                color: SpotifyColors.surfaceLight,
                child: const Icon(Icons.library_music_rounded,
                    color: SpotifyColors.textTertiary),
              )
                  : CachedNetworkImage(
                imageUrl: collection.imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: size,
                  height: size,
                  color: SpotifyColors.surfaceLight,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: size,
                  height: size,
                  color: SpotifyColors.surfaceLight,
                  child: const Icon(Icons.broken_image_rounded,
                      color: SpotifyColors.textTertiary),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SpotifyColors.textPrimary,
              ),
            ),
            if (collection.subtitle.isNotEmpty)
              Text(
                collection.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: SpotifyColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}