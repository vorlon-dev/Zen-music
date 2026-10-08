import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
// WAKELOCK
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/innertubex_bridge.dart';
import '../services/song_source_resolver.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/video_backdrop.dart';
import '../widgets/youtube_thumbnail.dart';

/// Last-active video session. Set when merged/muxed video playback
/// starts; on back-out the AUDIO is handed to the handler (mini
/// player keeps playing) and this session lets the mini player
/// REOPEN the watch page at the saved position instead of the audio
/// player — YouTube parity. Cleared when a normal song plays from
/// search, when the queue exhausts, or on dispose without transfer.
class VideoSession {
  VideoSession._();

  static bool active = false;
  static String videoId = '';
  static String title = '';
  static String artist = '';
  static String thumbnail = '';
  static Duration position = Duration.zero;

  static void clear() {
    active = false;
    videoId = '';
    position = Duration.zero;
  }
}

/// Dedicated YouTube video watch page — YouTube-style playback,
/// queue, and layout.
///
/// TIER ORDER (do not reorder — the native innertube merged player
/// is ALWAYS the first and primary path):
///
/// 1. MERGED (PRIMARY) — native ExoPlayer (zen_video_player platform
///    view) playing the VIDEO-ONLY + AUDIO-ONLY streams from ONE
///    native innertube player response inside a single
///    MergingMediaSource. One player = video and audio together,
///    zero drift, full 1080p — exactly how YouTube streams. If the
///    native source reports an error or never reaches READY within
///    ~10s, the screen falls down the chain on its own.
/// 2. MUXED (fallback) — single muxed file (video + audio in one),
///    <=720p, via video_player.
/// 3. DUAL (last fallback) — video-only stream + the video's own
///    audio through the handler pipeline.
///
/// The stall detector is deliberately generous (~10s): a cold
/// native extraction on a slow network legitimately takes longer,
/// and a too-strict window dumped working videos to the lower
/// tiers (the regression this file fixes).
///
/// CHANNEL ART loads only ~4s AFTER the player reports READY — it
/// must never compete with the video stream's first bytes.
///
/// QUEUE, CONTROLS, BACKGROUND: YouTube parity — related videos as
/// the up-next tail with auto-advance and re-rooting; tap-to-show
/// controls with 3s auto-hide (buffering never pops them);
/// double-tap ±10s; prev/next; back hands the audio to the mini
/// player and reopening it returns to this page at the position.
class VideoWatchScreen extends StatefulWidget {
  const VideoWatchScreen({
    super.key,
    required this.videoId,
    this.title,
    this.artist,
    this.thumbnail,
    this.startPosition,
  });

  final String videoId;
  final String? title;
  final String? artist;
  final String? thumbnail;

  /// Resume position when reopened from the mini player session.
  final Duration? startPosition;

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

enum _WatchMode { resolving, merged, dual, muxed, failed }

class _VideoWatchScreenState extends State<VideoWatchScreen> {
  final _yt = YoutubeService();

  _WatchMode _mode = _WatchMode.resolving;

  // ── Queue (YouTube parity) ──
  List<Song> _queue = [];
  int _queueIndex = 0;
  bool _advancing = false; // guards double auto-advance fires

  // MERGED mode (primary): native ExoPlayer, video + audio in one
  // player. Position/duration come from a 500ms poll on the
  // per-view channel.
  MethodChannel? _nativeChannel;
  String? _mergedVideoUrl;
  String? _mergedAudioUrl;
  Map<String, String> _mergedHeaders = const {};
  Duration _mergedPos = Duration.zero;
  Duration _mergedDur = Duration.zero;
  bool _mergedPlaying = false;
  Timer? _mergedPoll;
  // Stall detection — GENEROUS (~10s = 20 polls): a cold native
  // extraction on a slow network takes longer than it looks. The
  // old 3s window dumped working merged videos to the muxed tier.
  int _stallPolls = 0;
  bool _mergedWasReady = false;

  // ── YouTube-feel controls (merged tier) ──
  bool _controlsVisible = true;
  bool _mergedBuffering = false;
  Timer? _hideTimer;
  int _seekHintSide = 0; // 0 none, -1 rewind, 1 forward
  Timer? _seekHintTimer;

