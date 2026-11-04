// ZenMusic · vorlon-dev
//
// Pages of the web player: Home, Search, Library, Settings and the album /
// playlist detail pages.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_widgets.dart';

Listenable _watch(WebScope s) => Listenable.merge([s.player, s.store]);

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const List<String> _rows = <String>[
    'Top Hindi',
    'Punjabi Hits',
    'Lo-fi Chill',
    'Hip Hop',
  ];

  final Map<String, List<WebCollection>> _loaded = {};
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final api = WebScope.of(context).api;
    for (final title in _rows) {
      unawaited(() async {
        try {
          final r = await api.searchCollections(title, albums: false, limit: 10);
          if (!mounted) return;
          setState(() => _loaded[title] = r);
        } catch (_) {
          // A row that fails to load is simply left out.
        }
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: _watch(scope),
      builder: (context, _) {
        final history = scope.store.history;
        final favourites = scope.store.favourites;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SectionTitle('Welcome back'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: favourites.isEmpty
                        ? null
                        : () => scope.player.playShuffled(favourites),
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle favourites'),
                  ),
                  OutlinedButton.icon(
                    onPressed: history.isEmpty
                        ? null
                        : () => scope.player.playQueue(history, 0),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Resume recent'),
                  ),
                ],
              ),
            ),
            if (history.isNotEmpty) ...[
              const SectionTitle('Recently played'),
              CardRow(
                cards: [
                  for (var i = 0; i < history.length && i < 20; i++)
                    MediaCard(
                      image: history[i].image,
                      title: history[i].title,
                      subtitle: history[i].artist,
                      onTap: () => scope.player.playQueue(history, i),
                    ),
                ],
              ),
            ],
            if (favourites.isNotEmpty) ...[
              const SectionTitle('Your favourites'),
              CardRow(
                cards: [
                  for (var i = 0; i < favourites.length && i < 20; i++)
                    MediaCard(
                      image: favourites[i].image,
                      title: favourites[i].title,
                      subtitle: favourites[i].artist,
                      onTap: () => scope.player.playQueue(favourites, i),
                    ),
                ],
              ),
            ],
            for (final title in _rows)
              if ((_loaded[title] ?? const <WebCollection>[]).isNotEmpty) ...[
                SectionTitle(title),
                CardRow(
                  cards: [
                    for (final c in _loaded[title]!)
                      MediaCard(
                        image: c.image,
                        title: c.title,
                        subtitle: c.subtitle,
                        onTap: () => openCollection(context, c),
                      ),
                  ],
                ),
              ],
          ],
        );
      },
    );
  }
}

void openCollection(BuildContext context, WebCollection c) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CollectionPage(collection: c)),
  );
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

