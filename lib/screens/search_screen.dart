import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yt_extractor/yt_extractor.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _yt = YoutubeService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<Song> _results = [];
  List<String> _recentQueries = [];
  bool _loading = false;
  bool _hasSearched = false;
  SearchFilter _filter = SearchFilter.musicSongs;

  static const _filters = <SearchFilter, String>{
    SearchFilter.musicSongs: 'Songs',
    SearchFilter.videos: 'Videos',
    SearchFilter.musicVideos: 'Music videos',
    SearchFilter.all: 'All',
  };

  @override
  void initState() {
    super.initState();
    _recentQueries = storage.getRecentQueries();
    _focusNode.addListener(() => setState(() {}));
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  Future<void> _search([String? query]) async {
    final q = (query ?? _controller.text).trim();
    if (q.isEmpty) return;

    _controller.text = q;
    await storage.saveQuery(q);

    setState(() {
      _loading = true;
      _hasSearched = true;
    });
    try {
      final res = await _yt.search(q, filter: _filter);
      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
        _recentQueries = storage.getRecentQueries();
      });
      for (final s in res) {
        if (s.thumbnail.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(s.thumbnail), context);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Search failed: $e')));
    }
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _results = [];
      _hasSearched = false;
    });
  }

  Future<void> _playSong(Song song) async {
    try {
      await audioHandler.startRadio(song);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Playback failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _searchField(),
          _filterTabs(),
          const SizedBox(height: 4),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _searchField() {
    final hasText = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(
          color: SpotifyColors.textPrimary,
          fontSize: 15,
        ),
        cursorColor: SpotifyColors.textPrimary,
        decoration: InputDecoration(
          hintText: 'What do you want to listen to?',
          hintStyle: TextStyle(
            color: SpotifyColors.textSecondary.withOpacity(0.9),
            fontSize: 15,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: SpotifyColors.textSecondary,
            size: 22,
          ),
          suffixIcon: hasText
              ? IconButton(
            splashRadius: 18,
            icon: const Icon(
              Icons.close_rounded,
              color: SpotifyColors.textSecondary,
              size: 20,
            ),
            onPressed: _clear,
          )
              : null,
          filled: true,
          fillColor: SpotifyColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: SpotifyColors.textPrimary.withOpacity(0.4),
              width: 1,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _search(),
      ),
    );
  }

  // Understated underline tabs, same treatment as the home screen filters —
  // keeps the green accent reserved for whichever one is actually selected.
  Widget _filterTabs() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: _filters.entries.map((e) {
          final selected = _filter == e.key;
          return Padding(
            padding: const EdgeInsets.only(right: 22),
            child: InkWell(
              onTap: () {
                setState(() => _filter = e.key);
                if (_controller.text.trim().isNotEmpty) _search();
              },
              borderRadius: BorderRadius.circular(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? SpotifyColors.textPrimary
                          : SpotifyColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 2,
                    width: 14,
                    color: selected ? SpotifyColors.green : Colors.transparent,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: SpotifyColors.green,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return _beforeSearchView();
    }

    if (_results.isEmpty) {
      return _noResultsView();
    }

    return _resultsList();
  }

  Widget _beforeSearchView() {
    if (_recentQueries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 40,
                color: SpotifyColors.textTertiary.withOpacity(0.5),
              ),
              const SizedBox(height: 12),
              const Text(
                'Search to find songs and videos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SpotifyColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Recent searches',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ),
        ..._recentQueries.map((q) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _search(q),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: SpotifyColors.textTertiary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    q,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
                Icon(
                  Icons.north_west_rounded,
                  size: 16,
                  color: SpotifyColors.textTertiary.withOpacity(0.7),
                ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _noResultsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: SpotifyColors.textTertiary.withOpacity(0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "${_controller.text.trim()}"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different search or filter',
              style: TextStyle(
                color: SpotifyColors.textTertiary.withOpacity(0.85),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final s = _results[i];
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _playSong(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                YoutubeThumbnail(
                  videoId: s.id,
                  imageUrl: s.thumbnail,
                  width: 52,
                  height: 52,
                  borderRadius: 6,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        s.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.play_circle_outline_rounded,
                  size: 22,
                  color: SpotifyColors.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _yt.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}