// ZenMusic — queue drawer. SP-6: switches source based on who owns
// playback. Engine-owned tracks render from MediaPlayer.queueSnapshot (the
// section the user tapped); just_audio-owned tracks render from the player
// sequence as before. Engine tiles are read-only (no reorder/dismiss) but
// tappable — tapping plays that item from the snapshot.
//
// SP-39d (field log): the drawer's shell Container paints a background
// color, which hides ListTile's own Material background + ink splashes
// ("ListTile background color or ink splashes may be invisible"). Both
// tile types are now wrapped in their own transparent Material — the
// shell blur/tint is untouched, taps ripple properly again.

import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/utils/song_thumbnail.dart';

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
              mediaPlayer: mediaPlayer,
              player: player,
              children: [
                for (int i = 0; i < snapshot.length; i++)
                  _EngineQueueTile(
                    key: ValueKey('eng-${snapshot[i]['videoId'] ?? i}'),
                    index: i,
                    song: snapshot[i],
                  ),
              ],
              reorderable: false,
            ),
          );
        }
        return StreamBuilder(
          stream: mediaPlayer.currentTrackStream,
          builder: (context, snapshot) {
            final sequence = snapshot.data?.sequence ?? [];
            final currentIndex = snapshot.data?.currentIndex ?? 0;
            return _Shell(
              mediaPlayer: mediaPlayer,
              player: player,
              children: [
                for (int i = 0; i < sequence.length; i++)
                  QueueTile(
                    key: Key(sequence[i].tag?.id ?? '$i'),
                    index: i,
                    isCurrent: i == currentIndex,
                    source: sequence[i],
                  ),
              ],
              reorderable: true,
            );
          },
        );
      },
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.mediaPlayer,
    required this.player,
    required this.children,
    required this.reorderable,
  });
  final MediaPlayer mediaPlayer;
  final AudioPlayer player;
  final List<Widget> children;
  final bool reorderable;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // SP-61: under M3 the scaffold background is transparent, so the
        // drawer shell takes a real M3 surface container (blur still reads
        // through); classic keeps the translucent scaffold tint.
        color: GetIt.I<SettingsManager>().isMaterial3
            ? Theme.of(context)
                .colorScheme
                .surfaceContainer
                .withValues(alpha: 0.88)
            : Theme.of(context).scaffoldBackgroundColor.withAlpha(70),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: reorderable
                      ? ReorderableListView(
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex -= 1;
                      await player.moveAudioSource(oldIndex, newIndex);
                    },
                    children: children,
                  )
                      : ListView(children: children),
                ),
                if (Platform.isAndroid)
                  StreamBuilder<bool>(
                    stream: player.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final shuffle = snapshot.data ?? false;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              style: ButtonStyle(
                                // SP-61: M3 — container/onContainer pairing.
                                backgroundColor: WidgetStatePropertyAll(
                                  shuffle
                                      ? (GetIt.I<SettingsManager>().isMaterial3
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                          : Colors.white)
                                      : (GetIt.I<SettingsManager>().isMaterial3
                                          ? Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHigh
                                          : Colors.white.withAlpha(50)),
                                ),
                                foregroundColor: WidgetStatePropertyAll(
                                  shuffle
                                      ? (GetIt.I<SettingsManager>().isMaterial3
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer
                                          : Theme.of(context)
                                              .scaffoldBackgroundColor)
                                      : (GetIt.I<SettingsManager>().isMaterial3
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                          : Colors.white),
                                ),
                              ),
                              onPressed: () {
                                player.setShuffleModeEnabled(!shuffle);
                              },
                              icon: const Icon(Icons.shuffle_outlined),
                              label: const Text('Shuffle'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
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
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        key: ValueKey('eng-tile-$index'),
        title: Text(
          song['title']?.toString() ?? '',
          maxLines: 1,
          // SP-61: M3 — the playing tile takes the theme primary.
          style: isCurrent && GetIt.I<SettingsManager>().isMaterial3
              ? TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )
              : null,
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              thumb.isEmpty
                  ? const SizedBox(
                  width: 50,
                  height: 50,
                  child: Icon(Icons.music_note))
                  : CachedNetworkImage(
                imageUrl: thumb,
                height: 50,
                width: 50,
                fit: BoxFit.cover,
              ),
              if (isCurrent)
                Container(
                  height: 50,
                  width: 50,
                  color: Colors.black.withOpacity(0.6),
                ),
              if (isCurrent)
                const Positioned(
                  width: 34,
                  height: 34,
                  left: 8,
                  top: 8,
                  child: Center(
                    child:
                    Icon(Icons.music_note_outlined, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        subtitle: Text(song['artist']?.toString() ?? '', maxLines: 1),
        onTap: () {
          mp.playFromSection(mp.queueSnapshot.value, index);
        },
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
      key: Key(song.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await player.removeAudioSourceAt(index);
        return true;
      },
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: Key(index.toString()),
          title: Text(
            song.title,
            maxLines: 1,
            // SP-61: M3 — the playing tile takes the theme primary.
            style: isCurrent && GetIt.I<SettingsManager>().isMaterial3
                ? TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  )
                : null,
          ),
          leading: ArtworkWidget(song: song, isCurrent: isCurrent),
          subtitle: Text(
            song.artist ?? song.album ?? song.extras?['subtitle'] ?? '',
            maxLines: 1,
          ),
          onTap: () {
            player.seek(Duration.zero, index: index);
          },
        ),
      ),
    );
  }
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
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          SongThumbnail(
            song: song.extras!,
            dp: dp,
            height: 50,
            width: 50,
            fit: BoxFit.fill,
            errorWidget: (_, __, ___) => const Icon(Icons.music_note, size: 32),
          ),
          if (isCurrent)
            Container(
              height: 50,
              width: 50,
              color: Colors.black.withOpacity(0.6),
            ),
          if (isCurrent)
            const Positioned(
              width: 34,
              height: 34,
              left: 8,
              top: 8,
              child: Center(
                child: Icon(
                  Icons.music_note_outlined,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}