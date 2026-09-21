import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/jiosaavn_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/song_row.dart';
import 'player_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.collection});

  final Collection collection;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final _jiosaavn = JiosaavnService();

  List<Song> _songs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = widget.collection.isAlbum
          ? await _jiosaavn.getAlbum(widget.collection.id)
          : await _jiosaavn.getPlaylist(widget.collection.id);
      if (!mounted) return;
      setState(() {
        _songs = detail?.songs ?? [];
        _loading = false;
        _error = _songs.isEmpty ? 'No songs found' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load';
      });
    }
  }

  void _openPlayer(int index) {
    audioHandler.setQueue(_songs, startIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: _loading
          ? const Center(
          child:
          CircularProgressIndicator(color: SpotifyColors.green))
          : _error != null
          ? _errorView()
          : CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, i) => SongRow(
                  song: _songs[i],
                  onTap: () => _openPlayer(i),
                ),
                childCount: _songs.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 300,
              child: widget.collection.imageUrl.isEmpty
                  ? Container(color: SpotifyColors.surface)
                  : CachedNetworkImage(
                imageUrl: widget.collection.imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      SpotifyColors.background.withOpacity(0.55),
                      SpotifyColors.background,
                    ],
                    stops: const [0.35, 0.7, 1.0],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: SpotifyColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.collection.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: SpotifyColors.textPrimary,
                ),
              ),
              if (widget.collection.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.collection.subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SpotifyColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: SpotifyColors.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                    ),
                    onPressed: _songs.isEmpty ? null : () => _openPlayer(0),
                    icon: const Icon(Icons.play_arrow_rounded, size: 26),
                    label: const Text('Play',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    onPressed: _songs.isEmpty
                        ? null
                        : () => _openPlayer(
                        DateTime.now().millisecond % _songs.length),
                    icon: const Icon(Icons.shuffle_rounded,
                        color: SpotifyColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!,
              style: const TextStyle(
                  color: SpotifyColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 16),
          FilledButton(
            style:
            FilledButton.styleFrom(backgroundColor: SpotifyColors.green),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}