  // Channel avatar — fetched ONLY after playback is running (+4s),
  // so the artist browse can never starve the video stream.
  String? _channelThumb;
  Timer? _artDelayTimer;

  // Dual mode: muted video-only stream; audio lives in the handler.
  String? _dualVideoUrl;
  Map<String, String> _dualHeaders = const {};

  // Muxed mode: one file, video + audio together.
  VideoPlayerController? _muxedController;
  bool _muxedReady = false;

  String? _loadedId;
  bool _fullscreen = false;
  bool _loadingRelated = true;
  String? _resolveError;

  // Background/mini-player session state.
  Duration? _resumePosition;
  bool _transferred = false;

  Song? get _current =>
      (_queueIndex >= 0 && _queueIndex < _queue.length)
          ? _queue[_queueIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _resumePosition = widget.startPosition;
    _transferred = false;
    _queue = [
      Song(
        id: widget.videoId,
        title: widget.title ?? 'Video',
        artist: widget.artist ?? 'YouTube',
        // mqdefault: true 16:9 — hqdefault carries baked-in black bars.
        thumbnail: widget.thumbnail ??
            'https://i.ytimg.com/vi/${widget.videoId}/mqdefault.jpg',
        duration: Duration.zero,
      ),
    ];
    _playFromQueue(0);
  }

  @override
  void dispose() {
    _mergedPoll?.cancel();
    _hideTimer?.cancel();
    _seekHintTimer?.cancel();
    _artDelayTimer?.cancel();
    final ch = _nativeChannel;
    _nativeChannel = null;
    if (ch != null) {
      ch.invokeMethod('release').catchError((_) {});
    }
    // Pop without a playing video (failed/ended) — drop the session.
    if (!_transferred) VideoSession.clear();
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
    // Back with a video playing → hand the audio to the handler so
    // the mini player keeps it alive (YouTube parity). The session
    // stays registered so reopening the mini player returns HERE.
    if (_mode == _WatchMode.merged || _mode == _WatchMode.muxed) {
      await _transferToHandler();
    } else {
      VideoSession.clear();
    }
    return true;
  }

  /// Hands the current video's audio to the handler at the current
  /// position. The exact video is marked explicit so the strict
  /// resolver streams THIS recording and never a catalog swap.
  Future<void> _transferToHandler() async {
    if (_transferred) return;
    _transferred = true;
    final song = _current;
    if (song == null) return;
    try {
      // Already playing this exact audio in the handler (e.g. a
      // reopen-then-back cycle) — keep it running, no restart.
      final handlerPlaying = audioHandler.playbackState.value.playing;
      final handlerId = audioHandler.mediaItem.value?.id;
      if (handlerPlaying && handlerId == song.id) return;

      final pos = _mode == _WatchMode.merged
          ? _mergedPos
          : _muxedController?.value.position;
      SongSourceResolver.instance.markExplicit(song);
      await audioHandler.setQueue([song], startIndex: 0);
      if (pos != null && pos > Duration.zero) {
        await audioHandler.seekSafe(pos);
      }
      await audioHandler.play();
    } catch (_) {}
  }

  // ── Queue driving ──

  Future<void> _playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _exitFullscreen();
    _advancing = false;
    final song = _queue[index];
    setState(() => _queueIndex = index);
    await _loadVideo(song.id);
    if (!mounted) return;
    _extendQueueWithRelated(song.id);
  }

  /// Refills the queue tail from the current video's related
  /// streams (radio first, native watch-next when radio is empty).
  Future<void> _extendQueueWithRelated(String videoId) async {
    setState(() => _loadingRelated = true);
    var fresh = <Song>[];
    try {
      final related = await _yt.getYtmRadio(videoId);
      fresh = related.where((s) => s.id != videoId).take(20).toList();
    } catch (_) {}
    // Radio empty/failed → native watch-next as the second source.
    if (fresh.isEmpty && mounted) {
      final native = await InnertubexBridge.relatedSongs(videoId);
      fresh = native;
    }
    if (!mounted) return;
    final knownIds = _queue.map((s) => s.id).toSet();
    final deduped = fresh
        .where((s) => s.id != videoId && !knownIds.contains(s.id))
        .take(20)
        .toList();
    setState(() {
      _queue = [..._queue.take(_queueIndex + 1), ...deduped];
      _loadingRelated = false;
    });
  }

