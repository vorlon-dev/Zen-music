// ZenMusic · vorlon-dev
//
// Full-screen player: artwork, controls, volume, speed, sleep timer,
// synced lyrics and the queue.

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_widgets.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.store]),
      builder: (context, _) {
        final player = scope.player;
        final song = player.current;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('Now playing'),
          ),
          body: song == null
              ? const Center(child: Text('Nothing playing'))
              : wide
                  ? Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: _Controls(artSize: 320),
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        const Expanded(child: _LyricsQueueTabs()),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _Controls(
                            artSize: MediaQuery.sizeOf(context).width - 64 > 320
                                ? 320
                                : MediaQuery.sizeOf(context).width - 64,
                          ),
                          const SizedBox(
                            height: 420,
                            child: _LyricsQueueTabs(),
                          ),
                        ],
                      ),
                    ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.artSize});
  final double artSize;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final player = scope.player;
    final song = player.current!;
    final primary = Theme.of(context).colorScheme.primary;
    final total = player.duration.inMilliseconds;
    final pos = player.position.inMilliseconds.clamp(0, total > 0 ? total : 1);
    final fav = scope.store.isFavourite(song.id);

    return Column(
      children: [
        Art(url: song.image, size: artSize, radius: 16),
        const SizedBox(height: 20),
        Text(
          song.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          song.artist,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (player.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              player.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Slider(
          value: total > 0 ? pos.toDouble() : 0,
          max: total > 0 ? total.toDouble() : 1,
          onChanged: total > 0
              ? (v) => player.seek(Duration(milliseconds: v.round()))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(clock(player.position)),
              Text(clock(player.duration)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Shuffle',
              color: player.shuffle ? primary : null,
              icon: const Icon(Icons.shuffle_rounded),
              onPressed: player.toggleShuffle,
            ),
            IconButton(
              tooltip: 'Previous',
              iconSize: 36,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: player.previous,
            ),
            player.loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  )
                : IconButton.filled(
                    tooltip: player.playing ? 'Pause' : 'Play',
                    iconSize: 40,
                    icon: Icon(player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    onPressed: player.toggle,
                  ),
            IconButton(
              tooltip: 'Next',
              iconSize: 36,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: player.hasNext ? player.next : null,
            ),
            IconButton(
              tooltip: 'Repeat',
              color: player.repeat == WebRepeat.off ? null : primary,
              icon: Icon(player.repeat == WebRepeat.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded),
              onPressed: player.cycleRepeat,
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            IconButton(
              tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
              icon: Icon(fav
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              onPressed: () => scope.store.toggleFavourite(song),
            ),
            IconButton(
              tooltip: 'Add to playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => showAddToPlaylist(context, song),
            ),
            PopupMenuButton<double>(
              tooltip: 'Speed',
              icon: const Icon(Icons.speed_rounded),
              initialValue: player.speed,
              onSelected: player.setSpeed,
              itemBuilder: (_) => [
                for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem(value: s, child: Text('${s}x')),
              ],
            ),
            PopupMenuButton<int>(
              tooltip: 'Sleep timer',
              icon: Icon(
                Icons.bedtime_rounded,
                color: player.sleepEndsAt == null ? null : primary,
              ),
              onSelected: (m) =>
                  player.setSleepTimer(m == 0 ? null : Duration(minutes: m)),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 0, child: Text('Off')),
                for (final m in const [15, 30, 45, 60])
                  PopupMenuItem(value: m, child: Text('$m minutes')),
              ],
            ),
            SizedBox(
              width: 170,
              child: Row(
                children: [
                  Icon(
                    player.volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 20,
                  ),
                  Expanded(
                    child: Slider(
                      value: player.volume,
                      onChanged: player.setVolume,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LyricsQueueTabs extends StatelessWidget {
  const _LyricsQueueTabs();

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(tabs: [Tab(text: 'Lyrics'), Tab(text: 'Queue')]),
          Expanded(
            child: TabBarView(children: [_LyricsView(), _QueueView()]),
          ),
        ],
      ),
    );
  }
}

class _LyricsView extends StatefulWidget {
  const _LyricsView();

  @override
  State<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<_LyricsView> {
  final Map<int, GlobalKey> _keys = {};
  int _lastScrolled = -2;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: scope.player,
      builder: (context, _) {
        final player = scope.player;
        final lines = player.lyrics;
        if (lines.isEmpty) {
          return const Center(child: Text('No synced lyrics for this song'));
        }
        final primary = Theme.of(context).colorScheme.primary;
        final active = player.lyricIndex;
        if (active != _lastScrolled) {
          _lastScrolled = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _keys[active]?.currentContext;
            if (ctx != null && ctx.mounted) {
              Scrollable.ensureVisible(
                ctx,
                alignment: 0.4,
                duration: const Duration(milliseconds: 300),
              );
            }
          });
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines.length; i++)
                InkWell(
                  key: _keys.putIfAbsent(i, () => GlobalKey()),
                  onTap: () => player.seek(lines[i].time),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lines[i].text.isEmpty ? '♪' : lines[i].text,
                      style: TextStyle(
                        fontSize: i == active ? 22 : 18,
                        fontWeight:
                            i == active ? FontWeight.w700 : FontWeight.w500,
                        color: i == active ? primary : Colors.white54,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QueueView extends StatelessWidget {
  const _QueueView();

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: scope.player,
      builder: (context, _) {
        final player = scope.player;
        final q = player.queue;
        if (q.isEmpty) return const Center(child: Text('Queue is empty'));
        return ListView.builder(
          itemCount: q.length,
          itemBuilder: (context, i) => ListTile(
            selected: i == player.index,
            leading: Art(url: q[i].image, size: 40),
            title: Text(q[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle:
                Text(q[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: i == player.index
                ? const Icon(Icons.equalizer_rounded)
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => player.removeFromQueue(i),
                  ),
            onTap: () => player.jumpTo(i),
          ),
        );
      },
    );
  }
}
