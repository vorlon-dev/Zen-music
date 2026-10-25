// ZenMusic Desktop — SP-29: Windows video backdrop (service).
//
// Resolves the current track's YouTube video (via youtube_explode_dart)
// and plays it MUTED in a dedicated media_kit player whose texture the
// WindowsVideoBackdrop widget (windows_backdrop.dart) renders as the
// player screen's blurred 16:9 canvas backdrop.
//
// Doctrine — same as smtc/discord/lastfm/mini/overlay:
//  • This is the ONLY file that touches youtube_explode / media_kit video.
//  • Windows-only (hard Platform.isWindows guard everywhere).
//  • init() is idempotent; failures latch _dead for the session and the
//    backdrop silently disappears — playback is never touched.
//  • The media player (media_player.dart SP-29 block) drives this service
//    from the existing notifiers: trackChanged / playing / paused /
//    seekTo. Everything here is fire-and-swallow.
//  • The video is a separate muted player (muxed ≤360p30 when YouTube
//    still serves one, else a video-only DASH fallback — SP-35): the
//    audio path (just_audio → mpv) is completely untouched. No double
//    audio — volume is pinned at 0.
//  • Toggle lives in Hive ('VIDEO_BACKDROP', default ON), controlled from
//    Saved → Video backdrop (backdrop_page.dart).
//
// SP-35 — two hardening fixes after the first live Windows log:
//  1. YouTube stopped serving muxed (progressive) streams for most music
//     videos ("no muxed video stream available" → backdrop hidden). The
//     pick now falls back to a video-only DASH stream: for a muted,
//     blurred layer the audio track is irrelevant (volume pinned at 0).
//  2. The libmpv build loaded at runtime may lack video decoding (stale
//     incremental build, or libmpv-2.dll resolved from %PATH% instead of
//     the app dir). media_kit_video's VideoController then dies with
//     "[VideoController] is not available…" — thrown asynchronously via
//     a fire-and-forget Completer, surfacing as an Unhandled Exception
//     while the layer silently never renders. _startup() now runs the
//     SAME decoder query media_kit_video uses (queryDecoders — its
//     result is cached process-wide, so the verdict is identical) and
//     latches _dead with one actionable log line instead. It also logs
//     the size of the libmpv-2.dll sitting next to the exe: video builds
//     are many tens of MB; a small or missing file is the smoking gun
//     (fix: flutter clean && flutter pub get && rebuild).
//
// SP-35b — compile fix: media_kit_video >=1.3.0 changed queryDecoders to
//  return HashSet<String> (was List<String> in 1.2.x) — a breaking API
//  change inside 1.x that the ^1.2.5 constraint silently resolves to.
//  The decoder variable now uses type inference — the exact pattern
//  media_kit_video's own native_video_controller/real.dart uses — so the
//  file compiles against any of those return types.
//
// Design notes:
//  • The video loops (PlaylistMode.loop) — most songs outlast their video.
//  • The blur makes small drift between video and audio invisible; user
//    seeks are forwarded so the layer realigns on every manual seek.
//  • Resolution failures (age-restricted, embed-blocked, offline, YouTube
//    layout changes) hide the backdrop and retry ONCE after 20 s — no
//    hammering, no error UI. The next track change retries naturally.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
// SP-35: media_kit_video's own decoder probe — the exact util its
// NativeVideoController.create() uses internally (and caches), so the
// verdict here and there is always identical.
// ignore: implementation_imports
import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Lifecycle of the backdrop layer (drives the widget + the setup page).
enum WindowsBackdropState {
  /// Toggle off (or not started yet) — nothing rendered.
  off,

  /// Looking up the video stream for the current track.
  resolving,

  /// Muted video playing/paused behind the UI.
  active,

  /// This track has no usable video (unavailable / offline / restricted) —
  /// nothing rendered until the next track.
  hidden,
}

class WindowsBackdropService {
  WindowsBackdropService._();
  static final WindowsBackdropService instance = WindowsBackdropService._();

  static const String _kEnabledKey = 'VIDEO_BACKDROP';

  bool _inited = false;
  bool _dead = false;
  bool _enabled = true;
  bool _isPlaying = false;

  WindowsBackdropState _state = WindowsBackdropState.off;
  final ValueNotifier<WindowsBackdropState> _stateNotifier =
  ValueNotifier<WindowsBackdropState>(WindowsBackdropState.off);

  Player? _player;
  VideoController? _controller;
  YoutubeExplode? _yt;
  String? _currentVideoId;
  int _resolveToken = 0;
  Timer? _retryTimer;

  // ── public surface ──────────────────────────────────────────────────

  ValueListenable<WindowsBackdropState> get state => _stateNotifier;

  VideoController? get videoController => _controller;

  bool get isEnabled => _enabled;

  bool get isSupported => Platform.isWindows;

