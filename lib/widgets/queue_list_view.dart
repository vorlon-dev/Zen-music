import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';

/// Full-featured queue view: reorder by drag, swipe to remove,
/// auto-scroll to the current song, clear-all with confirmation.
class QueueListView extends StatefulWidget {
  const QueueListView({super.key, this.isBottomSheet = false});

  final bool isBottomSheet;

  @override
  State<QueueListView> createState() => _QueueListViewState();
}

class _QueueListViewState extends State<QueueListView> {
  List<Song> _queue = [];
  late final StreamSubscription<List<Song>> _subscription;
  bool _isDismissing = false;
  bool _hasScrolledToInitial = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _subscription = audioHandler.queueStream.listen((queue) {
      if (mounted && !_isDismissing) {
        setState(() => _queue = List<Song>.from(queue));
        if (!_hasScrolledToInitial && queue.isNotEmpty) {
          _hasScrolledToInitial = true;
          _scrollToCurrentSong();
        }
      }
    });
    // Prime the list immediately.
    _queue = audioHandler.queueSongs;
  }

  void _scrollToCurrentSong() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final currentIndex = audioHandler.currentQueueIndex;
      if (currentIndex <= 0) return;
      const estimatedItemHeight = 68.0;
      final targetOffset = currentIndex * estimatedItemHeight;
      final clamped = targetOffset.clamp(
          0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(clamped,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _confirmClearQueue() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: const Text('Clear queue?',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: const Text('Remove all upcoming songs?',
            style: TextStyle(color: SpotifyColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                audioHandler.clearQueue();
                if (widget.isBottomSheet) Navigator.pop(context);
              },
              child: const Text('Clear',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = audioHandler.currentQueueIndex;

    if (widget.isBottomSheet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(compact: true),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.52,
            child: _queue.isEmpty
                ? _emptyState()
                : _list(currentIndex, closeOnTap: true),
          ),
        ],
      );
    }

    return Column(
      children: [
        _header(compact: false),
        Expanded(
          child: _queue.isEmpty ? _emptyState() : _list(currentIndex),
        ),
      ],
    );
  }

  Widget _header({required bool compact}) {
    return Padding(
      padding: compact
          ? const EdgeInsets.only(left: 20, right: 16, top: 16, bottom: 8)
          : const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(compact ? 8 : 10),
            decoration: BoxDecoration(
              color: SpotifyColors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              FluentIcons.apps_list_24_regular,
              color: SpotifyColors.green,
              size: compact ? 20.0 : 22.0,
            ),
          ),
          SizedBox(width: compact ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Queue',
                    style: TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontSize: compact ? 17 : 18,
                        fontWeight: FontWeight.w700)),
                if (_queue.isNotEmpty)
                  Text('${_queue.length} songs',
                      style: const TextStyle(
                          color: SpotifyColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          if (_queue.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClearQueue,
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: SpotifyColors.textSecondary,
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: SpotifyColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(FluentIcons.music_note_1_24_regular,
                  color: SpotifyColors.textTertiary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text('No songs in queue',
                style: TextStyle(color: SpotifyColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _list(int currentIndex, {bool closeOnTap = false}) {
    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: _queue.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          audioHandler.reorderQueue(oldIndex, newIndex);
          _queue = audioHandler.queueSongs;
        });
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(14),
        shadowColor: Colors.black.withOpacity(0.35),
        child: child,
      ),
      itemBuilder: (context, index) {
        final song = _queue[index];
        final isCurrent = index == currentIndex;
        return _QueueTile(
          key: ValueKey('${song.id}_$index'),
          song: song,
          index: index,
          isCurrentSong: isCurrent,
          onTap: () {
            audioHandler.skipToQueueItem(index);
            if (closeOnTap) Navigator.pop(context);
          },
          onDismissed: () {
            audioHandler.removeFromQueue(index);
            setState(() => _queue = audioHandler.queueSongs);
          },
        );
      },
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required super.key,
    required this.song,
    required this.index,
    required this.isCurrentSong,
    required this.onTap,
    required this.onDismissed,
  });

  final Song song;
  final int index;
  final bool isCurrentSong;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('dismiss_${song.id}_$index'),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(FluentIcons.delete_24_regular,
            color: Colors.redAccent),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.25),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(FluentIcons.delete_24_regular,
            color: Colors.redAccent),
      ),
      onDismissed: (_) => onDismissed(),
      child: Material(
        color: isCurrentSong
            ? SpotifyColors.green.withOpacity(0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                YoutubeThumbnail(
                  videoId: song.id,
                  imageUrl: song.thumbnail,
                  width: 46,
                  height: 46,
                  borderRadius: 10,
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
                        style: TextStyle(
                          color: isCurrentSong
                              ? SpotifyColors.green
                              : SpotifyColors.textPrimary,
                          fontSize: 14,
                          fontWeight: isCurrentSong
                              ? FontWeight.w600
                              : FontWeight.w500,
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
                if (isCurrentSong) ...[
                  const Icon(FluentIcons.music_note_2_24_regular,
                      color: SpotifyColors.green, size: 16),
                  const SizedBox(width: 6),
                ],
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                    child: Icon(
                      FluentIcons.re_order_24_regular,
                      color: SpotifyColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}