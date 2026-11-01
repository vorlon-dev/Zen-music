import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart';

/// Video backdrop behind the player UI — one contract, two engines.
///
/// SP-76: Android / iOS / macOS keep the proven video_player implementation.
/// Windows runs media_kit (libmpv) instead: `video_player` ships NO Windows
/// implementation in this app's dependency set (pubspec.lock carries only
/// the android / avfoundation / web hosts), so every Spotify canvas on
/// Windows used to die inside initialize() and the backdrop silently
/// cleared itself — the canvas "never worked" on the platform this app is
/// mostly used on. Both engines report the same signals: poster while
/// warming up, first-frame reveal, [onReadyChanged], [onUnavailable].
///
/// Looping: [shortLoop] marks a source that is already a short loop
/// (Spotify canvases are 3–8 s clips) — the whole asset loops, muted,
/// seamlessly where the engine supports it. [synchronized] marks a
/// full-length video (YT music video) that is position-locked to the audio
/// stream instead. The two are mutually exclusive by contract.
class VideoBackdrop extends StatelessWidget {
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

  /// True when the source is already a short loop (Spotify canvas):
  /// loop the entire asset, no clip window.
  final bool shortLoop;

  /// SYNCHRONIZED mode: full-length, unmuted, position locked to
  /// [positionStream]. Requires positionStream to be provided.
  final bool synchronized;

