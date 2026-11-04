// ZenMusic · vorlon-dev
//
// Full-screen player in the style of the app: tinted background, big
// artwork, pill controls, lyrics and queue in a sheet (or side panel).

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_theme.dart';
import 'package:zenmusic/web/web_widgets.dart';

class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.store]),
      builder: (context, _) {
        final song = scope.player.current;
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0xFF2A0A10), Color(0xFF000000)]
                    : const [Color(0xFFF1D9DD), Color(0xFFF8F3F4)],
                stops: const [0.0, 0.7],
              ),
            ),
            child: SafeArea(
              child: song == null
                  ? Column(
                      children: [
                        _TopBar(song: null),
                        const Expanded(
                          child: Center(child: Text('Nothing playing')),
                        ),
                      ],
                    )
                  : wide
                      ? Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  _TopBar(song: song),
                                  const Expanded(
                                    child: _Controls(showLyricsButton: false),
                                  ),
                                ],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            const Expanded(child: _LyricsQueueTabs()),
                          ],
                        )
                      : Column(
                          children: [
                            _TopBar(song: song),
                            const Expanded(
                              child: _Controls(showLyricsButton: true),
                            ),
                          ],
                        ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.song});
  final WebSong? song;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          SquareButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Close',
            size: 52,
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    color: primary,
                    fontSize: 13,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  song?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17),
                ),
              ],
            ),
          ),
          SquareButton(
            icon: Icons.more_vert_rounded,
            tooltip: 'Options',
            size: 52,
            onTap: song == null ? null : () => _showOptions(context),
          ),
        ],
      ),
    );
  }
}

void _showOptions(BuildContext context) {
  final scope = WebScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => ListenableBuilder(
      listenable: Listenable.merge([scope.player, scope.store]),
      builder: (_, __) {
        final player = scope.player;
        final song = player.current;
        if (song == null) return const SizedBox.shrink();
        final fav = scope.store.isFavourite(song.id);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: Icon(fav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded),
                  title: Text(
                      fav ? 'Remove from favourites' : 'Add to favourites'),
                  onTap: () => scope.store.toggleFavourite(song),
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to playlist'),
                  onTap: () {
                    Navigator.of(sheet).pop();
                    showAddToPlaylist(context, song);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('Speed'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0])
                        ChoiceChip(
                          label: Text('${v}x'),
                          selected: player.speed == v,
                          onSelected: (_) => player.setSpeed(v),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Sleep timer'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Off'),
                        selected: player.sleepEndsAt == null,
                        onSelected: (_) => player.setSleepTimer(null),
                      ),
                      for (final m in const [15, 30, 45, 60])
                        ChoiceChip(
                          label: Text('$m min'),
                          selected: false,
                          onSelected: (_) =>
                              player.setSleepTimer(Duration(minutes: m)),
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Volume'),
                ),
                Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(player.volume == 0
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded),
                    Expanded(
                      child: Slider(
                        value: player.volume,
                        onChanged: player.setVolume,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _showLyricsQueue(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: const _LyricsQueueTabs(),
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.showLyricsButton});
  final bool showLyricsButton;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final player = scope.player;
    final song = player.current!;
    final cs = Theme.of(context).colorScheme;
    final total = player.duration.inMilliseconds;
    final pos = player.position.inMilliseconds.clamp(0, total > 0 ? total : 1);
    final remaining = player.duration - player.position;

    return LayoutBuilder(
      builder: (context, box) {
        // Artwork takes the width, but never more than half the height.
        final art = [box.maxWidth - 48, box.maxHeight * 0.45, 460.0]
            .reduce((a, b) => a < b ? a : b)
            .clamp(120.0, 460.0)
            .toDouble();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Art(url: song.image, size: art, radius: 32),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showLyricsButton) ...[
                        const SizedBox(width: 12),
                        SquareButton(
                          icon: Icons.lyrics_rounded,
                          tooltip: 'Lyrics and queue',
                          size: 52,
                          onTap: () => _showLyricsQueue(context),
                        ),
                      ],
                    ],
                  ),
                  if (player.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        player.error!,
                        style: TextStyle(color: cs.error),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(clock(player.position)),
                        Text('-${clock(remaining)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _BigButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: 'Previous',
                        width: 84,
                        height: 76,
                        color: kTonal,
                        iconColor: Colors.white,
                        onTap: player.previous,
                      ),
                      const SizedBox(width: 14),
                      player.loading
                          ? const SizedBox(
                              width: 112,
                              height: 96,
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _BigButton(
                              icon: player.playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              tooltip: player.playing ? 'Pause' : 'Play',
                              width: 112,
                              height: 96,
                              color: kAccent,
                              iconColor: kOnAccent,
                              iconSize: 44,
                              onTap: player.toggle,
                            ),
                      const SizedBox(width: 14),
                      _BigButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: 'Next',
                        width: 84,
                        height: 76,
                        color: kTonal,
                        iconColor: Colors.white,
                        onTap: player.hasNext ? player.next : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _Pill(
                          onTap: player.toggleShuffle,
                          highlighted: player.shuffle,
                          child: const Icon(Icons.shuffle_rounded),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _Pill(
                          onTap: () => _showOptions(context),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.tune_rounded),
                              const SizedBox(width: 8),
                              Text(
                                song.yt
                                    ? 'YouTube · ${player.speed}x'
                                    : 'Auto · ${player.speed}x',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Pill(
                          onTap: player.cycleRepeat,
                          highlighted: player.repeat != WebRepeat.off,
                          child: Icon(player.repeat == WebRepeat.one
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.tooltip,
    required this.width,
    required this.height,
    required this.color,
    required this.iconColor,
    required this.onTap,
    this.iconSize = 34,
  });

  final IconData icon;
  final String tooltip;
  final double width;
  final double height;
  final Color color;
  final Color iconColor;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onTap == null ? color.withValues(alpha: 0.4) : color,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            height: height,
            child: Icon(icon, color: iconColor, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.child,
    required this.onTap,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? kTonal : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(height: 58, child: Center(child: child)),
      ),
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
