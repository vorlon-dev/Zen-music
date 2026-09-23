import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/jiosaavn_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/media_shelf.dart';
import '../widgets/wave_spinner.dart';
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

  void _shufflePlay() {
    if (_songs.isEmpty) return;
    final shuffled = List<Song>.from(_songs)..shuffle();
    audioHandler.setQueue(shuffled, startIndex: 0);
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
          ? const Center(child: WaveSpinner(size: 26))
          : _error != null
          ? _errorView()
          : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _header(),
          _playButtons(),
          _trackList(),
        ],
      ),
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
          TextButton(
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

  Widget _header() {
    final c = widget.collection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Row(
            children: [
              BackButton(color: SpotifyColors.textPrimary),
              const Spacer(),
            ],
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 190,
                height: 190,
                child: c.imageUrl.isEmpty
                    ? Container(
                  color: SpotifyColors.surfaceLight,
                  child: Icon(
                    c.isAlbum
                        ? Icons.album_rounded
                        : Icons.queue_music_rounded,
                    size: 56,
                    color: SpotifyColors.textTertiary,
                  ),
                )
                    : CachedNetworkImage(
                  imageUrl: c.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: SpotifyColors.surfaceLight),
                  errorWidget: (_, __, ___) => Container(
                    color: SpotifyColors.surfaceLight,
                    child: const Icon(
                      Icons.album_rounded,
                      size: 56,
                      color: SpotifyColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.isAlbum ? 'ALBUM' : 'PLAYLIST',
                style: const TextStyle(
                  color: SpotifyColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.title,
                style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              if (c.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  c.subtitle,
                  style: TextStyle(
                    color: SpotifyColors.textSecondary.withOpacity(0.66),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _playButtons() {
    final disabled = _songs.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: disabled ? SpotifyColors.surfaceLight : SpotifyColors.green,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: disabled ? null : () => _openPlayer(0),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          color: disabled
                              ? SpotifyColors.textTertiary
                              : Colors.black,
                          size: 26),
                      const SizedBox(width: 6),
                      Text(
                        disabled
                            ? 'Play'
                            : 'Play ${_songs.length} tracks',
                        style: TextStyle(
                          color: disabled
                              ? SpotifyColors.textTertiary
                              : Colors.black,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: disabled ? null : _shufflePlay,
              child: const SizedBox(
                height: 48,
                width: 48,
                child: Icon(
                  Icons.shuffle_rounded,
                  size: 22,
                  color: SpotifyColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < _songs.length; i++)
            _SongTile(
              index: i + 1,
              song: _songs[i],
              onTap: () => _openPlayer(i),
            ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.index,
    required this.song,
    required this.onTap,
  });

  final int index;
  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: audioHandler.currentSongStream,
      builder: (context, snap) {
        final playing = snap.data?.id == song.id &&
            snap.data?.title == song.title;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: SpotifyColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ),
                ShelfCover(
                  item: ShelfItem.fromSong(song),
                  isPlaying: playing,
                  songMode: true,
                  songVideoId: song.id,
                  size: 48,
                  borderRadius: 6,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (song.artist.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SpotifyColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: SpotifyColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}