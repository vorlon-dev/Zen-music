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
///    slider, and pause follows playback. Use [synchronized] for
///    "watch the actual song video" mode.
class VideoBackdrop extends StatefulWidget {
  final String streamUrl;
  final bool playing;
  final Duration clipLength;
  final Duration? clipStart;
  final Map<String, String> httpHeaders;
  final void Function(String reason)? onUnavailable;
  final Stream<Duration>? positionStream;

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

  // Synchronized mode: suppress our own position-subscription writes
  // while the user drags a seek elsewhere in the UI (the seek event
  // itself will arrive via positionStream and re-align us).
  StreamSubscription<Duration>? _posSub;
  bool _applyingSeek = false;
  Duration _lastAudioPos = Duration.zero;

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

    // Synchronized mode: keep the video locked to the audio position.
    if (widget.synchronized) {
      final audioPos = _lastAudioPos;
      final videoPos = c.value.position;
      final drift = (videoPos - audioPos).abs();
      if (_applyingSeek) return;
      // Re-align when drift exceeds a second (seek from the UI,LT
      // host seek, buffering difference).
      if (drift > const Duration(seconds: 1)) {
        _applyingSeek = true;
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
    // Nudge the video on significant jumps (slider seek, LT seek).
    // Fine drift is corrected by _onVideoTick.
    if (!widget.synchronized) return;
    final c = _controller;
    if (c == null || !_initialized || _applyingSeek) return;
    if ((c.value.position - pos).abs() > const Duration(seconds: 2)) {
      _applyingSeek = true;
      unawaited(c.seekTo(pos).whenComplete(() => _applyingSeek = false));
    }
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
      child: ColoredBox(
        color: Colors.black,
        child: (_initialized && c != null)
            ? LayoutBuilder(
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
            : const SizedBox.expand(),
      ),
    );
  }
}