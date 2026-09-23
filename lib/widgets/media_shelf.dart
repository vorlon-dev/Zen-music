import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/extension_feed_service.dart';
import '../theme/spotify_theme.dart';
import 'youtube_thumbnail.dart';

/// Unified display model for shelf cards from either source.
class ShelfItem {
  ShelfItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.coverHeaders = const {},
    this.coverHex,
    this.isVideo = false,
  });

  factory ShelfItem.fromSong(Song s) => ShelfItem(
    kind: 'Track',
    id: s.id,
    title: s.title,
    subtitle: s.artist,
    coverUrl: s.thumbnail,
  );

  factory ShelfItem.fromExt(ExtMedia m) => ShelfItem(
    kind: m.kind,
    id: m.id,
    title: m.title,
    subtitle: m.subtitle,
    coverUrl: m.coverUrl,
    coverHeaders: m.coverHeaders,
    coverHex: m.coverHex,
    isVideo: m.isVideo,
  );

  final String kind; // Track | Album | Artist | Playlist | Radio
  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final Map<String, String> coverHeaders;
  final String? coverHex;
  final bool isVideo;
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'Artist':
      return FluentIcons.person_24_filled;
    case 'Album':
      return FluentIcons.album_24_filled;
    case 'Playlist':
      return FluentIcons.list_24_filled;
    case 'Radio':
      return FluentIcons.library_24_regular;
    default:
      return FluentIcons.music_note_1_24_filled;
  }
}

/// Animated 3-bar "now playing" visualizer badge.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(duration: const Duration(milliseconds: 900), vsync: this)
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? SpotifyColors.green;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: widget.size * 0.12,
                height: widget.size *
                    (0.28 +
                        0.4 * (0.5 + 0.5 * math.sin(_c.value * 6.28 + i * 1.1))),
                margin: EdgeInsets.symmetric(horizontal: widget.size * 0.04),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(widget.size * 0.06),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Cover with Echo's stack-peek background layers, type badge and
/// now-playing overlay.
class ShelfCover extends StatelessWidget {
  const ShelfCover({
    super.key,
    required this.item,
    required this.isPlaying,
    this.songMode = false,
    this.songVideoId,
    this.size = 150,
    this.borderRadius = 10,
  });

  final ShelfItem item;
  final bool isPlaying;
  final bool songMode;
  final String? songVideoId;
  final double size;
  final double borderRadius;

  bool get _isList =>
      item.kind == 'Album' || item.kind == 'Playlist' || item.kind == 'Radio';
  bool get _isArtist => item.kind == 'Artist';

  Widget _coverWidget() {
    if (songMode && (item.coverUrl == null || item.coverUrl!.isEmpty)) {
      return YoutubeThumbnail(
        videoId: songVideoId ?? item.id,
        imageUrl: '',
        width: size,
        height: size,
        borderRadius: _isArtist ? size / 2 : borderRadius,
      );
    }
    return CoverArt(
      url: item.coverUrl,
      headers: item.coverHeaders,
      hex: item.coverHex,
      size: size,
      borderRadius: _isArtist ? size / 2 : borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(_isArtist ? size / 2 : borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _coverWidget(),
            if (item.isVideo)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(FluentIcons.video_24_regular,
                      size: 14, color: Colors.white),
                ),
              ),
            if (isPlaying)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: SpotifyColors.background.withOpacity(0.9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: NowPlayingBars(size: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!_isList) return cover;

    // Stack-peek: two fading sheets behind albums / playlists / radios,
    // plus the type badge bottom-left.
    return SizedBox(
      width: size,
      height: size + 8,
      child: Stack(
        children: [
          Positioned(
            left: 6,
            right: 6,
            top: 0,
            child: Container(
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.15),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
          Positioned(
            left: 2.5,
            right: 2.5,
            top: 2.5,
            child: Container(
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
          ),
          Positioned(top: 5, left: 0, right: 0, child: cover),
          if (item.kind == 'Playlist' || item.kind == 'Radio')
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                width: 24,
                height: 24,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SpotifyColors.background.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _kindIcon(item.kind),
                  size: 14,
                  color: SpotifyColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cover renderer: network (with headers) / hex tile / fallback icon.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.url,
    required this.headers,
    this.hex,
    this.size,
    this.borderRadius = 10,
    this.circular = false,
  });

  final String? url;
  final Map<String, String> headers;
  final String? hex;
  final double? size;
  final double borderRadius;
  final bool circular;

  static ImageProvider provider(String url, {Map<String, String>? headers}) =>
      CachedNetworkImageProvider(url, headers: headers);

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(hex);
    if (color != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circular ? null : BorderRadius.circular(borderRadius),
        ),
      );
    }
    final u = url ?? '';
    final shape = circular
        ? const CircleBorder()
        : RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius));
    if (u.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: SpotifyColors.surfaceLight,
          shape: shape,
        ),
        child: Icon(Icons.music_note_rounded,
            color: SpotifyColors.textTertiary, size: (size ?? 48) * 0.4),
      );
    }
    return ClipPath(
      clipper: _ShapeClipper(shape),
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: u,
          httpHeaders: headers.isEmpty ? null : headers,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: SpotifyColors.surfaceLight),
          errorWidget: (_, __, ___) => Container(
            color: SpotifyColors.surfaceLight,
            child: Icon(Icons.music_note_rounded,
                color: SpotifyColors.textTertiary, size: (size ?? 48) * 0.4),
          ),
        ),
      ),
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  _ShapeClipper(this.shape);
  final ShapeBorder shape;

  @override
  Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(_ShapeClipper oldClipper) => false;
}

// ── Extension-model wrappers (used by the detail screen via the
//    extension_feed_view export chain) ──

