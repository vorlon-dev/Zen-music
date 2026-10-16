// ZenMusic Desktop — mobile square artwork. FRESH widget (not a port):
// guarantees a perfect 1:1 artwork box from any thumbnail URL — upgrades
// the source via getEnhancedImage (regex size normalization) and paints
// BoxFit.cover inside a fixed square. Optional onImageReady replays the
// resolved ImageProvider so screens can keep palette extraction alive.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/utils/enhanced_image.dart';

class SquareArtwork extends StatefulWidget {
  const SquareArtwork({
    super.key,
    required this.song,
    this.size,
    this.borderRadius = 12.0,
    this.onImageReady,
  });

  /// Song map — expects 'thumbnails' (List with 'url' entries), the same
  /// shape every screen passes around.
  final Map song;

  /// Edge length of the square. Null = expand to available space
  /// (parent must provide bounded constraints, e.g. AspectRatio/Expanded).
  final double? size;

  final double borderRadius;

  /// Fires once per resolved artwork URL with its ImageProvider — used by
  /// the player page to feed PaletteGenerator (gradient colors).
  final void Function(ImageProvider)? onImageReady;

  @override
  State<SquareArtwork> createState() => _SquareArtworkState();
}

class _SquareArtworkState extends State<SquareArtwork> {
  String _lastNotifiedUrl = '';

  String _resolveUrl() {
    final List thumbnails = (widget.song['thumbnails'] as List?) ?? const [];
    if (thumbnails.isEmpty) return '';
    return getEnhancedImage(
      thumbnails.first['url'] ?? '',
      quality: 'high',
    );
  }

  @override
  Widget build(BuildContext context) {
    final String url = _resolveUrl();

    final Widget image = (url.isNotEmpty)
        ? CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      imageBuilder: (context, provider) {
        if (url != _lastNotifiedUrl) {
          _lastNotifiedUrl = url;
          final cb = widget.onImageReady;
          if (cb != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) cb(provider);
            });
          }
        }
        return Image(image: provider, fit: BoxFit.cover);
      },
      placeholder: (_, __) => Container(
        color: Colors.white.withValues(alpha: 0.05),
      ),
      errorWidget: (_, __, ___) => Container(
        color: Colors.white.withValues(alpha: 0.05),
        child: const Icon(
          Icons.music_note,
          size: 56,
          color: Colors.white54,
        ),
      ),
    )
        : Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: const Icon(
        Icons.music_note,
        size: 56,
        color: Colors.white54,
      ),
    );

    final Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: image,
    );

    if (widget.size != null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: clipped,
      );
    }
    return AspectRatio(
      aspectRatio: 1,
      child: clipped,
    );
  }
}