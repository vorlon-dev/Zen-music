import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
// WAKELOCK
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/song_source_resolver.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/video_backdrop.dart';
import '../widgets/youtube_thumbnail.dart';

/// Dedicated YouTube video watch page — YouTube-style playback.
///
/// ARCHITECTURE (the proven-first order — do not invert back):
///
/// 1. DUAL STREAM (PRIMARY — this is how YouTube itself plays):
///    the VIDEO-ONLY stream via visionOs (proven to resolve even for
///    bot-checked videos: "✅ Video: HD stream via visionOs") + the
///    video's OWN audio through the normal handler pipeline (marked
///    explicit so the strict resolver cannot swap the song). Shown
///    muted + position-locked via VideoBackdrop's synchronized mode.
///    1080p picture, plays for bot-checked AND normal videos alike.
///
/// 2. MUXED (fallback) — single video+audio stream if the video-only
///    resolution failed.
///
/// The old ITX-video layer is removed: its videoUrl property was
/// unverified and blocked builds. The unverified layer must never sit
/// on the critical path.
class VideoWatchScreen extends StatefulWidget {
  const VideoWatchScreen({
    super.key,
    required this.videoId,
    this.title,
    this.artist,
    this.thumbnail,
  });

  final String videoId;
  final String? title;
  final String? artist;
  final String? thumbnail;

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

enum _WatchMode { resolving, dual, muxed, failed }

class _VideoWatchScreenState extends State<VideoWatchScreen> {
  final _yt = YoutubeService();

  _WatchMode _mode = _WatchMode.resolving;

  // Dual mode: muted video-only stream; audio lives in the handler.
  String? _dualVideoUrl;
  Map<String, String> _dualHeaders = const {};

  // Muxed fallback mode.
  VideoPlayerController? _muxedController;
  bool _muxedReady = false;

  String? _loadedId;
  bool _fullscreen = false;

  Song? _current;
  List<Song> _related = [];
  bool _loadingRelated = true;
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    _current = Song(
      id: widget.videoId,
      title: widget.title ?? 'Video',
      artist: widget.artist ?? 'YouTube',
      // mqdefault: true 16:9 — hqdefault carries baked-in black bars.
      thumbnail: widget.thumbnail ??
          'https://i.ytimg.com/vi/${widget.videoId}/mqdefault.jpg',
      duration: Duration.zero,
    );
    _loadVideo(widget.videoId);
    _loadRelated(widget.videoId);
  }

  @override
  void dispose() {
    _exitFullscreen();
    _muxedController?.dispose();
    super.dispose();
  }

