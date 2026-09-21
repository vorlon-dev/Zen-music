import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/current_lyric_line.dart';
import '../widgets/gradient_background.dart';
import '../widgets/lyrics_preview_card.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/up_next_row.dart';
import '../widgets/youtube_embed.dart';
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
  String? _videoId;
  String? _videoForSongId;

  List<Song> _relatedSongs = [];
  String? _relatedForId;
  bool _lyricsSynced = false;

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

  Future<void> _toggleVideo(Song song) async {
    if (_showVideo && _videoForSongId == song.id) {
      setState(() => _showVideo = false);
      return;
    }

    if (_videoForSongId == song.id && _videoId != null) {
      setState(() => _showVideo = true);
      return;
    }

    setState(() {
      _videoLoading = true;
      _showVideo = true;
    });

    final id = await _yt.getVideoId(song);
    if (!mounted) return;

    if (id == null) {
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
      _videoId = id;
      _videoForSongId = song.id;
      _videoLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final song = controller.currentSong;
    final handler = audioHandler;

    if (song == null) {
      return const Scaffold(
        backgroundColor: SpotifyColors.background,
        body: Center(
          child: Text(
            'Nothing playing',
            style: TextStyle(color: SpotifyColors.textSecondary),
          ),
        ),
      );
    }

    if (_videoForSongId != null && _videoForSongId != song.id) {
      _showVideo = false;
      _videoId = null;
      _videoForSongId = null;
    }

    if (_relatedForId != song.id) {
      _lyricsSynced = false;
    }

    _loadRelated();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_showVideo && _videoId != null)
            Positioned.fill(
              child: YouTubeEmbed(
                key: ValueKey(_videoId),
                videoId: _videoId!,
              ),
            )
          else
          // Same album-art-derived colour wash behind both the main
          // artwork view and the lyrics view — this is what makes the
          // lyrics screen feel like part of the same "now playing"
          // surface instead of a plain dark page bolted on.
            Positioned.fill(
              child: GradientBackground(
                imageUrl: song.thumbnail,
                child: const SizedBox.expand(),
              ),
            ),

          // Lyrics mode gets its own darkening scrim on top of the colour
          // wash so the large lyric text stays legible against busy or
          // bright artwork, without flattening the colour to plain gray.
          if (_showLyrics && !_showVideo)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(0.35),
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
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: SpotifyColors.green,
                      strokeWidth: 2.5,
                    ),
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
            songId: song.id,
            title: song.title,
            artist: song.artist,
            imageUrl: song.thumbnail,
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
                    padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Hero(
                        tag: 'artwork-${song.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: YoutubeThumbnail(
                              videoId: song.id,
                              imageUrl: song.thumbnail,
                              borderRadius: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 340),

                if (!_showVideo)
                  CurrentLyricLine(
                    title: song.title,
                    artist: song.artist,
                    duration: song.duration,
                    positionStream: handler.positionStream,
                    onTap: () => setState(() => _showLyrics = true),
                    onSyncStatus: (synced) {
                      if (mounted && synced != _lyricsSynced) {
                        setState(() => _lyricsSynced = synced);
                      }
                    },
                  ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    song.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: SpotifyColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (_lyricsSynced) ...[
                                  const SizedBox(width: 10),
                                  Tooltip(
                                    message: 'Synced lyrics available',
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: const BoxDecoration(
                                        color: SpotifyColors.green,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: SpotifyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 26,
                        splashRadius: 22,
                        icon: const Icon(
                          Icons.playlist_add_rounded,
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

                const SizedBox(height: 16),
                _SeekBar(handler: handler, song: song),
                const SizedBox(height: 4),
                _PlayerControls(handler: handler, controller: controller),
                const SizedBox(height: 16),
                _smallIconsRow(song, handler),
                const SizedBox(height: 28),
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
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.expand_more_rounded,
              size: 30,
              color: SpotifyColors.textPrimary,
            ),
            splashRadius: 22,
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  _showVideo ? 'PLAYING VIDEO' : 'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: SpotifyColors.textSecondary.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _showVideo ? 'Show cover art' : 'Show video',
            splashRadius: 22,
            icon: Icon(
              _showVideo ? Icons.album_rounded : Icons.videocam_outlined,
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
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              Icons.lyrics_outlined,
              color: SpotifyColors.textSecondary,
              size: 22,
            ),
            onPressed: () => setState(() => _showLyrics = true),
          ),
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              Icons.share_outlined,
              color: SpotifyColors.textSecondary,
              size: 22,
            ),
            onPressed: () {},
          ),
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              Icons.queue_music_rounded,
              color: SpotifyColors.textSecondary,
              size: 24,
            ),
            onPressed: () => _showQueue(context),
          ),
        ],
      ),
    );
  }

  Widget _miniControls(Song song, dynamic handler) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              splashRadius: 20,
              icon: const Icon(
                Icons.album_outlined,
                color: SpotifyColors.textSecondary,
                size: 22,
              ),
              tooltip: 'Show cover art',
              onPressed: () => setState(() => _showLyrics = false),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: SpotifyColors.textPrimary,
                ),
                onPressed: () => handler.skipToPrevious(),
              ),
              const SizedBox(width: 12),
              Container(
                width: 52,
                height: 52,
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
                      iconSize: 28,
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                      ),
                      onPressed: () =>
                      playing ? handler.pause() : handler.play(),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 32,
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: SpotifyColors.textPrimary,
                ),
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
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: SpotifyColors.textPrimary,
                      inactiveTrackColor:
                      SpotifyColors.textTertiary.withOpacity(0.3),
                      thumbColor: SpotifyColors.textPrimary,
                      thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                      overlayColor: Colors.white.withOpacity(0.12),
                    ),
                    child: Slider(
                      min: 0,
                      max: maxValue,
                      value: value,
                      onChanged: (v) =>
                          handler.seek(Duration(seconds: v.toInt())),
                    ),
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

