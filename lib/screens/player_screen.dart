import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/physics.dart';
import '../services/echomusic_canvas_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// WAKELOCK: requires `flutter pub add wakelock_plus`.
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/audio_device_service.dart';
import '../services/audio_output_service.dart';
import '../widgets/audio_device_sheet.dart';
import '../widgets/cookie_play_button.dart';
import '../widgets/player_backgrounds.dart';
import '../widgets/status_chip.dart';
import '../widgets/wave_spinner.dart';
import '../main.dart';
import '../models/song.dart';
import '../services/appearance_prefs.dart';
import '../services/apple_canvas_service.dart';
import '../services/downloads_service.dart';
import '../services/listen_together_service.dart';
import '../services/video_preference_service.dart';
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
import 'ambient_mode_screen.dart';
import 'artist_screen.dart';
import 'listen_together_screen.dart';

/// Subtle haptic tick for transport interactions when enabled.
void _maybeHaptic() {
  if (AppearancePrefs.haptics.value) HapticFeedback.selectionClick();
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;

  // Video state (extracted stream, synchronized song-video mode).
  bool _showVideo = false;
  bool _videoLoading = false;
  String? _videoUrl;
  Map<String, String> _videoHeaders = const {};
  String? _videoForSongId;
  String? _resolvingFor;
  bool _videoTriedSd = false;

  // Fullscreen video (YouTube-style): landscape + immersive.
  bool _videoFullscreen = false;

  // Apple Music canvas (animated artwork background).
  String? _canvasUrl;
  String? _canvasForSongId;
  final Set<String> _canvasFailed = {};

  // Prefetched video streams — resolved in the background while the
  // audio plays, so switching to video mode is instant. The caches
  // are APP-LIFETIME (owned by YoutubeService statics) so they
  // survive player close/reopen — no backdrop refetch on re-entry.
  final Map<String, VideoStreamResult> _videoPrefetch =
      YoutubeService.videoPrefetchCache;
  final Set<String> _videoPrefetchFailed =
      YoutubeService.videoPrefetchFailed;
  String? _prefetchInFlight;

  // Song queued with "Play with video" — the player enters video mode
  // for this id on its first current-song tick.
  String? _pendingVideoSongId;

  List<Song> _relatedSongs = [];
  String? _relatedForId;
  bool _lyricsSynced = false;

  StreamSubscription<Song?>? _songSub;

  final _yt = YoutubeService();

  // ── Track-change slide state ──
  bool _slideForward = true;
  bool? _pendingSlideForward;
  DateTime _slideIntentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSlideSongId;

  @override
  void initState() {
    super.initState();
    AppearancePrefs.load();
    _loadRelated();

    AudioDeviceService.instance.start();

    _songSub = audioHandler.currentSongStream.listen((song) {
      if (!mounted || song == null) return;
      if (_lyricsSynced) setState(() => _lyricsSynced = false);
      _loadRelated();
      if (_showVideo) _resolveVideoFor(song);
      _resolveCanvas(song);
      _prefetchVideoFor(song);
      VideoPreferenceService.instance
          .isVideoPreferred(song.id)
          .then((preferred) {
        if (!mounted || !preferred) return;
        if (audioHandler.currentSong?.id != song.id) return;
        if (_showVideo) return;
        _toggleVideo(song);
      });
      if (_pendingVideoSongId == song.id) {
        _pendingVideoSongId = null;
        if (!_showVideo) _toggleVideo(song);
      }
    });

    AppearancePrefs.keepScreenOn.addListener(_applyKeepScreenOn);
    _applyKeepScreenOn();

    AppearancePrefs.hideStatusBarOnLyrics.addListener(_applySystemUi);
    AppearancePrefs.canvasEnabled.addListener(_onCanvasPrefChanged);
  }

  void _applyKeepScreenOn() {
    if (AppearancePrefs.keepScreenOn.value) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _applySystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _setLyricsOpen(bool open) {
    setState(() => _showLyrics = open);
  }

  void _noteSlideIntent(bool forward) {
    _pendingSlideForward = forward;
    _slideIntentAt = DateTime.now();
  }

  void _consumeSlideIntentIfNeeded(Song song) {
    if (song.id == _lastSlideSongId) return;
    final pending = _pendingSlideForward;
    if (pending != null &&
        DateTime.now().difference(_slideIntentAt) <
            const Duration(milliseconds: 3000)) {
      _slideForward = pending;
    }
    _pendingSlideForward = null;
    _lastSlideSongId = song.id;
  }

  @override
  void dispose() {
    AppearancePrefs.keepScreenOn.removeListener(_applyKeepScreenOn);
    AppearancePrefs.hideStatusBarOnLyrics.removeListener(_applySystemUi);
    AppearancePrefs.canvasEnabled.removeListener(_onCanvasPrefChanged);
    if (_videoFullscreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    WakelockPlus.disable(); // WAKELOCK
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

  // ── Apple Music canvas ──

  void _onCanvasPrefChanged() {
    if (!mounted) return;
    if (!AppearancePrefs.canvasEnabled.value) {
      if (_canvasUrl != null) {
        setState(() {
          _canvasUrl = null;
          _canvasForSongId = null;
        });
      }
    } else {
      final song = audioHandler.currentSong;
      if (song != null) _resolveCanvas(song);
    }
  }

  Future<void> _resolveCanvas(Song song) async {
    if (!AppearancePrefs.canvasEnabled.value ||
        song.thumbnail.isEmpty ||
        _canvasFailed.contains(song.id)) {
      return;
    }
    if (_canvasForSongId == song.id) return;
    _canvasForSongId = song.id;
    String? canvasUrl;
    final echo = await EchomusicCanvasService.instance
        .getBySongArtist(song.title, song.artist);
    if (!mounted) return;
    if (audioHandler.currentSong?.id != song.id) return;
    if (echo != null && echo.videoUrl.isNotEmpty) {
      canvasUrl = echo.videoUrl;
      print('Canvas: echomusic match for "${song.title}"');
    } else {
      final apple = await AppleCanvasService.instance
          .getBySongArtist(song.title, song.artist);
      if (!mounted) return;
      if (audioHandler.currentSong?.id != song.id) return;
      if (apple != null && apple.animated.isNotEmpty) {
        canvasUrl = apple.animated;
        print('Canvas: Apple Music match for "${song.title}"');
      }
    }
    if (canvasUrl == null || canvasUrl.isEmpty) {
      _canvasFailed.add(song.id);
      setState(() => _canvasUrl = null);
      return;
    }
    setState(() => _canvasUrl = canvasUrl);
  }

  // ── Video prefetch ──

  Future<void> _prefetchVideoFor(Song song) async {
    if (_videoPrefetch.containsKey(song.id) ||
        _videoPrefetchFailed.contains(song.id) ||
        _prefetchInFlight == song.id) {
      return;
    }
    _prefetchInFlight = song.id;
    try {
      final result = await _yt.getVideoStreamUrl(song, preferHd: true);
      if (!mounted) return;
      if (audioHandler.currentSong?.id != song.id) return;
      if (result != null && result.url.isNotEmpty) {
        _videoPrefetch[song.id] = result;
      } else {
        _videoPrefetchFailed.add(song.id);
      }
    } catch (_) {
      _videoPrefetchFailed.add(song.id);
    } finally {
      _prefetchInFlight = null;
    }
  }

  Future<void> _toggleVideo(Song song) async {
    if (_showVideo) {
      setState(() => _showVideo = false);
      VideoPreferenceService.instance.setPreferred(song.id, false);
      return;
    }

    if (_videoForSongId == song.id && _videoUrl != null) {
      setState(() => _showVideo = true);
      return;
    }

    final prefetched = _videoPrefetch[song.id];
    if (prefetched != null) {
      setState(() {
        _videoUrl = prefetched.url;
        _videoHeaders = prefetched.headers;
        _videoForSongId = song.id;
        _showVideo = true;
      });
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
      _videoPrefetch[song.id] = result;
    });
  }

  void _onVideoUnavailable(String reason) {
    if (!mounted) return;
    if (_videoFullscreen) _exitVideoFullscreen();

    if (!_videoTriedSd) {
      _videoTriedSd = true;
      final song = audioHandler.currentSong;
      if (song != null && _showVideo) {
        print('Video: HD failed ($reason) — retrying SD');
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

  void _enterVideoFullscreen() {
    if (!_showVideo || _videoUrl == null) return;
    setState(() => _videoFullscreen = true);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // WAKELOCK
  }

  void _exitVideoFullscreen() {
    if (!_videoFullscreen) return;
    setState(() => _videoFullscreen = false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    AppearancePrefs.keepScreenOn.value
        ? WakelockPlus.enable()
        : WakelockPlus.disable(); // WAKELOCK
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

    _consumeSlideIntentIfNeeded(song);

    if (_videoFullscreen && _showVideo && _videoUrl != null) {
      return WillPopScope(
        onWillPop: () async {
          _exitVideoFullscreen();
          return false;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              VideoBackdrop(
                streamUrl: _videoUrl!,
                playing: controller.isPlaying,
                httpHeaders: _videoHeaders,
                synchronized: true,
                positionStream: handler.positionStream,
                posterUrl: song.thumbnail,
                onUnavailable: (reason) {
                  _exitVideoFullscreen();
                  _onVideoUnavailable(reason);
                },
              ),
              Center(
                child: GestureDetector(
                  onTap: () {
                    _maybeHaptic();
                    controller.isPlaying
                        ? audioHandler.pause()
                        : audioHandler.play();
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      controller.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _exitVideoFullscreen,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.fullscreen_exit_rounded,
                          size: 22, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_showVideo && _videoUrl != null) ...[
            Positioned.fill(
              child: VideoBackdrop(
                streamUrl: _videoUrl!,
                playing: controller.isPlaying,
                httpHeaders: _videoHeaders,
                synchronized: true,
                positionStream: handler.positionStream,
                posterUrl: song.thumbnail,
                onUnavailable: _onVideoUnavailable,
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _enterVideoFullscreen,
              ),
            ),
          ] else if (_canvasUrl != null)
            Positioned.fill(
              child: VideoBackdrop(
                key: ValueKey(_canvasUrl),
                streamUrl: _canvasUrl!,
                playing: controller.isPlaying,
                httpHeaders: const {},
                shortLoop: true,
                onUnavailable: (reason) {
                  print('AppleCanvas: playback unavailable ($reason)');
                  if (!mounted) return;
                  final id = audioHandler.currentSong?.id;
                  if (id != null) _canvasFailed.add(id);
                  setState(() => _canvasUrl = null);
                },
              ),
            )
          else
            Positioned.fill(
              child: ValueListenableBuilder<String>(
                valueListenable: AppearancePrefs.playerBackground,
                builder: (context, bg, _) {
                  final hasArt = song.thumbnail.isNotEmpty;
                  if (bg == 'blur' && hasArt) {
                    return _BlurBackground(imageUrl: song.thumbnail);
                  }
                  if (bg == 'glow' && hasArt) {
                    return GlowBackground(imageUrl: song.thumbnail);
                  }
                  if (bg == 'mesh' && hasArt) {
                    return MeshBackground(imageUrl: song.thumbnail);
                  }
                  if (bg == 'apple' && hasArt) {
                    return AppleArtworkBackground(imageUrl: song.thumbnail);
                  }
                  if (bg == 'solid') {
                    return const ColoredBox(color: Colors.black);
                  }
                  return GradientBackground(
                    imageUrl: song.thumbnail,
                    child: const SizedBox.expand(),
                  );
                },
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

          if (_showVideo || _canvasUrl != null)
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

  Widget _slideOnChange({
    required String slideKey,
    required Widget child,
    AlignmentGeometry stackAlignment = Alignment.center,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: stackAlignment,
        clipBehavior: Clip.hardEdge,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(slideKey);
        final Offset slideFrom = incoming
            ? Offset(_slideForward ? 0.26 : -0.26, 0)
            : Offset(_slideForward ? -0.26 : 0.26, 0);
        return IgnorePointer(
          ignoring: !incoming,
          child: FadeTransition(
            opacity: incoming
                ? Tween<double>(begin: 0.35, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut))
                : Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeIn)),
            child: SlideTransition(
              position: Tween<Offset>(begin: slideFrom, end: Offset.zero)
                  .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(slideKey),
        child: child,
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
            ValueListenableBuilder<bool>(
              valueListenable: AppearancePrefs.hideThumbnail,
              builder: (context, hidden, _) => hidden
                  ? const SizedBox(height: 24)
                  : Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
                child: _slideOnChange(
                  slideKey: song.id,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragEnd: (d) {
                      final v = d.primaryVelocity ?? 0;
                      if (v < -300) {
                        _maybeHaptic();
                        _noteSlideIntent(true);
                        handler.skipToNext();
                      } else if (v > 300) {
                        _maybeHaptic();
                        _noteSlideIntent(false);
                        handler.skipToPrevious();
                      }
                    },
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Hero(
                        tag: 'artwork-${song.id}',
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                AppearancePrefs.thumbRadius.value),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                                AppearancePrefs.thumbRadius.value),
                            child: LayoutBuilder(
                              builder: (context, box) {
                                final size = box.maxWidth;
                                return Image.network(
                                  song.thumbnail,
                                  width: size,
                                  height: size,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: SpotifyColors.surfaceLight,
                                    child: const Icon(
                                        Icons.music_note_rounded,
                                        size: 64,
                                        color: SpotifyColors.textTertiary),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
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
              onTap: () => _setLyricsOpen(true),
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
                  child: _slideOnChange(
                    slideKey: 'meta-${song.id}',
                    stackAlignment: Alignment.centerLeft,
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
                        const SizedBox(height: 6),
                        ValueListenableBuilder<bool>(
                          valueListenable: AppearancePrefs.showQualityBadge,
                          builder: (context, show, _) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (show)
                                Flexible(
                                  child: StreamBuilder<Map<String, String?>>(
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
                                          color: SpotifyColors.green
                                              .withOpacity(0.15),
                                          borderRadius:
                                          BorderRadius.circular(6),
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
                                ),
                              if (_showVideo) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('VIDEO',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: Colors.redAccent)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
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

          const SizedBox(height: 14),
          ValueListenableBuilder<LtRoomSnapshot?>(
            valueListenable: ListenTogetherService.instance.roomNotifier,
            builder: (context, ltRoom, _) {
              final locked = ListenTogetherService.instance.isInRoom &&
                  !ListenTogetherService.instance.isHost;
              return Column(
                children: [
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: SpotifyColors.green.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Host controls playback',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: SpotifyColors.green),
                        ),
                      ),
                    ),
                  ValueListenableBuilder<String>(
                    valueListenable: AppearancePrefs.sliderStyle,
                    builder: (context, style, _) => switch (style) {
                      'bar' =>
                          _BarSlider(
                              handler: handler, song: song, locked: locked),
                      'wavy' =>
                          _WavySlider(
                              handler: handler, song: song, locked: locked),
                      _ =>
                          _SlimSlider(
                              handler: handler, song: song, locked: locked),
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _PlayerControls(
            handler: handler,
            controller: controller,
            song: song,
            onSkipIntent: _noteSlideIntent,
          ),
          const _DeviceRow(),
          const SizedBox(height: 18),
          _smallIconsRow(song),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: LyricsPreviewCard(
              title: song.title,
              artist: song.artist,
              duration: song.duration,
              onShowFull: () => _setLyricsOpen(true),
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
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
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
          if (_showVideo && _videoUrl != null)
            IconButton(
              tooltip: 'Fullscreen video',
              splashRadius: 22,
              icon: const Icon(
                Icons.fullscreen_rounded,
                size: 28,
                color: SpotifyColors.textPrimary,
              ),
              onPressed: _enterVideoFullscreen,
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
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
            onPressed: () => _setLyricsOpen(true),
          ),
          _DownloadButton(song: song),
          IconButton(
            splashRadius: 20,
            tooltip: 'Ambient mode',
            icon: const Icon(
              Icons.auto_awesome,
              color: SpotifyColors.textSecondary,
              size: 22,
            ),
            onPressed: () => pushSharedAxisY(
              context,
              const AmbientModeScreen(),
            ),
          ),
          IconButton(
            splashRadius: 20,
            tooltip: 'Listen together',
            icon: const Icon(
              Icons.people_outline,
              color: SpotifyColors.textSecondary,
              size: 22,
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
              size: 22,
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
              onPressed: () => _setLyricsOpen(false),
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
                onPressed: () {
                  _maybeHaptic();
                  _noteSlideIntent(false);
                  handler.skipToPrevious();
                },
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
                        onTap: () {
                          _maybeHaptic();
                          playing
                              ? handler.pause()
                              : handler.play();
                        },
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
                onPressed: () {
                  _maybeHaptic();
                  _noteSlideIntent(true);
                  handler.skipToNext();
                },
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
// SLIDER TIME ROW
// ═════════════════════════════════════════════

class _SliderTimeRow extends StatelessWidget {
  final dynamic handler;
  final String left;
  final String right;

  const _SliderTimeRow({
    required this.handler,
    required this.left,
    required this.right,
  });

  static const _timeStyle = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    color: SpotifyColors.textSecondary,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              left,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _timeStyle,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: ValueListenableBuilder<bool>(
              valueListenable: AppearancePrefs.showQualityBadge,
              builder: (context, showBadge, _) => StatusChip(
                playbackState: handler.playbackState,
                qualityStream: handler.audioQualityStream,
                showCodec: !showBadge,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: _timeStyle,
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SLIM SLIDER
// ═════════════════════════════════════════════

class _SlimSlider extends StatefulWidget {
  final dynamic handler;
  final Song song;
  final bool locked;

  const _SlimSlider({
    required this.handler,
    required this.song,
    this.locked = false,
  });

  @override
  State<_SlimSlider> createState() => _SlimSliderState();
}

class _SlimSliderState extends State<_SlimSlider> {
  double? _dragFraction;
  bool _seekPending = false;
  double _streamFraction = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.handler.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (_dragFraction == null && !_seekPending) {
          _streamFraction = _fractionOf(p);
        }
      });
    });
    _stateSub = widget.handler.playbackState.listen((st) {
      if (!mounted || _dragFraction != null || _seekPending) return;
      final p = st.updatePosition;
      if ((p - _position).abs() > const Duration(milliseconds: 400)) {
        setState(() {
          _position = p;
          _streamFraction = _fractionOf(p);
        });
      }
    });
    _durSub = widget.handler.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
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

  void _endDrag() async {
    if (widget.locked) return;
    final f = _dragFraction;
    if (f == null) return;
    final total = _effectiveDuration.inMilliseconds;
    if (total <= 0) {
      setState(() => _dragFraction = null);
      return;
    }
    final targetMs = (f * total).round();
    setState(() {
      _seekPending = true;
      _dragFraction = null;
    });
    final ok =
    await widget.handler.seekSafe(Duration(milliseconds: targetMs));
    if (!mounted) return;
    if (!ok) {
      _seekPending = false;
      setState(() {});
      return;
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _seekPending = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (_dragFraction ?? _streamFraction).clamp(0.0, 1.0);
    final shownPosition = _dragFraction != null
        ? Duration(
        milliseconds:
        (fraction * _effectiveDuration.inMilliseconds).round())
        : (_seekPending
        ? Duration(
        milliseconds:
        (fraction * _effectiveDuration.inMilliseconds).round())
        : _position);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              const trackH = 4.0;
              const thumbR = 7.0;
              final usable = width - thumbR * 2;
              final thumbX = thumbR + usable * fraction;

              void setDrag(double localX) {
                if (widget.locked) return;
                setState(() => _dragFraction =
                    ((localX - thumbR) / usable).clamp(0.0, 1.0).toDouble());
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragEnd: (_) => _endDrag(),
                onHorizontalDragCancel: () {
                  if (mounted) setState(() => _dragFraction = null);
                },
                onTapUp: (d) {
                  if (widget.locked) return;
                  final f = ((d.localPosition.dx - thumbR) / usable)
                      .clamp(0.0, 1.0)
                      .toDouble();
                  _dragFraction = f;
                  _endDrag();
                },
                onTapCancel: () {
                  if (mounted) setState(() => _dragFraction = null);
                },
                child: SizedBox(
                  height: 28,
                  width: width,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: (28 - trackH) / 2,
                        child: Container(
                          height: trackH,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(trackH),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: (28 - trackH) / 2,
                        child: Container(
                          height: trackH,
                          width: thumbX.clamp(0.0, width),
                          decoration: BoxDecoration(
                            color: SpotifyColors.green,
                            borderRadius: BorderRadius.circular(trackH),
                          ),
                        ),
                      ),
                      Positioned(
                        left: thumbX - thumbR,
                        top: (28 - thumbR * 2) / 2,
                        child: Container(
                          width: thumbR * 2,
                          height: thumbR * 2,
                          decoration: BoxDecoration(
                            color: widget.locked
                                ? SpotifyColors.textTertiary
                                : SpotifyColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        _SliderTimeRow(
          handler: widget.handler,
          left: _fmt(shownPosition),
          right: _fmt(_effectiveDuration),
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

// ═════════════════════════════════════════════
// WAVY SLIDER
// ═════════════════════════════════════════════

class _WavySlider extends StatefulWidget {
  final dynamic handler;
  final Song song;
  final bool locked;

  const _WavySlider({
    required this.handler,
    required this.song,
    this.locked = false,
  });

  @override
  State<_WavySlider> createState() => _WavySliderState();
}

class _WavySliderState extends State<_WavySlider>
    with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  late final AnimationController _amp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 0,
  );

  bool _playing = false;
  double? _dragFraction;
  bool _seekPending = false;
  double _streamFraction = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.handler.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (_dragFraction == null && !_seekPending) {
          _streamFraction = _fractionOf(p);
        }
      });
    });
    _stateSub = widget.handler.playbackState.listen((st) {
      if (!mounted || _dragFraction != null || _seekPending) return;
      final p = st.updatePosition;
      if ((p - _position).abs() > const Duration(milliseconds: 400)) {
        setState(() {
          _position = p;
          _streamFraction = _fractionOf(p);
        });
      }
    });
    _durSub = widget.handler.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });

    _playing = widget.handler.playbackState.value.playing;
    if (_playing) {
      _phase.repeat();
      _amp.value = 1;
    }
    _playingSub = widget.handler.playingStream.listen((playing) {
      if (!mounted || playing == _playing) return;
      setState(() => _playing = playing);
      if (playing) {
        _phase.repeat();
        _amp.forward();
      } else {
        _amp.reverse();
        _phase.stop();
      }
    });
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  double _fractionOf(Duration p) {
    final total = _effectiveDuration.inMilliseconds;
    if (total <= 0) return 0;
    return (p.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }

  Duration get _effectiveDuration =>
      _duration.inSeconds > 0 ? _duration : widget.song.duration;

  void _endDrag() async {
    if (widget.locked) return;
    final f = _dragFraction;
    if (f == null) return;
    final total = _effectiveDuration.inMilliseconds;
    if (total <= 0) {
      setState(() => _dragFraction = null);
      return;
    }
    final targetMs = (f * total).round();
    setState(() {
      _seekPending = true;
      _dragFraction = null;
    });
    final ok =
    await widget.handler.seekSafe(Duration(milliseconds: targetMs));
    if (!mounted) return;
    if (!ok) {
      _seekPending = false;
      setState(() {});
      return;
    }
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _seekPending = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fraction = (_dragFraction ?? _streamFraction).clamp(0.0, 1.0);
    final shownPosition = _dragFraction != null
        ? Duration(
        milliseconds:
        (fraction * _effectiveDuration.inMilliseconds).round())
        : (_seekPending
        ? Duration(
        milliseconds:
        (fraction * _effectiveDuration.inMilliseconds).round())
        : _position);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;

              void setDrag(double localX) {
                if (widget.locked) return;
                setState(() => _dragFraction =
                    (localX / width).clamp(0.0, 1.0).toDouble());
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setDrag(d.localPosition.dx),
                onHorizontalDragEnd: (_) => _endDrag(),
                onHorizontalDragCancel: () {
                  if (mounted) setState(() => _dragFraction = null);
                },
                onTapUp: (d) {
                  if (widget.locked) return;
                  final f =
                  (d.localPosition.dx / width).clamp(0.0, 1.0).toDouble();
                  _dragFraction = f;
                  _endDrag();
                },
                onTapCancel: () {
                  if (mounted) setState(() => _dragFraction = null);
                },
                child: SizedBox(
                  height: 34,
                  width: width,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_phase, _amp]),
                    builder: (context, _) => CustomPaint(
                      size: Size(width, 34),
                      painter: _WavyPainter(
                        progress: fraction,
                        phase: _phase.value * 2 * math.pi,
                        amplitude: _amp.value,
                        color: SpotifyColors.green,
                        dimColor: Colors.white.withOpacity(0.18),
                        thumbColor: widget.locked
                            ? SpotifyColors.textTertiary
                            : SpotifyColors.green,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        _SliderTimeRow(
          handler: widget.handler,
          left: _fmt(shownPosition),
          right: _fmt(_effectiveDuration),
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

class _WavyPainter extends CustomPainter {
  final double progress;
  final double phase;
  final double amplitude;
  final Color color;
  final Color dimColor;
  final Color thumbColor;

  _WavyPainter({
    required this.progress,
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.dimColor,
    required this.thumbColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    const wavelength = 26.0;
    const maxAmp = 3.2;
    final amp = maxAmp * amplitude;

    final path = Path();
    var first = true;
    for (var x = 0.0; x <= size.width; x += 2) {
      final y = mid + math.sin((x / wavelength) * 2 * math.pi + phase) * amp;
      if (first) {
        path.moveTo(x, y);
        first = false;
      } else {
        path.lineTo(x, y);
      }
    }

    final dimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = dimColor;
    canvas.drawPath(path, dimPaint);

    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
        0, 0, size.width * progress.clamp(0.0, 1.0), size.height));
    canvas.drawPath(path, activePaint);
    canvas.restore();

    canvas.drawCircle(
      Offset(size.width * progress.clamp(0.0, 1.0), mid),
      7,
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_WavyPainter old) =>
      old.progress != progress ||
          old.phase != phase ||
          old.amplitude != amplitude;
}

// ═════════════════════════════════════════════
// BAR SLIDER
// ═════════════════════════════════════════════

class _BarSlider extends StatefulWidget {
  final dynamic handler;
  final Song song;
  final bool locked;

  const _BarSlider({
    required this.handler,
    required this.song,
    this.locked = false,
  });

  @override
  State<_BarSlider> createState() => _BarSliderState();
}

class _BarSliderState extends State<_BarSlider> {
  double? _dragFraction;
  bool _seekPending = false;
  double _streamFraction = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription? _stateSub;
  StreamSubscription<Duration?>? _durSub;

  @override
  void initState() {
    super.initState();
    _posSub = widget.handler.positionStream.listen((p) {
      if (!mounted) return;
      setState(() {
        _position = p;
        if (_dragFraction == null && !_seekPending) {
          _streamFraction = _fractionOf(p);
        }
      });
    });
    _stateSub = widget.handler.playbackState.listen((st) {
      if (!mounted || _dragFraction != null || _seekPending) return;
      final p = st.updatePosition;
      if ((p - _position).abs() > const Duration(milliseconds: 400)) {
        setState(() {
          _position = p;
          _streamFraction = _fractionOf(p);
        });
      }
    });
    _durSub = widget.handler.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    final value = (_dragFraction ?? _streamFraction).clamp(0.0, 1.0);
    final shown = _dragFraction != null
        ? Duration(
        milliseconds:
        (value * _effectiveDuration.inMilliseconds).round())
        : _position;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value,
            activeColor: SpotifyColors.green,
            onChanged: locked
                ? null
                : (v) => setState(() => _dragFraction = v),
            onChangeEnd: locked
                ? null
                : (v) {
              final total = _effectiveDuration;
              if (total.inMilliseconds > 0) {
                widget.handler.seekSafe(Duration(
                    milliseconds:
                    (v * total.inMilliseconds).round()));
              }
              setState(() => _dragFraction = null);
            },
          ),
        ),
        _SliderTimeRow(
          handler: widget.handler,
          left: _fmt(shown),
          right: _fmt(_effectiveDuration),
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

// ═════════════════════════════════════════════
// PLAY BUTTON
// ═════════════════════════════════════════════

class _PlayButton extends StatefulWidget {
  final dynamic handler;
  final Song song;
  final bool playing;
  final bool locked;

  const _PlayButton({
    required this.handler,
    required this.song,
    required this.playing,
    this.locked = false,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: widget.handler.playbackState,
      builder: (context, stateSnap) {
        final st = stateSnap.data;
        final buffering = st != null &&
            (st.processingState == AudioProcessingState.loading ||
                st.processingState == AudioProcessingState.buffering);
        return CookiePlayButton(
          playing: widget.playing,
          loading: buffering,
          size: 84,
          onToggle: () {
            if (widget.locked || buffering) return;
            _maybeHaptic();
            widget.playing
                ? widget.handler.pause()
                : widget.handler.play();
          },
        );
      },
    );
  }
}

// ═════════════════════════════════════════════
// TRANSPORT BUTTON
// ═════════════════════════════════════════════

class _TransportButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _TransportButton({required this.icon, this.onPressed});

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale =
  AnimationController(vsync: this, value: 1.0);

  static final _pressSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 0.6,
  );

  void _setPressed(bool pressed) {
    _scale.animateWith(
      SpringSimulation(_pressSpring, _scale.value, pressed ? 0.9 : 1.0, 0),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTap: widget.onPressed,
        child: Transform.scale(
          scale: _scale.value,
          child: SizedBox(
            width: 68,
            height: 68,
            child: Center(
              child: Icon(
                widget.icon,
                size: 34,
                color: enabled ? Colors.white : SpotifyColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// BLUR BACKGROUND
// ═════════════════════════════════════════════

class _BlurBackground extends StatelessWidget {
  final String imageUrl;
  const _BlurBackground({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
          const ColoredBox(color: Colors.black),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: ColoredBox(color: Colors.black.withOpacity(0.45)),
        ),
      ],
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
  final ValueChanged<bool>? onSkipIntent;

  const _PlayerControls({
    required this.handler,
    required this.controller,
    required this.song,
    this.onSkipIntent,
  });

  @override
  State<_PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<_PlayerControls> {
  bool _shuffleOn = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  bool get _locked =>
      ListenTogetherService.instance.isInRoom &&
          !ListenTogetherService.instance.isHost;

  void _toggleShuffle() {
    if (_locked) return;
    _maybeHaptic();
    setState(() => _shuffleOn = !_shuffleOn);
    widget.handler.setShuffleMode(
      _shuffleOn ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  void _cycleRepeat() {
    if (_locked) return;
    _maybeHaptic();
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
    final locked = _locked;
    final repeatOn = _repeatMode != AudioServiceRepeatMode.none;

    // ── OVERFLOW FIX ──
    // Natural row width was 316 px (48 + 68 + 84 + 68 + 48) which
    // overflows the 312 px available inside the 24 px horizontal
    // padding on a 360 dp screen. The four non-play controls are now
    // each wrapped in Flexible+FittedBox(scaleDown), so they shrink
    // proportionally on any narrow screen — down to ~240 dp — without
    // ever throwing a RenderFlex overflow. The play button stays at
    // its natural size (it's the visual anchor).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: IconButton(
                iconSize: 22,
                splashRadius: 20,
                icon: Icon(
                  _shuffleOn
                      ? FluentIcons.arrow_shuffle_24_filled
                      : FluentIcons.arrow_shuffle_off_24_regular,
                  color: _shuffleOn
                      ? SpotifyColors.green
                      : (locked
                      ? SpotifyColors.textTertiary
                      : SpotifyColors.textSecondary),
                ),
                onPressed: locked ? null : _toggleShuffle,
              ),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _TransportButton(
                icon: FluentIcons.previous_24_regular,
                onPressed: locked
                    ? null
                    : () {
                  _maybeHaptic();
                  widget.onSkipIntent?.call(false);
                  handler.skipToPrevious();
                },
              ),
            ),
          ),
          _PlayButton(
            handler: handler,
            song: widget.song,
            playing: widget.controller.isPlaying,
            locked: locked,
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _TransportButton(
                icon: FluentIcons.next_24_regular,
                onPressed: locked
                    ? null
                    : () {
                  _maybeHaptic();
                  widget.onSkipIntent?.call(true);
                  handler.skipToNext();
                },
              ),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: IconButton(
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
                      : (locked
                      ? SpotifyColors.textTertiary
                      : SpotifyColors.textSecondary),
                ),
                onPressed: locked ? null : _cycleRepeat,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DEVICE ROW
// ═════════════════════════════════════════════

class _DeviceRow extends StatefulWidget {
  const _DeviceRow();

  @override
  State<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends State<_DeviceRow> {
  AudioOutputDevice? _active;
  static const _prio = {
    'bluetooth': 0,
    'wired': 1,
    'usb': 2,
    'hdmi': 3,
    'speaker': 4,
  };

  @override
  void initState() {
    super.initState();
    _load();
    AudioDeviceService.instance.deviceName.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    AudioDeviceService.instance.deviceName.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final devices = await AudioOutputService.instance.listDevices();
    if (!mounted) return;
    AudioOutputDevice? active;
    for (final t in const ['wired', 'usb', 'hdmi', 'speaker']) {
      active = devices.where((d) => d.type == t).firstOrNull;
      if (active != null) break;
    }
    setState(() => _nonBtActive = active);
  }

  AudioOutputDevice? _nonBtActive;

  @override
  Widget build(BuildContext context) {
    final btName = AudioDeviceService.instance.deviceName.value;

    final IconData icon;
    final String name;

    if (btName != null && btName.isNotEmpty) {
      icon = AudioDeviceService.isSpeaker(btName)
          ? Icons.speaker_rounded
          : (AudioDeviceService.isBuds(btName)
          ? Icons.earbuds_rounded
          : Icons.headset_rounded);
      name = btName;
    } else {
      final device = _nonBtActive;
      icon = switch (device?.type) {
        'wired' => Icons.headphones_rounded,
        'usb' => Icons.usb_rounded,
        'hdmi' => Icons.tv_rounded,
        _ => Icons.phone_android_rounded,
      };
      name = device?.name ?? 'Phone speaker';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAudioDeviceSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: SpotifyColors.textSecondary.withOpacity(0.8)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SpotifyColors.textSecondary.withOpacity(0.8),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                size: 14,
                color: SpotifyColors.textSecondary.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}