  // ── Video loading (tier chain — merged FIRST, always) ──

  Future<void> _loadVideo(String videoId) async {
    _mergedPoll?.cancel();
    _artDelayTimer?.cancel();
    setState(() {
      _mode = _WatchMode.resolving;
      _resolveError = null;
      _muxedReady = false;
      _dualVideoUrl = null;
      _dualHeaders = const {};
      _mergedVideoUrl = null;
      _mergedAudioUrl = null;
      _mergedHeaders = const {};
      _mergedPos = Duration.zero;
      _mergedDur = Duration.zero;
      _mergedPlaying = false;
      _channelThumb = null;
    });

    // ── PRIMARY: native merged player (video + audio, one player) ──
    final merged = await _startMerged(videoId);
    if (!mounted) return;
    if (merged) return;

    // ── FALLBACK 1: muxed stream (single file, <=720p) ──
    final started = await _startMuxed(videoId);
    if (!mounted) return;
    if (started) return;

    // ── FALLBACK 2: dual stream (video-only + handler audio) ──
    final dual = await _startDualMode();
    if (!mounted) return;
    if (dual) return;

    setState(() {
      _mode = _WatchMode.failed;
      _resolveError =
      'Could not load this video. It may be restricted or offline — try another.';
    });
  }

  /// PRIMARY: native merged player via innertube. Requires BOTH
  /// layers from one native player response (same recording
  /// guaranteed). Returns true when the merged surface is up.
  Future<bool> _startMerged(String videoId) async {
    // YouTube behavior + focus hygiene: opening a video stops the
    // app's music, and the freed audio focus can no longer defer
    // the video player's start.
    await audioHandler.pause();
    if (!mounted) return false;

    var native = await InnertubexBridge.extractVideo(videoId);
    if (!mounted) return false;

    // SOURCE B — the bot-gate bridge: when YouTube blocks the native
    // video clients (LOGIN_REQUIRED / UNPLAYABLE for this IP), the
    // Dart visionOs video path frequently still resolves. Feed THAT
    // video URL into the SAME native ExoPlayer with the native audio
    // stream — one player, video + audio together, as before.
    var dartVideoUrl = '';
    var dartVideoHeaders = const <String, String>{};
    var useDartVideo = false;
    var videoUrl = native?.videoUrl ?? '';
    var audioUrl = native?.audioUrl ?? '';
    var headers = native?.headers ?? const <String, String>{};
    if (videoUrl.isEmpty || audioUrl.isEmpty) {
      final videoStream = await _yt.getVideoStreamUrl(_current!);
      if (!mounted) return false;
      if (videoStream != null && videoStream.url.isNotEmpty) {
        dartVideoUrl = videoStream.url;
        dartVideoHeaders = videoStream.headers;
        useDartVideo = true;
        // Audio: native audio chain (separate client set — often not
        // gated when the video clients are).
        final nativeAudio =
        await InnertubexBridge.extract(videoId, maxKbps: 320);
        if (!mounted) return false;
        if (nativeAudio?.url.isNotEmpty ?? false) {
          videoUrl = dartVideoUrl;
          headers = dartVideoHeaders;
          audioUrl = nativeAudio!.url;
          native = null;
        } else {
          return false; // no audio layer anywhere → muxed/dual handle it
        }
      } else {
        return false;
      }
    }
    if (videoUrl.isEmpty || audioUrl.isEmpty) {
      return false;
    }
    // ignore: unused_local_variable
    final unusedGuard = useDartVideo;
    // Release any previous native player before replacing it.
    final old = _nativeChannel;
    _nativeChannel = null;
    if (old != null) {
      old.invokeMethod('release').catchError((_) {});
    }

    // Reset stall detection for the new source.
    _stallPolls = 0;
    _mergedWasReady = false;

    setState(() {
      _mergedVideoUrl = videoUrl;
      _mergedAudioUrl = audioUrl;
      _mergedHeaders = native?.headers ?? const {};
      _mergedPlaying = true;
      _mergedBuffering = true;
      _controlsVisible = true;
      _loadedId = videoId;
      _mode = _WatchMode.merged;
    });

    // Register the session so backing out keeps the audio in the
    // mini player and reopening the mini player returns here.
    // Plain static assignments — Dart cascades cannot set static
    // members through the class name.
    final currentSong = _current;
    if (currentSong != null) {
      VideoSession.active = true;
      VideoSession.videoId = videoId;
      VideoSession.title = currentSong.title;
      VideoSession.artist = currentSong.artist;
      VideoSession.thumbnail = currentSong.thumbnail;
      VideoSession.position = Duration.zero;
    }

    _mergedPoll?.cancel();
    _mergedPoll = Timer.periodic(
      const Duration(milliseconds: 500),
          (_) => _pollMerged(),
    );
    // YouTube parity: controls show on load, then auto-hide while
    // playing (paused keeps them up).
    _pokeControls();
    print('Watch: merged tier (native innertube) $videoId');
    return true;
  }

