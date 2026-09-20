import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/gradient_background.dart';
import '../widgets/lyrics_preview_card.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/up_next_row.dart';
import '../widgets/video_background.dart';
import '../widgets/youtube_thumbnail.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;
  bool _showVideo = false;
  bool _videoLoading = false;
  String? _videoUrl;
  String? _videoForSongId;

  List<Song> _relatedSongs = [];
  String? _relatedForId;

  final _yt = YoutubeService();

  @override
  void initState() {
    super.initState();
    _loadRelated();
  }

  Future<void> _loadRelated() async {
    final song = audioHandler.currentSong;
    if (song == null) return;
    if (_relatedForId == song.id) return;
    _relatedForId = song.id;
    final related = await audioHandler.getRelatedForUI(song);
    if (!mounted) return;
    setState(() => _relatedSongs = related);
  }

  // ═════════════════════════════════════════════
  // VIDEO TOGGLE
  // ═════════════════════════════════════════════

  Future<void> _toggleVideo(Song song) async {
    if (_showVideo && _videoForSongId == song.id) {
      setState(() => _showVideo = false);
      return;
    }

    if (_videoForSongId == song.id && _videoUrl != null) {
      setState(() => _showVideo = true);
      return;
    }

    setState(() {
      _videoLoading = true;
      _showVideo = true;
    });

    final streamUrl = await _yt.getVideoStreamUrl(song);
    if (!mounted) return;

    if (streamUrl == null) {
      setState(() {
        _videoLoading = false;
        _showVideo = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video not available for this song')),
      );
      return;
    }

    setState(() {
      _videoUrl = streamUrl;
      _videoForSongId = song.id;
      _videoLoading = false;
    });
  }

  // ═════════════════════════════════════════════
  // BUILD
  // ═════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final song = controller.currentSong;
    final handler = audioHandler;

    if (song == null) {
      return const Scaffold(
        backgroundColor: SpotifyColors.background,
        body: Center(child: Text('Nothing playing')),
      );
    }

    if (_videoForSongId != null && _videoForSongId != song.id) {
      _showVideo = false;
      _videoUrl = null;
      _videoForSongId = null;
    }

    _loadRelated();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_showVideo && _videoUrl != null)
            Positioned.fill(
              child: VideoBackground(
                key: ValueKey(_videoUrl),
                videoUrl: _videoUrl!,
                positionStream: handler.positionStream,
                playingStream: handler.playingStream,
              ),
            )
          else if (!_showLyrics)
            Positioned.fill(
              child: GradientBackground(
                imageUrl: song.thumbnail,
                child: const SizedBox.expand(),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
                  ),
                ),
              ),
            ),

          if (_showVideo)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.5),
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.85),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ),

          SafeArea(
            child: _showLyrics
                ? _buildLyricsMode(song, handler)
                : _buildMainMode(song, handler, controller),
          ),

          if (_videoLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: SpotifyColors.green,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLyricsMode(Song song, dynamic handler) {
    return Column(
      children: [
        _topBar(song),
        Expanded(
          child: LyricsView(
            key: ValueKey('lyrics-${song.id}'),
            title: song.title,
            artist: song.artist,
            duration: song.duration,
            positionStream: handler.positionStream,
            onSeek: (pos) => handler.seek(pos),
          ),
        ),
        _miniControls(song, handler),
      ],
    );
  }

  Widget _buildMainMode(Song song, dynamic handler, dynamic controller) {
    return Column(
      children: [
        _topBar(song),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              children: [
                if (!_showVideo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Hero(
                        tag: 'artwork-${song.id}',
                        child: YoutubeThumbnail(
                          videoId: song.id,
                          imageUrl: song.thumbnail,
                          borderRadius: 12,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 340),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: SpotifyColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                color: SpotifyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.add_circle_outline,
                          color: SpotifyColors.textPrimary,
                        ),
                        onPressed: () {
                          handler.addToQueue(song);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Added to queue'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                _SeekBar(handler: handler, song: song),
                const SizedBox(height: 4),
                _PlayerControls(handler: handler, controller: controller),
                const SizedBox(height: 12),
                _smallIconsRow(song, handler),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LyricsPreviewCard(
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration,
                    onShowFull: () => setState(() => _showLyrics = true),
                  ),
                ),
                const SizedBox(height: 28),
                UpNextRow(
                  songs: _relatedSongs,
                  onTap: (s) async {
                    await handler.playNext(s);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Playing next: ${s.title}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(Song song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _showVideo ? 'Video' : 'Playing from Search',
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpotifyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _showVideo ? song.title : 'Recent Searches',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _showVideo ? 'Hide video' : 'Show video',
            icon: Icon(
              _showVideo ? Icons.music_note : Icons.videocam_outlined,
              color: _showVideo
                  ? SpotifyColors.green
                  : SpotifyColors.textPrimary,
            ),
            onPressed: () => _toggleVideo(song),
          ),
        ],
      ),
    );
  }

  Widget _smallIconsRow(Song song, dynamic handler) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.lyrics_outlined,
              color: SpotifyColors.textSecondary,
            ),
            onPressed: () => setState(() => _showLyrics = true),
          ),
          IconButton(
            icon: const Icon(
              Icons.share_outlined,
              color: SpotifyColors.textSecondary,
            ),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(
              Icons.queue_music,
              color: SpotifyColors.textSecondary,
            ),
            onPressed: () => _showQueue(context),
          ),
        ],
      ),
    );
  }

  Widget _miniControls(Song song, dynamic handler) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.image_outlined,
                  color: SpotifyColors.textSecondary,
                ),
                onPressed: () => setState(() => _showLyrics = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous),
                onPressed: () => handler.skipToPrevious(),
              ),
              const SizedBox(width: 16),
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: StreamBuilder<bool>(
                  stream: handler.playingStream,
                  initialData: true,
                  builder: (context, snap) {
                    final playing = snap.data ?? false;
                    return IconButton(
                      iconSize: 32,
                      icon: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                      ),
                      onPressed: () =>
                      playing ? handler.pause() : handler.play(),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next),
                onPressed: () => handler.skipToNext(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQueue(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const QueueSheet(),
    );
  }
}

