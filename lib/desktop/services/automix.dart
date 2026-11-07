// ZenMusic · vorlon-dev
//
// Automix: a DJ-style transition planner that sits on top of CrossfadeEngine.
// Inspired by BitChord's Automix (GPL-3.0,
// https://github.com/kushagrasinghx/BitChord).
//
// What this does:
//  * finds the tempo of both tracks (cached studio tempo, Deezer lookup),
//  * stretches the two decks toward each other with the player's pitch-
//    preserving speed control, so they meet at the same BPM mid-blend,
//  * sizes the overlap to whole bars of the outgoing track (a bar = 4 beats),
//  * falls back to a short plain crossfade when the tempos are too far apart.
//
// What it does NOT do (and BitChord does): it has no audio analysis of its
// own. BitChord runs an on-device beat tracker (ONNX model) and a native
// tempo estimator to find the actual beat grid; that cannot be ported to
// plain Dart. Here the tempo comes from a database and the beat PHASE of the
// two tracks is not aligned, so this is tempo-matched, not phase-locked.
// Plug a [TempoSource] with a real analyser in to improve it.
//
// NOT compiled or run by the author (no Dart/Flutter SDK was available).

import 'package:hive_flutter/hive_flutter.dart';

import 'beat_haptics.dart' show BpmCache, DeezerTempoSource, TempoSource;
import 'crossfade_engine.dart';
import 'song_dna.dart';

class AutomixPrefs {
  AutomixPrefs._();

  static const String _key = 'AUTOMIX_ENABLED';

  static bool get enabled {
    try {
      return Hive.box('SETTINGS').get(_key, defaultValue: false) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool v) async {
    try {
      await Hive.box('SETTINGS').put(_key, v);
    } catch (_) {}
  }
}

class Automix {
  Automix({TempoSource? tempoSource})
      : _tempo = tempoSource ?? DeezerTempoSource();

  final TempoSource _tempo;
  final BpmCache _cache = BpmCache();

  /// Largest tempo gap (as a fraction) that is bridged by stretching.
  static const double maxStretch = 0.08;

  Future<double?> _bpm(Map<String, dynamic> song) async {
    final direct = song['bpm'];
    if (direct is num && direct >= 50 && direct <= 240) {
      return direct.toDouble();
    }
    final (title, artist, _) = SongDna.idsFromSong(song);
    if (title.isEmpty) return null;
    final cached = await _cache.get(title, artist);
    if (cached != null) return cached;
    final found = await _tempo.tempoFor(title, artist);
    if (found != null) await _cache.put(title, artist, found);
    return found;
  }

  /// Plan for one transition. Always returns a plan (at worst a short plain
  /// fade) so Automix never turns into a hard cut.
  Future<CrossfadePlan?> plan(
    Map<String, dynamic> outgoing,
    Map<String, dynamic> incoming,
  ) async {
    final results = await Future.wait<double?>(
        [_bpm(outgoing), _bpm(incoming)]);
    final out = results[0];
    final inn = results[1];
    if (out == null || inn == null) {
      return const CrossfadePlan(
          window: Duration(seconds: 5), label: 'automix (no tempo)');
    }

    // Compare tempos allowing half / double time (70 vs 140 are the same groove).
    double ratio = out / inn;
    for (final r in <double>[ratio, ratio * 2, ratio / 2]) {
      if ((r - 1).abs() < (ratio - 1).abs()) ratio = r;
    }

    if ((ratio - 1).abs() > maxStretch) {
      return const CrossfadePlan(
          window: Duration(seconds: 4), label: 'automix (tempos too far)');
    }

    // Whole bars of the outgoing track: 16 beats, or 8 if that is too long.
    final beatSec = 60.0 / out;
    var beats = 16;
    if (beats * beatSec > 14) beats = 8;
    if (beats * beatSec < 5) beats = 32;
    final window = Duration(milliseconds: (beats * beatSec * 1000).round());

    // Meet in the middle: the outgoing deck drifts to the incoming tempo,
    // the incoming deck starts at the outgoing tempo and relaxes to normal.
    return CrossfadePlan(
      window: window,
      outgoingEndSpeed: 1.0 / ratio,
      incomingStartSpeed: ratio,
      label: 'automix ${out.round()}→${inn.round()} BPM',
    );
  }
}