  /// Per-view channel handshake + prepare, once the platform view
  /// exists. A resume position (mini player reopen) is consumed on
  /// the first prepare only.
  void _onNativeViewCreated(int viewId) {
    final channel = MethodChannel('zen/video_player_$viewId');
    _nativeChannel = channel;
    final resume = _resumePosition;
    _resumePosition = null;
    channel.invokeMethod('prepare', {
      'videoUrl': _mergedVideoUrl,
      'audioUrl': _mergedAudioUrl,
      'headers': _mergedHeaders,
      'startPositionMs': resume?.inMilliseconds ?? 0,
    }).catchError((_) {});
  }

  Future<void> _pollMerged() async {
    final ch = _nativeChannel;
    if (ch == null) return;
    try {
      final raw = await ch.invokeMethod('position');
      if (!mounted) return;
      if (raw is! Map) return;

      // Native source error → drop to the proven muxed tier.
      final err = raw['error'];
      if (err is String && err.isNotEmpty) {
        print('Watch merged: native error $err — falling back');
        await _fallbackFromMerged();
        return;
      }

      final durMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
      if (durMs > 0) {
        final wasReady = _mergedWasReady;
        _mergedWasReady = true;
        _stallPolls = 0;
        // Channel art loads only well AFTER playback is running —
        // the artist browse must never compete with the video
        // stream's first bytes (that contention was the muxed
        // regression).
        if (!wasReady) {
          _artDelayTimer?.cancel();
          _artDelayTimer = Timer(const Duration(seconds: 4), () {
            final id = _loadedId;
            if (id != null) _loadChannelThumb(id);
          });
        }
      } else if (!_mergedWasReady) {
        // Not READY yet — keep waiting (the buffering spinner
        // shows). 20 polls ≈ 10s before declaring the merged source
        // dead: cold extractions on slow networks legitimately
        // take longer than a strict window.
        _stallPolls++;
        if (_stallPolls >= 20) {
          print('Watch merged: never reached READY — falling back');
          await _fallbackFromMerged();
          return;
        }
      }

      final ended = raw['ended'] == true;
      setState(() {
        _mergedPos = Duration(
            milliseconds: (raw['positionMs'] as num?)?.toInt() ?? 0);
        _mergedDur = Duration(milliseconds: durMs);
        _mergedPlaying = raw['isPlaying'] == true;
        _mergedBuffering = raw['ready'] != true;
      });
      // Keep the mini-player session's resume position current.
      VideoSession.position = _mergedPos;
      // AUTO-ADVANCE (YouTube parity): the video ended — roll the
      // next queue entry. Queue exhausted → the session dies.
      if (ended && !_advancing) {
        _advancing = true;
        if (_queueIndex + 1 < _queue.length) {
          _playFromQueue(_queueIndex + 1);
        } else {
          VideoSession.clear();
        }
      }
    } catch (_) {}
  }