  // ── Fullscreen (YouTube-style): landscape + immersive + wakelock ──

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
  }

  void _exitFullscreen() {
    if (!_fullscreen) return;
    setState(() => _fullscreen = false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    // REGRESSION #1 (do not regress to edgeToEdge): the app is
    // immersive-sticky EVERYWHERE.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.disable();
  }

  void _toggleFullscreen() {
    _fullscreen ? _exitFullscreen() : _enterFullscreen();
  }

  // ── System back button exits fullscreen first ──

  Future<bool> _onWillPop() async {
    if (_fullscreen) {
      _exitFullscreen();
      return false;
    }
    return true;
  }

  // ── Video loading ──

  Future<void> _loadVideo(String videoId) async {
    setState(() {
      _mode = _WatchMode.resolving;
      _resolveError = null;
      _muxedReady = false;
      _dualVideoUrl = null;
      _dualHeaders = const {};
    });

    // ── PRIMARY: dual stream — video-only (visionOs, proven) + the
    // video's own audio through the handler pipeline. ──
    final started = await _startDualMode();
    if (!mounted) return;
    if (started) return;

    // ── FALLBACK: muxed chain (single video+audio stream) ──
    final result = await _yt.getMuxedStreamUrl(videoId, preferHd: true);
    if (!mounted) return;

    if (result == null || result.url.isEmpty) {
      setState(() {
        _mode = _WatchMode.failed;
        _resolveError =
        'Could not load this video. It may be restricted or offline — try another.';
      });
      return;
    }

    final old = _muxedController;
    _muxedController = null;
    setState(() {});
    await old?.dispose();

    final c = VideoPlayerController.networkUrl(
      Uri.parse(result.url),
      httpHeaders: result.headers,
    );
    _muxedController = c;

    try {
      await c.initialize();
    } catch (_) {
      if (!mounted) return;
      await c.dispose();
      _muxedController = null;
      setState(() {
        _mode = _WatchMode.failed;
        _resolveError = 'Playback failed for this video.';
      });
      return;
    }
    if (!mounted || _muxedController != c) {
      await c.dispose();
      return;
    }

    await c.setVolume(1.0);
    await c.play();

    setState(() {
      _loadedId = videoId;
      _mode = _WatchMode.muxed;
      _muxedReady = true;
      if (_current != null && _current!.duration == Duration.zero) {
        _current = Song(
          id: _current!.id,
          title: _current!.title,
          artist: _current!.artist,
          thumbnail: _current!.thumbnail,
          duration: c.value.duration,
        );
      }
    });

    // Auto-fullscreen for landscape content (YouTube parity) —
    // portrait videos stay inline.
    if (c.value.size.width > c.value.size.height && mounted) {
      _enterFullscreen();
    }
  }

  /// Dual stream start. Returns true when playback is running:
  ///
  /// - VIDEO: the video-only stream via [YoutubeService.getVideoStreamUrl]
  ///   (visionOs — proven to resolve even for bot-checked videos).
  /// - AUDIO: the video's OWN audio through the handler pipeline,
  ///   marked explicit BEFORE queuing so the strict resolver cannot
  ///   swap it for a catalog rendition — video and audio must be the
  ///   same recording, or the muted picture desyncs.
  ///
  /// The audio keeps playing when the page is closed (YouTube Music
  /// parity — mini player + notification take over).
  Future<bool> _startDualMode() async {
    final song = _current;
    if (song == null) return false;

    // Video-only first — if even this fails, fail before touching audio.
    final videoStream = await _yt.getVideoStreamUrl(song);
    if (!mounted) return false;
    if (videoStream == null || videoStream.url.isEmpty) return false;

    // Mark explicit BEFORE queuing.
    SongSourceResolver.instance.markExplicit(song);

    await audioHandler.setQueue([song], startIndex: 0);
    if (!mounted) return false;

    setState(() {
      _dualVideoUrl = videoStream.url;
      // REQUIRED: the video-only URL is UA-gated — without these
      // headers the request 403s and the video never renders.
      _dualHeaders = videoStream.headers;
      _loadedId = song.id;
      _mode = _WatchMode.dual;
    });
    return true;
  }

  Future<void> _loadRelated(String videoId) async {
    setState(() => _loadingRelated = true);
    try {
      final related = await _yt.getYtmRadio(videoId);
      if (!mounted) return;
      setState(() {
        _related = related.where((s) => s.id != videoId).take(20).toList();
        _loadingRelated = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRelated = false);
    }
  }

  void _openRelated(Song song) {
    _exitFullscreen();
    setState(() => _current = song);
    _loadVideo(song.id);
    _loadRelated(song.id);
  }

  // ── Transport ──

  void _togglePlay() {
    switch (_mode) {
      case _WatchMode.muxed:
        final c = _muxedController;
        if (c == null || !_muxedReady) return;
        c.value.isPlaying ? c.pause() : c.play();
        if (mounted) setState(() {});
        break;
      case _WatchMode.dual:
        audioHandler.playbackState.value.playing
            ? audioHandler.pause()
            : audioHandler.play();
        break;
      default:
        break;
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Fullscreen: video edge-to-edge, no scaffold chrome at all.
    if (_fullscreen) {
      return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onDoubleTap: _toggleFullscreen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _videoSurface(),
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: _fullscreenButton(
                        icon: Icons.fullscreen_exit_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal (portrait) watch page.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: SpotifyColors.background,
        appBar: AppBar(
          backgroundColor: SpotifyColors.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
          title: const Text('Video',
              style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _videoArea(),
            if (_mode == _WatchMode.failed)
              _errorBlock()
            else ...[
              _infoBlock(),
              const SizedBox(height: 8),
              _relatedShelf(),
              const SizedBox(height: 16),
              _relatedList(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Inline video area (portrait): 16:9 wrapper around the surface ──

  Widget _videoArea() {
    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _videoSurface(),
      ),
    );
  }

  // ── Video surface (shared between inline and fullscreen) ──

  Widget _videoSurface() {
    switch (_mode) {
      case _WatchMode.dual:
        return _dualSurface();
      case _WatchMode.muxed:
        return _muxedSurface();
      case _WatchMode.failed:
        return _failedSurface();
      case _WatchMode.resolving:
        return _loadingSurface();
    }
  }

  // ── Dual surface — muted video synced to the handler's audio ──

  Widget _dualSurface() {
    final url = _dualVideoUrl;
    if (url == null) return _loadingSurface();

    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, stateSnap) {
        final playing = stateSnap.data?.playing ?? false;
        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _togglePlay,
              onDoubleTap: _toggleFullscreen,
              child: VideoBackdrop(
                key: ValueKey(url),
                streamUrl: url,
                playing: playing,
                // REQUIRED: the video-only URL is UA-gated. Without
                // these headers the request 403s and nothing renders.
                httpHeaders: _dualHeaders,
                synchronized: true,
                positionStream: audioHandler.positionStream,
                posterUrl: _current?.thumbnail,
                onUnavailable: (reason) {
                  print('Watch dual: video unavailable ($reason)');
                  if (!mounted) return;
                  setState(() {
                    _mode = _WatchMode.failed;
                    _resolveError =
                    'Video stream unavailable — audio is still playing.';
                  });
                },
              ),
            ),

            // Scrubbable progress bar (YouTube-style) — driven by the
            // handler's audio position, seeks via seekSafe.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DualProgressBar(),
            ),

            // Center play overlay when paused.
            if (!playing)
              Center(
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        size: 40, color: Colors.white),
                  ),
                ),
              ),

            // Fullscreen button overlay (portrait mode).
            if (!_fullscreen)
              Positioned(
                right: 8,
                top: 8,
                child: _fullscreenButton(icon: Icons.fullscreen_rounded),
              ),
          ],
        );
      },
    );
  }

  // ── Muxed surface (fallback) ──

  Widget _muxedSurface() {
    final c = _muxedController;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_muxedReady && c != null)
          GestureDetector(
            onTap: _togglePlay,
            onDoubleTap: _toggleFullscreen,
            child: FittedBox(
              fit: _fullscreen ? BoxFit.cover : BoxFit.contain,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          )
        else
          _loadingSurface(),

        if (_muxedReady && c != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: SpotifyColors.highlight,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),

        if (_muxedReady && c != null && !c.value.isPlaying)
          Center(
            child: GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 40, color: Colors.white),
              ),
            ),
          ),

        if (_muxedReady && !_fullscreen)
          Positioned(
            right: 8,
            top: 8,
            child: _fullscreenButton(icon: Icons.fullscreen_rounded),
          ),
      ],
    );
  }

  // ── Loading / failed surfaces ──

  Widget _loadingSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_current != null && _current!.thumbnail.isNotEmpty)
          Image.network(
            _current!.thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const ColoredBox(color: SpotifyColors.surfaceLight),
          )
        else
          const ColoredBox(color: SpotifyColors.surfaceLight),
        const Center(
          child: CircularProgressIndicator(color: SpotifyColors.highlight),
        ),
      ],
    );
  }

  Widget _failedSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_current != null && _current!.thumbnail.isNotEmpty)
          Image.network(
            _current!.thumbnail,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
            const ColoredBox(color: SpotifyColors.surfaceLight),
          )
        else
          const ColoredBox(color: SpotifyColors.surfaceLight),
        ColoredBox(color: Colors.black.withOpacity(0.65)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: SpotifyColors.highlight,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _resolveError ?? 'Playback failed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: SpotifyColors.textPrimary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fullscreenButton({required IconData icon}) {
    return GestureDetector(
      onTap: _toggleFullscreen,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }

  Widget _errorBlock() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: SpotifyColors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23)),
            ),
            onPressed: () =>
            _current != null ? _loadVideo(_current!.id) : null,
            child: const Text('Retry',
                style: TextStyle(
                    color: SpotifyColors.background,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: SpotifyColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            _mode == _WatchMode.dual
                ? '${v.artist} · audio + video may drift a moment on slow networks'
                : v.artist,
            style: const TextStyle(
                fontSize: 13, color: SpotifyColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _relatedShelf() {
    if (_loadingRelated || _related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Up next',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _related.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = _related[i];
              return GestureDetector(
                onTap: () => _openRelated(s),
                child: SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          YoutubeThumbnail(
                            videoId: s.id,
                            imageUrl: s.thumbnail,
                            width: 180,
                            height: 101,
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
                                _fmt(s.duration),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: SpotifyColors.textPrimary)),
                      Text(s.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: SpotifyColors.textSecondary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _relatedList() {
    if (_loadingRelated) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child:
            CircularProgressIndicator(color: SpotifyColors.highlight)),
      );
    }
    if (_related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('More videos',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
        ),
        for (final s in _related)
          InkWell(
            onTap: () => _openRelated(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  YoutubeThumbnail(
                    videoId: s.id,
                    imageUrl: s.thumbnail,
                    width: 110,
                    height: 62,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: SpotifyColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: SpotifyColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// DUAL PROGRESS BAR — scrubbable (YouTube-style). Position from the
// handler's audio clock (the master clock in dual mode); taps and
// drags seek the AUDIO via seekSafe — VideoBackdrop's drift
// correction then pulls the muted video back into sync.
// ═════════════════════════════════════════════

class _DualProgressBar extends StatefulWidget {
  const _DualProgressBar();

  @override
  State<_DualProgressBar> createState() => _DualProgressBarState();
}

class _DualProgressBarState extends State<_DualProgressBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioHandler.positionStream,
      builder: (context, posSnap) {
        return StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, mediaSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = mediaSnap.data?.duration ?? Duration.zero;
            final totalMs = dur.inMilliseconds;
            final fraction = _dragFraction ??
                (totalMs > 0
                    ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                    : 0.0);

            Duration durationFor(double f) =>
                Duration(milliseconds: (f * totalMs).round());

            void seekTo(double f) {
              if (totalMs <= 0) return;
              audioHandler.seekSafe(durationFor(f));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                if (_dragFraction == null) return;
                final f = _dragFraction!;
                _dragFraction = null;
                seekTo(f);
              },
              onHorizontalDragStart: (d) {
                if (totalMs <= 0) return;
                setState(() => _dragFraction =
                    (d.localPosition.dx / context.size!.width)
                        .clamp(0.0, 1.0));
              },
              onHorizontalDragUpdate: (d) {
                if (totalMs <= 0 || context.size == null) return;
                setState(() => _dragFraction =
                    (d.localPosition.dx / context.size!.width)
                        .clamp(0.0, 1.0));
              },
              onHorizontalDragEnd: (_) {
                final f = _dragFraction;
                _dragFraction = null;
                if (f != null) seekTo(f);
              },
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        height: 3,
                        color: Colors.white12,
                      ),
                      FractionallySizedBox(
                        widthFactor: fraction,
                        child: Container(
                          height: 3,
                          color: SpotifyColors.highlight,
                        ),
                      ),
                      Positioned(
                        left: MediaQuery.sizeOf(context).width * fraction -
                            7,
                        top: -5,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SpotifyColors.highlight,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Time labels.
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(_dragFraction != null
                              ? durationFor(fraction)
                              : pos),
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _fmt(dur),
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.w600),
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
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}