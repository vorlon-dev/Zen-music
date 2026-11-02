// ZenMusic · vorlon-dev

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

import 'package:zenmusic/desktop/screens/video/video_watch_page.dart';
import 'package:zenmusic/desktop/youtube/yt_browse.dart';

/// The one brand accent the YouTube section is allowed to hardcode.
const Color kYtRed = Color(0xFFFF0033);

/// Flattened view-model both data sources (InnerTube feed + youtube_explode)
/// render through, so every card looks identical.
class YtItemVm {
  final String id;
  final String title;
  final String author;
  final String authorId;
  final String thumb;
  final String? length;
  final String? views;
  final String? published;
  final bool live;
  final bool isShort;

  const YtItemVm({
    required this.id,
    required this.title,
    required this.author,
    required this.authorId,
    required this.thumb,
    this.length,
    this.views,
    this.published,
    this.live = false,
    this.isShort = false,
  });

  factory YtItemVm.fromFeed(YtFeedVideo v) => YtItemVm(
        id: v.id,
        title: v.title,
        author: v.author,
        authorId: v.authorId,
        thumb: v.thumb.isEmpty ? 'https://i.ytimg.com/vi/${v.id}/hqdefault.jpg' : v.thumb,
        length: v.length,
        views: v.views,
        published: v.published,
        live: v.live,
        isShort: v.isShort,
      );

  factory YtItemVm.fromVideo(yexp.Video v) => YtItemVm(
        id: v.id.value,
        title: v.title,
        author: v.author,
        authorId: v.channelId.value,
        thumb: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
        length: v.duration == null
            ? null
            : _fmtDuration(v.duration!),
        views: v.engagement.viewCount > 0
            ? '${_compact(v.engagement.viewCount)} views'
            : null,
        live: v.isLive,
      );

  factory YtItemVm.fromSearchVideo(yexp.SearchVideo v) => YtItemVm(
        id: v.id.value,
        title: v.title,
        author: v.author,
        authorId: v.channelId,
        thumb: v.thumbnails.isEmpty
            ? 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg'
            : v.thumbnails.last.url.toString(),
        length: v.duration,
        views: v.viewCount > 0 ? '${_compact(v.viewCount)} views' : null,
        published: v.uploadDate,
        live: v.isLive,
      );

  static String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  static String _compact(int n) {
    if (n >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)}B';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Open in the full video watch page (the existing, SP-proven player).
  void open(BuildContext context) {
    if (id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoWatchPage(
        videoId: id,
        item: {'videoId': id, 'title': title, 'subtitle': author, 'authorId': authorId},
      ),
    ));
  }
}


class YtThumb extends StatelessWidget {
  const YtThumb({super.key, required this.vm, this.radius = 14});
  final YtItemVm vm;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // NOTE: no AspectRatio here — the CALLER owns the box aspect (grid cards
    // use 16/9, search tiles give shorts 9/16). Stacking AspectRatio widgets
    // inside each other fights the layout.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: cs.surfaceContainerHighest),
            if (vm.thumb.isNotEmpty)
              CachedNetworkImage(
                imageUrl: vm.thumb,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 160),
                errorWidget: (_, __, ___) => ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.play_circle_outline, size: 34)),
                placeholder: (_, __) => ColoredBox(
                    color: cs.surfaceContainerHighest,
                    child: const Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)))),
              ),
            if (vm.live)
              Positioned(
                left: 8,
                top: 8,
                child: _badge('LIVE', kYtRed),
              )
            else if ((vm.length ?? '').isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: _badge(vm.length!, Colors.black87),
              ),
          ],
        ),
    );
  }

  Widget _badge(String text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2)),
      );
}


/// Grid card — YouTube-style 16:9 thumb over two lines of text.
class YtVideoCard extends StatelessWidget {
  const YtVideoCard({super.key, required this.vm, this.onOpenChannel});
  final YtItemVm vm;
  final ValueChanged<String>? onOpenChannel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => vm.open(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: vm.isShort ? 9 / 16 : 16 / 9,
            child: YtThumb(vm: vm),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vm.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, height: 1.25, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: vm.authorId.isEmpty
                      ? null
                      : () => onOpenChannel?.call(vm.authorId),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      vm.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
                if ((vm.views ?? vm.published ?? '').isNotEmpty)
                  Text(
                    [
                      if (vm.views != null) vm.views!,
                      if (vm.published != null) vm.published!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// List row — search results, playlist contents.
class YtVideoTile extends StatelessWidget {
  const YtVideoTile({super.key, required this.vm, this.onOpenChannel});
  final YtItemVm vm;
  final ValueChanged<String>? onOpenChannel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => vm.open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: vm.isShort ? 74 : 148,
              child: AspectRatio(
                aspectRatio: vm.isShort ? 9 / 16 : 16 / 9,
                child: YtThumb(vm: vm, radius: 10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(vm.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: vm.authorId.isEmpty
                        ? null
                        : () => onOpenChannel?.call(vm.authorId),
                    child: Text(vm.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ),
                  if ((vm.views ?? vm.published ?? '').isNotEmpty)
                    Text(
                      [
                        if (vm.views != null) vm.views!,
                        if (vm.published != null) vm.published!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class YtErrorCard extends StatelessWidget {
  const YtErrorCard({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 42, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class YtGridSkeleton extends StatelessWidget {
  const YtGridSkeleton({super.key, this.columns = 4});
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: _gridChildAspectRatio,
      ),
      itemCount: columns * 4,
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14))),
          ),
          const SizedBox(height: 8),
          Container(
              width: double.infinity,
              height: 11,
              color: cs.surfaceContainerHighest),
        ],
      ),
    );
  }

  static const double _gridChildAspectRatio = 0.98;
}
