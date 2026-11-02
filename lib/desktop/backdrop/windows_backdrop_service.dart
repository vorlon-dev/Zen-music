// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
    try {
      final box = Hive.box('SETTINGS');
      final dynamic stored = box.get(_kEnabledKey);
      if (stored is bool) _enabled = stored;
    } catch (e) {
      debugPrint('[backdrop] settings read failed (defaulting to on): $e');
    }
    if (!_enabled) {
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


  Future<void> _startup() async {
    if (_dead || _player != null) return;
    try {
      MediaKit.ensureInitialized();

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
