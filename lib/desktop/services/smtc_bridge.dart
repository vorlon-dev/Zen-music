// ZenMusic Desktop — services/smtc_bridge.dart (GPL-3.0).
//
// SP-22 — Windows System Media Transport Controls (SMTC) bridge.
// SP-22b — adapted to the REAL smtc_windows 1.1.0 API (verified against
//          the package's generated Dart source, not its stale README):
//          PlaybackStatus constants are lowercase (playing/paused/stopped),
//          SMTCConfig requires all 7 flags incl. fastForwardEnabled and
//          rewindEnabled (off here — ZenMusic binds no seek keys), and
//          WidgetsFlutterBinding needs package:flutter/widgets.dart.
// SP-22c — traced version: init() and the playback-driven pushes print one
//          [smtc] line each in the debug console, so a "media card not
//          showing" report carries its own diagnosis. Playback behavior is
//          unchanged from SP-22b.
//
// What this gives ZenMusic on Windows:
//  • Media keys: play/pause, next, previous work from the keyboard even
//    when the app window is not focused.
//  • The Windows volume flyout / Quick Settings (Win+A) and the lock
//    screen show the current track: title, artist, album, artwork and a
//    live progress bar.
//  • The overlay's own play/pause/next/previous buttons control ZenMusic.
//
// Design rules:
//  • This is the ONLY ZenMusic file that imports package:smtc_windows.
//    Every other file talks through SmtcTrack / SmtcButton and the methods
//    below, so the smtc package API surface stays inside one small file.
//  • Hard no-op off Windows and on any init failure — media_player.dart can
//    call these methods unconditionally from any platform, in any state.
//  • Every native call is fire-and-swallow: a bridge problem can never take
//    audio playback down with it.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:smtc_windows/smtc_windows.dart';

/// Buttons ZenMusic reacts to. Translated from smtc_windows's PressedButton
/// here, so no other ZenMusic file ever needs the package import.
enum SmtcButton { play, pause, next, previous, stop }

/// One track's worth of OS-overlay metadata.
class SmtcTrack {
  final String title;
  final String artist;
  final String album;

  /// http(s) artwork URL, or null. Non-web values (local file paths) are
  /// dropped by the caller — the overlay then simply shows no artwork.
  final String? thumbnailUrl;

  final Duration duration;

  const SmtcTrack({
    this.title = '',
    this.artist = '',
    this.album = '',
    this.thumbnailUrl,
    this.duration = Duration.zero,
  });
}

class SmtcBridge {
  SmtcBridge._();
  static final SmtcBridge instance = SmtcBridge._();

  SMTCWindows? _smtc;
  bool _ready = false;
  bool _dead = false; // init failed once — never retry, never crash again
  StreamSubscription<PressedButton>? _pressSub;

  final StreamController<SmtcButton> _presses =
      StreamController<SmtcButton>.broadcast();

  /// OS media-key / overlay-button presses (play, pause, next, previous, stop).
  Stream<SmtcButton> get buttonPresses => _presses.stream;

  bool get isReady => _ready;