  /// Called once from media_player.dart's `_initBackdrop()`. Safe to call
  /// on any platform — off-Windows this is a permanent no-op.
  Future<void> init() async {
    if (!Platform.isWindows) return;
    if (_inited) return;
    _inited = true;
    debugPrint('[backdrop] init — Windows video backdrop');
    try {
      final box = Hive.box('SETTINGS');
      final dynamic stored = box.get(_kEnabledKey);
      if (stored is bool) _enabled = stored;
    } catch (e) {
      debugPrint('[backdrop] settings read failed (defaulting to on): $e');
    }
    if (!_enabled) {
      debugPrint('[backdrop] disabled in settings — staying off');
      return;
    }
    await _startup();
  }

  /// Toggle from the Saved → Video backdrop page. Persisted in Hive.
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      Hive.box('SETTINGS').put(_kEnabledKey, value);
    } catch (_) {}
    debugPrint('[backdrop] enabled: $value');
    if (!Platform.isWindows || _dead) return;
    if (value) {
      await _startup();
      if (_player != null && _currentVideoId != null) {
        _resolve(_currentVideoId!);
      }
    } else {
      _retryTimer?.cancel();
      ++_resolveToken;
      _isPlaying = false;
      _fire(() async {
        await _player?.pause();
      });
      _setState(WindowsBackdropState.off);
    }
  }

  /// New current track (MediaItem.id — a YouTube videoId for YT songs,
  /// null for Spotify-engine/local tracks). Pushed by media_player.dart.
  void trackChanged({String? videoId}) {
    _retryTimer?.cancel();
    final String? id =
    (videoId == null || videoId.isEmpty || videoId.startsWith('spotify:'))
        ? null
        : videoId;
    // Always remember the latest id so enabling the backdrop mid-track
    // (Saved → Video backdrop) can pick the song up immediately.
    _currentVideoId = id;
    if (!_inited || _dead || !_enabled) return;
    if (id == null) {
      _fire(() async {
        await _player?.pause();
      });
      // Nothing playing / non-video source: only replace a visible layer;
      // keep "off" as "off" at app start so the status stays honest.
      if (_state == WindowsBackdropState.active ||
          _state == WindowsBackdropState.resolving) {
        _setState(WindowsBackdropState.hidden);
      }
      return;
    }
    _resolve(id);
  }

  /// Audio is playing — keep the layer moving (after resolution).
  void playing() {
    _isPlaying = true;
    if (!_inited || _dead || !_enabled) return;
    if (_state == WindowsBackdropState.active) {
      _fire(() => _player!.play());
    }
  }

  /// Audio paused/buffering — freeze the layer.
  void paused() {
    _isPlaying = false;
    if (!_inited || _dead || !_enabled) return;
    if (_state == WindowsBackdropState.active) {
      _fire(() => _player!.pause());
    }
  }

  /// User seeked the audio — realign the layer (best effort, blurred
  /// anyway). Pushed from media_player.dart's seekTo().
  void seekTo(Duration position) {
    if (!_inited || _dead || !_enabled) return;
    if (_state == WindowsBackdropState.active) {
      _fire(() => _player!.seek(position));
    }
  }

  /// Called from media_player.dart's dispose(). Tears the video player
  /// down; a later init() can start fresh.
  Future<void> shutdown() async {
    _retryTimer?.cancel();
    ++_resolveToken;
    _inited = false;
    _dead = false;
    _isPlaying = false;
    _setState(WindowsBackdropState.off);
    try {
      await _player?.dispose();
    } catch (_) {}
    try {
      _yt?.close();
    } catch (_) {}
    _player = null;
    _controller = null;
    _yt = null;
  }

  // ── internals ───────────────────────────────────────────────────────

  Future<void> _startup() async {
    if (_dead || _player != null) return;
    try {
      MediaKit.ensureInitialized();

      // SP-35: which libmpv did we actually load? The video texture only
      // works with the video-capable DLL that media_kit_libs_windows_video
      // bundles next to the exe (tens of MB). A stale incremental build or
      // a stray copy picked up via %PATH% has no h264 decoder — logging
      // the size makes that instantly visible in the log.
      try {
        final String exeDir = File(Platform.resolvedExecutable).parent.path;
        final File dll = File('$exeDir\\libmpv-2.dll');
        if (dll.existsSync()) {
          final double mb = dll.lengthSync() / (1024 * 1024);
          debugPrint(
              '[backdrop] libmpv-2.dll ${mb.toStringAsFixed(1)} MB in app dir');
        } else {
          debugPrint(
              '[backdrop] libmpv-2.dll NOT found in app dir — mpv likely resolved from %PATH%');
        }
      } catch (_) {}

      final Player player = Player();
      await player.setVolume(0.0); // never any double audio
      await player.setPlaylistMode(PlaylistMode.loop); // video loops forever

      // SP-35: probe video-decoder support BEFORE creating the
      // VideoController. NativeVideoController.create runs this exact
      // query internally (cached process-wide → identical verdict), but
      // when it fails there the error escapes through a fire-and-forget
      // Completer as an "Unhandled Exception" and the layer silently
      // never renders. Probing here turns that into one clean, actionable
      // log line and latches _dead.
      try {
        final int handle = await player.handle;
        // SP-35b: type inference, NOT List<String> — media_kit_video
        // >=1.3.0 returns HashSet<String> here (1.2.x: List<String>).
        // .contains('h264') works on both; same as real.dart:135.
        final decoders = await queryDecoders(handle);
        if (!decoders.contains('h264')) {
          _dead = true;
          debugPrint(
              '[backdrop] libmpv has NO h264 decoder — the loaded libmpv-2.dll '
                  'is not the video build. Keep media_kit_libs_windows_video in '
                  'pubspec.yaml, then flutter clean && flutter pub get && rebuild.');
          _fire(() => player.dispose());
          return;
        }
      } catch (e) {
        // Probe itself could not run — leave the decision to the
        // controller creation below (same as pre-SP-35 behavior).
        debugPrint('[backdrop] decoder probe skipped (non-fatal): $e');
      }

      final VideoController controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      _player = player;
      _controller = controller;
      debugPrint('[backdrop] video player ready (muted, looping)');
    } catch (e) {
      _dead = true;
      _player = null;
      _controller = null;
      debugPrint('[backdrop] init failed — disabled this session: $e');
    }
  }

  Future<void> _resolve(String videoId) async {
    final int token = ++_resolveToken;
    _setState(WindowsBackdropState.resolving);
    try {
      final YoutubeExplode yt = _yt ??= YoutubeExplode();
      final StreamManifest manifest =
      await yt.videos.streamsClient.getManifest(videoId);
      if (token != _resolveToken || !_enabled || _dead) return;

      // SP-35: pick a video URL. Muxed (audio+video, ≤360p30) is preferred
      // when YouTube still serves one, but most music videos are DASH-only
      // now — and for a muted, blurred layer the audio track is irrelevant
      // anyway (volume pinned at 0), so a video-only DASH stream is a
      // perfect fallback. Either way: sharpest stream still ≤ the cap,
      // else the smallest one above it.
      String url;
      int width = 0;
      int height = 0;
      final List<MuxedStreamInfo> muxed = manifest.muxed.toList()
        ..sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
            a.videoResolution.height.compareTo(b.videoResolution.height));
      if (muxed.isNotEmpty) {
        final MuxedStreamInfo pick = muxed.lastWhere(
              (MuxedStreamInfo s) => s.videoResolution.height <= 720,
          orElse: () => muxed.first,
        );
        url = pick.url.toString();
        width = pick.videoResolution.width;
        height = pick.videoResolution.height;
      } else {
        final List<VideoOnlyStreamInfo> videoOnly = manifest.videoOnly.toList()
          ..sort((VideoOnlyStreamInfo a, VideoOnlyStreamInfo b) =>
              a.videoResolution.height.compareTo(b.videoResolution.height));
        if (videoOnly.isEmpty) {
          throw Exception('no video stream available (muxed & DASH both empty)');
        }
        // ≤480p for the DASH fallback — under the σ=10 blur that is
        // indistinguishable from 720p and keeps bandwidth (incl. loop
        // re-fetches) cheap.
        final VideoOnlyStreamInfo pick = videoOnly.lastWhere(
              (VideoOnlyStreamInfo s) => s.videoResolution.height <= 480,
          orElse: () => videoOnly.first,
        );
        url = pick.url.toString();
        width = pick.videoResolution.width;
        height = pick.videoResolution.height;
        debugPrint(
            '[backdrop] no muxed stream — DASH video-only fallback for $videoId');
      }

      final Player? player = _player;
      if (player == null) return;
      await player.open(Media(url), play: _isPlaying);
      if (token != _resolveToken || !_enabled) return;
      _setState(WindowsBackdropState.active);
      debugPrint('[backdrop] video ${width}x$height → $videoId');
    } catch (e) {
      if (token != _resolveToken || !_enabled) return;
      _setState(WindowsBackdropState.hidden);
      debugPrint('[backdrop] resolve failed for $videoId — hidden: $e');
      // One quiet retry for transient failures; the next track change
      // retries naturally anyway.
      _retryTimer = Timer(const Duration(seconds: 20), () {
        if (_enabled &&
            _currentVideoId == videoId &&
            _state == WindowsBackdropState.hidden) {
          debugPrint('[backdrop] retrying $videoId…');
          _resolve(videoId);
        }
      });
    }
  }

  void _setState(WindowsBackdropState s) {
    if (_state == s) return;
    _state = s;
    _stateNotifier.value = s;
  }

  /// Fire-and-swallow — a backdrop hiccup must never ripple upward.
  Future<void> _fire(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e) {
      debugPrint('[backdrop] call failed (ignored): $e');
    }
  }
}