class ExtCover extends StatelessWidget {
  const ExtCover({
    super.key,
    required this.url,
    required this.headers,
    this.hex,
    this.size,
    this.borderRadius = 10,
  });

  final String? url;
  final Map<String, String> headers;
  final String? hex;
  final double? size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return CoverArt(
      url: url,
      headers: headers,
      hex: hex,
      size: size,
      borderRadius: borderRadius,
    );
  }
}

class ExtTrackRow extends StatelessWidget {
  const ExtTrackRow({
    super.key,
    required this.index,
    required this.track,
    required this.onTap,
  });

  final int index;
  final ExtMedia track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: SpotifyColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
            ExtCover(
              url: track.coverUrl,
              headers: track.coverHeaders,
              hex: track.coverHex,
              size: 48,
              borderRadius: 6,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if ((track.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      track.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (track.durationMs != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  formatExtDuration(track.durationMs!),
                  style: const TextStyle(
                    color: SpotifyColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                FluentIcons.play_16_filled,
                size: 18,
                color: SpotifyColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(value);
}

String formatExtDuration(int ms) {
  final s = (ms / 1000).round();
  final m = s ~/ 60;
  final sec = s % 60;
  return '$m:${sec.toString().padLeft(2, '0')}';
}

/// Echo-style section header: 20sp title, optional subtitle, optional
/// shuffle action.
class ShelfHeaderBar extends StatelessWidget {
  const ShelfHeaderBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onShuffle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if ((subtitle ?? '').isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SpotifyColors.textSecondary.withOpacity(0.66),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (onShuffle != null)
              IconButton(
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded,
                    size: 20, color: SpotifyColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Square media card (Echo Items row item). Width comes from the parent.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.isPlaying,
    required this.onTap,
    this.onLongPress,
  });

  final ShelfItem item;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final centered = item.kind == 'Artist';
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment:
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          ShelfCover(item: item, isPlaying: isPlaying),
          const SizedBox(height: 8),
          SizedBox(
            width: 150,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
            ),
          ),
          if ((item.subtitle ?? '').isNotEmpty)
            SizedBox(
              width: 150,
              child: Text(
                item.subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: SpotifyColors.textSecondary.withOpacity(0.66),
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Echo's ThreeTracks card: 240dp column of three numbered track tiles.
class ThreeTracksCard extends StatelessWidget {
  const ThreeTracksCard({
    super.key,
    required this.items,
    required this.startIndex,
    required this.playingId,
    required this.onTap,
    this.onLongPress,
  });

  final List<ShelfItem> items; // exactly the chunk (1–3 entries)
  final int startIndex; // absolute index of items[0] in the section
  final String? playingId;
  final void Function(int absoluteIndex) onTap;
  final void Function(int absoluteIndex)? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            if (i < items.length)
              _Tile(
                item: items[i],
                number: startIndex + i + 1,
                isPlaying: playingId == items[i].id,
                onTap: () => onTap(startIndex + i),
                onLongPress: onLongPress == null
                    ? null
                    : () => onLongPress!(startIndex + i),
              )
            else
              const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.number,
    required this.isPlaying,
    required this.onTap,
    this.onLongPress,
  });

  final ShelfItem item;
  final int number;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            ShelfCover(
              item: item,
              isPlaying: isPlaying,
              size: 52,
              borderRadius: 6,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$number. ${item.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-bleed horizontal row of media cards with an Echo header.
class MediaShelfRow extends StatelessWidget {
  const MediaShelfRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTapItem,
    this.onItemLongPress,
    this.subtitle,
    this.onShuffle,
    this.playingIdStream,
    this.cardWidth = 150,
  });

  final String title;
  final String? subtitle;
  final List<ShelfItem> items;
  final void Function(int index) onTapItem;
  final void Function(int index)? onItemLongPress;
  final VoidCallback? onShuffle;
  final Stream<Song?>? playingIdStream;
  final double cardWidth;

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: items.length.clamp(0, 20),
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final item = items[i];
          return StreamBuilder<Song?>(
            stream: playingIdStream,
            builder: (context, snap) {
              final playing = snap.data?.id == item.id;
              return MediaCard(
                item: item,
                isPlaying: playing,
                onTap: () => onTapItem(i),
                onLongPress:
                onItemLongPress == null ? null : () => onItemLongPress!(i),
              );
            },
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(
            title: title, subtitle: subtitle, onShuffle: onShuffle),
        body,
      ],
    );
  }
}

/// Full-bleed horizontal row of ThreeTracks cards.
class ThreeTracksRow extends StatelessWidget {
  const ThreeTracksRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTapItem,
    this.onItemLongPress,
    this.subtitle,
    this.playingIdStream,
  });

  final String title;
  final String? subtitle;
  final List<ShelfItem> items;
  final void Function(int index) onTapItem;
  final void Function(int index)? onItemLongPress;
  final Stream<Song?>? playingIdStream;

  @override
  Widget build(BuildContext context) {
    final chunks = <List<ShelfItem>>[];
    for (var i = 0; i + 3 <= items.length; i += 3) {
      chunks.add(items.sublist(i, i + 3));
    }
    final rest = items.length % 3;
    if (rest > 0) {
      chunks.add(items.sublist(items.length - rest));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(title: title, subtitle: subtitle),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            clipBehavior: Clip.none,
            itemCount: chunks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, c) {
              final start = c * 3;
              return StreamBuilder<Song?>(
                stream: playingIdStream,
                builder: (context, snap) {
                  return ThreeTracksCard(
                    items: chunks[c],
                    startIndex: start,
                    playingId: snap.data?.id,
                    onTap: onTapItem,
                    onLongPress: onItemLongPress,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}