enum _SearchKind { songs, albums, playlists }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  _SearchKind _kind = _SearchKind.songs;
  bool _ytm = false;

  List<WebSong> _songs = const [];
  List<WebCollection> _collections = const [];
  bool _busy = false;
  String? _error;
  int _run = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    final id = ++_run;
    final q = _query.text.trim();
    final api = WebScope.of(context).api;
    if (q.isEmpty) {
      setState(() {
        _songs = const [];
        _collections = const [];
        _busy = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_kind == _SearchKind.songs) {
        final r = _ytm ? await api.searchYtm(q) : await api.search(q);
        if (id != _run || !mounted) return;
        setState(() {
          _songs = r;
          _collections = const [];
        });
      } else {
        final r = await api.searchCollections(
          q,
          albums: _kind == _SearchKind.albums,
        );
        if (id != _run || !mounted) return;
        setState(() {
          _collections = r;
          _songs = const [];
        });
      }
      setState(() => _busy = false);
    } catch (_) {
      if (id != _run || !mounted) return;
      setState(() {
        _busy = false;
        _error = 'Search failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            onChanged: _changed,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search songs, albums, playlists',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('JioSaavn'),
                selected: !_ytm,
                onSelected: (_) {
                  setState(() => _ytm = false);
                  _search();
                },
              ),
              ChoiceChip(
                label: const Text('YouTube Music'),
                selected: _ytm,
                onSelected: (_) {
                  setState(() {
                    _ytm = true;
                    _kind = _SearchKind.songs;
                  });
                  _search();
                },
              ),
            ],
          ),
        ),
        if (!_ytm)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<_SearchKind>(
            segments: const [
              ButtonSegment(value: _SearchKind.songs, label: Text('Songs')),
              ButtonSegment(value: _SearchKind.albums, label: Text('Albums')),
              ButtonSegment(
                value: _SearchKind.playlists,
                label: Text('Playlists'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              setState(() => _kind = s.first);
              _search();
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListenableBuilder(
            listenable: _watch(scope),
            builder: (context, _) => _body(context, scope),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, WebScope scope) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (_kind == _SearchKind.songs) {
      if (_songs.isEmpty) return _hint();
      return ListView.builder(
        itemCount: _songs.length,
        itemBuilder: (context, i) => SongTile(
          song: _songs[i],
          onTap: () => scope.player.playQueue(_songs, i),
        ),
      );
    }
    if (_collections.isEmpty) return _hint();
    return ListView.builder(
      itemCount: _collections.length,
      itemBuilder: (context, i) {
        final c = _collections[i];
        return ListTile(
          leading: Art(url: c.image, size: 48),
          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(c.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => openCollection(context, c),
        );
      },
    );
  }

  Widget _hint() => Center(
        child: Text(
          _query.text.trim().isEmpty
              ? 'Search to start listening.'
              : 'Nothing found.',
        ),
      );
}

// ---------------------------------------------------------------------------
// Album / playlist detail
// ---------------------------------------------------------------------------

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.collection});
  final WebCollection collection;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  WebDetail? _detail;
  bool _loading = true;
  bool _failed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final api = WebScope.of(context).api;
    try {
      final d = await api.collection(widget.collection);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
        _failed = d == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final c = _detail?.collection ?? widget.collection;
    final songs = _detail?.songs ?? const <WebSong>[];
    return Scaffold(
      appBar: AppBar(title: Text(c.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(child: Text('Could not load this.'))
              : ListenableBuilder(
                  listenable: _watch(scope),
                  builder: (context, _) => ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Art(url: c.image, size: 120, radius: 12),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  Text('${songs.length} songs'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: songs.isEmpty
                                            ? null
                                            : () => scope.player
                                                .playQueue(songs, 0),
                                        icon: const Icon(
                                            Icons.play_arrow_rounded),
                                        label: const Text('Play'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: songs.isEmpty
                                            ? null
                                            : () => scope.player
                                                .playShuffled(songs),
                                        icon: const Icon(
                                            Icons.shuffle_rounded),
                                        label: const Text('Shuffle'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var i = 0; i < songs.length; i++)
                        SongTile(
                          song: songs[i],
                          onTap: () => scope.player.playQueue(songs, i),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'Favourites'),
              Tab(text: 'Playlists'),
              Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_Favourites(), _Playlists(), _History()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SongList extends StatelessWidget {
  const _SongList({required this.songs, required this.empty});
  final List<WebSong> songs;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    if (songs.isEmpty) return Center(child: Text(empty));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => scope.player.playQueue(songs, 0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play all'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => scope.player.playShuffled(songs),
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, i) => SongTile(
              song: songs[i],
              onTap: () => scope.player.playQueue(songs, i),
            ),
          ),
        ),
      ],
    );
  }
}

class _Favourites extends StatelessWidget {
  const _Favourites();

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: _watch(scope),
      builder: (context, _) => _SongList(
        songs: scope.store.favourites,
        empty: 'No favourites yet. Tap the heart on a song.',
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: _watch(scope),
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: _SongList(
              songs: scope.store.history,
              empty: 'Nothing played yet.',
            ),
          ),
          if (scope.store.history.isNotEmpty)
            TextButton(
              onPressed: scope.store.clearHistory,
              child: const Text('Clear history'),
            ),
        ],
      ),
    );
  }
}

class _Playlists extends StatelessWidget {
  const _Playlists();

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: scope.store,
      builder: (context, _) {
        final names = scope.store.playlistNames;
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await promptText(context, 'New playlist', 'Name');
                if (name != null) scope.store.createPlaylist(name);
              },
            ),
            Expanded(
              child: names.isEmpty
                  ? const Center(child: Text('No playlists yet.'))
                  : ListView.builder(
                      itemCount: names.length,
                      itemBuilder: (context, i) {
                        final n = names[i];
                        return ListTile(
                          leading: const Icon(Icons.queue_music_rounded),
                          title: Text(n),
                          subtitle:
                              Text('${scope.store.playlist(n).length} songs'),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => scope.store.deletePlaylist(n),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PlaylistPage(name: n),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListenableBuilder(
        listenable: _watch(scope),
        builder: (context, _) {
          final songs = scope.store.playlist(name);
          if (songs.isEmpty) {
            return const Center(
              child: Text('Empty. Add songs from the song menu.'),
            );
          }
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => scope.player.playQueue(songs, 0),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => scope.player.playShuffled(songs),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Shuffle'),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  onTap: () => scope.player.playQueue(songs, i),
                  extraMenu: const [
                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                  ],
                  onExtra: (v) {
                    if (v == 'remove') {
                      scope.store.removeFromPlaylist(name, songs[i].id);
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return ListenableBuilder(
      listenable: scope.store,
      builder: (context, _) => ListView(
        children: [
          const SectionTitle('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {scope.store.themeMode},
              onSelectionChanged: (s) => scope.store.setThemeMode(s.first),
            ),
          ),
          const SectionTitle('Data'),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('Clear listening history'),
            onTap: () {
              scope.store.clearHistory();
              toast(context, 'History cleared');
            },
          ),
          const SectionTitle('About'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('ZenMusic Web'),
            subtitle: Text(
              'Your favourites, playlists and history are saved in this '
              'browser only. The Android and Windows apps have more features '
              '(downloads, equalizer, YouTube Music).',
            ),
          ),
        ],
      ),
    );
  }
}
