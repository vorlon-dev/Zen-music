import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';
import 'wave_spinner.dart';

/// Thumbnail widget used across shelves, grids, queue and the mini
/// player. Prefers the provided imageUrl; falls back to YouTube's
/// thumbnail for the videoId; shows the wavy spinner while loading.
class YoutubeThumbnail extends StatelessWidget {
  const YoutubeThumbnail({
    super.key,
    required this.videoId,
    required this.imageUrl,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  final String videoId;
  final String imageUrl;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final w = width ?? 100;
    final h = height ?? 100;

    Widget buildImage(String url) => CachedNetworkImage(
      imageUrl: url,
      width: w,
      height: h,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: w,
        height: h,
        color: SpotifyColors.surfaceLight,
        child: Center(
          child: WaveSpinner(
            size: (w * 0.4).clamp(14.0, 24.0),
            strokeWidth: 2,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => buildImage(
          'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'),
    );

    if (imageUrl.isEmpty) {
      // No imageUrl — go straight to the YouTube thumbnail; if that
      // also fails, show the music-note fallback.
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
          width: w,
          height: h,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: w,
            height: h,
            color: SpotifyColors.surfaceLight,
            child: Center(
              child: WaveSpinner(
                size: (w * 0.4).clamp(14.0, 24.0),
                strokeWidth: 2,
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: w,
            height: h,
            color: SpotifyColors.surfaceLight,
            child: const Icon(
              Icons.music_note_rounded,
              size: 24,
              color: SpotifyColors.textTertiary,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: buildImage(imageUrl),
    );
  }
}