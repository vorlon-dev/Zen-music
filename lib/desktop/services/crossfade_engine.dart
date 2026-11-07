// ZenMusic · vorlon-dev
//
// True two-deck crossfade (and the Automix transition on top of it).
//
// The idea follows BitChord's CrossfadeController (GPL-3.0,
// https://github.com/kushagrasinghx/BitChord), redone in Dart for just_audio:
//
//  * The normal player keeps the queue and is always the "incoming" deck.
//  * A short while before the track ends, a second player is loaded with the
//    SAME track, positioned exactly where the first one will be when the
//    fade starts. At that instant the second deck takes over the tail of the
//    outgoing track while the normal player jumps to the next one.
//  * The decks are blended with an equal-power curve, so the overlap is real
//    (both tracks audible together), not a dip to silence.
//
// Because the normal player moves on immediately, the UI, notification,
// scrobbling and lyrics all switch to the new track at the start of the
// blend, exactly as they would for a hard cut.
//
// NOT compiled or run by the author (no Dart/Flutter SDK was available).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// How one transition should sound. Plain crossfade uses [CrossfadePlan.plain].
class CrossfadePlan {
  const CrossfadePlan({
    required this.window,
    this.outgoingEndSpeed = 1.0,
    this.incomingStartSpeed = 1.0,
    this.label = 'crossfade',
  });

  factory CrossfadePlan.plain(int seconds) =>
      CrossfadePlan(window: Duration(seconds: seconds));

  /// Length of the overlap.
  final Duration window;

  /// Speed the outgoing deck is ramped to by the end of the overlap.
  final double outgoingEndSpeed;

  /// Speed the incoming deck starts at; it ramps back to 1.0 by the end.
  final double incomingStartSpeed;

  final String label;

  bool get stretches =>
      (outgoingEndSpeed - 1.0).abs() > 0.001 ||
      (incomingStartSpeed - 1.0).abs() > 0.001;
}

/// Asked right before a transition: how long and how to blend it. Returning
/// null means "no overlap for this one" (a hard, gapless cut).
typedef PlanProvider = Future<CrossfadePlan?> Function(
  Map<String, dynamic> outgoing,
  Map<String, dynamic> incoming,
);

class CrossfadeEngine {
  CrossfadeEngine({
    required AudioPlayer player,
    required this.buildSource,
    required this.songAt,
    required this.nextSong,
    required this.advance,
    required this.plan,
    required this.isBlocked,
    this.onPlanStarted,
  }) : _player = player;

  final AudioPlayer _player;

  /// Builds a fresh audio source for a song map (the app's own resolver).
  final Future<AudioSource> Function(Map<String, dynamic> song) buildSource;

  /// The song map at a queue index, or null.
  final Map<String, dynamic>? Function(int index) songAt;

  /// The song that follows the one at [index]: from the loaded sequence, or
  /// from the wider queue when the player has not preloaded it yet.
  final Map<String, dynamic>? Function(int index) nextSong;

  /// Moves playback to the next track (the app's own skip logic).
  final Future<void> Function() advance;

  /// Plan for the coming transition.
  final PlanProvider plan;

  /// True while crossfading must stay out of the way (engine-owned playback,
  /// repeat-one, etc.).
  final bool Function() isBlocked;

  final void Function(CrossfadePlan)? onPlanStarted;

  static const Duration _lead = Duration(seconds: 8);
  static const Duration _tick = Duration(milliseconds: 40);

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<int?>? _idxSub;
  StreamSubscription<bool>? _playingSub;

  AudioPlayer? _deck; // the outgoing tail
  Timer? _ramp;
  int _token = 0;
  bool _preparing = false;
  bool _blending = false;
  DateTime _ignoreIndexUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int? _preparedFor; // queue index we already handled

  bool get active => _preparing || _blending;

  void attach() {
    _posSub = _player.positionStream.listen(_onPosition);
    _idxSub = _player.currentIndexStream.listen(_onIndex);
    _playingSub = _player.playingStream.listen(_onPlaying);
  }

  Future<void> dispose() async {
    await _posSub?.cancel();
    await _idxSub?.cancel();
    await _playingSub?.cancel();
    await cancel();
  }

  void _onIndex(int? i) {
    // Our own advance can emit several index events (stop, then the new
    // track); ignore them for a few seconds.
    if (DateTime.now().isBefore(_ignoreIndexUntil)) return;
    // A manual skip / stop / new queue while a blend is in flight.
    if (active) unawaited(cancel());
  }

  void _onPlaying(bool playing) {
    final deck = _deck;
    if (deck == null || !_blending) return;
    try {
      playing ? deck.play() : deck.pause();
    } catch (_) {}
  }

