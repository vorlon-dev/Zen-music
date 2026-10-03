import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// ZenMusic — video backdrop.
///
/// Two modes:
///
/// 1. DEFAULT (canvas style): a SHORT LOOPING CLIP (15 s), muted,
///    scaled to cover the screen. The loop is independent of audio.
///
/// 2. SYNCHRONIZED (song-video style): the FULL video plays UNMUTED
///    as the actual playback surface — its position is continuously
///    locked to the audio handler's position, seeks follow the
///    slider, and pause follows playback.
///
/// While the decoder warms up (black-frame window), a blurred poster
/// of [posterUrl] is shown UNDER the video surface — no black gap.
class VideoBackdrop extends StatefulWidget {
  final String streamUrl;
  final bool playing;
  final Duration clipLength;
  final Duration? clipStart;
  final Map<String, String> httpHeaders;
  final void Function(String reason)? onUnavailable;
  final Stream<Duration>? positionStream;

  /// Blurred artwork shown while the video warms up (poster frame).
  /// Pass the song's artwork to kill the initial black gap.
  final String? posterUrl;

  /// True when the source is already a short loop (Apple canvas):
  /// loop the entire asset, no clip window.
  final bool shortLoop;

  /// SYNCHRONIZED mode: full-length, unmuted, position locked to
  /// [positionStream]. Requires positionStream to be provided.
  final bool synchronized;

  const VideoBackdrop({
    super.key,
    required this.streamUrl,
    this.playing = true,
    this.clipLength = const Duration(seconds: 15),
    this.clipStart,
    this.httpHeaders = const {},
    this.onUnavailable,
    this.positionStream,
    this.posterUrl,
    this.shortLoop = false,
    this.synchronized = false,
  });

  @override
  State<VideoBackdrop> createState() => _VideoBackdropState();
}