class _PlayerControls extends StatefulWidget {
  final dynamic handler;
  final dynamic controller;

  const _PlayerControls({required this.handler, required this.controller});

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
  bool _shuffleOn = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  void _toggleShuffle() {
    setState(() => _shuffleOn = !_shuffleOn);
    widget.handler.setShuffleMode(
      _shuffleOn ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  void _cycleRepeat() {
    final next = switch (_repeatMode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };
    setState(() => _repeatMode = next);
    widget.handler.setRepeatMode(next);
  }

  @override
  Widget build(BuildContext context) {
    final handler = widget.handler;
    final controller = widget.controller;
    final repeatOn = _repeatMode != AudioServiceRepeatMode.none;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            iconSize: 22,
            splashRadius: 20,
            icon: Icon(
              Icons.shuffle_rounded,
              color: _shuffleOn
                  ? SpotifyColors.green
                  : SpotifyColors.textSecondary,
            ),
            onPressed: _toggleShuffle,
          ),
          IconButton(
            iconSize: 38,
            splashRadius: 26,
            icon: const Icon(
              Icons.skip_previous_rounded,
              color: SpotifyColors.textPrimary,
            ),
            onPressed: () => handler.skipToPrevious(),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 38,
              icon: Icon(
                controller.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.black,
              ),
              onPressed: () =>
              controller.isPlaying ? handler.pause() : handler.play(),
            ),
          ),
          IconButton(
            iconSize: 38,
            splashRadius: 26,
            icon: const Icon(
              Icons.skip_next_rounded,
              color: SpotifyColors.textPrimary,
            ),
            onPressed: () => handler.skipToNext(),
          ),
          IconButton(
            iconSize: 22,
            splashRadius: 20,
            icon: Icon(
              _repeatMode == AudioServiceRepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: repeatOn
                  ? SpotifyColors.green
                  : SpotifyColors.textSecondary,
            ),
            onPressed: _cycleRepeat,
          ),
        ],
      ),
    );
  }
}