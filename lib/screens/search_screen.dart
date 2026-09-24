import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:yt_extractor/yt_extractor.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/downloads_service.dart';
import '../services/jiosaavn_service.dart';
import '../services/yt_music_service.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/media_shelf.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/skeleton.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/youtube_thumbnail.dart';
import 'collection_screen.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchBar = TextEditingController();
  final _inputNode = FocusNode();
  final _ytm = YtMusicService();
  final _jiosaavn = JiosaavnService();
  final _youtube = YoutubeService();

  List<Song> _songResults = [];
  List<Song> _videoResults = [];
  List<Collection> _playlistResults = [];
  List<Collection> _albumResults = [];
  List<String> _suggestions = [];
  List<String> _history = [];

  // Echo quick-search overlay: true while the full-screen search view
  // is expanded over the results.
  bool _expanded = false;

  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;
  bool _searching = false;
  bool _hasSearchedOnce = false;

  @override
  void initState() {
    super.initState();
    _history = storage.getRecentQueries().reversed.toList();
    _searchBar.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchBar.dispose();
    _inputNode.dispose();
    _debounce?.cancel();
    super.dispose();
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
    if (_expanded && mounted) setState(() => _expanded = false);
    await _search();
    if (mounted) _inputNode.unfocus();
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

    setState(() {
      _searching = true;
      _hasSearchedOnce = true;
    });

    _history
      ..remove(query)
      ..insert(0, query);
    storage.saveQuery(query);
    if (mounted) setState(() {});

    // Five sources in parallel; each publishes as it lands.
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

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final songs = await _ytm.searchSongs(query, limit: 8);
      if (!mounted || requestId != _latestSuggestionRequest) return;
      if (_searchBar.text != query) return;
      setState(() => _suggestions = songs.map((s) => s.title).toList());
    });
  }

  /// Plays the tapped song and builds a RADIO queue of related songs
  /// (YTM automix → related streams → filtered search) — like the
  /// radio system in YT Music / Spotify. NOT the search-result list.
  void _playWithRadio(Song song) {
    audioHandler.startRadio(song);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  /// Echo's long-click more-menu: download, playlist, queue actions.
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

  @override
  Widget build(BuildContext context) {
    final hasResults = _songResults.isNotEmpty ||
        _videoResults.isNotEmpty ||
        _playlistResults.isNotEmpty ||
        _albumResults.isNotEmpty;

    return WillPopScope(
      onWillPop: () async {
        if (_expanded) {
          setState(() => _expanded = false);
          _inputNode.unfocus();
          return false;
        }
        return true;
      },
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: _searchBarView(expanded: false),
                ),
                Expanded(
                  child: hasResults
                      ? _resultsView()
                      : (_searching && _hasSearchedOnce
                      ? _skeletonResults()
                      : _idleView()),
                ),
              ],
            ),
          ),
          if (_expanded) _quickSearchOverlay(),
        ],
      ),
    );
  }

  // ── Echo M3 search bar (56dp, full-rounded, surface fill) ──

  Widget _searchBarView({required bool expanded}) {
    final hasText = _searchBar.text.isNotEmpty;
    return GestureDetector(
      onTap: expanded
          ? null
          : () {
        setState(() => _expanded = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputNode.requestFocus();
        });
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: SpotifyColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          children: [
            if (expanded)
              IconButton(
                onPressed: () {
                  setState(() => _expanded = false);
                  _inputNode.unfocus();
                },
                icon: const Icon(Icons.arrow_back_rounded,
                    color: SpotifyColors.textPrimary),
              )
            else
              const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(Icons.search_rounded,
                    size: 24, color: SpotifyColors.textSecondary),
              ),
            Expanded(
              child: TextField(
                controller: _searchBar,
                focusNode: _inputNode,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                    color: SpotifyColors.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Songs, artists, albums...',
                  hintStyle:
                  const TextStyle(color: SpotifyColors.textTertiary),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
          ],
        ),
      ),
    );
  }

  // ── Echo quick-search overlay (suggestions + history) ──

  Widget _quickSearchOverlay() {
    return Positioned.fill(
      child: Material(
        color: SpotifyColors.background,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: _searchBarView(expanded: true),
              ),
              Expanded(child: _quickList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickList() {
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
      padding: const EdgeInsets.only(top: 4),
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
              : () {
            setState(() => _history.remove(items[i]));
            storage.clearQueries();
            for (final q in _history.reversed) {
              storage.saveQuery(q);
            }
          },
        );
      },
    );
  }

  Widget _skeletonResults() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 24),
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

  Widget _idleView() {
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

  Widget _resultsView() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_songResults.isNotEmpty)
          ThreeTracksRow(
            title: 'Songs',
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
                  // Radio from the video: video's audio + related queue.
                  onTap: () => _playWithRadio(video),
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