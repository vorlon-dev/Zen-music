import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:yt_extractor/yt_extractor.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _yt = YoutubeService();
  final _controller = TextEditingController();
  List<Song> _results = [];
  bool _loading = false;
  SearchFilter _filter = SearchFilter.musicSongs;

  static const _filters = <SearchFilter, String>{
    SearchFilter.musicSongs: 'Songs',
    SearchFilter.videos: 'Videos',
    SearchFilter.musicVideos: 'Music Videos',
    SearchFilter.all: 'All',
  };

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;

    // Save query to history
    await storage.saveQuery(q);

    setState(() => _loading = true);
    try {
      final res = await _yt.search(q, filter: _filter);
      if (!mounted) return;
      setState(() {
        _results = res;
        _loading = false;
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: SpotifyColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'What do you want to listen to?',
                hintStyle: const TextStyle(color: SpotifyColors.textSecondary),
                prefixIcon: const Icon(Icons.search,
                    color: SpotifyColors.textSecondary),
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _filters.entries.map((e) {
                final selected = _filter == e.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _filter = e.key);
                      if (_controller.text.trim().isNotEmpty) _search();
                    },
                    backgroundColor: SpotifyColors.surfaceLight,
                    selectedColor: SpotifyColors.green,
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.black
                          : SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                child:
                CircularProgressIndicator(color: SpotifyColors.green))
                : _results.isEmpty
                ? const Center(
              child: Text(
                'Search to find songs and videos',
                style:
                TextStyle(color: SpotifyColors.textSecondary),
              ),
            )
                : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final s = _results[i];
                return ListTile(
                  leading: YoutubeThumbnail(
                    videoId: s.id,
                    imageUrl: s.thumbnail,
                    width: 56,
                    height: 56,
                    borderRadius: 6,
                  ),
                  title: Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    s.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpotifyColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () async {
                    try {
                      await audioHandler.startRadio(s);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Playback failed: $e')),
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _yt.dispose();
    _controller.dispose();
    super.dispose();
  }
}