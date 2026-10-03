import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/listen_together_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';

/// Echo-style queue view: now-playing header (art, title, like, edit
/// lock), connected Shuffle/Repeat/Radio group, up-next stats,
/// multi-select deletion, swipe-to-remove with undo, drag reorder and
/// clear-with-undo. Listen Together guests get a read-only queue.
class QueueListView extends StatefulWidget {
  const QueueListView({super.key, this.isBottomSheet = false});

  final bool isBottomSheet;

  @override
  State<QueueListView> createState() => _QueueListViewState();
}

class _QueueListViewState extends State<QueueListView> {
  List<Song> _queue = [];
  late final StreamSubscription<List<Song>> _subscription;
  late final StreamSubscription<Song?> _songSubscription;

  bool _inSelectMode = false;
  final Set<int> _selected = {};
  bool _locked = false;

  bool _shuffleOn = false;
  // none -> all -> one -> none (matches the player's cycler).
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  bool _radioBusy = false;

  bool _hasScrolledToInitial = false;
  final ScrollController _scrollController = ScrollController();

  bool get _isGuest =>
      ListenTogetherService.instance.isInRoom &&
          !ListenTogetherService.instance.isHost;

  bool get _reorderLocked => _locked || _isGuest || _inSelectMode;

  @override
  void initState() {
    super.initState();
    _subscription = audioHandler.queueStream.listen((queue) {
      if (!mounted) return;
      setState(() {
        _queue = List<Song>.from(queue);
        // Queue reshaped under a selection — drop it (indices shifted).
        if (_inSelectMode && _selected.any((i) => i >= _queue.length)) {
          _inSelectMode = false;
          _selected.clear();
        }
      });
      if (!_hasScrolledToInitial && queue.isNotEmpty) {
        _hasScrolledToInitial = true;
        _scrollToCurrentSong();
      }
    });
    // Repaint the highlight when the current song changes.
    _songSubscription = audioHandler.currentSongStream.listen((_) {
      if (mounted) setState(() {});
    });
    _queue = audioHandler.queueSongs;
  }

  void _scrollToCurrentSong() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
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
    _songSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ── actions ──

