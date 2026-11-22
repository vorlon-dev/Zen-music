// ZenMusic · vorlon-dev
//
// Strict lossless: when a FLAC tier is selected, EVERY song must be served
// lossless. The old chain silently fell back to JioSaavn / YouTube (lossy)
// after one timeout, an open circuit breaker, a busy resolver or a cached
// miss - so after a few songs "lossless" quietly stopped. This wrapper keeps
// retrying the whole lossless chain (Dart mirrors -> Kotlin engine ->
// emergency endpoint) with the blocks cleared, and reports failure instead of
// handing the player a lossy stream.

import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'lossless_quality.dart';
import 'lossless_service.dart';
import 'mirror_arbiter.dart';
import 'mirror_source.dart';

/// Thrown by the player when a song has no lossless stream (strict mode).
class LosslessUnavailable implements Exception {
  LosslessUnavailable(this.title);
  final String title;
  @override
  String toString() => 'LosslessUnavailable: no lossless stream for "$title"';
}

class StrictLossless {
  StrictLossless._();

  /// Rounds of the full lossless chain per song, and the overall cap.
  static const int _maxRounds = 3;
  static const Duration _overallBudget = Duration(seconds: 35);
  static const List<Duration> _backoff = [
    Duration(milliseconds: 700),
    Duration(milliseconds: 1600),
  ];

  /// True when [song] must be served lossless-only.
  static bool appliesTo(Map<String, dynamic> song) =>
      LosslessPrefs.strict &&
      LosslessPrefs.current != LosslessQuality.mp3_320 &&
      song['isYtVideo'] != true;

  // --- fast-fail bookkeeping -------------------------------------------

  /// User-initiated resolves in flight. Background work (queue preloads)
  /// waits for these so a tap on "next" never queues behind a preload.
  static int _foreground = 0;

  /// Songs that cleanly have no lossless version (every source answered
  /// "no match" quickly). Skipped instantly instead of re-running 35 s of
  /// retries every time the queue touches them again.
  static final Map<String, DateTime> _missUntil = {};
  static const Duration _missTtl = Duration(minutes: 5);

  /// A failed round that finishes faster than this (with the blocks
  /// cleared) is a definitive "not in any lossless catalog", not a
  /// timeout - retrying it again would only waste time.
  static const Duration _cleanMissThreshold = Duration(seconds: 6);

  static String _key(Map<String, dynamic> song) =>
      '${song['videoId'] ?? song['title']}';

  /// Never throws. Null = no lossless stream could be resolved.
  /// [fresh] clears breaker / fail cache / manifests before the first round
  /// (used when a previously resolved stream died).
  /// [background] = queue preload: one round, yields to user-initiated work.
  static Future<AudioSource?> resolve(
    Map<String, dynamic> song,
    MediaItem tag, {
    bool fresh = false,
    bool background = false,
  }) async {
    final key = _key(song);
    if (!fresh) {
      final until = _missUntil[key];
      if (until != null && DateTime.now().isBefore(until)) {
        print('[strict-lossless] "${song['title']}" known no-lossless - skipped');
        return null;
      }
    } else {
      _missUntil.remove(key);
    }

    if (background) {
      final stop = DateTime.now().add(const Duration(seconds: 20));
      while (_foreground > 0 && DateTime.now().isBefore(stop)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } else {
      _foreground++;
    }
    try {
      final rounds = background ? 1 : _maxRounds;
      final started = DateTime.now();
      var cleanMiss = false;
      for (var round = 0; round < rounds; round++) {
        if (fresh && round == 0) LosslessService.instance.forgetSong(song);
        if (round > 0 || fresh) {
          MirrorSource.instance.clearBlocksFor(song);
          MirrorArbiter.instance.resetCooldowns();
        }
        if (round > 0) {
          await Future<void>.delayed(_backoff[round - 1]);
        }
        final roundStart = DateTime.now();
        try {
          final src = await LosslessService.instance.tryBuildSource(song, tag);
          if (src != null) return src;
        } catch (e) {
          print('[strict-lossless] round ${round + 1} error: $e');
        }
        final took = DateTime.now().difference(roundStart);
        cleanMiss = (round >= 1 || fresh) && took < _cleanMissThreshold;
        final last = round == rounds - 1 ||
            cleanMiss ||
            DateTime.now().difference(started) > _overallBudget;
        print('[strict-lossless] "${song['title']}" not resolved '
            '(round ${round + 1}/$rounds) - '
            '${last ? 'no lossless version found' : 'retrying'}');
        if (last) break;
      }
      if (cleanMiss && !background) {
        _missUntil[key] = DateTime.now().add(_missTtl);
        while (_missUntil.length > 200) {
          _missUntil.remove(_missUntil.keys.first);
        }
      }
      return null;
    } finally {
      if (!background) _foreground--;
    }
  }
}