  /// Call once at startup (idempotent). Safe on every platform — off Windows
  /// this returns immediately and every method below no-ops.
  Future<void> init() async {
    if (!Platform.isWindows) {
      debugPrint('[smtc] init skipped — not Windows');
      return;
    }
    if (_ready) {
      debugPrint('[smtc] init skipped — already ready');
      return;
    }
    if (_dead) {
      debugPrint('[smtc] init skipped — failed earlier this session');
      return;
    }
    debugPrint('[smtc] init starting — loading the Rust plugin…');
    try {
      // main.dart stays untouched: running initialize() from a service is
      // equivalent to the package example's "await SMTCWindows.initialize()"
      // in main(), and ensureInitialized() keeps it safe even if the player
      // singleton is constructed before runApp().
      WidgetsFlutterBinding.ensureInitialized();
      await SMTCWindows.initialize();
      debugPrint('[smtc] plugin loaded');
      final smtc = SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          prevEnabled: true,
          rewindEnabled: false,
          stopEnabled: true,
        ),
        metadata: const MusicMetadata(title: 'ZenMusic'),
      );
      _pressSub = smtc.buttonPressStream.listen((PressedButton b) {
        final SmtcButton? ours = switch (b) {
          PressedButton.play => SmtcButton.play,
          PressedButton.pause => SmtcButton.pause,
          PressedButton.next => SmtcButton.next,
          PressedButton.previous => SmtcButton.previous,
          PressedButton.stop => SmtcButton.stop,
          _ => null,
        };
        debugPrint('[smtc] OS button press: $ours');
        if (ours != null && !_presses.isClosed) _presses.add(ours);
      });
      _smtc = smtc;
      _ready = true;
      debugPrint('[smtc] ready — play a track and the card should appear '
          'in Quick Settings (Win+A)');
    } catch (e) {
      _dead = true;
      debugPrint('[smtc] init failed — SMTC disabled this session: $e');
    }
  }

  // ── Playback status ──

  void playing() {
    debugPrint('[smtc] status → playing');
    _fire(() => _smtc!.setPlaybackStatus(PlaybackStatus.playing));
  }

  void paused() {
    debugPrint('[smtc] status → paused');
    _fire(() => _smtc!.setPlaybackStatus(PlaybackStatus.paused));
  }

  void stopped() {
    debugPrint('[smtc] status → stopped');
    _fire(() async {
      await _smtc!.setPlaybackStatus(PlaybackStatus.stopped);
      await _smtc!.clearMetadata();
    });
  }

  // ── Track metadata ──

  void updateTrack(SmtcTrack track) {
    debugPrint('[smtc] track → "${track.title}" — ${track.artist}');
    _fire(() async {
      await _smtc!.updateMetadata(MusicMetadata(
        title: track.title.isEmpty ? 'ZenMusic' : track.title,
        artist: track.artist,
        album: track.album,
      ));
      final String? thumb = track.thumbnailUrl;
      if (thumb != null && thumb.isNotEmpty) {
        await _smtc!.setThumbnail(thumb);
      }
      _resetTimeline(track.duration);
    });
  }

  // ── Timeline (progress bar in the Windows volume flyout) ──

  static const Duration _minPushInterval = Duration(milliseconds: 950);
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastPushedPosition = Duration.zero;

  /// Called on every position tick from the player. Throttled to ~1 push per
  /// second; seeks (position jump > 2 s) and track changes push immediately.
  void position(Duration current, Duration total, {bool force = false}) {
    if (!_ready || total <= Duration.zero) return;
    final DateTime now = DateTime.now();
    final bool jumped =
        (current - _lastPushedPosition).abs() > const Duration(seconds: 2);
    if (!force && !jumped && now.difference(_lastPush) < _minPushInterval) {
      return;
    }
    _lastPush = now;
    _lastPushedPosition = current;
    _fire(() => _smtc!.updateTimeline(PlaybackTimeline(
          startTimeMs: current.inMilliseconds,
          endTimeMs: total.inMilliseconds,
          positionMs: current.inMilliseconds,
          minSeekTimeMs: 0,
          maxSeekTimeMs: total.inMilliseconds,
        )));
  }

  void _resetTimeline(Duration total) {
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    _lastPushedPosition = Duration.zero;
    if (!_ready || total <= Duration.zero) return;
    _fire(() => _smtc!.updateTimeline(PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: total.inMilliseconds,
          positionMs: 0,
          minSeekTimeMs: 0,
          maxSeekTimeMs: total.inMilliseconds,
        )));
  }

  // ── Internals ──

  /// Runs a native call, swallowing every error. Also guards !_ready so the
  /// call sites above can stay one-liners.
  void _fire(Future<void> Function() action) {
    if (!_ready || _smtc == null) {
      debugPrint('[smtc] dropped a push — bridge not ready yet');
      return;
    }
    Future<void>(() async {
      try {
        await action();
      } catch (e) {
        debugPrint('[smtc] call failed (ignored): $e');
      }
    });
  }

  Future<void> dispose() async {
    _pressSub?.cancel();
    _pressSub = null;
    final smtc = _smtc;
    _smtc = null;
    _ready = false;
    if (smtc == null) return;
    try {
      await smtc.dispose();
    } catch (_) {}
  }
}
