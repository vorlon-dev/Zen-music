import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class YoutubeThumbnail extends StatelessWidget {
  final String videoId;
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;

  const YoutubeThumbnail({
    super.key,
    required this.videoId,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 8,
  });

  bool _isYouTubeUrl(String url) =>
      url.contains('i.ytimg.com') ||
          url.contains('img.youtube.com') ||
          url.contains('ytimg.com');

  String _upgradeYouTube(String url) {
    return url
        .replaceAll('hqdefault.jpg', 'maxresdefault.jpg')
        .replaceAll('mqdefault.jpg', 'maxresdefault.jpg')
        .replaceAll('sddefault.jpg', 'maxresdefault.jpg')
        .replaceAll('default.jpg', 'maxresdefault.jpg');
  }

  @override
  Widget build(BuildContext context) {
    final hasExplicit = imageUrl != null && imageUrl!.isNotEmpty;

    String primaryUrl;
    String? fallbackUrl;

    if (hasExplicit) {
      if (_isYouTubeUrl(imageUrl!)) {
        primaryUrl = _upgradeYouTube(imageUrl!);
        fallbackUrl = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
      } else {
        // JioSaavn or other — use directly
        primaryUrl = imageUrl!;
        fallbackUrl = null;
      }
    } else {
      primaryUrl = 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg';
      fallbackUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    // ── Force fill when no explicit dimensions ──
    // This is the KEY FIX. Without it, AspectRatio parents can't
    // constrain the image and intrinsic size wins.
    if (width == null && height == null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return _buildImage(
            primaryUrl: primaryUrl,
            fallbackUrl: fallbackUrl,
            width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
            height:
            constraints.maxHeight.isFinite ? constraints.maxHeight : null,
          );
        },
      );
    }

    return _buildImage(
      primaryUrl: primaryUrl,
      fallbackUrl: fallbackUrl,
      width: width,
      height: height,
    );
  }

  Widget _buildImage({
    required String primaryUrl,
    required String? fallbackUrl,
    required double? width,
    required double? height,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: CachedNetworkImage(
          imageUrl: primaryUrl,
          fit: fit,
          width: width,
          height: height,
          placeholder: (context, url) => Container(
            color: Colors.grey[900],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) {
            if (fallbackUrl == null) {
              return Container(
                color: Colors.grey[900],
                child: const Icon(Icons.music_note, color: Colors.white54),
              );
            }
            return CachedNetworkImage(
              imageUrl: fallbackUrl,
              fit: fit,
              width: width,
              height: height,
              placeholder: (context, url) => Container(color: Colors.grey[900]),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[900],
                child: const Icon(Icons.music_note, color: Colors.white54),
              ),
            );
          },
        ),
      ),
    );
  }
}