  void _onPosition(Duration pos) {
    // Safety net: outside a blend the main player is always at full volume
    // and normal speed, so a missed restore can never leave a track quiet.
    if (!active && _player.volume < 0.999) {
      unawaited(_player.setVolume(1.0));
    }
    if (active || isBlocked() || !_player.playing) return;
    final index = _player.currentIndex;
    if (index == null || _preparedFor == index) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    final remaining = total - pos;
    // Early enough to load the deck, not so early we miss the fade point.
    if (remaining > _lead + const Duration(seconds: 12) ||
        remaining <= Duration.zero) {
      return;
    }
    unawaited(_prepare(index, total));
  }

  Future<void> _prepare(int index, Duration total) async {
    final int token = ++_token;
    _preparing = true;
    _preparedFor = index;
    AudioPlayer? deck;
    try {
      final out = songAt(index);
      final inn = nextSong(index);
      if (out == null || inn == null) return;
      final p = await plan(out, inn);
      if (p == null || p.window <= Duration.zero) return;
      if (token != _token) return;
      // The window can never be longer than the track allows.
      var window = p.window;
      final maxWindow = Duration(milliseconds: (total.inMilliseconds * 0.45).round());
      if (window > maxWindow) window = maxWindow;
      if (window < const Duration(milliseconds: 500)) return;

      final switchAt = total - window;
      final now = _player.position;
      if (switchAt <= now + const Duration(milliseconds: 600)) return;

      // Load the outgoing track on the second deck, parked at the switch point.
      deck = AudioPlayer();
      final src = await buildSource(out);
      await deck.setAudioSource(src, initialPosition: switchAt);
      await deck.setVolume(0.0);
      if (token != _token) {
        await deck.dispose();
        return;
      }
      _deck = deck;

      // Wait for the main player to reach the switch point.
      final deadline = DateTime.now().add(total - now + const Duration(seconds: 3));
      while (_player.position < switchAt - const Duration(milliseconds: 25)) {
        if (token != _token ||
            !_player.playing ||
            _player.currentIndex != index ||
            DateTime.now().isAfter(deadline)) {
          await _teardownDeck(deck);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }

      // Switch: deck takes the tail, the main player moves on, blend starts.
      _blending = true;
      _preparing = false;
      onPlanStarted?.call(p);
      await deck.setVolume(1.0);
      unawaited(deck.play());
      await _player.setVolume(0.0);
      _ignoreIndexUntil = DateTime.now().add(const Duration(seconds: 4));
      unawaited(advance().catchError((Object e) {
        debugPrint('[crossfade] advance failed: $e');
        unawaited(cancel());
      }));
      if (p.incomingStartSpeed != 1.0) {
        unawaited(_player.setSpeed(p.incomingStartSpeed));
      }
      _startRamp(token, deck, CrossfadePlan(
        window: window,
        outgoingEndSpeed: p.outgoingEndSpeed,
        incomingStartSpeed: p.incomingStartSpeed,
        label: p.label,
      ));
      deck = null; // owned by the ramp now
    } catch (e) {
      debugPrint('[crossfade] aborted: $e');
      if (deck != null) await _teardownDeck(deck);
      await _restoreMain();
    } finally {
      if (_blending == false) _preparing = false;
    }
  }

  void _startRamp(int token, AudioPlayer deck, CrossfadePlan p) {
    final start = DateTime.now();
    _ramp?.cancel();
    _ramp = Timer.periodic(_tick, (t) async {
      if (token != _token) {
        t.cancel();
        return;
      }
      final f = (DateTime.now().difference(start).inMicroseconds /
              p.window.inMicroseconds)
          .clamp(0.0, 1.0);
      // Equal-power: constant loudness through the overlap.
      final outVol = math.cos(f * math.pi / 2);
      final inVol = math.sin(f * math.pi / 2);
      try {
        unawaited(deck.setVolume(outVol));
        unawaited(_player.setVolume(inVol));
        if (p.stretches) {
          if (p.outgoingEndSpeed != 1.0) {
            unawaited(deck.setSpeed(1.0 + (p.outgoingEndSpeed - 1.0) * f));
          }
          if (p.incomingStartSpeed != 1.0) {
            unawaited(_player.setSpeed(
                p.incomingStartSpeed + (1.0 - p.incomingStartSpeed) * f));
          }
        }
      } catch (_) {}
      if (f >= 1.0) {
        t.cancel();
        _ramp = null;
        await _teardownDeck(deck);
        await _restoreMain();
        _blending = false;
      }
    });
  }

  /// Stops any blend in flight and puts the main player back to normal.
  Future<void> cancel() async {
    ++_token;
    _ramp?.cancel();
    _ramp = null;
    final deck = _deck;
    if (deck != null) await _teardownDeck(deck);
    await _restoreMain();
    _preparing = false;
    _blending = false;
  }

  Future<void> _teardownDeck(AudioPlayer deck) async {
    if (identical(_deck, deck)) _deck = null;
    try {
      await deck.stop();
    } catch (_) {}
    try {
      await deck.dispose();
    } catch (_) {}
  }

  Future<void> _restoreMain() async {
    try {
      await _player.setVolume(1.0);
      await _player.setSpeed(1.0);
    } catch (_) {}
  }
}
