import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:yt_extractor/yt_extractor.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/jiosaavn_service.dart';
import '../services/yt_music_service.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/collection_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/song_row.dart';
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

  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;
  bool _searching = false;
  bool _hasSearchedOnce = false;

  @override
  void initState() {
    super.initState();
    _history = storage.getRecentQueries().reversed.toList();
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

  void _openCollection(Collection c) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CollectionScreen(collection: c)),
    );
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

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _searchBar,
              focusNode: _inputNode,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: SpotifyColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Songs, artists, albums...',
                hintStyle: const TextStyle(
                  color: SpotifyColors.textTertiary,
                ),
                prefixIcon: _searching
                    ? const Padding(
                  padding: EdgeInsets.all(13),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: WaveSpinner(size: 20, strokeWidth: 2.2),
                  ),
                )
                    : const Icon(Icons.search_rounded,
                    color: SpotifyColors.textSecondary),
                suffixIcon: _searchBar.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: SpotifyColors.textSecondary),
                  onPressed: _clearSearch,
                )
                    : null,
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _submitSearch(),
            ),
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

  Widget _resultsView() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_songResults.isNotEmpty) ...[
          _sectionTitle('Songs', Icons.music_note_rounded),
          ...List.generate(
            _songResults.length.clamp(0, 20),
                (i) {
              final song = _songResults[i];
              return SongRow(
                song: song,
                // Radio queue: this song + related songs, not the list.
                onTap: () => _playWithRadio(song),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.playlist_add_rounded,
                    color: SpotifyColors.textSecondary,
                    size: 22,
                  ),
                  onPressed: () {
                    audioHandler.addToQueue(song);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Added to queue'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
        if (_videoResults.isNotEmpty) ...[
          _sectionTitle('Videos', Icons.videocam_rounded),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
        if (_playlistResults.isNotEmpty) ...[
          _sectionTitle('Playlists', Icons.queue_music_rounded),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _playlistResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => CollectionCard(
                collection: _playlistResults[i],
                onTap: () => _openCollection(_playlistResults[i]),
              ),
            ),
          ),
        ],
        if (_albumResults.isNotEmpty) ...[
          _sectionTitle('Albums', Icons.album_rounded),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _albumResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, i) => CollectionCard(
                collection: _albumResults[i],
                onTap: () => _openCollection(_albumResults[i]),
              ),
            ),
          ),
        ],
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

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: SpotifyColors.green),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}