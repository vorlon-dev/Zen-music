// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/song_thumbnail.dart';

/// Queue drawer — Material 3 Expressive cards on a frosted "liquid" slab
/// (same recipe as the rest of the app: one blur, opaque-ish tint, no
/// per-tile BackdropFilters, so scrolling stays smooth).
class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaPlayer = GetIt.I<MediaPlayer>();
    final player = mediaPlayer.player;

    return ValueListenableBuilder<bool>(
      valueListenable: mediaPlayer.engineOwnsNotifier,
      builder: (context, engineOwns, _) {
        if (engineOwns) {
          return ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: mediaPlayer.queueSnapshot,
            builder: (context, snapshot, _) => _Shell(
              player: player,
              count: snapshot.length,
              reorderable: false,
              items: [
                for (int i = 0; i < snapshot.length; i++)
                  _EngineQueueTile(
                    key: ValueKey('eng-${snapshot[i]['videoId'] ?? i}'),
                    index: i,
                    song: snapshot[i],
                  ),
              ],
            ),
          );
        }
        return StreamBuilder(
          stream: mediaPlayer.currentTrackStream,
          builder: (context, snapshot) {
            final sequence = snapshot.data?.sequence ?? [];
            final currentIndex = snapshot.data?.currentIndex ?? 0;
            return _Shell(
              player: player,
              count: sequence.length,
              currentIndex: currentIndex,
              reorderable: true,
              items: [
                for (int i = 0; i < sequence.length; i++)
                  QueueTile(
                    key: ValueKey(sequence[i].tag?.id ?? '$i'),
                    index: i,
                    isCurrent: i == currentIndex,
                    source: sequence[i],
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

const _slab = Color(0xFF1C1C1E);

class _Shell extends StatelessWidget {
  const _Shell({
    required this.player,
    required this.items,
    required this.count,
    required this.reorderable,
    this.currentIndex = 0,
  });
  final AudioPlayer player;
  final List<Widget> items;
  final int count, currentIndex;
  final bool reorderable;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final upNext = reorderable
        ? (count - currentIndex - 1).clamp(0, 1 << 30)
        : count;

    return ClipRRect(
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
            sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _slab.withValues(alpha: .84),
            border: Border(
              left: BorderSide(
                  color: Colors.white.withValues(alpha: .10), width: .6),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // ── header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Queue'.tr,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.4)),
                            const SizedBox(height: 2),
                            Text(
                              '$count ${'songs'.tr} · $upNext ${'up next'.tr}',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      StreamBuilder<bool>(
                        stream: player.shuffleModeEnabledStream,
                        builder: (context, snap) {
                          final on = snap.data ?? false;
                          return _HeadBtn(
                            icon: Icons.shuffle_rounded,
                            tip: on ? 'Shuffle: on' : 'Shuffle: off',
                            on: on,
                            accent: accent,
                            onTap: () => player.setShuffleModeEnabled(!on),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<LoopMode>(
                        stream: player.loopModeStream,
                        builder: (context, snap) {
                          final m = snap.data ?? LoopMode.off;
                          return _HeadBtn(
                            icon: m == LoopMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                            tip: m == LoopMode.off
                                ? 'Repeat: off'
                                : m == LoopMode.one
                                    ? 'Repeat: one'
                                    : 'Repeat: all',
                            on: m != LoopMode.off,
                            accent: accent,
                            onTap: () => player.setLoopMode(
                              m == LoopMode.off
                                  ? LoopMode.all
                                  : m == LoopMode.all
                                      ? LoopMode.one
                                      : LoopMode.off,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _HeadBtn(
                        icon: Icons.close_rounded,
                        tip: 'Close',
                        on: false,
                        accent: accent,
                        onTap: () {
                          final sc = Scaffold.maybeOf(context);
                          if (sc?.isEndDrawerOpen == true) {
                            sc!.closeEndDrawer();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                // ── list ──
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text('Queue is empty'.tr,
                              style: const TextStyle(color: Colors.white54)),
                        )
                      : reorderable
                          ? ReorderableListView(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              buildDefaultDragHandles: false,
                              proxyDecorator: (child, _, anim) =>
                                  AnimatedBuilder(
                                animation: anim,
                                builder: (_, c) => Transform.scale(
                                  scale: 1 + .03 * anim.value,
                                  child: Material(
                                    color: Colors.transparent,
                                    elevation: 12 * anim.value,
                                    shadowColor: Colors.black,
                                    borderRadius: BorderRadius.circular(22),
                                    child: c,
                                  ),
                                ),
                                child: child,
                              ),
                              onReorder: (oldIndex, newIndex) async {
                                if (newIndex > oldIndex) newIndex -= 1;
                                HapticFeedback.selectionClick();
                                await player.moveAudioSource(
                                    oldIndex, newIndex);
                              },
                              children: items,
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 4, 12, 24),
                              children: items,
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

/// Round tonal header button (shuffle / repeat / close).
class _HeadBtn extends StatelessWidget {
  const _HeadBtn({
    required this.icon,
    required this.tip,
    required this.on,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final bool on;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: on
              ? accent.withValues(alpha: .28)
              : Colors.white.withValues(alpha: .10),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 20, color: on ? accent : Colors.white),
            ),
          ),
        ),
      );
}

/// One expressive row. Current track = tonal pill; others = faint card.
class _Card extends StatelessWidget {
  const _Card({
    required this.isCurrent,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final bool isCurrent;
  final Widget leading;
  final String title, subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isCurrent
            ? accent.withValues(alpha: .24)
            : Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(isCurrent ? 26 : 20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: isCurrent ? accent : Colors.white,
                              fontSize: 14.5,
                              fontWeight: isCurrent
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EngineQueueTile extends StatelessWidget {
  const _EngineQueueTile({
    super.key,
    required this.index,
    required this.song,
  });
  final int index;
  final Map<String, dynamic> song;

  @override
  Widget build(BuildContext context) {
    final mp = GetIt.I<MediaPlayer>();
    final currentId = mp.currentSongNotifier.value?.id;
    final isCurrent = song['videoId'] == currentId;
    final thumb = (song['thumbnails'] as List?)?.isNotEmpty == true
        ? (song['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return _Card(
      isCurrent: isCurrent,
      title: song['title']?.toString() ?? '',
      subtitle: song['artist']?.toString() ?? '',
      onTap: () => mp.playFromSection(mp.queueSnapshot.value, index),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            thumb.isEmpty
                ? const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.music_note, color: Colors.white54))
                : CachedNetworkImage(
                    imageUrl: thumb,
                    height: 52,
                    width: 52,
                    memCacheWidth: 160,
                    fit: BoxFit.cover,
                  ),
            if (isCurrent) const _NowBadge(),
          ],
        ),
      ),
    );
  }
}

class QueueTile extends StatelessWidget {
  final int index;
  final bool isCurrent;
  final IndexedAudioSource source;

  const QueueTile({
    super.key,
    required this.index,
    required this.isCurrent,
    required this.source,
  });

  @override
  Widget build(BuildContext context) {
    final player = GetIt.I<MediaPlayer>().player;
    final MediaItem? song = source.tag as MediaItem?;

    if (song == null) return const SizedBox();

    return Dismissible(
      key: ValueKey('dis-${song.id}-$index'),
      direction: DismissDirection.endToStart,
      background: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          decoration: BoxDecoration(
            color: const Color(0xFFFF453A).withValues(alpha: .28),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.delete_outline_rounded,
              color: Color(0xFFFF6B63)),
        ),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        await player.removeAudioSourceAt(index);
        return true;
      },
      child: _Card(
        isCurrent: isCurrent,
        title: song.title,
        subtitle:
            song.artist ?? song.album ?? song.extras?['subtitle'] ?? '',
        onTap: () => player.seek(Duration.zero, index: index),
        leading: ArtworkWidget(song: song, isCurrent: isCurrent),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Remove from queue'.tr,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded,
                  size: 18, color: Colors.white54),
              onPressed: () async {
                HapticFeedback.selectionClick();
                await player.removeAudioSourceAt(index);
              },
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Icon(Icons.drag_indicator_rounded,
                    size: 22, color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowBadge extends StatelessWidget {
  const _NowBadge();

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .55),
          child: const Center(
            child: Icon(Icons.graphic_eq_rounded,
                color: Colors.white, size: 24),
          ),
        ),
      );
}

class ArtworkWidget extends StatelessWidget {
  final MediaItem song;
  final bool isCurrent;

  const ArtworkWidget({
    super.key,
    required this.song,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final double dp = MediaQuery.of(context).devicePixelRatio;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SongThumbnail(
              song: song.extras ?? const {},
              dp: dp,
              height: 52,
              width: 52,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.music_note, size: 28, color: Colors.white54),
            ),
            if (isCurrent) const _NowBadge(),
          ],
        ),
      ),
    );
  }
}
