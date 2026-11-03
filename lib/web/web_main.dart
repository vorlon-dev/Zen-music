// ZenMusic · vorlon-dev
//
// Web player entry point. Build with:
//   flutter build web -t lib/web/web_main.dart
//
// Self-contained: it imports nothing that needs dart:io, so the Android and
// Windows apps are unaffected by this file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_api.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_player.dart';

void main() => runApp(const ZenWebApp());

class ZenWebApp extends StatelessWidget {
  const ZenWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C6CF0),
        scaffoldBackgroundColor: const Color(0xFF0E0E12),
      ),
      home: const WebHome(),
    );
  }
}

class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  final WebApi _api = WebApi();
  late final WebPlayer _player = WebPlayer(_api);
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  List<WebSong> _results = const [];
  bool _searching = false;
  String? _searchError;
  int _search = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _player.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(value));
  }

  Future<void> _run(String value) async {
    final id = ++_search;
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await _api.search(value);
      if (id != _search || !mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } catch (_) {
      if (id != _search || !mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'Search failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _player,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final list = _buildList(context);
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('ZenMusic',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _query,
                  onChanged: _onQueryChanged,
                  onSubmitted: _run,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(flex: 3, child: list),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: _SidePanel(player: _player),
                          ),
                        ],
                      )
                    : list,
              ),
              _PlayerBar(
                player: _player,
                onOpen: wide ? null : () => _openSheet(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    if (_searching) return const Center(child: CircularProgressIndicator());
    if (_searchError != null) {
      return Center(child: Text(_searchError!, textAlign: TextAlign.center));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _query.text.trim().isEmpty
              ? 'Search for a song to start listening.'
              : 'No playable results.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final s = _results[i];
        final active = _player.current?.id == s.id;
        return ListTile(
          leading: _Art(url: s.image, size: 48),
          title: Text(s.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: active
                  ? TextStyle(color: Theme.of(context).colorScheme.primary)
                  : null),
          subtitle: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: 'Add to queue',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: () {
              _player.enqueue(s);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Added to queue')),
                );
            },
          ),
          onTap: () => _player.playQueue(_results, i),
        );
      },
    );
  }

  void _openSheet(BuildContext context) {
    if (_player.current == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: _SidePanel(player: _player),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size});
  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: Colors.white10,
      child: const Icon(Icons.music_note_rounded),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.player, required this.onOpen});
  final WebPlayer player;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final total = player.duration.inMilliseconds;
    final pos = player.position.inMilliseconds.clamp(0, total > 0 ? total : 1);
    return Material(
      color: const Color(0xFF181820),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              value: total > 0 ? pos.toDouble() : 0,
              max: total > 0 ? total.toDouble() : 1,
              onChanged: total > 0
                  ? (v) => player.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
            ListTile(
              onTap: onOpen,
              leading: _Art(url: song.image, size: 44),
              title: Text(song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                player.error ??
                    '${clock(player.position)} / ${clock(player.duration)}'
                        '  ·  ${song.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous',
                    icon: const Icon(Icons.skip_previous_rounded),
                    onPressed: player.previous,
                  ),
                  player.loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton.filled(
                          tooltip: player.playing ? 'Pause' : 'Play',
                          icon: Icon(player.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          onPressed: player.toggle,
                        ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: player.hasNext ? player.next : null,
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

/// Lyrics and queue, as tabs.
class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.player});
  final WebPlayer player;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(tabs: [Tab(text: 'Lyrics'), Tab(text: 'Queue')]),
          Expanded(
            child: ListenableBuilder(
              listenable: player,
              builder: (context, _) => TabBarView(
                children: [
                  _LyricsView(player: player),
                  _QueueView(player: player),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsView extends StatelessWidget {
  const _LyricsView({required this.player});
  final WebPlayer player;

  @override
  Widget build(BuildContext context) {
    if (player.current == null) {
      return const Center(child: Text('Nothing playing'));
    }
    if (player.lyrics.isEmpty) {
      return const Center(child: Text('No synced lyrics for this song'));
    }
    final primary = Theme.of(context).colorScheme.primary;
    final lines = player.lyrics;
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final active = i == player.lyricIndex;
        return InkWell(
          onTap: () => player.seek(lines[i].time),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              lines[i].text.isEmpty ? '♪' : lines[i].text,
              style: TextStyle(
                fontSize: active ? 22 : 18,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? primary : Colors.white54,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QueueView extends StatelessWidget {
  const _QueueView({required this.player});
  final WebPlayer player;

  @override
  Widget build(BuildContext context) {
    final q = player.queue;
    if (q.isEmpty) return const Center(child: Text('Queue is empty'));
    return ListView.builder(
      itemCount: q.length,
      itemBuilder: (context, i) => ListTile(
        selected: i == player.index,
        leading: _Art(url: q[i].image, size: 40),
        title: Text(q[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle:
            Text(q[i].artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => player.jumpTo(i),
      ),
    );
  }
}