  void _removeAt(int index) {
    if (index < 0 || index >= _queue.length) return;
    final song = _queue[index];
    audioHandler.removeFromQueue(index);
    setState(() {
      _queue = audioHandler.queueSongs;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed "${song.title}"',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await audioHandler.insertQueueAt(index, song);
          if (mounted) setState(() => _queue = audioHandler.queueSongs);
        },
      ),
    ));
  }

  Future<void> _clearQueue() async {
    final saved = List<Song>.from(audioHandler.queueSongs);
    final savedIndex = audioHandler.currentQueueIndex;
    await audioHandler.clearQueue();
    if (!mounted) return;
    setState(() {
      _queue = audioHandler.queueSongs;
      _inSelectMode = false;
      _selected.clear();
    });
    if (widget.isBottomSheet) Navigator.pop(context);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Queue cleared'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          if (saved.isEmpty) return;
          await audioHandler.setQueue(
              saved,
              startIndex:
              savedIndex.clamp(0, saved.length - 1));
        },
      ),
    ));
  }

  Future<void> _deleteSelected() async {
    final indices = _selected.toList()..sort();
    if (indices.isEmpty) return;
    // Capture (index, song) pairs, then remove bottom-up so the
    // remaining indices stay valid.
    final removed = <MapEntry<int, Song>>[];
    for (final i in indices.reversed) {
      if (i >= 0 && i < _queue.length) {
        removed.add(MapEntry(i, _queue[i]));
        await audioHandler.removeFromQueue(i);
      }
    }
    if (!mounted) return;
    setState(() {
      _queue = audioHandler.queueSongs;
      _inSelectMode = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Removed ${removed.length} songs'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          // Re-insert ascending — restores original positions.
          for (final e in removed) {
            await audioHandler.insertQueueAt(e.key, e.value);
          }
          if (mounted) setState(() => _queue = audioHandler.queueSongs);
        },
      ),
    ));
  }

  Future<void> _appendRadio() async {
    if (_radioBusy) return;
    final current = audioHandler.currentSong;
    if (current == null) return;
    setState(() => _radioBusy = true);
    try {
      final existing = audioHandler.queueSongs.map((s) => s.id).toSet();
      final related = await audioHandler.getRelatedForUI(current);
      final fresh =
      related.where((s) => !existing.contains(s.id)).take(15).toList();
      for (final s in fresh) {
        await audioHandler.addToQueue(s);
      }
      if (!mounted) return;
      setState(() => _queue = audioHandler.queueSongs);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fresh.isEmpty
            ? 'No radio songs found'
            : 'Added ${fresh.length} radio songs'),
        duration: const Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _radioBusy = false);
    }
  }

  void _toggleShuffle() {
    setState(() => _shuffleOn = !_shuffleOn);
    audioHandler.setShuffleMode(
      _shuffleOn ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  void _cycleRepeat() {
    final next = switch (_repeatMode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
    setState(() => _repeatMode = next);
    audioHandler.setRepeatMode(next);
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final currentSong = audioHandler.currentSong;
    final currentIndex = audioHandler.currentQueueIndex;
    final repeatOn = _repeatMode != AudioServiceRepeatMode.none;

    if (widget.isBottomSheet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(currentSong),
          _modeRow(repeatOn),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.52,
            child: _queue.isEmpty ? _emptyState() : _list(currentIndex),
          ),
        ],
      );
    }

    return Column(
      children: [
        _header(currentSong),
        _modeRow(repeatOn),
        Expanded(
          child: _queue.isEmpty ? _emptyState() : _list(currentIndex),
        ),
      ],
    );
  }

  // ── header: art + title/artist + like + lock + clear ──

  Widget _header(Song? currentSong) {
    final inSelect = _inSelectMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
      child: inSelect ? _selectionBar() : _nowPlayingBar(currentSong),
    );
  }

  Widget _nowPlayingBar(Song? currentSong) {
    final liked = currentSong != null && storage.isLiked(currentSong.id);
    return Row(
      children: [
        YoutubeThumbnail(
          videoId: currentSong?.id ?? '',
          imageUrl: currentSong?.thumbnail ?? '',
          width: 48,
          height: 48,
          borderRadius: 10,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentSong?.title ?? 'Queue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: SpotifyColors.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700),
              ),
              if (currentSong != null)
                Text(
                  '${_queue.length} songs · up next',
                  style: const TextStyle(
                      color: SpotifyColors.textSecondary, fontSize: 12),
                ),
            ],
          ),
        ),
        if (currentSong != null)
          IconButton(
            tooltip: liked ? 'Unlike' : 'Like',
            onPressed: () async {
              await storage.setLiked(currentSong, !liked);
              if (mounted) setState(() {});
            },
            icon: Icon(
              liked
                  ? FluentIcons.heart_24_filled
                  : FluentIcons.heart_24_regular,
              color: liked ? SpotifyColors.green : SpotifyColors.textSecondary,
              size: 20,
            ),
          ),
        IconButton(
          tooltip: _locked ? 'Unlock queue' : 'Lock queue',
          onPressed: () => setState(() => _locked = !_locked),
          icon: Icon(
            _locked
                ? FluentIcons.lock_closed_24_regular
                : FluentIcons.lock_open_24_regular,
            color: _locked ? SpotifyColors.green : SpotifyColors.textSecondary,
            size: 20,
          ),
        ),
        IconButton(
          tooltip: 'Select songs',
          onPressed: _queue.isEmpty || _isGuest
              ? null
              : () => setState(() => _inSelectMode = true),
          icon: const Icon(
            FluentIcons.checkmark_square_24_regular,
            color: SpotifyColors.textSecondary,
            size: 20,
          ),
        ),
        if (_queue.isNotEmpty)
          IconButton(
            tooltip: 'Clear queue',
            onPressed: _showClearDialog,
            icon: const Icon(
              FluentIcons.dismiss_24_regular,
              color: SpotifyColors.textSecondary,
              size: 20,
            ),
          ),
      ],
    );
  }

  Widget _selectionBar() {
    final count = _selected.length;
    final allSelected = count == _queue.length && _queue.isNotEmpty;
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(() {
            _inSelectMode = false;
            _selected.clear();
          }),
          icon: const Icon(Icons.close_rounded,
              color: SpotifyColors.textPrimary, size: 22),
        ),
        Expanded(
          child: Text('$count selected',
              style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700)),
        ),
        IconButton(
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          onPressed: () {
            setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(List<int>.generate(_queue.length, (i) => i));
              }
            });
          },
          icon: Icon(
            allSelected
                ? FluentIcons.square_24_regular
                : FluentIcons.checkmark_square_24_regular,
            color: SpotifyColors.textPrimary,
            size: 20,
          ),
        ),
        TextButton.icon(
          onPressed: count == 0 ? null : _deleteSelected,
          icon: const Icon(FluentIcons.delete_24_regular, size: 16),
          label: const Text('Delete'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ],
    );
  }

  void _showClearDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: const Text('Clear queue?',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: const Text('Remove all upcoming songs? You can undo.',
            style: TextStyle(color: SpotifyColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _clearQueue();
              },
              child: const Text('Clear',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  // ── connected Shuffle | Repeat | Radio group ──

  Widget _modeRow(bool repeatOn) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          _groupButton(
            icon: _shuffleOn
                ? FluentIcons.arrow_shuffle_24_filled
                : FluentIcons.arrow_shuffle_24_regular,
            label: 'Shuffle',
            active: _shuffleOn,
            enabled: !_isGuest,
            position: _GroupPosition.leading,
            onTap: _toggleShuffle,
          ),
          const SizedBox(width: 2),
          _groupButton(
            icon: _repeatMode == AudioServiceRepeatMode.one
                ? FluentIcons.arrow_repeat_1_24_filled
                : repeatOn
                ? FluentIcons.arrow_repeat_all_24_filled
                : FluentIcons.arrow_repeat_all_off_24_regular,
            label: 'Repeat',
            active: repeatOn,
            enabled: !_isGuest,
            position: _GroupPosition.middle,
            onTap: _cycleRepeat,
          ),
          const SizedBox(width: 2),
          _groupButton(
            // Material icon — PROVEN in this codebase (home_screen
            // Library radio button). Do not swap for a FluentIcons
            // radio name; both fluent candidates were undefined.
            icon: Icons.radio_rounded,
            label: 'Radio',
            active: false,
            enabled: !_isGuest && !_radioBusy && _queue.isNotEmpty,
            position: _GroupPosition.trailing,
            onTap: _appendRadio,
            busy: _radioBusy,
          ),
        ],
      ),
    );
  }

  Widget _groupButton({
    required IconData icon,
    required String label,
    required bool active,
    required bool enabled,
    required _GroupPosition position,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    final leftRadius = position == _GroupPosition.leading ? 26.0 : 3.0;
    final rightRadius = position == _GroupPosition.trailing ? 26.0 : 3.0;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Material(
          color: active
              ? SpotifyColors.green.withOpacity(0.18)
              : SpotifyColors.surface,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(leftRadius),
            right: Radius.circular(rightRadius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(leftRadius),
              right: Radius.circular(rightRadius),
            ),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  busy
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            SpotifyColors.green)),
                  )
                      : Icon(
                    icon,
                    size: 18,
                    color: active
                        ? SpotifyColors.green
                        : SpotifyColors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? SpotifyColors.green
                            : SpotifyColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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

  Widget _list(int currentIndex) {
    // Occurrence-based keys — stable per item even with duplicates in
    // the queue (index-based keys glitched reorder).
    final occMap = <String, int>{};
    final items = <({Song song, int occ})>[];
    for (final s in _queue) {
      final o = occMap[s.id] ?? 0;
      occMap[s.id] = o + 1;
      items.add((song: s, occ: o));
    }

    return ReorderableListView.builder(
      scrollController: _scrollController,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        if (_reorderLocked) return;
        audioHandler.reorderQueue(oldIndex, newIndex);
        setState(() => _queue = audioHandler.queueSongs);
      },
      proxyDecorator: (child, index, animation) => Material(
        elevation: 8,
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(14),
        shadowColor: Colors.black.withOpacity(0.35),
        child: child,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final song = item.song;
        final isCurrent = index == currentIndex;
        final isSelected = _selected.contains(index);
        return _QueueTile(
          key: ValueKey('${song.id}#${item.occ}'),
          song: song,
          index: index,
          isCurrentSong: isCurrent,
          isSelected: isSelected,
          inSelectMode: _inSelectMode,
          reorderLocked: _reorderLocked,
          swipeEnabled: !_locked && !_isGuest && !_inSelectMode,
          onTap: () {
            if (_inSelectMode) {
              setState(() {
                if (isSelected) {
                  _selected.remove(index);
                } else {
                  _selected.add(index);
                }
              });
              return;
            }
            if (_isGuest) {
              if (isCurrent) return;
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Host controls playback'),
                duration: Duration(seconds: 1),
              ));
              return;
            }
            audioHandler.skipToQueueItem(index);
            if (widget.isBottomSheet) Navigator.pop(context);
          },
          onLongPress: _isGuest
              ? null
              : () {
            setState(() {
              _inSelectMode = true;
              _selected.add(index);
            });
          },
          onDismissed: () => _removeAt(index),
          onToggleSelect: (sel) {
            setState(() {
              if (sel == true) {
                _selected.add(index);
              } else {
                _selected.remove(index);
              }
            });
          },
        );
      },
    );
  }
}

enum _GroupPosition { leading, middle, trailing }

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required super.key,
    required this.song,
    required this.index,
    required this.isCurrentSong,
    required this.isSelected,
    required this.inSelectMode,
    required this.reorderLocked,
    required this.swipeEnabled,
    required this.onTap,
    required this.onLongPress,
    required this.onDismissed,
    required this.onToggleSelect,
  });

  final Song song;
  final int index;
  final bool isCurrentSong;
  final bool isSelected;
  final bool inSelectMode;
  final bool reorderLocked;
  final bool swipeEnabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onDismissed;
  final ValueChanged<bool?> onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: isSelected
          ? SpotifyColors.green.withOpacity(0.10)
          : isCurrentSong
          ? SpotifyColors.green.withOpacity(0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (inSelectMode)
                Checkbox(
                  value: isSelected,
                  onChanged: onToggleSelect,
                  activeColor: SpotifyColors.green,
                ),
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
              if (!inSelectMode && !reorderLocked)
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 14),
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
    );

    if (!swipeEnabled) return tile;

    return Dismissible(
      key: ValueKey('dismiss_${song.id}#$index'),
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
      child: tile,
    );
  }
}