  /// First frame is on screen (and the poster can hand over), or the
  /// backdrop went back to warming up. SP-76: the player screen uses this
  /// to fade the still cover out exactly while the canvas fades in.
  final ValueChanged<bool>? onReadyChanged;

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
    this.onReadyChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return _MediaKitBackdrop(
        streamUrl: streamUrl,
        playing: playing,
        httpHeaders: httpHeaders,
        onUnavailable: onUnavailable,
        posterUrl: posterUrl,
        onReadyChanged: onReadyChanged,
      );
    }
    return _VideoPlayerBackdrop(
      streamUrl: streamUrl,
      playing: playing,
      clipLength: clipLength,
      clipStart: clipStart,
      httpHeaders: httpHeaders,
      onUnavailable: onUnavailable,
      positionStream: positionStream,
      posterUrl: posterUrl,
      shortLoop: shortLoop,
      synchronized: synchronized,
      onReadyChanged: onReadyChanged,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════
// Engine 1 — video_player (Android / iOS / macOS / web). Unchanged
// behavior, plus onReadyChanged reporting and native looping for
// shortLoop sources.
// ══════════════════════════════════════════════════════════════════════

class _VideoPlayerBackdrop extends StatefulWidget {
  final String streamUrl;
  final bool playing;
  final Duration clipLength;
  final Duration? clipStart;
  final Map<String, String> httpHeaders;
  final void Function(String reason)? onUnavailable;
  final Stream<Duration>? positionStream;
  final String? posterUrl;
  final bool shortLoop;
  final bool synchronized;
  final ValueChanged<bool>? onReadyChanged;

  const _VideoPlayerBackdrop({
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
    this.onReadyChanged,
  });

  @override
  State<_VideoPlayerBackdrop> createState() => _VideoPlayerBackdropState();
}

class _VideoPlayerBackdropState extends State<_VideoPlayerBackdrop> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _errorSent = false;
  bool _loopingSeek = false;

  Duration _loopStart = Duration.zero;
  Duration? _loopEnd;

  // Synchronized mode state.
  StreamSubscription<Duration>? _posSub;
  Timer? _driftTimer;
  bool _applyingSeek = false;

  // Audio clock: last stream sample + when it arrived. The ticker
  // extrapolates between events — comparing the live video position
  // against a frozen sample (up to ~200ms stale) manufactured drift
  // that never existed.
  Duration _lastAudioPos = Duration.zero;
  DateTime _lastAudioAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _gotAudioSample = false;

  // Jump (explicit-seek) detection + boomerang guard.
  bool? _lastJumpForward;
  DateTime _lastJumpAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Rebuffer tracking: corrections (speed or seek) rest 2s after ANY
  // observed video buffering — acting on a just-recovered decoder
  // re-triggers the rebuffer.
  bool _wasBuffering = false;
  DateTime _lastBufferingAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Speed catch-up state. setPlaybackSpeed is a long-standard
  // video_player API but unverified in this project's pinned version —
  // first failure permanently disables it and restores the old
  // rare-seek corrector (fallback contract).
  bool _speedControlAvailable = true;
  double _currentSpeed = 1.0;
  DateTime _lastSpeedAdjustAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeekAt = DateTime.fromMillisecondsSinceEpoch(0);
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
  void didUpdateWidget(covariant _VideoPlayerBackdrop oldWidget) {
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
        if (!widget.playing) _setSpeed(1.0);
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
    // Fresh controller → fresh reveal/error state. A stale
    // _videoReady from the previous song suppressed the new poster;
    // a stale _errorSent suppressed the new controller's error
    // reporting. (Audio-clock state is NOT reset — it belongs to the
    // position stream, which outlives controller swaps.)
    _videoReady = false;
    _errorSent = false;
    _applyingSeek = false;
    _loopingSeek = false;
    _currentSpeed = 1.0;
    widget.onReadyChanged?.call(false);

    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.streamUrl),
      httpHeaders: widget.httpHeaders,
    );
    _controller = c;

    // Time-bounded initialize: a stalled stream converts into the
    // standard onUnavailable path (SD retry / snackbar upstream)
    // instead of hanging on black forever.
    try {
      await c.initialize().timeout(const Duration(seconds: 12));
    } catch (_) {
      if (_controller == c) _controller = null;
      await c.dispose();
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
      // Initial seek ONLY when an audio sample has already arrived.
      // Otherwise the first position event's jump detection performs
      // the single sync seek — one decoder flush, not two.
      if (_gotAudioSample) {
        try {
          await c.seekTo(_lastAudioPos)
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          // Seek unresolved — proceed; catch-up will align.
        }
      }
      if (!mounted || _controller != c) {
        await c.dispose();
        return;
      }
      if (widget.playing) unawaited(c.play());
      c.addListener(_onVideoTick);
      // The initial seek just happened — start its cooldown.
      _lastSeekAt = DateTime.now();
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

    if (widget.shortLoop) {
      // SP-76: the whole asset IS the loop (a Spotify canvas is a 3–8 s
      // clip). Prefer the platform's native looping — seamless where it
      // is supported — and keep the tick seek below as the safety net
      // for engines where setLooping is a no-op.
      await c.setLooping(true);
      _loopStart = Duration.zero;
      _loopEnd = c.value.duration > Duration.zero
          ? c.value.duration
          : const Duration(seconds: 5);
    } else {
      await c.setLooping(false);
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

  /// Audio position extrapolated to NOW. Stream events arrive up to
  /// ~200ms apart; between them the sample is advanced by elapsed
  /// wall time (playing only). Staleness-capped so a dead stream
  /// degrades to the raw sample instead of extrapolating forever.
  Duration get _liveAudioPos {
    if (!widget.playing) return _lastAudioPos;
    final elapsed = DateTime.now().difference(_lastAudioAt);
    if (elapsed > const Duration(seconds: 2)) return _lastAudioPos;
    return _lastAudioPos + elapsed;
  }

  void _onAudioPosition(Duration pos) {
    final jump = pos - _lastAudioPos; // signed
    _lastAudioPos = pos;
    _lastAudioAt = DateTime.now();
    _gotAudioSample = true;

    final absJump = jump.abs();
    if (absJump <= const Duration(milliseconds: 1200)) {
      // Normal playback tick — resets the com window.
      _lastJumpForward = null;
      return;
    }

    final forward = jump > Duration.zero;
    final now = DateTime.now();

    // Boomerang guard: a huge jump in the OPPOSITE direction within
    // 1.5s of the previous one is the com of a stale stream tick,
    // not a user action. Skip it.
    final isEcho = _lastJumpForward != null &&
        _lastJumpForward != forward &&
        now.difference(_lastJumpAt) < const Duration(milliseconds: 1500);

    _lastJumpForward = forward;
    _lastJumpAt = now;

    if (isEcho) {
      debugPrint('VideoBackdrop: skipped com jump '
          '${forward ? "+" : "-"}${absJump.inMilliseconds}ms');
      return;
    }
    debugPrint('VideoBackdrop: hard seek on audio jump '
        '${forward ? "+" : "-"}${absJump.inMilliseconds}ms');
    _hardSeekTo(pos);
  }

  /// Immediate, cooldown-free video seek for explicit audio jumps.
  void _hardSeekTo(Duration pos) {
    if (!widget.synchronized) return;
    final c = _controller;
    if (c == null || !_initialized || _applyingSeek) return;
    _applyingSeek = true;
    _lastSeekAt = DateTime.now();
    _setSpeed(1.0);
    unawaited(
      c.seekTo(pos).whenComplete(() => _applyingSeek = false),
    );
  }

  /// Playback-speed catch-up — the drift correction that never
  /// flushes the decoder. try/catch guards the unverified API: on
  /// first failure it is permanently disabled and the caller falls
  /// back to the rare-seek corrector.
  void _setSpeed(double speed) {
    if (speed == _currentSpeed) return;
    final c = _controller;
    if (c == null) return;
    try {
      c.setPlaybackSpeed(speed);
      _currentSpeed = speed;
    } catch (_) {
      _speedControlAvailable = false;
      _currentSpeed = 1.0;
      debugPrint('VideoBackdrop: setPlaybackSpeed unavailable — '
          'falling back to seek corrections');
    }
  }

  void _onVideoTick() {
    final c = _controller;
    if (c == null || !_initialized) return;

    if (c.value.hasError) {
      _reportUnavailable('player_error');
      return;
    }

    // Rebuffer tracking: timestamp on every buffering tick, so the
    // settle window measures from the LAST buffering observation.
    if (c.value.isBuffering) {
      _lastBufferingAt = DateTime.now();
      if (!_wasBuffering) {
        debugPrint('VideoBackdrop: video rebuffering');
      }
    }
    _wasBuffering = c.value.isBuffering;

    // First playable frame → reveal the video over the poster.
    if (!_videoReady) {
      if (c.value.isBuffering) return;
      if (c.value.position <= Duration.zero && !c.value.isPlaying) return;
      if (mounted) {
        setState(() => _videoReady = true);
        widget.onReadyChanged?.call(true);
      }
    }

    if (widget.synchronized) {
      if (!_videoReady || !widget.playing || c.value.isBuffering) return;
      // Settle window after any rebuffer.
      if (DateTime.now().difference(_lastBufferingAt) <
          const Duration(seconds: 2)) {
        return;
      }

      final audioPos = _liveAudioPos;
      final videoPos = c.value.position;
      final driftMs = (videoPos - audioPos).inMilliseconds;

      // Aligned → restore normal speed.
      if (driftMs.abs() <= 300) {
        _setSpeed(1.0);
        return;
      }

      // Gentle catch-up band: 0.3s–4s of drift → playbackSpeed,
      // never a seek. Speed-up (video behind) requires ≥1.5s of
      // buffered headroom so catch-up can never starve the buffer;
      // slow-down (video ahead) is always safe.
      if (driftMs.abs() <= 4000 && _speedControlAvailable) {
        if (_applyingSeek) return;
        if (DateTime.now().difference(_lastSpeedAdjustAt) <
            const Duration(milliseconds: 1000)) {
          return;
        }
        if (driftMs < 0) {
          // Video behind — needs buffered headroom to speed up.
          final bufferedEnd = c.value.buffered.isNotEmpty
              ? c.value.buffered.last.end
              : Duration.zero;
          final ahead = bufferedEnd - videoPos;
          if (ahead >= const Duration(milliseconds: 1500)) {
            _lastSpeedAdjustAt = DateTime.now();
            _setSpeed(1.2);
          }
        } else {
          // Video ahead — let the audio clock catch up.
          _lastSpeedAdjustAt = DateTime.now();
          _setSpeed(0.9);
        }
        return;
      }

      // Giant drift (>4s) or speed API unavailable → the old rare
      // seek corrector, unchanged guards (2.5s cooldown).
      if (_applyingSeek) return;
      if (DateTime.now().difference(_lastSeekAt) <
          const Duration(milliseconds: 2500)) {
        return;
      }
      debugPrint('VideoBackdrop: drift seek '
          '${driftMs}ms (giant drift / speed fallback)');
      _applyingSeek = true;
      _lastSeekAt = DateTime.now();
      unawaited(c
          .seekTo(audioPos)
          .whenComplete(() => _applyingSeek = false));
      return;
    }

    // Canvas mode: loop window (safety net beside native looping).
    final end = _loopEnd;
    if (end == null || _loopingSeek) return;

    if (c.value.position >= end) {
      _loopingSeek = true;
      unawaited(
        c.seekTo(_loopStart).whenComplete(() => _loopingSeek = false),
      );
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          // POSTER under everything: blurred artwork — kills the black
          // warm-up gap AND gives stalled starts a visible state.
          if (!_videoReady)
            Positioned.fill(
              child: (widget.posterUrl?.isNotEmpty ?? false)
                  ? _PosterArtwork(imageUrl: widget.posterUrl!)
                  : const ColoredBox(color: Colors.black),
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
                // dimensions are filled; ClipRect crops the rest.
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

// ══════════════════════════════════════════════════════════════════════
// Engine 2 — media_kit (Windows). libmpv plays the canvas: muted, the
// whole asset looped via PlaylistMode.loop (loop-file restarts a clip
// without a reload gap), hardware acceleration on — the exact player
// recipe the Windows video backdrop service already ships.
// ══════════════════════════════════════════════════════════════════════

class _MediaKitBackdrop extends StatefulWidget {
  final String streamUrl;
  final bool playing;
  final Map<String, String> httpHeaders;
  final void Function(String reason)? onUnavailable;
  final String? posterUrl;
  final ValueChanged<bool>? onReadyChanged;

  const _MediaKitBackdrop({
    required this.streamUrl,
    this.playing = true,
    this.httpHeaders = const {},
    this.onUnavailable,
    this.posterUrl,
    this.onReadyChanged,
  });

  @override
  State<_MediaKitBackdrop> createState() => _MediaKitBackdropState();
}

class _MediaKitBackdropState extends State<_MediaKitBackdrop> {
  Player? _player;
  VideoController? _controller;
  bool _ready = false;
  bool _errorSent = false;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<VideoParams>? _videoSub;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _MediaKitBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.streamUrl != oldWidget.streamUrl) {
      // A fresh URL is a fresh attempt — the previous one's failure
      // must not latch the new one into the error state.
      _errorSent = false;
      _setReady(false);
      _open(playing: widget.playing);
    }
    if (widget.playing != oldWidget.playing) {
      final p = _player;
      if (p != null) {
        if (widget.playing) {
          p.play();
        } else {
          p.pause();
        }
      }
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _videoSub?.cancel();
    final p = _player;
    _player = null;
    _controller = null;
    try {
      p?.dispose();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _player != null) return;
    _starting = true;
    try {
      MediaKit.ensureInitialized();

      final player = Player();
      await player.setVolume(0.0); // silent layer — audio owns the app
      // Whole-asset loop: canvases are 3–8 s clips and mpv restarts the
      // file without a reload gap.
      await player.setPlaylistMode(PlaylistMode.loop);

      _errorSub = player.stream.error.listen((String e) {
        debugPrint('[canvas-mk] playback error: $e');
        _reportUnavailable('player_error');
      });
      _videoSub = player.stream.videoParams.listen((VideoParams p) {
        // VideoParams arrive once the decoder knows the frame geometry —
        // the media_kit equivalent of "first frame is renderable". mpv
        // names the frame size w/h and hands them over nullable.
        final int w = p.w ?? 0;
        final int h = p.h ?? 0;
        if (!_ready && w > 0 && h > 0 && mounted) {
          setState(() => _ready = true);
          widget.onReadyChanged?.call(true);
        }
      });

      _player = player;
      _controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      await _open(playing: widget.playing);
    } catch (e) {
      debugPrint('[canvas-mk] init failed: $e');
      _reportUnavailable('stream_init_failed');
    } finally {
      _starting = false;
    }
  }

  Future<void> _open({required bool playing}) async {
    final p = _player;
    if (p == null) return;
    try {
      await p.open(
        Media(
          widget.streamUrl,
          httpHeaders:
              widget.httpHeaders.isEmpty ? null : widget.httpHeaders,
        ),
        play: playing,
      );
    } catch (e) {
      debugPrint('[canvas-mk] open failed: $e');
      _reportUnavailable('stream_init_failed');
    }
  }

  void _setReady(bool ready) {
    if (_ready == ready) return;
    _ready = ready;
    if (mounted) setState(() {});
    widget.onReadyChanged?.call(ready);
  }

  void _reportUnavailable(String reason) {
    if (_errorSent) return;
    _errorSent = true;
    _setReady(false);
    widget.onUnavailable?.call(reason);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return IgnorePointer(
      // Pure backdrop — every tap belongs to the player UI above it.
      child: Stack(
        fit: StackFit.expand,
        children: [
          // POSTER under everything: blurred artwork — kills the black
          // warm-up gap AND gives stalled starts a visible state.
          if (!_ready)
            Positioned.fill(
              child: (widget.posterUrl?.isNotEmpty ?? false)
                  ? _PosterArtwork(imageUrl: widget.posterUrl!)
                  : const ColoredBox(color: Colors.black),
            ),
          if (_ready && controller != null)
            Positioned.fill(
              // COVER: fill both dimensions, crop the rest — the same
              // presentation the video_player engine computes by hand.
              child: Video(
                controller: controller,
                fit: BoxFit.cover,
                wakelock: false,
                filterQuality: FilterQuality.low,
                controls: NoVideoControls,
              ),
            )
          else if (!_errorSent)
            const SizedBox.expand(),
        ],
      ),
    );
  }
}

/// Blurred artwork poster — same proven structure as the player
/// screen's blur background: cover image, BackdropFilter on top,
/// dark scrim. Rendered while the decoder warms up.
class _PosterArtwork extends StatelessWidget {
  final String imageUrl;
  const _PosterArtwork({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) =>
          const ColoredBox(color: Colors.black),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: ColoredBox(color: Colors.black.withOpacity(0.3)),
        ),
      ],
    );
  }
}
