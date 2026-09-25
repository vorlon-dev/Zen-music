import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

/// History screen — Echo Nightly port. Songs grouped by real play time
/// (Today / Yesterday / This week / Last week / month), search filter,
/// long-press multi-select with select-all and batch add-to-playlist,
/// per-group playback, single-song menu with remove-from-history,
/// hide-on-scroll shuffle FAB.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryGroup {
  final String label;
  final List<Song> songs;
  const _HistoryGroup(this.label, this.songs);
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scroll = ScrollController();

  bool _selectMode = false;
  bool _searching = false;
  bool _fabVisible = true;
  final Set<String> _selection = {}; // song ids

  List<_HistoryGroup> _groups = [];
  List<Song> _flat = [];

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _rebuild();
    _searchCtrl.addListener(_rebuild);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final dir = _scroll.position.userScrollDirection;
    final visible = dir != ScrollDirection.reverse;
    if (visible != _fabVisible && mounted) {
      setState(() => _fabVisible = visible);
    }
  }

  void _rebuild() {
    final entries = storage.getPlayedHistoryDetailed();
    final q = _searchCtrl.text.trim().toLowerCase();
    var src = entries;
    if (q.isNotEmpty) {
      src = src
          .where((e) =>
      e.song.title.toLowerCase().contains(q) ||
          e.song.artist.toLowerCase().contains(q))
          .toList();
    }

    // Echo's DateAgo bucketing on real timestamps.
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));

    final today = <Song>[];
    final yesterday = <Song>[];
    final thisWeek = <Song>[];
    final lastWeek = <Song>[];
    final months = <String, List<Song>>{};
    final earlier = <Song>[];

    for (final e in src) {
      final t = e.playedAt;
      if (t == null) {
        earlier.add(e.song);
      } else if (!t.isBefore(todayStart)) {
        today.add(e.song);
      } else if (!t.isBefore(yesterdayStart)) {
        yesterday.add(e.song);
      } else if (!t.isBefore(weekStart)) {
        thisWeek.add(e.song);
      } else if (!t.isBefore(lastWeekStart)) {
        lastWeek.add(e.song);
      } else {
        final key =
            '${t.year}-${t.month.toString().padLeft(2, '0')}';
        (months[key] ??= []).add(e.song);
      }
    }

    final groups = <_HistoryGroup>[];
    void add(String label, List<Song> list) {
      if (list.isNotEmpty) groups.add(_HistoryGroup(label, list));
    }

    add('Today', today);
    add('Yesterday', yesterday);
    add('This week', thisWeek);
    add('Last week', lastWeek);
    final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final k in keys) {
      final parts = k.split('-');
      final label =
          '${_monthNames[int.parse(parts[1]) - 1]} ${parts[0]}';
      add(label, months[k]!);
    }
    add('Earlier', earlier);

    if (!mounted) return;
    setState(() {
      _groups = groups;
      _flat = [for (final g in groups) ...g.songs];
      _selection.removeWhere(
              (id) => !_flat.any((s) => s.id == id));
      if (_selection.isEmpty) _selectMode = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selection.clear();
    });
  }

  void _toggleSelect(String songId) {
    setState(() {
      if (!_selection.add(songId)) _selection.remove(songId);
    });
  }

  void _playFrom(List<Song> queue, int index) {
    audioHandler.setQueue(queue, startIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _shuffleAll() {
    if (_flat.isEmpty) return;
    final shuffled = List<Song>.from(_flat)..shuffle();
    audioHandler.setQueue(shuffled, startIndex: 0);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── Add-to-playlist (new or existing) ──

  Future<void> _addToPlaylist(List<Song> songs) async {
    final playlists = storage.getUserPlaylists();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 10),
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded,
                  color: SpotifyColors.green),
              title: const Text('New playlist',
                  style: TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await showCreatePlaylistSheet(context);
                if (name == null) return;
                final id = await storage.createUserPlaylist(name);
                await storage.addUserPlaylistSongs(id, songs);
                _snack('Added ${songs.length} song${songs.length == 1 ? '' : 's'} to $name');
              },
            ),
            if (playlists.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text('YOUR PLAYLISTS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: SpotifyColors.textSecondary)),
              ),
            for (final p in playlists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded,
                    color: SpotifyColors.textSecondary),
                title: Text(p.name,
                    style: const TextStyle(
                        color: SpotifyColors.textPrimary)),
                subtitle: Text('${p.count} songs',
                    style: const TextStyle(
                        fontSize: 12,
                        color: SpotifyColors.textSecondary)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await storage.addUserPlaylistSongs(p.id, songs);
                  _snack('Added ${songs.length} song${songs.length == 1 ? '' : 's'} to ${p.name}');
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Single-song menu ──

  void _songMenu(Song song) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Play next',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                audioHandler.playNext(song);
                _snack('Playing next: ${song.title}');
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Add to queue',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                audioHandler.addToQueue(song);
                _snack('Added to queue');
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Add to playlist',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _addToPlaylist([song]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: const Text('Remove from history',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () async {
                Navigator.pop(ctx);
                await storage.removePlayedSong(song.id);
                _rebuild();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectMode) {
          _exitSelect();
          return false;
        }
        if (_searching) {
          setState(() {
            _searching = false;
            _searchCtrl.clear();
          });
          return false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: SpotifyColors.background,
        appBar: _appBar(),
        floatingActionButton: AnimatedScale(
          scale: _fabVisible && _flat.isNotEmpty ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: FloatingActionButton.extended(
            backgroundColor: SpotifyColors.green,
            foregroundColor: Colors.black,
            heroTag: 'history_shuffle_fab',
            onPressed: _shuffleAll,
            icon: const Icon(Icons.shuffle_rounded),
            label: const Text('Shuffle',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        body: _flat.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_rounded,
                size: 52,
                color: SpotifyColors.textTertiary.withOpacity(0.6),
              ),
              const SizedBox(height: 12),
              Text(
                _searchCtrl.text.isEmpty
                    ? 'No listening history yet'
                    : 'No results for "${_searchCtrl.text}"',
                style: const TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        )
            : ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: _sectionCount,
          itemBuilder: (context, i) => _buildItem(i),
        ),
      ),
    );
  }

  int get _sectionCount {
    var count = 0;
    for (final g in _groups) {
      count += 1 + g.songs.length; // header + songs
    }
    return count;
  }

  Widget _buildItem(int i) {
    var cursor = 0;
    for (final g in _groups) {
      if (i == cursor) return _sectionHeader(g.label);
      cursor += 1;
      if (i < cursor + g.songs.length) {
        return _songRow(g, i - cursor);
      }
      cursor += g.songs.length;
    }
    return const SizedBox.shrink();
  }

  Widget _sectionHeader(String label) {
    return Container(
      color: SpotifyColors.background,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(label,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: SpotifyColors.textPrimary)),
    );
  }

  Widget _songRow(_HistoryGroup group, int index) {
    final song = group.songs[index];
    final selected = _selection.contains(song.id);

    return InkWell(
      onTap: () {
        if (_selectMode) {
          _toggleSelect(song.id);
        } else {
          _playFrom(group.songs, index);
        }
      },
      onLongPress: () {
        if (_selectMode) return;
        HapticFeedback.selectionClick();
        setState(() => _selectMode = true);
        _toggleSelect(song.id);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
        child: Row(
          children: [
            if (_selectMode)
              Checkbox(
                value: selected,
                activeColor: SpotifyColors.green,
                onChanged: (_) => _toggleSelect(song.id),
              )
            else
              YoutubeThumbnail(
                videoId: song.id,
                imageUrl: song.thumbnail,
                width: 48,
                height: 48,
                borderRadius: 8,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SpotifyColors.textPrimary)),
                  Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          color: SpotifyColors.textSecondary)),
                ],
              ),
            ),
            if (_selectMode)
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 20, color: SpotifyColors.textTertiary),
                onPressed: () => _toggleSelect(song.id),
              )
            else
              IconButton(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 20, color: SpotifyColors.textTertiary),
                onPressed: () => _songMenu(song),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: SpotifyColors.background,
      elevation: 0,
      iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
      title: _selectMode
          ? Text('${_selection.length} selected',
          style: const TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700))
          : _searching
          ? TextField(
        controller: _searchCtrl,
        focusNode: _focusNode,
        autofocus: true,
        style: const TextStyle(
            color: SpotifyColors.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search history',
          hintStyle: TextStyle(
              color: SpotifyColors.textTertiary.withOpacity(0.8),
              fontSize: 15),
          border: InputBorder.none,
        ),
      )
          : const Text('History',
          style: TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700)),
      leading: IconButton(
        icon: Icon(_selectMode || _searching
            ? Icons.close_rounded
            : Icons.arrow_back_rounded),
        onPressed: () {
          if (_selectMode) {
            _exitSelect();
          } else if (_searching) {
            setState(() {
              _searching = false;
              _searchCtrl.clear();
            });
          } else {
            Navigator.pop(context);
          }
        },
      ),
      actions: [
        if (_selectMode) ...[
          IconButton(
            icon: Icon(
              _selection.length == _flat.length && _flat.isNotEmpty
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank_rounded,
              color: SpotifyColors.textPrimary,
            ),
            onPressed: () {
              setState(() {
                if (_selection.length == _flat.length) {
                  _selection.clear();
                } else {
                  _selection
                    ..clear()
                    ..addAll(_flat.map((s) => s.id));
                }
              });
            },
          ),
          TextButton(
            onPressed: _selection.isEmpty
                ? null
                : () {
              final picked = [
                for (final s in _flat)
                  if (_selection.contains(s.id)) s
              ];
              _exitSelect();
              _addToPlaylist(picked);
            },
            child: const Text('Add',
                style: TextStyle(
                    color: SpotifyColors.green,
                    fontWeight: FontWeight.w700)),
          ),
        ] else if (!_searching)
          IconButton(
            icon: const Icon(FluentIcons.search_24_regular,
                color: SpotifyColors.textPrimary),
            onPressed: () {
              setState(() => _searching = true);
              _focusNode.requestFocus();
            },
          ),
      ],
    );
  }
}