  /// Merged tier died (native error or never-READY): release the
  /// native player and continue down the proven chain.
  Future<void> _fallbackFromMerged() async {
    final videoId = _loadedId;
    _mergedPoll?.cancel();
    _artDelayTimer?.cancel();
    final ch = _nativeChannel;
    _nativeChannel = null;
    ch?.invokeMethod('release').catchError((_) {});
    if (videoId == null || !mounted) return;
    final muxed = await _startMuxed(videoId);
    if (!mounted || muxed) return;
    final dual = await _startDualMode();
    if (!mounted || dual) return;
    setState(() {
      _mode = _WatchMode.failed;
      _resolveError =
      'Could not load this video. It may be restricted or offline — try another.';
    });
  }

  /// MUXED fallback: single file with video + audio, <=720p.
  Future<bool> _startMuxed(String videoId) async {
    // Same focus hygiene as merged mode.
    await audioHandler.pause();
    if (!mounted) return false;

    final result = await _yt.getMuxedStreamUrl(videoId, preferHd: true);
    if (!mounted) return false;
    if (result == null || result.url.isEmpty) return false;

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
      if (!mounted) return false;
      await c.dispose();
      _muxedController = null;
      return false;
    }
    if (!mounted || _muxedController != c) {
      await c.dispose();
      return false;
    }

    await c.setVolume(1.0);
    await c.play();

    setState(() {
      _loadedId = videoId;
      _mode = _WatchMode.muxed;
      _muxedReady = true;
    });

    // Session stays registered in the muxed fallback too. Plain
    // static assignments (cascades cannot set statics).
    final currentSong = _current;
    if (currentSong != null) {
      VideoSession.active = true;
      VideoSession.videoId = videoId;
      VideoSession.title = currentSong.title;
      VideoSession.artist = currentSong.artist;
      VideoSession.thumbnail = currentSong.thumbnail;
      VideoSession.position = Duration.zero;
    }

    print('Watch: muxed tier $videoId');

