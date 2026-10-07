import 'dart:async';
import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:yt_extractor/yt_extractor.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/downloads_service.dart';
import '../services/home_service.dart';
import '../services/jiosaavn_service.dart';
import '../services/song_source_resolver.dart';
import '../services/yt_music_service.dart';
import '../services/video_preference_service.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/media_shelf.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/skeleton.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/youtube_thumbnail.dart';
import 'collection_screen.dart';
import 'new_release_screen.dart';
import 'player_screen.dart';
import 'recognize_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with WidgetsBindingObserver {
  final _searchBar = TextEditingController();
  final _inputNode = FocusNode();
  final _ytm = YtMusicService();
  final _jiosaavn = JiosaavnService();
  final _youtube = YoutubeService();
  final _homeService = HomeService();

  List<Song> _songResults = [];
  List<Song> _videoResults = [];
  List<Collection> _playlistResults = [];
  List<Collection> _albumResults = [];
  List<String> _suggestions = [];
  List<String> _history = [];

  // Echo search-source toggle: 'online' or 'library'.
  String _source = 'online';
  List<Song> _librarySongs = [];

  // Echo explore idle content: new-release albums grid.
  List<Collection> _newAlbums = [];
  bool _albumsLoading = true;

  // ── Echo search states ──
  // _searchActive: the bar's left icon shows a back arrow and the
  // area below the bar shows suggestions/history INLINE (the bar
  // itself stays a pill — Echo's current design does NOT morph the
  // bar to full-bleed).
  // _showSearchContent: Echo's 100ms delay so the activation settles
  // before the suggestion list appears.
  bool _searchActive = false;
  bool _showSearchContent = false;
  Timer? _contentDelay;

  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;
  bool _searching = false;
  bool _hasSearchedOnce = false;

  // A pasted YouTube link is an explicit user pick.
  static final _ytUrlVideo = RegExp(
      r'(?:youtu\.be\/|watch\?v=|shorts\/|embed\/|live\/)([A-Za-z0-9_-]{11})');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _history = storage.getRecentQueries().reversed.toList();
    _searchBar.addListener(() {
      if (mounted) setState(() {});
    });
    // Echo: gaining focus activates search (suggestions below the bar).
    _inputNode.addListener(() {
      if (_inputNode.hasFocus && !_searchActive) _activateSearch();
    });
    _loadExplore();
    _loadLibrary();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchBar.dispose();
    _inputNode.dispose();
    _debounce?.cancel();
    _contentDelay?.cancel();
    _homeService.dispose();
    super.dispose();
  }

  // Echo's lifecycle observer: app paused → keyboard down, focus gone.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      _inputNode.unfocus();
    }
  }

  Future<void> _loadExplore() async {
    try {
      final albums = await _homeService.getNewReleaseAlbums();
      if (!mounted) return;
      setState(() {
        _newAlbums = albums;
        _albumsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _albumsLoading = false);
    }
  }

  Future<void> _loadLibrary() async {
    final liked = storage.getLikedSongs();
    final played = storage.getPlayedHistory();
    final downloads = await DownloadsService().downloadedSongs();
    if (!mounted) return;
    final seen = <String>{};
    final merged = <Song>[];
    for (final s in [...liked, ...downloads, ...played]) {
      if (seen.add(s.id)) merged.add(s);
    }
    setState(() => _librarySongs = merged);
  }

  // ── Echo activation/deactivation ──

  void _activateSearch() {
    if (_searchActive) return;
    setState(() => _searchActive = true);
    // Echo's 100ms delay before the suggestion content appears.
    _contentDelay?.cancel();
    _contentDelay = Timer(const Duration(milliseconds: 100), () {
      if (mounted && _searchActive) {
        setState(() => _showSearchContent = true);
      }
    });
  }

  void _deactivateSearch() {
    _contentDelay?.cancel();
    if (!_searchActive && !_showSearchContent) return;
    setState(() {
      _searchActive = false;
      _showSearchContent = false;
    });
    _inputNode.unfocus();
  }

  Future<void> _submitSearch([String? query]) async {
    if (query != null) {
      _searchBar.text = query;
      _searchBar.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchBar.text.length),
      );
    }
    _latestSuggestionRequest++;
    _debounce?.cancel();
    _suggestions = [];
    _deactivateSearch();
    await _search();
    if (mounted) _inputNode.unfocus();
  }

  bool _tryPlayFromUrl(String query) {
    final m = _ytUrlVideo.firstMatch(query);
    if (m == null) return false;
    unawaited(_playPastedVideo(m.group(1)!));
    return true;
  }

  /// A pasted link is an explicit pick by the user — it plays as AUDIO
  /// in the normal player, and it plays THAT EXACT VIDEO. The real
  /// title and channel are fetched for display, the song is marked
  /// explicit so the source resolver can never substitute a different
  /// catalog song, and playback falls through to the exact video's
  /// audio. Video mode stays available from the player screen as
  /// usual. (Deliberately different from Echo's direct-queue: the
  /// explicit-pick contract is load-bearing here.)
  Future<void> _playPastedVideo(String videoId) async {
    var title = 'YouTube video';
    var artist = '';
    try {
      final uri = Uri.https('www.youtube.com', '/oembed', {
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        title = (data['title'] as String?)?.trim() ?? title;
        artist = ((data['author_name'] as String?) ?? '')
            .replaceAll(RegExp(r'\s*-\s*Topic$'), '')
            .trim();
      }
    } catch (_) {
      // Metadata fetch failed — the placeholder title still plays the
      // exact video's audio below; nothing is substituted either way.
    }
    final song = Song(
      id: videoId,
      title: title,
      artist: artist,
      thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      duration: Duration.zero,
    );
    // The user linked THIS video. Mark it explicit so the resolver
    // returns null for it and the handler streams this exact video's
    // audio — never a fuzzy-matched different song.
    SongSourceResolver.instance.markExplicit(song);
    if (!mounted) return;
    _playWithRadio(song);
  }

  Future<void> _search() async {
    final query = _searchBar.text.trim();
    final requestId = ++_latestSearchRequest;

    if (query.isEmpty) {
      setState(() {
        _songResults = [];
        _videoResults = [];
        _playlistResults = [];
        _albumResults = [];
        _suggestions = [];
        _hasSearchedOnce = false;
      });
      return;
    }

    if (_tryPlayFromUrl(query)) {
      return;
    }

    if (_source == 'library') {
      final q = query.toLowerCase();
      final matches = _librarySongs
          .where((s) =>
      s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q))
          .toList();
      _history
        ..remove(query)
        ..insert(0, query);
      storage.saveQuery(query);
      if (!mounted) return;
      setState(() {
        _songResults = matches;
        _videoResults = [];
        _playlistResults = [];
        _albumResults = [];
        _searching = false;
        _hasSearchedOnce = true;
      });
      return;
    }

    setState(() {
      _searching = true;
      _hasSearchedOnce = true;
    });

    _history
      ..remove(query)
      ..insert(0, query);
    storage.saveQuery(query);
    if (mounted) setState(() {});

    final songsF = _youtube.search(query);
    final ytmF = _ytm.searchSongs(query, limit: 15);
    final videosF = _youtube.search(query, filter: SearchFilter.videos);
    final playlistsF = _jiosaavn.searchPlaylists(query, limit: 8);
    final albumsF = _jiosaavn.searchAlbums(query, limit: 8);

    unawaited(songsF.then((songs) {
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() => _songResults = songs);
    }));

    unawaited(ytmF.then((ytmSongs) {
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() {
        final existing = _songResults.map((s) => s.id).toSet();
        final fresh =
        ytmSongs.where((s) => !existing.contains(s.id)).toList();
        _songResults = [..._songResults, ...fresh];
      });
    }));

    unawaited(videosF.then((videos) {
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() => _videoResults = videos);
    }));

    unawaited(playlistsF.then((playlists) {
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() => _playlistResults = playlists);
    }));

    unawaited(albumsF.then((albums) {
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() => _albumResults = albums);
    }));

    await Future.wait([songsF, ytmF, videosF, playlistsF, albumsF]);
    if (!mounted || requestId != _latestSearchRequest) return;
    setState(() => _searching = false);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value;
    final requestId = ++_latestSuggestionRequest;

    if (query.isEmpty) {
      _suggestions = [];
      if (mounted) setState(() {});
      return;
    }

    if (_source == 'library') {
      if (mounted) setState(() {});
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final songs = await _ytm.searchSongs(query, limit: 8);
      if (!mounted || requestId != _latestSuggestionRequest) return;
      if (_searchBar.text != query) return;
      setState(() => _suggestions = songs.map((s) => s.title).toList());
    });
  }

  void _toggleSource() {
    setState(() => _source = _source == 'online' ? 'library' : 'online');
    if (_source == 'library') {
      _loadLibrary();
      _suggestions = [];
    }
  }

  void _playWithRadio(Song song) {
    audioHandler.startRadio(song);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  /// ZenMusic's long-press actions sheet (stands in for Echo's menu
  /// system until the shared SongMenuSheet round lands).
  void _songActions(Song song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.ondemand_video_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Play with video',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                VideoPreferenceService.instance
                    .setPreferred(song.id, true);
                _playWithRadio(song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Download',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await DownloadsService().download(song);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Downloaded — plays offline'
                        : 'Download failed'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Add to playlist',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                showAddToPlaylistSheet(context, song);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Play next',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                audioHandler.playNext(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playing next: ${song.title}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Add to queue',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                audioHandler.addToQueue(song);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Added to queue'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _openCollection(Collection c) {
    pushSharedAxisY(context, CollectionScreen(collection: c));
  }

  void _clearSearch() {
    _searchBar.clear();
    _latestSearchRequest++;
    setState(() {
      _songResults = [];
      _videoResults = [];
      _playlistResults = [];
      _albumResults = [];
      _searching = false;
      _hasSearchedOnce = false;
    });
  }

  void _removeHistoryItem(String q) {
    setState(() => _history.remove(q));
    storage.clearQueries();
    for (final query in _history.reversed) {
      storage.saveQuery(query);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _songResults.isNotEmpty ||
        _videoResults.isNotEmpty ||
        _playlistResults.isNotEmpty ||
        _albumResults.isNotEmpty;

    return WillPopScope(
      onWillPop: () async {
        // Echo's BackHandler: back while suggesting deactivates the
        // search state; otherwise the pop proceeds.
        if (_searchActive) {
          _deactivateSearch();
          return false;
        }
        return true;
      },
      child: SafeArea(
        child: Column(
          children: [
            // Echo's bar geometry: 16dp horizontal, 8dp top, 16dp
            // below — identical in BOTH states (the pill never
            // morphs to full-bleed).
        Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _echoSearchBar(),
      ),
            const SizedBox(height: 16),
            Expanded(
              child: _searchActive && _showSearchContent
                  ? _quickList()
                  : hasResults
                  ? _resultsView()
                  : (_searching && _hasSearchedOnce
                  ? _skeletonResults()
                  : _idleExplore()),
            ),
          ],
        ),
      ),
    );
  }

  /// Echo's bar: back/search toggle (left) · source-aware field ·
  /// clear + recognize + source toggle (right). Stays a 28-radius
  /// pill in every state.
  Widget _echoSearchBar() {
    final hasText = _searchBar.text.isNotEmpty;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          // Echo: search icon when idle, back arrow when active —
          // back deactivates the search state.
          IconButton(
            onPressed: () {
              if (_searchActive) {
                _deactivateSearch();
                _searchBar.clear();
                _latestSearchRequest++;
                setState(() {
                  _songResults = [];
                  _videoResults = [];
                  _playlistResults = [];
                  _albumResults = [];
                  _searching = false;
                  _hasSearchedOnce = false;
                });
              } else {
                _activateSearch();
                _inputNode.requestFocus();
              }
            },
            icon: Icon(
              _searchActive
                  ? Icons.arrow_back_rounded
                  : Icons.search_rounded,
              color: SpotifyColors.textPrimary,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _searchBar,
              focusNode: _inputNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                  color: SpotifyColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: _source == 'library'
                    ? 'Search your library'
                    : 'Search songs, artists, playlists',
                hintStyle:
                const TextStyle(color: SpotifyColors.textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                prefixIcon: _searching
                    ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child:
                    WaveSpinner(size: 20, strokeWidth: 2.2),
                  ),
                )
                    : null,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
          if (hasText)
            IconButton(
              onPressed: _clearSearch,
              icon: const Icon(Icons.close_rounded,
                  color: SpotifyColors.textSecondary),
            ),
          IconButton(
            onPressed: () =>
                pushSharedAxisY(context, const RecognizeScreen()),
            tooltip: 'Recognize a song',
            icon: const Icon(Icons.graphic_eq_rounded,
                color: SpotifyColors.textSecondary, size: 22),
          ),
          IconButton(
            onPressed: _toggleSource,
            tooltip: _source == 'library'
                ? 'Search online'
                : 'Search your library',
            icon: Icon(
              _source == 'library'
                  ? Icons.library_music_rounded
                  : Icons.public_rounded,
              color: _source == 'library'
                  ? SpotifyColors.green
                  : SpotifyColors.textSecondary,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }

  /// Suggestions / history — shown INLINE below the bar while the
  /// search is active (Echo's LocalSearchScreen/OnlineSearchScreen
  /// slot). Bottom padding clears the floating mini player + nav bar
  /// (extendBody).
  Widget _quickList() {
    if (_source == 'library') {
      final q = _searchBar.text.trim().toLowerCase();
      if (q.isEmpty) {
        return Center(
          child: Text(
            'Search your liked songs, downloads and history',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpotifyColors.textTertiary.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        );
      }
      final matches = _librarySongs
          .where((s) =>
      s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q))
          .take(20)
          .toList();
      if (matches.isEmpty) {
        return Center(
          child: Text(
            'No matches in your library',
            style: TextStyle(
              color: SpotifyColors.textTertiary.withOpacity(0.8),
              fontSize: 14,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 170),
        itemCount: matches.length,
        itemBuilder: (context, i) {
          final song = matches[i];
          return ListTile(
            leading: YoutubeThumbnail(
              videoId: song.id,
              imageUrl: song.thumbnail,
              width: 44,
              height: 44,
              borderRadius: 8,
            ),
            title: Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: SpotifyColors.textPrimary, fontSize: 14)),
            subtitle: Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: SpotifyColors.textSecondary, fontSize: 12)),
            onTap: () => _playWithRadio(song),
            onLongPress: () => _songActions(song),
          );
        },
      );
    }

    final items = _suggestions.isNotEmpty ? _suggestions : _history;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Search for songs, artists, playlists',
          style: TextStyle(
            color: SpotifyColors.textTertiary.withOpacity(0.8),
            fontSize: 14,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 170),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final isSuggestion = _suggestions.isNotEmpty;
        return ListTile(
          leading: Icon(
            isSuggestion ? Icons.trending_up_rounded : Icons.history_rounded,
            size: 20,
            color: SpotifyColors.textTertiary,
          ),
          title: Text(
            items[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 14,
            ),
          ),
          trailing: isSuggestion
              ? const Icon(Icons.north_west_rounded,
              size: 16, color: SpotifyColors.textTertiary)
              : null,
          onTap: () => _submitSearch(items[i]),
          onLongPress: isSuggestion
              ? null
              : () => _removeHistoryItem(items[i]),
        );
      },
    );
  }

  Widget _idleExplore() {
    return ListView(
      // Bottom padding clears the floating mini player + nav bar
      // (extendBody) — closes the blueprint's pending search-padding
      // item.
      padding: const EdgeInsets.only(bottom: 170),
      children: [
        if (_history.isNotEmpty) ...[
          const ShelfHeaderBar(title: 'Recent searches'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in _history.take(10))
                  InputChip(
                    label: Text(q,
                        style: const TextStyle(
                            color: SpotifyColors.textPrimary,
                            fontSize: 12.5)),
                    backgroundColor: SpotifyColors.surface,
                    side: BorderSide(
                        color: Colors.white.withOpacity(0.06)),
                    onPressed: () => _submitSearch(q),
                    onDeleted: () => _removeHistoryItem(q),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        InkWell(
          onTap: () =>
              pushSharedAxisY(context, const NewReleaseScreen()),
          child: const ShelfHeaderBar(title: 'New releases'),
        ),
        if (_albumsLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: WaveSpinner(size: 24)),
          )
        else if (_newAlbums.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Nothing here right now',
              style: TextStyle(
                  color: SpotifyColors.textTertiary.withOpacity(0.8),
                  fontSize: 13),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: _newAlbums.length.clamp(0, 8),
            itemBuilder: (context, i) {
              final album = _newAlbums[i];
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openCollection(album),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: album.imageUrl.isNotEmpty
                            ? Image.network(
                          album.imageUrl,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: SpotifyColors.surfaceLight,
                            child: const Icon(Icons.album_rounded,
                                size: 40,
                                color: SpotifyColors.textTertiary),
                          ),
                        )
                            : Container(
                          color: SpotifyColors.surfaceLight,
                          child: const Icon(Icons.album_rounded,
                              size: 40,
                              color: SpotifyColors.textTertiary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SpotifyColors.textPrimary)),
                    Text(album.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11,
                            color: SpotifyColors.textSecondary)),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _skeletonResults() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 170),
      children: const [
        SkeletonTile(),
        SkeletonTile(),
        SkeletonTile(),
        SkeletonTile(),
        SkeletonTile(),
        SkeletonTile(),
      ],
    );
  }

  Widget _resultsView() {
    return ListView(
      // Bottom padding clears the floating mini player + nav bar
      // (extendBody).
      padding: const EdgeInsets.only(bottom: 170),
      children: [
        if (_songResults.isNotEmpty)
          ThreeTracksRow(
            title: _source == 'library' ? 'In your library' : 'Songs',
            items: [
              for (final s in _songResults.take(20)) ShelfItem.fromSong(s)
            ],
            onTapItem: (i) => _playWithRadio(_songResults[i]),
            onItemLongPress: (i) => _songActions(_songResults[i]),
            playingIdStream: audioHandler.currentSongStream,
          ),
        if (_videoResults.isNotEmpty) ...[
          const ShelfHeaderBar(title: 'Videos'),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              clipBehavior: Clip.none,
              itemCount: _videoResults.length.clamp(0, 15),
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) {
                final video = _videoResults[i];
                return GestureDetector(
                  onTap: () => _playWithRadio(video),
                  onLongPress: () => _songActions(video),
                  child: SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            children: [
                              YoutubeThumbnail(
                                videoId: video.id,
                                imageUrl: video.thumbnail,
                                width: 200,
                                height: 112,
                                borderRadius: 10,
                              ),
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _fmtDuration(video.duration),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          video.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: SpotifyColors.textPrimary,
                          ),
                        ),
                        Text(
                          video.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: SpotifyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_playlistResults.isNotEmpty)
          MediaShelfRow(
            title: 'Playlists',
            items: [
              for (final c in _playlistResults)
                ShelfItem(
                  kind: 'Playlist',
                  id: c.id,
                  title: c.title,
                  subtitle: c.subtitle,
                  coverUrl: c.imageUrl,
                ),
            ],
            onTapItem: (i) => _openCollection(_playlistResults[i]),
          ),
        if (_albumResults.isNotEmpty)
          MediaShelfRow(
            title: 'Albums',
            items: [
              for (final c in _albumResults)
                ShelfItem(
                  kind: 'Album',
                  id: c.id,
                  title: c.title,
                  subtitle: c.subtitle,
                  coverUrl: c.imageUrl,
                ),
            ],
            onTapItem: (i) => _openCollection(_albumResults[i]),
          ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    if (d == Duration.zero) return '';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}