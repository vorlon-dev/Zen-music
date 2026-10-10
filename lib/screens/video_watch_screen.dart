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
import '../widgets/playlist_sheets.dart';
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

/// Dedicated YouTube video watch page.
///
/// TIER ORDER (do not reorder — native innertube merged is FIRST):
/// 1. MERGED — video-only + audio-only from ONE native player
///    response inside a single MergingMediaSource: one player,
///    video and audio together, 1080p, zero drift. Bot-gated IP →
///    the Dart visionOs video URL bridges into the same player
///    with the native audio. Error/never-READY (~10s) → down-chain.
/// 2. MUXED — single file ≤720p via video_player.
/// 3. DUAL — video-only stream + handler audio (last fallback).
///
/// QUEUE: rooted at the opened video, related tail (radio → native
/// watch-next), auto-advance on end, tap-jump re-roots the tail.
///
/// BACKGROUND: back on merged/muxed transfers the audio to the
/// handler at the CURRENT position (pause → wait READY → seek →
/// play — the from-start regression is fixed); reopening the mini
/// player returns here at the LIVE handler position.
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

  // ── Queue ──
  List<Song> _queue = [];
  int _queueIndex = 0;
  bool _advancing = false;

  // MERGED mode (primary).
  MethodChannel? _nativeChannel;
  String? _mergedVideoUrl;
  String? _mergedAudioUrl;
  Map<String, String> _mergedHeaders = const {};
  Duration _mergedPos = Duration.zero;
  Duration _mergedDur = Duration.zero;
  bool _mergedPlaying = false;
  Timer? _mergedPoll;
  // Stall detection — GENEROUS (~10s = 20 polls).
  int _stallPolls = 0;
  bool _mergedWasReady = false;

  // ── YouTube-feel controls (merged tier) ──
  bool _controlsVisible = true;
  bool _mergedBuffering = false;
  Timer? _hideTimer;
  int _seekHintSide = 0;
  Timer? _seekHintTimer;

  // ── Quality picker (merged tier) ──
  // The cached heights for the current video, the chosen cap
  // (0 = Auto), and the switch-in-progress flag.
  List<ItxVideoQuality> _qualities = [];
  int _qualityCap = 0; // 0 = Auto
  bool _switchingQuality = false;

  // Channel avatar — fetched ONLY after playback is running (+4s).
  String? _channelThumb;
  Timer? _artDelayTimer;

  // More-sheet state: loop + playback speed (session-scoped).
  bool _loopVideo = false;
  double _playbackSpeed = 1.0;

  // Dual mode.
  String? _dualVideoUrl;
  Map<String, String> _dualHeaders = const {};

  // Muxed mode.
  VideoPlayerController? _muxedController;
  bool _muxedReady = false;

  String? _loadedId;
  bool _fullscreen = false;
  bool _loadingRelated = true;
  String? _resolveError;

  // Background/mini-player session state.
  Duration? _resumePosition;
  bool _transferred = false;

  // Bot-gate short-circuit: native video extraction returned null
  // once → skip the native attempt for the rest of the session.
  bool _nativeVideoGated = false;

  Song? get _current =>
      (_queueIndex >= 0 && _queueIndex < _queue.length)
          ? _queue[_queueIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _resumePosition = widget.startPosition;
    _transferred = false;
    _nativeVideoGated = false;
    _queue = [
      Song(
        id: widget.videoId,
        title: widget.title ?? 'Video',
        artist: widget.artist ?? 'YouTube',
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
    if (!_transferred) VideoSession.clear();
    _exitFullscreen();
    _muxedController?.dispose();
    super.dispose();
  }

  // ── Fullscreen ──

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
    // REGRESSION #1 (do not regress to edgeToEdge).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.disable();
  }

  void _toggleFullscreen() {
    _fullscreen ? _exitFullscreen() : _enterFullscreen();
  }

  Future<bool> _onWillPop() async {
    if (_fullscreen) {
      _exitFullscreen();
      return false;
    }
    if (_mode == _WatchMode.merged || _mode == _WatchMode.muxed) {
      await _transferToHandler();
    } else {
      VideoSession.clear();
    }
    return true;
  }

  /// Hands the current video's audio to the handler at the CURRENT
  /// position. The handler's stream needs a moment to load — pause,
  /// wait for READY, THEN seek: seeking before the source is loaded
  /// was silently dropped and the audio started from 0 (regression).
  Future<void> _transferToHandler() async {
    if (_transferred) return;
    _transferred = true;
    final song = _current;
    if (song == null) return;
    try {
      // Already playing this exact video in the handler (a
      // reopen-then-back cycle) — it keeps playing live; no restart.
      final handlerPlaying = audioHandler.playbackState.value.playing;
      final handlerId = audioHandler.mediaItem.value?.id;
      if (handlerPlaying && handlerId == song.id) return;

      final pos = _mode == _WatchMode.merged
          ? _mergedPos
          : _muxedController?.value.position;
      SongSourceResolver.instance.markExplicit(song);
      await audioHandler.setQueue([song], startIndex: 0);
      await audioHandler.pause();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (true) {
        final st = audioHandler.playbackState.value.processingState;
        if (st == AudioProcessingState.ready ||
            st == AudioProcessingState.completed) {
          break;
        }
        if (DateTime.now().isAfter(deadline)) break;
        await Future.delayed(const Duration(milliseconds: 120));
      }
      if (pos != null && pos > Duration.zero) {
        await audioHandler.seekSafe(pos);
        // Guard against the seek racing the source swap: verify the
        // position took, retry once if the player reset to ~0.
        await Future.delayed(const Duration(milliseconds: 250));
        final now = audioHandler.playbackState.value.position;
        if (now < const Duration(seconds: 2) && pos > const Duration(seconds: 3)) {
          await audioHandler.seekSafe(pos);
        }
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

  Future<void> _extendQueueWithRelated(String videoId) async {
    setState(() => _loadingRelated = true);
    var fresh = <Song>[];
    try {
      final related = await _yt.getYtmRadio(videoId);
      fresh = related.where((s) => s.id != videoId).take(20).toList();
    } catch (_) {}
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
      // New video → the quality list belongs to the OLD video.
      _qualities = [];
      _qualityCap = 0;
      _switchingQuality = false;
    });

    final merged = await _startMerged(videoId);
    if (!mounted) return;
    if (merged) return;

    final started = await _startMuxed(videoId);
    if (!mounted) return;
    if (started) return;

    final dual = await _startDualMode();
    if (!mounted) return;
    if (dual) return;

    setState(() {
      _mode = _WatchMode.failed;
      _resolveError =
      'Could not load this video. It may be restricted or offline — try another.';
    });
  }

  /// PRIMARY: native merged player via innertube. When YouTube is
  /// bot-gating this IP (native video clients refuse), the Dart
  /// visionOs VIDEO url bridges into the SAME ExoPlayer with the
  /// native AUDIO — one player, video + audio together, as before.
  /// [_qualityCap] rides along: a picked quality re-extracts at
  /// that height.
  Future<bool> _startMerged(String videoId) async {
    await audioHandler.pause();
    if (!mounted) return false;

    final native = await InnertubexBridge.extractVideo(
      videoId,
      maxHeight: _qualityCap,
    );
    if (!mounted) return false;
    if (native == null) _nativeVideoGated = true;

    var videoUrl = native?.videoUrl ?? '';
    var audioUrl = native?.audioUrl ?? '';
    var headers = native?.headers ?? const <String, String>{};

    // SOURCE B — the bot-gate bridge (native video dead but the
    // Dart visionOs video path still resolves; native audio chain
    // is a separate client set and often answers when video is
    // gated). The quality cap does NOT apply to the bridge path —
    // the Dart path has no per-height selection.
    if (_nativeVideoGated || videoUrl.isEmpty || audioUrl.isEmpty) {
      final song = _current;
      if (song == null) return false;
      final videoStream = await _yt.getVideoStreamUrl(song);
      if (!mounted) return false;
      if (videoStream == null || videoStream.url.isEmpty) return false;
      final nativeAudio = await InnertubexBridge.extract(
        videoId,
        maxKbps: 320,
      );
      if (!mounted) return false;
      if (nativeAudio == null || nativeAudio.url.isEmpty) return false;
      videoUrl = videoStream.url;
      headers = videoStream.headers;
      audioUrl = nativeAudio.url;
    }
    if (videoUrl.isEmpty || audioUrl.isEmpty) return false;

    final old = _nativeChannel;
    _nativeChannel = null;
    if (old != null) {
      old.invokeMethod('release').catchError((_) {});
    }

    _stallPolls = 0;
    _mergedWasReady = false;

    setState(() {
      _mergedVideoUrl = videoUrl;
      _mergedAudioUrl = audioUrl;
      _mergedHeaders = headers;
      _mergedPlaying = true;
      _mergedBuffering = true;
      _controlsVisible = true;
      _loadedId = videoId;
      _mode = _WatchMode.merged;
    });

    // Session registration — plain static assignments (Dart
    // cascades cannot set statics through the class name).
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
    _pokeControls();
    print('Watch: merged tier (native innertube) $videoId');
    return true;
  }

  void _onNativeViewCreated(int viewId) {
    final channel = MethodChannel('zen/video_player_$viewId');
    _nativeChannel = channel;
    // Resume applies on every prepare of THIS screen instance when a
    // session position exists (reopen mid-video recreates the view).
    final resume = _resumePosition ?? VideoSession.position;
    channel
        .invokeMethod('prepare', {
      'videoUrl': _mergedVideoUrl,
      'audioUrl': _mergedAudioUrl,
      'headers': _mergedHeaders,
      'startPositionMs': resume?.inMilliseconds ?? 0,
    })
        .catchError((_) {});
    // Re-apply session loop/speed to the fresh player.
    if (_loopVideo) {
      channel.invokeMethod('setLoop', true).catchError((_) {});
    }
    if (_playbackSpeed != 1.0) {
      channel.invokeMethod('setSpeed', _playbackSpeed).catchError((_) {});
    }
    // Pull the quality list once the player machinery is up — the
    // native extraction populated the cache.
    final id = _loadedId;
    if (id != null && _qualities.isEmpty) {
      InnertubexBridge.videoQualities(id).then((q) {
        if (mounted && q.isNotEmpty) setState(() => _qualities = q);
      });
    }
  }

  Future<void> _pollMerged() async {
    final ch = _nativeChannel;
    if (ch == null) return;
    try {
      final raw = await ch.invokeMethod('position');
      if (!mounted) return;
      if (raw is! Map) return;

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
        if (!wasReady) {
          _artDelayTimer?.cancel();
          _artDelayTimer = Timer(const Duration(seconds: 4), () {
            final id = _loadedId;
            if (id != null) _loadChannelThumb(id);
          });
          // Late quality pull: the cache fills with the same
          // extraction that served playback.
          final id = _loadedId;
          if (id != null && _qualities.isEmpty) {
            InnertubexBridge.videoQualities(id).then((q) {
              if (mounted && q.isNotEmpty) setState(() => _qualities = q);
            });
          }
        }
      } else if (!_mergedWasReady) {
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
      VideoSession.position = _mergedPos;
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

  Future<bool> _startMuxed(String videoId) async {
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
    await c.setLooping(_loopVideo);
    if (_playbackSpeed != 1.0) {
      await c.setPlaybackSpeed(_playbackSpeed);
    }
    // Resume (mini-player reopen) — muxed fallback honors it too.
    final resume = _resumePosition;
    _resumePosition = null;
    if (resume != null && resume > Duration.zero) {
      await c.seekTo(resume);
    }
    await c.play();

    setState(() {
      _loadedId = videoId;
      _mode = _WatchMode.muxed;
      _muxedReady = true;
    });

    final currentSong = _current;
    if (currentSong != null) {
      VideoSession.active = true;
      VideoSession.videoId = videoId;
      VideoSession.title = currentSong.title;
      VideoSession.artist = currentSong.artist;
      VideoSession.thumbnail = currentSong.thumbnail;
      //VideoSession.position = Duration.zero;
    }

    print('Watch: muxed tier $videoId');

    if (c.value.size.width > c.value.size.height && mounted) {
      _enterFullscreen();
    }
    return true;
  }

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

  Future<void> _loadChannelThumb(String videoId) async {
    final url = await InnertubexBridge.channelThumb(videoId);
    if (!mounted || url == null || url.isEmpty) return;
    if (_loadedId != videoId) return;
    setState(() => _channelThumb = url);
  }

  // ── QUALITY (YouTube parity) ──

  /// YouTube-style quality sheet: Auto + every cached height. A
  /// pick re-extracts the video stream at that height from the
  /// native quality cache and re-prepares the merged player AT THE
  /// CURRENT POSITION — audio layer untouched.
  Future<void> _qualitySheet() async {
    if (_qualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpotifyColors.surfaceLight,
          content: Text('Quality options unavailable for this video',
              style: TextStyle(color: SpotifyColors.textPrimary)),
        ),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Quality for current video',
                    style: TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: Icon(
                  _qualityCap == 0
                      ? Icons.check_rounded
                      : Icons.auto_awesome_rounded,
                  color: _qualityCap == 0
                      ? SpotifyColors.highlight
                      : SpotifyColors.textPrimary),
              title: const Text('Auto (best)',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () => Navigator.pop(sheetContext, 0),
            ),
            for (final q in _qualities)
              ListTile(
                leading: Icon(
                    _qualityCap == q.height
                        ? Icons.check_rounded
                        : Icons.hd_outlined,
                    color: _qualityCap == q.height
                        ? SpotifyColors.highlight
                        : SpotifyColors.textPrimary),
                title: Text('${q.height}p',
                    style: TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                subtitle: q.kbps > 0
                    ? Text('${q.kbps} kbps',
                    style: const TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 12))
                    : null,
                onTap: () => Navigator.pop(sheetContext, q.height),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ).then((picked) {
      if (picked is! int) return;
      if (picked == _qualityCap) return;
      _applyQuality(picked);
    });
  }

  /// Applies a quality cap: re-extracts the video stream at the
  /// chosen height (native quality-cache fast path — no second
  /// player call) and re-prepares the merged player at the current
  /// position. Audio layer unchanged.
  Future<void> _applyQuality(int cap) async {
    final videoId = _loadedId;
    if (videoId == null || _mode != _WatchMode.merged) return;
    setState(() {
      _qualityCap = cap;
      _switchingQuality = true;
    });
    final native = await InnertubexBridge.extractVideo(
      videoId,
      maxHeight: cap,
    );
    if (!mounted) return;
    final newUrl = native?.videoUrl;
    if (newUrl == null || newUrl.isEmpty) {
      // Cache missed the height — keep current quality, report.
      setState(() => _switchingQuality = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: SpotifyColors.surfaceLight,
          content: Text('Could not switch quality — kept current',
              style: TextStyle(color: SpotifyColors.textPrimary)),
        ),
      );
      return;
    }
    final pos = _mergedPos;
    final wasPlaying = _mergedPlaying;
    setState(() {
      _mergedVideoUrl = newUrl;
      _mergedHeaders = native?.headers ?? _mergedHeaders;
      _mergedBuffering = true;
      _mergedPlaying = wasPlaying;
    });
    final ch = _nativeChannel;
    if (ch != null) {
      await ch.invokeMethod('prepare', {
        'videoUrl': newUrl,
        'audioUrl': _mergedAudioUrl,
        'headers': _mergedHeaders,
        'startPositionMs': pos.inMilliseconds,
      }).catchError((_) {});
      if (wasPlaying) {
        ch.invokeMethod('play').catchError((_) {});
      }
    }
    if (mounted) setState(() => _switchingQuality = false);
    _pokeControls();
  }

  // ── More-sheet actions (Loop / Playback speed) ──

  Future<void> _setLoop(bool loop) async {
    setState(() => _loopVideo = loop);
    switch (_mode) {
      case _WatchMode.merged:
        _nativeChannel?.invokeMethod('setLoop', loop).catchError((_) {});
        break;
      case _WatchMode.muxed:
        await _muxedController?.setLooping(loop);
        break;
      default:
        break;
    }
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    switch (_mode) {
      case _WatchMode.merged:
        _nativeChannel?.invokeMethod('setSpeed', speed).catchError((_) {});
        break;
      case _WatchMode.muxed:
        await _muxedController?.setPlaybackSpeed(speed);
        break;
      default:
        break;
    }
  }

  void _moreSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            SwitchListTile(
              activeColor: SpotifyColors.highlight,
              secondary: const Icon(Icons.repeat_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Loop video',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              value: _loopVideo,
              onChanged: (v) {
                _setLoop(v);
                if (mounted) setState(() {});
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Playback speed',
                    style: TextStyle(
                        color: SpotifyColors.textSecondary, fontSize: 13)),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: speeds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final s = speeds[i];
                  final selected = _playbackSpeed == s;
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: selected,
                    selectedColor: SpotifyColors.highlight,
                    backgroundColor: SpotifyColors.surfaceLight,
                    labelStyle: TextStyle(
                      color: selected
                          ? SpotifyColors.background
                          : SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) {
                      _setSpeed(s);
                      Navigator.pop(sheetContext);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── YouTube-feel controls helpers (merged tier) ──

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

  void _onSurfaceTap() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _pokeControls();
    }
  }

  void _onDoubleTapZone(int side) => _seekBy(side < 0 ? -10 : 10);

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

  /// Share = copy link (real action).
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

    // YouTube portrait layout: video pinned at the very top (the
    // app is immersive — no status bar), content list below. No
    // AppBar — the YT search bar is deliberately not reproduced.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: SpotifyColors.background,
        body: Column(
          children: [
            _videoArea(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (_mode == _WatchMode.failed)
                    _errorBlock()
                  else ...[
                    _titleBlock(),
                    _channelRow(),
                    _actionRow(),
                    Container(
                      height: 1,
                      color: SpotifyColors.surfaceLighter,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    _upNextSection(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoArea() {
    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _videoSurface(),
      ),
    );
  }

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

  Widget _mergedSurface() {
    if (_mergedVideoUrl == null) return _loadingSurface();
    final showControls =
        _controlsVisible || (!_mergedPlaying && !_mergedBuffering);
    final frac = _mergedDur > Duration.zero
        ? (_mergedPos.inMilliseconds / _mergedDur.inMilliseconds)
        .clamp(0.0, 1.0)
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        AndroidView(
          key: ValueKey('native_player_$_loadedId'),
          viewType: 'zen_video_player',
          onPlatformViewCreated: _onNativeViewCreated,
          creationParamsCodec: const StandardMessageCodec(),
        ),

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

        // Quality-switch indicator (distinct state from buffering).
        if (_switchingQuality)
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

        if (_seekHintSide != 0) _seekHint(),

        // YouTube parity: thin red progress line at the video's
        // bottom edge while the controls are hidden.
        if (!showControls)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: frac,
              child: Container(height: 2, color: Colors.redAccent),
            ),
          ),

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
                    child: Row(
                      children: [
                        // Quality gear (YouTube parity) — hidden while
                        // switching; opens the quality sheet.
                        if (!_switchingQuality)
                          GestureDetector(
                            onTap: _qualitySheet,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.tune_rounded,
                                  size: 22, color: Colors.white),
                            ),
                          ),
                        if (!_switchingQuality) const SizedBox(width: 8),
                        _fullscreenButton(
                            icon: Icons.fullscreen_rounded),
                      ],
                    ),
                  ),

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
  Widget _channelAvatar(String artist, {double size = 30}) {
    final letter = artist.isNotEmpty ? artist[0].toUpperCase() : '?';
    final url = _channelThumb;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: SpotifyColors.green,
      ),
      child: (url == null || url.isEmpty)
          ? Text(
        letter,
        style: TextStyle(
            fontSize: size * 0.45,
            fontWeight: FontWeight.w800,
            color: SpotifyColors.background),
      )
          : Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Text(
          letter,
          style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.w800,
              color: SpotifyColors.background),
        ),
      ),
    );
  }

  // ── YouTube-style content blocks ──

  Widget _titleBlock() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(v.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: SpotifyColors.textPrimary)),
    );
  }

  Widget _channelRow() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Row(
        children: [
          _channelAvatar(v.artist, size: 34),
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
        ],
      ),
    );
  }

  /// YouTube action row — REAL actions only:
  /// Like (local liked songs) · Share (copy link) · Save (app
  /// playlists) · More (loop + speed). Subscribe/dislike are
  /// deliberately absent — no YouTube account backend; nothing faked.
  Widget _actionRow() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    final liked = v != null && storage.isLiked(v.id);

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool active = false,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 24,
                    color: active
                        ? SpotifyColors.highlight
                        : SpotifyColors.textPrimary),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? SpotifyColors.highlight
                            : SpotifyColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          action(
            icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
            label: liked ? 'Liked' : 'Like',
            active: liked,
            onTap: () async {
              final song = v;
              if (song == null) return;
              final newValue = !liked;
              setState(() {});
              try {
                await storage.setLiked(song, newValue);
              } catch (_) {}
              if (mounted) setState(() {});
            },
          ),
          action(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: _copyLink,
          ),
          action(
            icon: Icons.playlist_add_rounded,
            label: 'Save',
            onTap: () {
              final song = v;
              if (song == null) return;
              showAddToPlaylistSheet(context, song);
            },
          ),
          action(
            icon: Icons.more_horiz,
            label: 'More',
            onTap: _moreSheet,
          ),
        ],
      ),
    );
  }

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
// MERGED PROGRESS BAR — scrubbable; position/duration arrive from
// the screen's 500ms poll of the native player.
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
// DUAL PROGRESS BAR — dual fallback mode only.
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