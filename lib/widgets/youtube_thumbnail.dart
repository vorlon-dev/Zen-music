import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';
import 'wave_spinner.dart';

/// Thumbnail widget used across shelves, grids, queue and the mini
/// player. Prefers the provided imageUrl; falls back to YouTube's
/// thumbnail for the videoId; shows the wavy spinner while loading.
///
/// BLACK-BARS FIX (do not regress): YouTube's hqdefault.jpg is 4:3
/// with the 16:9 frame letterboxed INSIDE the image — the black bars
/// are baked into the pixels. [_barFreeUrl] rewrites any hqdefault
/// URL to mqdefault (true 16:9, no bars) at LOAD time, which also
/// cleans rows parsed before the service-level fixes.
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

  /// hqdefault → mqdefault. Only touches hqdefault; maxres/mq URLs
  /// are already 16:9 and pass through untouched.
  static String _barFreeUrl(String url) =>
      url.replaceFirst('hqdefault.jpg', 'mqdefault.jpg');

  @override
  Widget build(BuildContext context) {
    final w = width ?? 100;
    final h = height ?? 100;

    Widget buildImage(String url) => CachedNetworkImage(
      imageUrl: _barFreeUrl(url),
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
          'https://i.ytimg.com/vi/$videoId/mqdefault.jpg'),
    );

    if (imageUrl.isEmpty) {
      // No imageUrl — go straight to the YouTube thumbnail; if that
      // also fails, show the zen-note fallback.
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
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