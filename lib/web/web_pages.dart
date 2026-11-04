// ZenMusic · vorlon-dev
//
// Pages of the web player: Home, Search, Library, Settings and the album /
// playlist detail pages.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_store.dart';
import 'package:zenmusic/web/web_theme.dart';
import 'package:zenmusic/web/web_widgets.dart';

Listenable _watch(WebScope s) => Listenable.merge([s.player, s.store]);

// ---------------------------------------------------------------------------
// Home
// ---------------------------------------------------------------------------

const List<String> _moods = <String>[
  'Work out',
  'Feel good',
  'Romance',
  'Party',
  'Energise',
  'Relax',
  'Commute',
  'Sad',
  'Focus',
  'Sleep',
];

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
        final quick = (history.isNotEmpty ? history : favourites)
            .take(6)
            .toList();
        final columns = MediaQuery.sizeOf(context).width >= 900 ? 3 : 2;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Text(
                'ZenMusic',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _moods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => Material(
                  color: kPill,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MoodPage(mood: _moods[i]),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Text(_moods[i]),
                    ),
                  ),
                ),
              ),
            ),
            if (quick.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: columns == 3 ? 4.6 : 3.2,
                  children: [
                    for (var i = 0; i < quick.length; i++)
                      QuickTile(
                        image: quick[i].image,
                        title: quick[i].title,
                        onTap: () => scope.player.playQueue(quick, i),
                      ),
                  ],
                ),
              ),
            ],
            if (history.isNotEmpty) ...[
              SectionTitle('Recently played', trailing: '${history.length} tracks'),
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
              SectionTitle('Your favourites', trailing: '${favourites.length} songs'),
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

/// Songs for a mood such as "Work out" or "Relax".
class MoodPage extends StatefulWidget {
  const MoodPage({super.key, required this.mood});
  final String mood;

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage> {
  List<WebSong> _songs = const [];
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
      final r = await api.search('${widget.mood} songs', limit: 30);
      if (!mounted) return;
      setState(() {
        _songs = r;
        _loading = false;
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.mood)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed || _songs.isEmpty
              ? const Center(child: Text('Nothing to show right now.'))
              : ListenableBuilder(
                  listenable: _watch(scope),
                  builder: (context, _) => _SongList(
                    songs: _songs,
                    empty: 'Nothing to show right now.',
                  ),
                ),
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

enum _Source { saavn, ytm, youtube }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  _SearchKind _kind = _SearchKind.songs;
  _Source _source = _Source.saavn;

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
        final r = switch (_source) {
          _Source.saavn => await api.search(q),
          _Source.ytm => await api.searchYtm(q),
          _Source.youtube => await api.searchYoutube(q),
        };
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
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
          child: TextField(
            controller: _query,
            onChanged: _changed,
            onSubmitted: (_) => _search(),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: 'Search songs, artists, videos',
              hintStyle: const TextStyle(fontSize: 20, color: Colors.grey),
              prefixIcon: const Icon(Icons.search_rounded, size: 28),
              border: InputBorder.none,
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _query.clear();
                        _search();
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _SourceTab(
                icon: Icons.search_rounded,
                label: 'JioSaavn',
                selected: _source == _Source.saavn,
                onTap: () => _pick(_Source.saavn),
              ),
              _SourceTab(
                icon: Icons.music_note_rounded,
                label: 'YouTube Music',
                selected: _source == _Source.ytm,
                onTap: () => _pick(_Source.ytm),
              ),
              _SourceTab(
                icon: Icons.smart_display_outlined,
                label: 'YouTube',
                selected: _source == _Source.youtube,
                onTap: () => _pick(_Source.youtube),
              ),
            ],
          ),
        ),
        if (_source == _Source.saavn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  _SearchKind.songs: 'Songs',
                  _SearchKind.albums: 'Albums',
                  _SearchKind.playlists: 'Playlists',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _kind == entry.key,
                    onSelected: (_) {
                      setState(() => _kind = entry.key);
                      _search();
                    },
                  ),
              ],
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

  void _pick(_Source source) {
    setState(() {
      _source = source;
      if (source != _Source.saavn) _kind = _SearchKind.songs;
    });
    _search();
  }

  Widget _body(BuildContext context, WebScope scope) {
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (_kind == _SearchKind.songs) {
      if (_songs.isEmpty) return _hint();
      if (_source == _Source.youtube) {
        return ListView.builder(
          itemCount: _songs.length,
          itemBuilder: (context, i) => VideoCard(
            song: _songs[i],
            onTap: () => scope.player.playQueue(_songs, i),
          ),
        );
      }
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
          leading: Art(url: c.image, size: 56, radius: 12),
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

class _SourceTab extends StatelessWidget {
  const _SourceTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? null : Colors.grey;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 3,
              width: 36,
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).colorScheme.onSurface : null,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
// Library ("Saved")
// ---------------------------------------------------------------------------

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final columns = MediaQuery.sizeOf(context).width >= 900 ? 4 : 2;
    return ListenableBuilder(
      listenable: scope.store,
      builder: (context, _) {
        final store = scope.store;
        final names = store.playlistNames;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Saved',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New playlist',
                  icon: const Icon(Icons.add_rounded, size: 30),
                  onPressed: () async {
                    final name =
                        await promptText(context, 'New playlist', 'Name');
                    if (name != null) store.createPlaylist(name);
                  },
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.86,
              children: [
                _LibTile(
                  icon: Icons.favorite_rounded,
                  title: 'Favourites',
                  count: store.favourites.length,
                  onTap: () => _open(
                    context,
                    SongListPage(
                      title: 'Favourites',
                      songs: (s) => s.favourites,
                      empty: 'No favourites yet. Tap the heart on a song.',
                    ),
                  ),
                ),
                _LibTile(
                  icon: Icons.history_rounded,
                  title: 'History',
                  count: store.history.length,
                  onTap: () => _open(
                    context,
                    SongListPage(
                      title: 'History',
                      songs: (s) => s.history,
                      empty: 'Nothing played yet.',
                      onClear: store.clearHistory,
                    ),
                  ),
                ),
                for (final n in names)
                  _LibTile(
                    icon: Icons.queue_music_rounded,
                    title: n,
                    count: store.playlist(n).length,
                    onTap: () => _open(context, PlaylistPage(name: n)),
                    onLongPress: () => store.deletePlaylist(n),
                  ),
              ],
            ),
            if (names.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Long-press a playlist to delete it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _LibTile extends StatelessWidget {
  const _LibTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(child: Icon(icon, size: 52)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Text('$count songs', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

/// A saved list (favourites, history) shown as a page.
class SongListPage extends StatelessWidget {
  const SongListPage({
    super.key,
    required this.title,
    required this.songs,
    required this.empty,
    this.onClear,
  });

  final String title;
  final List<WebSong> Function(WebStore store) songs;
  final String empty;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (onClear != null)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
      body: ListenableBuilder(
        listenable: _watch(scope),
        builder: (context, _) =>
            _SongList(songs: songs(scope.store), empty: empty),
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
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(
              'Settings',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
            ),
          ),
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
