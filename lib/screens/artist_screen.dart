import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/yt_music_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

/// Artist page (Spotify-style): header built from the artist's top
/// track artwork, real YouTube-ranked top songs, play-all + shuffle.
/// Powered by the verified YTM endpoints (searchArtistIds +
/// getArtistTopSongs).
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key, required this.artistName});

  final String artistName;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final _ytm = YtMusicService();

  List<Song> _topSongs = [];
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      final ids = await _ytm.searchArtistIds(widget.artistName, limit: 1);
      if (ids.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }
      final songs = await _ytm.getArtistTopSongs(ids.first, limit: 25);
      if (!mounted) return;
      setState(() {
        _topSongs = songs;
        _loading = false;
        _notFound = songs.isEmpty;
      });
    } catch (e) {
      print('ArtistScreen load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_topSongs.isEmpty) return;
    final queue = List<Song>.from(_topSongs);
    if (shuffle) queue.shuffle();
    audioHandler.setQueue(queue, startIndex: 0);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  String get _displayName =>
      widget.artistName.split(',').first.trim().isNotEmpty
          ? widget.artistName
          : 'Artist';

  String? get _headerImage =>
      _topSongs.isEmpty ? null : _topSongs.first.thumbnail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: _loading
          ? const Center(child: WaveSpinner(size: 26))
          : _notFound
          ? _errorView()
          : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _header(),
          _actions(),
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
          const Icon(
            FluentIcons.person_24_regular,
            size: 44,
            color: SpotifyColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'Artist page unavailable for "${widget.artistName}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpotifyColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _header() {
    final image = _headerImage;
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 300,
          child: image == null || image.isEmpty
              ? Container(color: SpotifyColors.surface)
              : CachedNetworkImage(
            imageUrl: image,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: (_, __) =>
                Container(color: SpotifyColors.surface),
            errorWidget: (_, __, ___) =>
                Container(color: SpotifyColors.surface),
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
        Positioned(
          left: 20,
          right: 20,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ARTIST',
                style: TextStyle(
                  color: SpotifyColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              if (_topSongs.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${_topSongs.length} top songs · YouTube Music',
                  style: const TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    final disabled = _topSongs.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color:
              disabled ? SpotifyColors.surfaceLight : SpotifyColors.green,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: disabled ? null : () => _playAll(),
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
                        disabled ? 'Play' : 'Play top songs',
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
              onTap: disabled ? null : () => _playAll(shuffle: true),
              child: SizedBox(
                height: 48,
                width: 48,
                child: Icon(
                  Icons.shuffle_rounded,
                  size: 22,
                  color: disabled
                      ? SpotifyColors.textTertiary
                      : SpotifyColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackList() {
    final currentId = audioHandler.currentSong?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < _topSongs.length; i++)
            _ArtistTrackTile(
              index: i + 1,
              song: _topSongs[i],
              isCurrent: currentId == _topSongs[i].id,
              onTap: () async {
                await audioHandler.setQueue(
                    List<Song>.from(_topSongs),
                    startIndex: i);
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlayerScreen()),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ArtistTrackTile extends StatelessWidget {
  final int index;
  final Song song;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ArtistTrackTile({
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            Stack(
              children: [
                YoutubeThumbnail(
                  videoId: song.id,
                  imageUrl: song.thumbnail,
                  width: 48,
                  height: 48,
                  borderRadius: 6,
                ),
                if (isCurrent)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded,
                          size: 20, color: SpotifyColors.green),
                    ),
                  ),
              ],
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
                    style: TextStyle(
                      color: isCurrent
                          ? SpotifyColors.green
                          : SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
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
              ),
            ),
            if (song.duration.inSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _fmt(song.duration),
                  style: const TextStyle(
                    color: SpotifyColors.textTertiary,
                    fontSize: 12,
                  ),
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
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}