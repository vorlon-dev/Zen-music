import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
      final Player player = Player();
      await player.setVolume(0.0); // never any double audio
      await player.setPlaylistMode(PlaylistMode.loop); // video loops forever
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
      final List<MuxedStreamInfo> muxed = manifest.muxed.toList();
      if (muxed.isEmpty) throw Exception('no muxed video stream available');
      muxed.sort((MuxedStreamInfo a, MuxedStreamInfo b) =>
          a.videoResolution.height.compareTo(b.videoResolution.height));
      // Sharpest stream that is still ≤720p — for a blurred layer 360p
      // (YouTube's usual muxed ceiling) is plenty and keeps bandwidth low.
      final MuxedStreamInfo pick = muxed.lastWhere(
            (MuxedStreamInfo s) => s.videoResolution.height <= 720,
        orElse: () => muxed.first,
      );
      final Player? player = _player;
      if (player == null) return;
      await player.open(Media(pick.url.toString()), play: _isPlaying);
      if (token != _resolveToken || !_enabled) return;
      _setState(WindowsBackdropState.active);
      debugPrint(
          '[backdrop] video ${pick.videoResolution.width}x'
              '${pick.videoResolution.height} → $videoId');
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