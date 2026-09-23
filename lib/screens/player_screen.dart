import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/wave_spinner.dart';
import '../main.dart';
import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/current_lyric_line.dart';
import '../widgets/gradient_background.dart';
import '../widgets/lyrics_preview_card.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/marquee_text.dart';
import '../widgets/queue_sheet.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/spinner.dart';
import '../widgets/up_next_row.dart';
import '../widgets/video_backdrop.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;

  // Video state (extracted stream, Canvas loop).
  bool _showVideo = false;
  bool _videoLoading = false;
  String? _videoUrl;
  Map<String, String> _videoHeaders = const {};
  String? _videoForSongId;
  String? _resolvingFor;
  bool _videoTriedSd = false;

  List<Song> _relatedSongs = [];
  String? _relatedForId;
  bool _lyricsSynced = false;

  StreamSubscription<Song?>? _songSub;

  final _yt = YoutubeService();

  @override
  void initState() {
    super.initState();
    _loadRelated();

    _songSub = audioHandler.currentSongStream.listen((song) {
      if (!mounted || song == null) return;
      if (_lyricsSynced) setState(() => _lyricsSynced = false);
      _loadRelated();
      if (_showVideo) _resolveVideoFor(song);
    });
  }

  @override
  void dispose() {
    _songSub?.cancel();
    super.dispose();
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
    if (_showVideo) {
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

    await _resolveVideoFor(song, userInitiated: true);

    if (!mounted) return;
    setState(() => _videoLoading = false);
  }

  Future<void> _resolveVideoFor(
      Song song, {
        bool userInitiated = false,
        bool preferHd = true,
      }) async {
    if (_videoForSongId == song.id && _videoUrl != null) return;
    if (_resolvingFor == song.id) return;
    _resolvingFor = song.id;

    if (_videoForSongId != song.id && preferHd) {
      _videoTriedSd = false;
    }

    final result = await _yt.getVideoStreamUrl(song, preferHd: preferHd);

    if (!mounted) {
      _resolvingFor = null;
      return;
    }
    _resolvingFor = null;

    final current = audioHandler.currentSong;
    if (current == null || current.id != song.id) return;

    if (result == null || result.url.isEmpty) {
      setState(() {
        _showVideo = false;
        _videoUrl = null;
        _videoHeaders = const {};
        _videoForSongId = null;
      });
      if (userInitiated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video not available for this song')),
        );
      }
      return;
    }

    setState(() {
      _videoUrl = result.url;
      _videoHeaders = result.headers;
      _videoForSongId = song.id;
    });
  }

  void _onVideoUnavailable(String reason) {
    if (!mounted) return;

    if (!_videoTriedSd) {
      _videoTriedSd = true;
      final song = audioHandler.currentSong;
      if (song != null && _showVideo) {
        print('🔁 Video: HD failed ($reason) — retrying SD');
        setState(() {
          _videoUrl = null;
          _videoHeaders = const {};
          _videoForSongId = null;
          _videoLoading = true;
        });
        _resolveVideoFor(song, preferHd: false).then((_) {
          if (mounted) setState(() => _videoLoading = false);
        });
        return;
      }
    }

    setState(() {
      _showVideo = false;
      _videoUrl = null;
      _videoHeaders = const {};
      _videoForSongId = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Video unavailable for this song')),
    );
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

    if (_relatedForId != song.id) {
      _lyricsSynced = false;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_showVideo && _videoUrl != null)
            Positioned.fill(
              child: VideoBackdrop(
                streamUrl: _videoUrl!,
                playing: controller.isPlaying,
                httpHeaders: _videoHeaders,
                onUnavailable: _onVideoUnavailable,
              ),
            )
          else
            Positioned.fill(
              child: GradientBackground(
                imageUrl: song.thumbnail,
                child: const SizedBox.expand(),
              ),
            ),

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
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: WaveSpinner(size: 26)),
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
                                  child: MarqueeText(
                                    text: song.title,
                                    style: const TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: SpotifyColors.textPrimary,
                                    ),
                                  ),
                                ),
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
                            // ── Quality/type badge ──
                            const SizedBox(height: 6),
                            StreamBuilder<Map<String, String?>>(
                              stream: audioHandler.audioQualityStream,
                              builder: (context, snap) {
                                final type = snap.data?['type'];
                                final bitrate = snap.data?['bitrate'];
                                if (type == null || type.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color:
                                    SpotifyColors.green.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${type.toUpperCase()}'
                                        '${bitrate != null && bitrate.isNotEmpty ? ' · $bitrate kbps' : ''}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: SpotifyColors.green),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        iconSize: 26,
                        splashRadius: 22,
                        icon: Icon(
                          storage.isLiked(song.id)
                              ? FluentIcons.heart_24_filled
                              : FluentIcons.heart_24_regular,
                          color: storage.isLiked(song.id)
                              ? SpotifyColors.green
                              : SpotifyColors.textPrimary,
                        ),
                        tooltip: storage.isLiked(song.id) ? 'Unlike' : 'Like',
                        onPressed: () async {
                          await storage.setLiked(
                              song, !storage.isLiked(song.id));
                          if (mounted) setState(() {});
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
              _showVideo
                  ? FluentIcons.album_24_regular
                  : FluentIcons.video_24_regular,
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
          const SleepTimerButton(),
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              FluentIcons.text_quote_24_regular,
              color: SpotifyColors.textSecondary,
              size: 22,
            ),
            onPressed: () => setState(() => _showLyrics = true),
          ),
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              FluentIcons.share_24_regular,
              color: SpotifyColors.textSecondary,
              size: 22,
            ),
            onPressed: () {},
          ),
          IconButton(
            splashRadius: 20,
            icon: const Icon(
              FluentIcons.apps_list_24_filled,
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
                FluentIcons.album_24_regular,
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
                  FluentIcons.previous_24_regular,
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
                            ? FluentIcons.pause_24_regular
                            : FluentIcons.play_24_regular,
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
                  FluentIcons.next_24_regular,
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

class _SeekBar extends StatefulWidget {
  final dynamic handler;
  final dynamic song;

  const _SeekBar({required this.handler, required this.song});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final handler = widget.handler;

    return StreamBuilder<Duration>(
      stream: handler.positionStream,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: handler.durationStream,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? widget.song.duration;
            final maxSec = duration.inSeconds.toDouble();
            final maxValue = maxSec > 0 ? maxSec : 1.0;
            final streamValue =
            position.inSeconds.toDouble().clamp(0.0, maxValue).toDouble();
            final value =
            (_dragValue ?? streamValue).clamp(0.0, maxValue).toDouble();

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
                      onChangeStart: (v) => setState(() => _dragValue = v),
                      onChanged: (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        handler.seek(Duration(seconds: v.toInt()));
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(_dragValue != null
                              ? Duration(seconds: _dragValue!.toInt())
                              : position),
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
              _shuffleOn
                  ? FluentIcons.arrow_shuffle_24_filled
                  : FluentIcons.arrow_shuffle_off_24_regular,
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
              FluentIcons.previous_24_regular,
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
                    ? FluentIcons.pause_24_regular
                    : FluentIcons.play_24_regular,
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
              FluentIcons.next_24_regular,
              color: SpotifyColors.textPrimary,
            ),
            onPressed: () => handler.skipToNext(),
          ),
          IconButton(
            iconSize: 22,
            splashRadius: 20,
            icon: Icon(
              _repeatMode == AudioServiceRepeatMode.one
                  ? FluentIcons.arrow_repeat_1_24_filled
                  : repeatOn
                  ? FluentIcons.arrow_repeat_all_24_filled
                  : FluentIcons.arrow_repeat_all_off_24_regular,
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