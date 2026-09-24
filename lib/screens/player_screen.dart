import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/wave_spinner.dart';
import '../main.dart';
import '../models/song.dart';
import '../services/downloads_service.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/current_lyric_line.dart';
import '../widgets/gradient_background.dart';
import '../widgets/lyrics_preview_card.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/marquee_text.dart';
import '../widgets/media_shelf.dart' show PlayPauseMorph;
import '../widgets/queue_sheet.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/up_next_row.dart';
import '../widgets/video_backdrop.dart';
import '../widgets/youtube_thumbnail.dart';
import 'artist_screen.dart';
import 'listen_together_screen.dart';

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
            child: Column(
              children: [
                _topBar(song),
                Expanded(
                  // Lyrics slide up from the bottom; closing slides them
                  // back down. The top bar stays pinned above.
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInOut,
                    transitionBuilder: (child, anim) => SlideTransition(
                      position: Tween(
                          begin: const Offset(0, 1), end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                    child: _showLyrics
                        ? KeyedSubtree(
                      key: const ValueKey('lyrics-body'),
                      child: SizedBox.expand(
                          child: _lyricsBody(song, handler)),
                    )
                        : KeyedSubtree(
                      key: const ValueKey('main-body'),
                      child: SizedBox.expand(
                          child: _mainBody(song, handler, controller)),
                    ),
                  ),
                ),
              ],
            ),
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

  Widget _lyricsBody(Song song, dynamic handler) {
    return Column(
      children: [
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
        _miniControls(handler),
      ],
    );
  }

  Widget _mainBody(
      Song song, dynamic handler, dynamic controller) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          if (!_showVideo)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              child: AspectRatio(
                aspectRatio: 1,
                child: Hero(
                  tag: 'artwork-${song.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: YoutubeThumbnail(
                        videoId: song.id,
                        imageUrl: song.thumbnail,
                        borderRadius: 14,
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
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => pushSharedAxisY(
                          context,
                          ArtistScreen(artistName: song.artist),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: SpotifyColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: SpotifyColors.textTertiary,
                            ),
                          ],
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
                              color: SpotifyColors.green.withOpacity(0.15),
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

          const SizedBox(height: 12),
          _WaveSeekBar(handler: handler, song: song),
          const SizedBox(height: 4),
          _PlayerControls(
              handler: handler, controller: controller, song: song),
          const SizedBox(height: 16),
          _smallIconsRow(song),
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

  Widget _smallIconsRow(Song song) {
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
          _DownloadButton(song: song),
          IconButton(
            splashRadius: 20,
            tooltip: 'Listen together',
            icon: const Icon(
              Icons.people_outline,
              color: SpotifyColors.textSecondary,
              size: 24,
            ),
            onPressed: () => pushSharedAxisY(
              context,
              const ListenTogetherScreen(),
            ),
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

  Widget _miniControls(dynamic handler) {
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
                    return Center(
                      child: PlayPauseMorph(
                        playing: playing,
                        size: 24,
                        color: Colors.black,
                        onTap: () =>
                        playing ? handler.pause() : handler.play(),
                      ),
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
// WAVE SEEK BAR — animated wave fill on the progress track
// ═════════════════════════════════════════════

class _WaveSeekBar extends StatefulWidget {
  final dynamic handler;
  final Song song;

  const _WaveSeekBar({required this.handler, required this.song});

  @override
  State<_WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<_WaveSeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    duration: const Duration(milliseconds: 2600),
    vsync: this,
  )..repeat();

  double? _dragFraction;
  double _streamFraction = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.handler.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (_dragFraction == null) {
          _streamFraction = _fractionOf(p);
        }
      });
    });
    _durSub = widget.handler.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _phase.dispose();
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  double _fractionOf(Duration p) {
    final total = _effectiveDuration.inMilliseconds;
    if (total <= 0) return 0;
    return (p.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }

  Duration get _effectiveDuration =>
      _duration.inSeconds > 0 ? _duration : widget.song.duration;

  void _seekToFraction(double f) {
    final total = _effectiveDuration;
    if (total.inMilliseconds <= 0) return;
    widget.handler
        .seek(Duration(milliseconds: (f * total.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (_dragFraction ?? _streamFraction).clamp(0.0, 1.0);
    final shownPosition = _dragFraction != null
        ? Duration(
        milliseconds:
        (fraction * _effectiveDuration.inMilliseconds).round())
        : _position;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              void setDrag(double localX) {
                setState(() => _dragFraction =
                    (localX / width).clamp(0.0, 1.0).toDouble());
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragEnd: (_) {
                  _seekToFraction(fraction);
                  setState(() => _dragFraction = null);
                },
                onTapUp: (d) {
                  final f = (d.localPosition.dx / width)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  _seekToFraction(f);
                  setState(() => _dragFraction = f);
                },
                child: AnimatedBuilder(
                  animation: _phase,
                  builder: (context, _) => CustomPaint(
                    size: const Size(double.infinity, 30),
                    painter: _WaveProgressPainter(
                      progress: fraction,
                      phase: _phase.value * 2 * math.pi,
                      color: SpotifyColors.green,
                      dimColor: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _fmt(shownPosition),
                style: const TextStyle(
                  fontSize: 11,
                  color: SpotifyColors.textSecondary,
                ),
              ),
              Text(
                _fmt(_effectiveDuration),
                style: const TextStyle(
                  fontSize: 11,
                  color: SpotifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _WaveProgressPainter extends CustomPainter {
  final double progress;
  final double phase;
  final Color color;
  final Color dimColor;

  _WaveProgressPainter({
    required this.progress,
    required this.phase,
    required this.color,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    const amp = 3.0;
    const waves = 3.0;

    // Faint neutral guide line across the full width.
    final dimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = dimColor;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), dimPaint);

    // Moving wave, clipped to the progress portion.
    final path = Path();
    var first = true;
    for (var x = 0.0; x <= size.width; x += 2) {
      final y = mid +
          math.sin((x / size.width) * waves * 2 * math.pi + phase) * amp;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }
    final brightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(0, 0, size.width * progress.clamp(0.0, 1.0), size.height));
    canvas.drawPath(path, brightPaint);
    canvas.restore();

    // Thumb — same color as the wave.
    canvas.drawCircle(
      Offset(size.width * progress.clamp(0.0, 1.0), mid),
      5.5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_WaveProgressPainter old) =>
      old.progress != progress || old.phase != phase;
}

// ═════════════════════════════════════════════
// PLAY BUTTON — wave progress ring + Echo morph
// ═════════════════════════════════════════════

class _PlayButton extends StatefulWidget {
  final dynamic handler;
  final Song song;
  final bool playing;

  const _PlayButton({
    required this.handler,
    required this.song,
    required this.playing,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    duration: const Duration(milliseconds: 4000),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: StreamBuilder<Duration>(
        stream: widget.handler.positionStream,
        builder: (context, posSnap) {
          final pos = (posSnap.data ?? Duration.zero).inMilliseconds
              .clamp(0, widget.song.duration.inMilliseconds)
              .toDouble();
          final total = widget.song.duration.inMilliseconds.toDouble();
          final progress = total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0;
          return AnimatedBuilder(
            animation: _phase,
            builder: (context, _) => CustomPaint(
              size: const Size(84, 84),
              painter: WaveRingPainter(
                phase: _phase.value * 2 * math.pi,
                startAngle: -math.pi / 2,
                sweepAngle: 2 * math.pi * progress,
                color: SpotifyColors.green,
                backgroundColor: SpotifyColors.textTertiary.withOpacity(0.25),
                strokeWidth: 3,
              ),
              child: Center(
                child: StreamBuilder<PlaybackState>(
                  stream: widget.handler.playbackState,
                  builder: (context, stateSnap) {
                    final st = stateSnap.data;
                    final buffering = st != null &&
                        (st.processingState ==
                            AudioProcessingState.loading ||
                            st.processingState ==
                                AudioProcessingState.buffering);
                    return Container(
                      width: 62,
                      height: 62,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: buffering
                            ? SizedBox(
                          width: 24,
                          height: 24,
                          child: WaveSpinner(
                            size: 24,
                            strokeWidth: 2.4,
                          ),
                        )
                            : PlayPauseMorph(
                          playing: widget.playing,
                          size: 28,
                          color: Colors.black,
                          onTap: () => widget.playing
                              ? widget.handler.pause()
                              : widget.handler.play(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DOWNLOAD BUTTON
// ═════════════════════════════════════════════

class _DownloadButton extends StatefulWidget {
  final Song song;
  const _DownloadButton({required this.song});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _checking = true;
  bool _downloaded = false;
  bool _downloading = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ok = await DownloadsService().isDownloadedAsync(widget.song.id);
    if (!mounted) return;
    setState(() {
      _downloaded = ok;
      _checking = false;
    });
  }

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    final ok = await DownloadsService()
        .download(widget.song, onProgress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _downloaded = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Downloaded — plays offline'
            : 'Download failed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: const Text('Delete download?'),
        content: Text(widget.song.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await DownloadsService().delete(widget.song.id);
    if (!mounted) return;
    setState(() => _downloaded = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_downloading) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _progress / 100,
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation(SpotifyColors.green),
            ),
            Text('$_progress%',
                style: const TextStyle(
                    fontSize: 9, color: SpotifyColors.textSecondary)),
          ],
        ),
      );
    }
    return IconButton(
      splashRadius: 20,
      tooltip: _downloaded ? 'Delete download' : 'Download',
      icon: Icon(
        _downloaded
            ? FluentIcons.arrow_download_24_filled
            : FluentIcons.arrow_download_24_regular,
        color: _downloaded
            ? SpotifyColors.green
            : SpotifyColors.textSecondary,
        size: 22,
      ),
      onPressed: _downloaded ? _confirmDelete : _start,
    );
  }
}

// ═════════════════════════════════════════════
// PLAYER CONTROLS
// ═════════════════════════════════════════════

class _PlayerControls extends StatefulWidget {
  final dynamic handler;
  final dynamic controller;
  final Song song;

  const _PlayerControls({
    required this.handler,
    required this.controller,
    required this.song,
  });

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
          _PlayButton(
            handler: handler,
            song: widget.song,
            playing: widget.controller.isPlaying,
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