// ═════════════════════════════════════════════
// SEEK BAR
// ═════════════════════════════════════════════

class _SeekBar extends StatelessWidget {
  final dynamic handler;
  final dynamic song;

  const _SeekBar({required this.handler, required this.song});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? song.duration;
            final maxSec = duration.inSeconds.toDouble();
            final maxValue = maxSec > 0 ? maxSec : 1.0;
            final value =
            position.inSeconds.toDouble().clamp(0.0, maxValue).toDouble();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Slider(
                    min: 0,
                    max: maxValue,
                    value: value,
                    onChanged: (v) =>
                        handler.seek(Duration(seconds: v.toInt())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(position),
                          style: const TextStyle(
                            fontSize: 11,
                            color: SpotifyColors.textSecondary,
                          ),
                        ),
                        Text(
                          _fmt(duration),
                          style: const TextStyle(
                            fontSize: 11,
                            color: SpotifyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ═════════════════════════════════════════════
// PLAYER CONTROLS
// ═════════════════════════════════════════════

class _PlayerControls extends StatelessWidget {
  final dynamic handler;
  final dynamic controller;

  const _PlayerControls({required this.handler, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            iconSize: 28,
            icon: const Icon(Icons.shuffle, color: SpotifyColors.green),
            onPressed: () {
              handler.setShuffleMode(AudioServiceShuffleMode.all);
            },
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_previous),
            onPressed: () => handler.skipToPrevious(),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 42,
              icon: Icon(
                controller.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.black,
              ),
              onPressed: () =>
              controller.isPlaying ? handler.pause() : handler.play(),
            ),
          ),
          IconButton(
            iconSize: 40,
            icon: const Icon(Icons.skip_next),
            onPressed: () => handler.skipToNext(),
          ),
          IconButton(
            iconSize: 28,
            icon: const Icon(
              Icons.timer_outlined,
              color: SpotifyColors.textSecondary,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}