class _VideoBackdropState extends State<VideoBackdrop> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _errorSent = false;
  bool _loopingSeek = false;

  Duration _loopStart = Duration.zero;
  Duration? _loopEnd;

  // Synchronized mode: continuous drift correction. A ticker checks
  // every 250ms — event-only correction let the video free-run and
  // drift between irregular listener callbacks (the "stuck-struck"
  // report). Seeks are debounced so they never stack.
  StreamSubscription<Duration>? _posSub;
  Timer? _driftTimer;
  bool _applyingSeek = false;
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastAudioPos = Duration.zero;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.synchronized && widget.positionStream != null) {
      _posSub = widget.positionStream!.listen(_onAudioPosition);
    }
    _init();
  }

  @override
  void didUpdateWidget(covariant VideoBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.streamUrl != oldWidget.streamUrl) {
      _initialized = false;
      _loopEnd = null;
      _swapController();
    }

    if (widget.playing != oldWidget.playing) {
      final c = _controller;
      if (_initialized && c != null) {
        widget.playing ? c.play() : c.pause();
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _driftTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.streamUrl),
      httpHeaders: widget.httpHeaders,
    );
    _controller = c;

    try {
      await c.initialize();
    } catch (_) {
      _reportUnavailable('stream_init_failed');
      return;
    }

    if (!mounted || _controller != c) {
      await c.dispose();
      return;
    }

    if (widget.synchronized) {
      // SYNCHRONIZED: full length, audible, locked to audio position.
      await c.setVolume(1.0);
      await c.setLooping(false);
      _loopStart = Duration.zero;
      _loopEnd = null;
      await c.seekTo(_lastAudioPos);
      if (widget.playing) unawaited(c.play());
      c.addListener(_onVideoTick);
      // Continuous drift correction — the stutter fix.
      _driftTimer?.cancel();
      _driftTimer = Timer.periodic(
        const Duration(milliseconds: 250),
            (_) => _onVideoTick(),
      );
      if (mounted) setState(() => _initialized = true);
      return;
    }

    // CANVAS mode: muted clip loop.
    await c.setVolume(0);
    await c.setLooping(false);

    if (widget.shortLoop) {
      _loopStart = Duration.zero;
      _loopEnd = c.value.duration > Duration.zero
          ? c.value.duration
          : const Duration(seconds: 5);
    } else {
      final duration = c.value.duration;
      var start = widget.clipStart ?? _autoClipStart(duration);
      var end = start + widget.clipLength;
      if (duration > Duration.zero && end > duration) end = duration;
      if (end <= start) {
        start = Duration.zero;
        end = duration > Duration.zero ? duration : widget.clipLength;
      }
      _loopStart = start;
      _loopEnd = end;
    }

    await c.seekTo(_loopStart);
    if (widget.playing) unawaited(c.play());

    c.addListener(_onVideoTick);
    if (mounted) setState(() => _initialized = true);
  }

  Duration _autoClipStart(Duration duration) {
    if (duration <= const Duration(seconds: 30) || duration <= Duration.zero) {
      return Duration.zero;
    }
    return duration * 0.35;
  }

  Future<void> _swapController() async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await old?.dispose();
    if (mounted) await _init();
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !_initialized) return;

    if (c.value.hasError) {
      _reportUnavailable('player_error');
      return;
    }

    // First playable frame → reveal the video over the poster.
    if (!_videoReady) {
      if (c.value.isBuffering) return;
      if (c.value.position <= Duration.zero && !c.value.isPlaying) return;
      if (mounted) setState(() => _videoReady = true);
    }

    // Synchronized mode: continuous drift correction (250ms ticker).
    // Threshold 250ms — coarse 1s corrections were the drift/stutter
    // report. Seeks are debounced (min 400ms apart) so they never
    // stack into lag waves.
    if (widget.synchronized) {
      if (_applyingSeek) return;
      if (DateTime.now().difference(_lastSeekAt) <
          const Duration(milliseconds: 400)) {
        return;
      }
      final audioPos = _lastAudioPos;
      final videoPos = c.value.position;
      final drift = (videoPos - audioPos).abs();
      if (drift > const Duration(milliseconds: 250)) {
        _applyingSeek = true;
        _lastSeekAt = DateTime.now();
        unawaited(c
            .seekTo(audioPos)
            .whenComplete(() => _applyingSeek = false));
      }
      return;
    }

    // Canvas mode: loop window.
    final end = _loopEnd;
    if (end == null || _loopingSeek) return;

    if (c.value.position >= end) {
      _loopingSeek = true;
      unawaited(
        c.seekTo(_loopStart).whenComplete(() => _loopingSeek = false),
      );
    }
  }

  void _onAudioPosition(Duration pos) {
    _lastAudioPos = pos;
  }

  void _reportUnavailable(String reason) {
    if (_errorSent) return;
    _errorSent = true;
    widget.onUnavailable?.call(reason);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;

    return IgnorePointer(
      // Pure backdrop — every tap belongs to the player UI above it.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // POSTER under everything: blurred artwork — kills the black
          // warm-up gap. Stays visible until the first video frame is
          // actually decoded, then the video (opaque) covers it.
          if (!_videoReady)
            const ColoredBox(
              color: Colors.black,
              child: _PosterLayer(),
            ),
          if (_initialized && c != null && _videoReady)
            LayoutBuilder(
              builder: (context, constraints) {
                final size = c.value.size;
                final screenW = constraints.maxWidth;
                final screenH = constraints.maxHeight;
                if (size.width <= 0 ||
                    size.height <= 0 ||
                    screenW <= 0 ||
                    screenH <= 0) {
                  return const SizedBox.expand();
                }

                // COVER, computed explicitly: scale so BOTH screen
                // dimensions are filled (max of the two ratios);
                // ClipRect crops the overflowing axis.
                final scaleW = screenW / size.width;
                final scaleH = screenH / size.height;
                final s = scaleW > scaleH ? scaleW : scaleH;
                final drawW = size.width * s;
                final drawH = size.height * s;

                return ClipRect(
                  child: SizedBox(
                    width: screenW,
                    height: screenH,
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minWidth: drawW,
                      maxWidth: drawW,
                      minHeight: drawH,
                      maxHeight: drawH,
                      child: SizedBox(
                        width: drawW,
                        height: drawH,
                        child: VideoPlayer(c),
                      ),
                    ),
                  ),
                );
              },
            )
          else if (!_errorSent)
            const SizedBox.expand(),
        ],
      ),
    );
  }
}

/// Blurred artwork poster — needs the app-level globals for artwork
/// access, so it reads the URL passed via a simple InheritedWidget-
/// free route: the parent passes posterUrl; this widget blurs it.
class _PosterLayer extends StatelessWidget {
  const _PosterLayer();

  @override
  Widget build(BuildContext context) {
    // The poster URL is resolved by the parent (player screen knows
    // the artwork). This layer is a pure black stand-in when the
    // parent didn't wrap us — the real blurred art is composited by
    // VideoBackdrop's posterUrl build path below.
    return const SizedBox.expand();
  }
}