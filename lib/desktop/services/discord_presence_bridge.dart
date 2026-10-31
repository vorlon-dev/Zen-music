import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_discord_rpc/flutter_discord_rpc.dart';
import 'package:hive_flutter/hive_flutter.dart';

const String kDiscordApplicationId = '1563182260516028516';

class _NowPlaying {
  final String title;
  final String artist;
  final String? artUrl;
  final String key; // stable per-track id for dedupe
  const _NowPlaying(this.title, this.artist, this.artUrl, this.key);
}

class DiscordPresenceBridge {
  DiscordPresenceBridge._();
  static final DiscordPresenceBridge instance = DiscordPresenceBridge._();

  bool _ready =
      false; // initialize() done — talking to the plugin is now legal
  bool _connected = false; // IPC handshake with the Discord client finished
  bool _dead = false; // init failed once — never retry, never crash again
  bool _noId = false; // no application id configured yet
  Timer? _reconnect;

  _NowPlaying? _track;
  bool? _lastPlaying; // true = playing, false = paused, null = stopped
  DateTime _elapsedAnchor = DateTime.now();
  String? _lastSig;

  bool get isReady => _ready;

  /// Call once at startup (idempotent). Safe on every platform.
  Future<void> init() async {
    if (_ready || _dead) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    final String appId = _resolveAppId();
    if (appId.isEmpty) {
      _noId = true;
      debugPrint('[discord] disabled — set kDiscordApplicationId in '
          'discord_presence_bridge.dart (or SETTINGS/DISCORD_APP_ID)');
      return;
    }
    _noId = false;
    try {
      await Future<void>.sync(() => FlutterDiscordRPC.initialize(appId));
    } catch (e) {
      _dead = true;
      debugPrint('[discord] init failed — presence disabled: $e');
      return;
    }
    _ready = true;
    unawaited(_connect());
  }

  /// Connects to the locally running Discord client. Never awaited by the
  /// player: the plugin's autoRetry keeps probing Discord's IPC pipe, and a
  /// 60 s manual fallback covers plugins whose connect() throws instead of
  /// retrying (Discord not open yet is a normal state, not a fatal one).
  /// When the handshake finally succeeds, whatever state accumulated in the
  /// meantime is flushed exactly once.
  Future<void> _connect() async {
    _reconnect?.cancel();
    _reconnect = null;
    try {
      await Future<void>.sync(
          () => FlutterDiscordRPC.instance.connect(autoRetry: true));
      _connected = true;
      _send(); // flush whatever arrived while connecting
    } catch (e) {
      _connected = false;
      debugPrint('[discord] connect failed — retrying in 60 s: $e');
      _reconnect = Timer(const Duration(seconds: 60), () {
        unawaited(_connect());
      });
    }
  }

  /// Persists a new application id into SETTINGS and (re)starts presence.
  /// Lets a future settings page toggle this without touching code.
  Future<void> setApplicationId(String id) async {
    final box = Hive.box('SETTINGS');
    if (id.isEmpty) {
      await box.delete('DISCORD_APP_ID');
    } else {
      await box.put('DISCORD_APP_ID', id);
    }
    if (_ready || _dead) return; // restart of the app applies the change
    await init();
  }

  String _resolveAppId() {
    try {
      final dynamic stored = Hive.box('SETTINGS').get('DISCORD_APP_ID');
      if (stored is String && stored.trim().isNotEmpty) {
        return stored.trim();
      }
    } catch (_) {}
    return kDiscordApplicationId.trim();
  }

  // ── State in, from media_player.dart ──

  /// Called whenever the current track changes. Safe to call on every
  /// notifier tick — internal dedupe decides what actually reaches Discord.
  void updateTrack({
    required String title,
    required String artist,
    String? artUrl,
    required String trackKey,
  }) {
    _track = _NowPlaying(title, artist, artUrl, trackKey);
    // Track changed while playing: restart the elapsed timer from ~0 so the
    // profile timer never shows the previous track's elapsed time.
    if (_lastPlaying == true) _elapsedAnchor = DateTime.now();
    _send();
  }

  /// Playback entered the playing state (also called on seek while playing,
  /// with the new position, so the timer jumps correctly).
  void playing({Duration position = Duration.zero}) {
    _lastPlaying = true;
    _elapsedAnchor = DateTime.now().subtract(position);
    _send();
  }

  /// Playback paused — the profile timer disappears until resumed.
  void paused() {
    _lastPlaying = false;
    _send();
  }

  /// Nothing loaded anymore (queue stopped / app disposing) — clear presence.
  void stopped() {
    _lastPlaying = null;
    _track = null;
    _lastSig = null;
    if (!_ready || !_connected) return;
    _fire(() => FlutterDiscordRPC.instance.clearActivity());
  }

  // ── Internals ──

  void _send() {
    if (!_ready || !_connected) return;
    final _NowPlaying? track = _track;
    final bool? playingNow = _lastPlaying;
    if (track == null || playingNow == null) return;

    final String sig = '${track.key}|$playingNow';
    if (sig == _lastSig) return;
    _lastSig = sig;

    final presence = RPCActivity(
      state: track.artist.isEmpty ? 'Listening on ZenMusic' : track.artist,
      details: track.title.isEmpty ? 'ZenMusic' : track.title,
      activityType: ActivityType.listening,
      // Timestamp present while playing (Discord shows live elapsed time),
      // absent while paused (Discord hides the timer).
      timestamps: playingNow
          ? RPCTimestamps(start: _elapsedAnchor.millisecondsSinceEpoch)
          : null,
      assets: track.artUrl == null
          ? null
          : RPCAssets(largeImage: track.artUrl, largeText: 'ZenMusic'),
    );
    _fire(() => FlutterDiscordRPC.instance.setActivity(activity: presence));
  }

  /// Fire-and-swallow native call — a Discord hiccup can never take audio
  /// playback down with it.
  void _fire(Future<void> Function() action) {
    if (!_ready || !_connected) return;
    Future<void>(() async {
      try {
        await Future<void>.sync(action);
      } catch (e) {
        debugPrint('[discord] call failed (ignored): $e');
      }
    });
  }
}