    // Auto-fullscreen for landscape content (YouTube parity) —
    // portrait videos stay inline.
    if (c.value.size.width > c.value.size.height && mounted) {
      _enterFullscreen();
    }
    return true;
  }

  /// LAST fallback: dual stream. VIDEO: native resolver first, then
  /// the proven Dart visionOs path (UA-gated — headers required or
  /// 403). AUDIO: the video's OWN audio through the handler
  /// pipeline, marked explicit BEFORE queuing so the strict resolver
  /// cannot swap it — video and audio must be the same recording.
  Future<bool> _startDualMode() async {
    final song = _current;
    if (song == null) return false;

    String? videoUrl;
    Map<String, String> headers = const {};
    final native = await InnertubexBridge.extractVideo(song.id);
    if (!mounted) return false;
    final nativeVideo = native?.videoUrl;
    if (nativeVideo != null && nativeVideo.isNotEmpty) {
      videoUrl = nativeVideo;
      headers = native?.headers ?? const {};
    } else {
      final videoStream = await _yt.getVideoStreamUrl(song);
      if (!mounted) return false;
      if (videoStream == null || videoStream.url.isEmpty) return false;
      videoUrl = videoStream.url;
      headers = videoStream.headers;
    }

    // Mark explicit BEFORE queuing.
    SongSourceResolver.instance.markExplicit(song);

    await audioHandler.setQueue([song], startIndex: 0);
    if (!mounted) return false;

    setState(() {
      _dualVideoUrl = videoUrl;
      _dualHeaders = headers;
      _loadedId = song.id;
      _mode = _WatchMode.dual;
    });
    print('Watch: dual tier ${song.id}');
    return true;
  }

  // ── Transport ──

  void _togglePlay() {
    switch (_mode) {
      case _WatchMode.merged:
        final ch = _nativeChannel;
        if (ch == null) return;
        if (_mergedPlaying) {
          ch.invokeMethod('pause').catchError((_) {});
          _mergedPlaying = false;
        } else {
          // Play after STATE_ENDED restarts only from position 0.
          if (_mergedDur > Duration.zero && _mergedPos >= _mergedDur) {
            ch.invokeMethod('seekTo', 0).catchError((_) {});
          }
          ch.invokeMethod('play').catchError((_) {});
          _mergedPlaying = true;
        }
        if (mounted) setState(() {});
        _pokeControls();
        break;
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

  /// Fetches the channel avatar for [videoId] via the native
  /// resolver. Called ONLY after playback is running (see the poll).
  /// Silently keeps the letter avatar on any failure, and ignores
  /// the result if the video switched meanwhile.
  Future<void> _loadChannelThumb(String videoId) async {
    final url = await InnertubexBridge.channelThumb(videoId);
    if (!mounted || url == null || url.isEmpty) return;
    if (_loadedId != videoId) return;
    setState(() => _channelThumb = url);
  }

  // ── YouTube-feel controls helpers (merged tier) ──

  /// Shows the controls; while playing, schedules the 3s auto-hide.
  /// Paused playback keeps them on (YouTube parity).
  void _pokeControls() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    if (_mode == _WatchMode.merged && _mergedPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  /// Tap on the video surface: toggle the controls overlay
  /// (YouTube parity — play/pause lives on the buttons).
  void _onSurfaceTap() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _pokeControls();
    }
  }

  void _onDoubleTapZone(int side) => _seekBy(side < 0 ? -10 : 10);

  /// Double-tap seek: ±10s on the merged player or the muxed
  /// controller. Dual mode is skipped (handler-clock tier, rare
  /// fallback).
  void _seekBy(int seconds) {
    switch (_mode) {
      case _WatchMode.merged:
        final ch = _nativeChannel;
        if (ch == null || _mergedDur <= Duration.zero) return;
        final target = (_mergedPos.inMilliseconds + seconds * 1000)
            .clamp(0, _mergedDur.inMilliseconds)
            .toInt();
        ch.invokeMethod('seekTo', target).catchError((_) {});
        setState(() => _mergedPos = Duration(milliseconds: target));
        break;
      case _WatchMode.muxed:
        final c = _muxedController;
        if (c == null || !_muxedReady) return;
        var target = c.value.position + Duration(seconds: seconds);
        if (target < Duration.zero) target = Duration.zero;
        if (target > c.value.duration) target = c.value.duration;
        c.seekTo(target);
        break;
      default:
        return;
    }
    _showSeekHint(seconds > 0 ? 1 : -1);
  }

  void _showSeekHint(int side) {
    _seekHintSide = side;
    if (mounted) setState(() {});
    _seekHintTimer?.cancel();
    _seekHintTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekHintSide = 0);
    });
  }

  Widget _transportButton({
    required Widget icon,
    required VoidCallback onTap,
    bool big = false,
  }) {
    return GestureDetector(
      onTap: () {
        onTap();
        _pokeControls();
      },
      child: Container(
        width: big ? 56 : 44,
        height: big ? 56 : 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          shape: BoxShape.circle,
        ),
        child: icon,
      ),
    );
  }

  Widget _seekHint() {
    final forward = _seekHintSide > 0;
    final arrow = const Icon(FluentIcons.next_24_filled,
        size: 22, color: Colors.white);
    return IgnorePointer(
      child: Center(
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!forward)
                Transform.rotate(angle: math.pi, child: arrow)
              else
                arrow,
              const SizedBox(width: 6),
              const Text('10 seconds',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy link (real, honest action — no fake like/dislike backend
  /// for YouTube videos; share-out would need an unverified package).
  void _copyLink() {
    final song = _current;
    if (song == null) return;
    Clipboard.setData(
      ClipboardData(text: 'https://www.youtube.com/watch?v=${song.id}'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SpotifyColors.surfaceLight,
        content: Text('Link copied',
            style: TextStyle(color: SpotifyColors.textPrimary)),
      ),
    );
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

    // Normal (portrait) watch page — YouTube feel: player on top,
    // title + channel + actions, then the up-next queue list.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: SpotifyColors.background,
        appBar: AppBar(
          backgroundColor: Colors.black,
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
              Container(
                height: 1,
                color: SpotifyColors.surfaceLighter,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
              _upNextSection(),
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
      case _WatchMode.merged:
        return _mergedSurface();
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

  // ── MERGED surface — native ExoPlayer, one player, both layers ──

  Widget _mergedSurface() {
    if (_mergedVideoUrl == null) return _loadingSurface();
    // Buffering is NOT paused: the overlay must not pop up while
    // the player is still loading (the spinner alone shows).
    final showControls =
        _controlsVisible || (!_mergedPlaying && !_mergedBuffering);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Native rendering surface. Keyed per video: a video switch
        // recreates the view (native dispose releases the old player).
        AndroidView(
          key: ValueKey('native_player_$_loadedId'),
          viewType: 'zen_video_player',
          onPlatformViewCreated: _onNativeViewCreated,
          creationParamsCodec: const StandardMessageCodec(),
        ),

        // Interaction layer: tap toggles the controls overlay;
        // double-tap on the left/right half seeks ±10s (YouTube
        // parity). Controls and bar sit ABOVE this layer and win
        // hit-testing.
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            final half = box.maxWidth / 2;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSurfaceTap,
              onDoubleTap: () {},
              onDoubleTapDown: (d) =>
                  _onDoubleTapZone(d.localPosition.dx < half ? -1 : 1),
              child: const SizedBox.expand(),
            );
          }),
        ),

        // Buffering spinner — always visible while the native player
        // is still loading (independent of the controls overlay).
        if (_mergedBuffering)
          const Center(
            child: SizedBox(
              width: 44,
              height: 44,
              child: CircularProgressIndicator(
                color: SpotifyColors.highlight,
                strokeWidth: 3,
              ),
            ),
          ),

        // Double-tap seek hint chip.
        if (_seekHintSide != 0) _seekHint(),

        // CONTROLS overlay — fades; always shown while paused.
        AnimatedOpacity(
          opacity: showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          child: IgnorePointer(
            ignoring: !showControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.black.withOpacity(0.25)),

                if (!_mergedBuffering && !_mergedPlaying)
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

                if (!_fullscreen)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _fullscreenButton(
                        icon: Icons.fullscreen_rounded),
                  ),

                // Transport row: prev · play/pause · next.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_queueIndex > 0)
                        _transportButton(
                          onTap: () => _playFromQueue(_queueIndex - 1),
                          icon: Transform.rotate(
                            angle: math.pi,
                            child: const Icon(
                                FluentIcons.next_24_filled,
                                size: 26,
                                color: Colors.white),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                      const SizedBox(width: 10),
                      _transportButton(
                        onTap: _togglePlay,
                        big: true,
                        icon: Icon(
                          _mergedPlaying
                              ? FluentIcons.pause_16_filled
                              : Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_queueIndex < _queue.length - 1)
                        _transportButton(
                          onTap: () => _playFromQueue(_queueIndex + 1),
                          icon: const Icon(FluentIcons.next_24_filled,
                              size: 26, color: Colors.white),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _MergedProgressBar(
                    position: _mergedPos,
                    duration: _mergedDur,
                    onSeek: (f) {
                      final ch = _nativeChannel;
                      if (ch == null || _mergedDur <= Duration.zero) {
                        return;
                      }
                      ch.invokeMethod(
                        'seekTo',
                        (f * _mergedDur.inMilliseconds).round(),
                      ).catchError((_) {});
                      // YouTube parity: releasing the scrubber
                      // resumes playback.
                      if (!_mergedPlaying) {
                        ch.invokeMethod('play').catchError((_) {});
                        _mergedPlaying = true;
                        if (mounted) setState(() {});
                      }
                      _pokeControls();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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

            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _DualProgressBar(),
            ),

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

  // ── Muxed surface (fallback — single file, <=720p) ──

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
            onPressed: () => _playFromQueue(_queueIndex),
            child: const Text('Retry',
                style: TextStyle(
                    color: SpotifyColors.background,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Channel avatar: native-fetched artist art when available,
  /// letter-on-brass fallback otherwise (nothing faked).
  Widget _channelAvatar(String artist) {
    final letter = artist.isNotEmpty ? artist[0].toUpperCase() : '?';
    final url = _channelThumb;
    return Container(
      width: 30,
      height: 30,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: SpotifyColors.green,
      ),
      child: (url == null || url.isEmpty)
          ? Text(
        letter,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: SpotifyColors.background),
      )
          : Image.network(
        url,
        width: 30,
        height: 30,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Text(
          letter,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: SpotifyColors.background),
        ),
      ),
    );
  }

  // ── Info block (YouTube feel): title, channel, actions ──

  Widget _infoBlock() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: SpotifyColors.textPrimary)),
          const SizedBox(height: 6),
          Row(
            children: [
              _channelAvatar(v.artist),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: SpotifyColors.textSecondary)),
              ),
              // Real action only — copy link (no like/dislike
              // backend for YouTube videos; nothing faked).
              GestureDetector(
                onTap: _copyLink,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: SpotifyColors.surfaceLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text('Copy link',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: SpotifyColors.textPrimary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Up next (the queue tail, YouTube-style list) ──

  List<Song> get _upNext => (_queueIndex + 1 <= _queue.length - 1)
      ? _queue.sublist(_queueIndex + 1)
      : const <Song>[];

  Widget _upNextSection() {
    final upNext = _upNext;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Text('Up next',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
        ),
        if (_loadingRelated && upNext.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: CircularProgressIndicator(
                    color: SpotifyColors.highlight)),
          )
        else if (upNext.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('Nothing queued yet.',
                style: TextStyle(
                    fontSize: 13, color: SpotifyColors.textSecondary)),
          )
        else
          for (var i = 0; i < upNext.length; i++)
            _upNextRow(upNext[i], i == 0),
      ],
    );
  }

  Widget _upNextRow(Song s, bool isFirst) {
    return InkWell(
      onTap: () {
        final idx = _queue.indexWhere((q) => identical(q, s));
        if (idx > _queueIndex) _playFromQueue(idx);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                YoutubeThumbnail(
                  videoId: s.id,
                  imageUrl: s.thumbnail,
                  width: 130,
                  height: 73,
                  borderRadius: 8,
                ),
                if (s.duration > Duration.zero)
                  Positioned(
                    right: 5,
                    bottom: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(3),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isFirst)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Text('UP NEXT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: SpotifyColors.highlight)),
                    ),
                  Text(s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          color: SpotifyColors.textPrimary)),
                  const SizedBox(height: 3),
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
    );
  }
}

// ═════════════════════════════════════════════
// MERGED PROGRESS BAR — used in native-merged mode. Scrubbable
// (YouTube-style). Position/duration arrive from the screen's
// 500ms poll of the native player; drags seek via the channel.
// ═════════════════════════════════════════════

class _MergedProgressBar extends StatefulWidget {
  const _MergedProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<double> onSeek;

  @override
  State<_MergedProgressBar> createState() => _MergedProgressBarState();
}

class _MergedProgressBarState extends State<_MergedProgressBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final fraction = _dragFraction ??
        (totalMs > 0
            ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0);

    Duration durationFor(double f) =>
        Duration(milliseconds: (f * totalMs).round());

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (_dragFraction == null) return;
        final f = _dragFraction!;
        _dragFraction = null;
        widget.onSeek(f);
      },
      onHorizontalDragStart: (d) {
        if (totalMs <= 0) return;
        setState(() => _dragFraction =
            (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0));
      },
      onHorizontalDragUpdate: (d) {
        if (totalMs <= 0 || context.size == null) return;
        setState(() => _dragFraction =
            (d.localPosition.dx / context.size!.width).clamp(0.0, 1.0));
      },
      onHorizontalDragEnd: (_) {
        final f = _dragFraction;
        _dragFraction = null;
        if (f != null) widget.onSeek(f);
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
                left: MediaQuery.sizeOf(context).width * fraction - 7,
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
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_dragFraction != null
                      ? durationFor(fraction)
                      : widget.position),
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _fmt(widget.duration),
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
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ═════════════════════════════════════════════
// DUAL PROGRESS BAR — used only in dual fallback mode. Scrubbable
// (YouTube-style). Position from the handler's audio clock (the
// master clock in dual mode); taps and drags seek the AUDIO via
// seekSafe — VideoBackdrop's drift correction then pulls the muted
// video back into sync.
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