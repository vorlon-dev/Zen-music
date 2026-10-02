import 'package:flutter/material.dart';

import '../theme/spotify_theme.dart';

/// Echo-style artist hero header: full-bleed square artwork that
/// dissolves into the background (alpha fade over the bottom 350dp +
/// scrim gradient), with the artist name (32sp bold) overlapping the
/// art and [content] (pills, description, action buttons) below it.
///
/// The header must be placed OUTSIDE SafeArea so the artwork bleeds
/// to the very top of the screen (ZenMusic hides system bars
/// app-wide, so no status-bar offset is needed — Echo's headerOffset
/// collapses to zero here).
class ArtistHeroHeader extends StatelessWidget {
  const ArtistHeroHeader({
    super.key,
    required this.imageUrl,
    required this.name,
    this.titleLeading,
    this.content,
    this.fadeHeight = 350,
  });

  final String imageUrl;
  final String name;

  /// Optional widget rendered left of the name (Echo's 45dp inline
  /// artist-video chip slot; unused until that feature ships).
  final Widget? titleLeading;

  /// Rendered below the name: stat pills, description, action buttons.
  final Widget? content;

  /// Height of the bottom alpha fade on the artwork (dp).
  final double fadeHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isTablet = width > 600;
    final artHeight = isTablet ? 400.0 : width;
    final hasArt = imageUrl.isNotEmpty;

    // Echo: ((artHeightPx / 1.2f) - 144).toDp() — the 144 is DEVICE
    // pixels, so it converts back through devicePixelRatio.
    final contentTop = hasArt
        ? (artHeight * media.devicePixelRatio / 1.2 - 144) /
        media.devicePixelRatio
        : 16.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (hasArt) ...[
          // Artwork with bottom alpha fade (Compose fadingEdge port).
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: artHeight,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                final fadeStart =
                ((bounds.height - fadeHeight) / bounds.height)
                    .clamp(0.0, 1.0);
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.0, fadeStart, 1.0],
                ).createShader(bounds);
              },
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => Container(
                  color: SpotifyColors.surfaceLight,
                  child: const Center(
                    child: Icon(Icons.person_rounded,
                        size: 64, color: SpotifyColors.textTertiary),
                  ),
                ),
              ),
            ),
          ),
          // Scrim: transparent -> background 60% -> background, so
          // text stays readable over bright artwork (Compose parity,
          // evenly spaced stops like the reference).
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: artHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    SpotifyColors.background.withOpacity(0.6),
                    SpotifyColors.background,
                  ],
                ),
              ),
            ),
          ),
        ],
        // Name + content block, overlapping the art's dissolved bottom.
        Padding(
          padding: EdgeInsets.only(
            top: contentTop,
            left: 16,
            right: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // NOTE: Flutter Row uses crossAxisAlignment: CrossAxisAlignment
              // — verticalAlignment/Alignment.centerVertically are Compose
              // APIs and do not exist here. Do not "port" this back.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (titleLeading != null) ...[
                    titleLeading!,
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: SpotifyColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (content != null) content!,
            ],
          ),
        ),
      ],
    );
  }
}