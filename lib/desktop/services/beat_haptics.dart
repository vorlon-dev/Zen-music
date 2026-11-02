// ZenMusic — beat-synced haptics (SP-78).
//
// The phone vibrates on the song's beat grid while it plays. The grid is a
// BPM metronome kept in lock-step with the player position: every fire
// re-reads the LIVE position and schedules the next beat from it, so the
// pattern can never drift — pauses, seeks and stalls self-correct on the
// very next tick without any explicit seek handling.
//
// Where the BPM comes from (honest chain, each step cached per song):
//   1. The persistent per-song cache (a previous lookup's answer).
//   2. Deezer's public keyless search API — its track objects carry the
//      studio `bpm`. No key, no auth, and deliberately no api.spotify.com
//      traffic (the app's shared 429 discipline must stay intact).
//   3. A neutral 120 BPM grid so the toggle still pulses when every
//      lookup fails (offline, rare instrumental with no Deezer entry).
//      The miss is NOT persisted — the next session retries Deezer.
//
// Mobile only: the production constructor gates on Android/iOS; on other
// platforms the engine is inert. Strength maps onto the platform impact
// tiers (light / medium / heavy) via HapticFeedback; the sink is
// injectable so tests can count beats without vibrating anything.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/media_player.dart'
    show ButtonState, MediaPlayer;

/// Vibration strength for each beat — maps to the platform's impact
/// tiers in [fireHapticFor].
enum BeatStrength { light, medium, strong }

BeatStrength beatStrengthFromIndex(int i) {
  final idx = i < 0 ? 0 : (i > 2 ? 2 : i);
  return BeatStrength.values[idx];
}

/// Fire the platform vibration for [s]. Split from the engine so tests can
/// intercept (the engine's [BeatHapticsEngine.onBeat] seam).
void fireHapticFor(BeatStrength s) {
  switch (s) {
    case BeatStrength.light:
      HapticFeedback.lightImpact();
    case BeatStrength.medium:
      HapticFeedback.mediumImpact();
    case BeatStrength.strong:
      HapticFeedback.heavyImpact();
  }
}

// ── beat math (pure, unit-tested) ────────────────────────────────────

class BeatClock {
  /// Milliseconds one beat of [bpm] lasts.
  static double intervalMs(double bpm) => 60000.0 / bpm;

  /// Time from [position] until the NEXT beat of the [bpm] grid. Floored
  /// at 16 ms so a fire landing exactly on a beat never schedules a
  /// zero-delay timer loop (a 0–15 ms lateness is imperceptible; the next
  /// tick re-anchors on the real position anyway).
  static Duration nextBeatOffset(Duration position, double bpm) {
    if (bpm <= 0) return Duration.zero;
    final interval = intervalMs(bpm);
    final pos = position.inMilliseconds.clamp(0, 1 << 40).toDouble();
    final offset = interval - (pos % interval);
    return Duration(milliseconds: offset < 16 ? 16 : offset.round());
  }
}

// ── BPM sources ──────────────────────────────────────────────────────

/// Where the engine asks for a song's tempo. Injectable for tests.
abstract class TempoSource {
  Future<double?> tempoFor(String title, String artist);
}

/// Deezer public search — keyless, separate quota from everything else the
/// app calls. `data[].bpm` is the studio tempo.
class DeezerTempoSource implements TempoSource {
  DeezerTempoSource({http.Client? client, this.base = 'https://api.deezer.com'})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// API origin — overridable for tests / self-hosted proxies.
  final String base;

  @override
  Future<double?> tempoFor(String title, String artist) async {
    if (title.trim().isEmpty) return null;
    // Plain text query — Deezer's matcher handles "artist title" well and
    // the quoted-field syntax misses more often on film-song edits.
    final q = Uri.encodeQueryComponent('$artist $title'.trim());
    final uri = Uri.parse('$base/search?q=$q&limit=5');
    try {
      final r = await _client
          .get(uri, headers: {'User-Agent': 'ZenMusic/1.0'})
          .timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) return null;
      final map = _tryDecode(r.body);
      if (map == null) return null;
      final data = map['data'];
      if (data is! List || data.isEmpty) return null;

      // Prefer a result whose title/artist actually resembles the query;
      // otherwise take the first sane bpm rather than failing the lookup.
      double? firstBpm;
      final titleLc = title.toLowerCase();
      final artistLc = artist.toLowerCase();
      for (final item in data) {
        if (item is! Map) continue;
        final bpm = (item['bpm'] as num?)?.toDouble();
        if (bpm == null || bpm < 50 || bpm > 240) continue;
        firstBpm ??= bpm;
        final t = (item['title'] ?? '').toString().toLowerCase();
        final a = ((item['artist'] ?? const {})['name'] ?? '')
            .toString()
            .toLowerCase();
        if (t.isNotEmpty && (titleLc.contains(t) || t.contains(titleLc))) {
          return bpm;
        }
        if (a.isNotEmpty && artistLc.contains(a)) {
          return bpm;
        }
      }
      return firstBpm;
    } catch (_) {
      return null; // offline / blocked / timeout — engine falls back
    }
  }

  static Map<String, dynamic>? _tryDecode(String body) {
    try {
      final v = const JsonDecoder().convert(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

/// Persistent per-song tempo cache. Key = normalized "artist|title".
class BpmCache {
  static const _prefix = 'ap_beat_bpm::';

  static String keyFor(String title, String artist) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '$_prefix${norm(artist)}|${norm(title)}';
  }

  Future<double?> get(String title, String artist) async {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(keyFor(title, artist));
    return (v != null && v > 0) ? v : null;
  }

  Future<void> put(String title, String artist, double bpm) async {
    if (bpm <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(keyFor(title, artist), bpm);
  }
}

// ── the engine ───────────────────────────────────────────────────────

/// The slice of the player the engine touches — injectable so tests can
/// drive pauses/seeks/song changes without a real AudioPlayer.
class BeatPlayerProbe {
  BeatPlayerProbe({
    required this.position,
    required this.buttonState,
    required this.currentSong,
  });

  /// Live playback position (re-read on every beat — the drift guard).
  final Duration Function() position;
  final ValueListenable<ButtonState> buttonState;
  final ValueListenable<MediaItem?> currentSong;
}

class BeatHapticsEngine {
  /// Production engine over the app's real MediaPlayer. Inert off mobile.
  BeatHapticsEngine(MediaPlayer mp, {bool? mobile})
      : this.probe(
          BeatPlayerProbe(
            position: () => mp.player.position,
            buttonState: mp.buttonState,
            currentSong: mp.currentSongNotifier,
          ),
          mobile: mobile ?? (Platform.isAndroid || Platform.isIOS),
        );

  /// Test engine with a fake probe (never touches platform channels).
  BeatHapticsEngine.probe(this.probe, {this.mobile = true});

  final BeatPlayerProbe probe;
  final bool mobile;

  /// Injectable tempo source (tests). Null → Deezer.
  TempoSource? tempoSource;

  /// Beat sink — tests replace it to collect beats; production keeps the
  /// default, which fires the platform haptic at the configured strength.
  void Function(BeatStrength s) onBeat = fireHapticFor;

  Timer? _timer;
  double _bpm = 0;
  String? _gridSongId;
  bool _started = false;
  bool _resolving = false;
  MediaItem? _resolveWanted; // latest song change wins the resolve slot

  bool get _enabled => AppearancePrefs.beatHaptics.value;
  bool get _playing => probe.buttonState.value == ButtonState.playing;
  bool get _active => mobile && _enabled && _playing && _bpm > 0;

  /// Wire listeners. Idempotent.
  void start() {
    if (_started) return;
    _started = true;
    tempoSource ??= DeezerTempoSource();
    probe.buttonState.addListener(_onStateChanged);
    probe.currentSong.addListener(_onSongChanged);
    AppearancePrefs.beatHaptics.addListener(_onToggleChanged);
    // Boot mid-song (session restore): resolve + arm for whatever plays.
    _onSongChanged();
  }

  void dispose() {
    _timer?.cancel();
    probe.buttonState.removeListener(_onStateChanged);
    probe.currentSong.removeListener(_onSongChanged);
    AppearancePrefs.beatHaptics.removeListener(_onToggleChanged);
    _started = false;
  }

  /// Toggle flipped — re-resolve/re-arm for the current song (covers the
  /// first-ever enable mid-song, where nothing resolved yet).
  void _onToggleChanged() => _onSongChanged();

  void _onStateChanged() {
    if (_active) {
      _scheduleNext();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onSongChanged() {
    final song = probe.currentSong.value;
    _timer?.cancel();
    _timer = null;
    if (song == null || song.id.isEmpty) return;
    if (song.id == _gridSongId) {
      // Same song again (queue refresh) — grid unchanged, just re-arm.
      if (_active) _scheduleNext();
      return;
    }
    _resolveTempo(song);
  }

  /// Resolve the beat grid for the latest requested song. Re-entrant-safe:
  /// a song change while a lookup is in flight ENQUEUES the new song
  /// (latest wins) instead of being dropped by a busy flag — the running
  /// loop discards the stale answer and picks the newer request up.
  Future<void> _resolveTempo(MediaItem song) async {
    _resolveWanted = song;
    if (_resolving) return;
    _resolving = true;
    try {
      while (_resolveWanted != null) {
        final target = _resolveWanted!;
        _resolveWanted = null;
        final title = target.title;
        final artist = (target.artist ?? target.album ?? '').toString();
        _bpm = 0;
        _gridSongId = null;
        double? resolved;
        try {
          final cache = BpmCache();
          resolved = await cache.get(title, artist);
          resolved ??= await (tempoSource ??= DeezerTempoSource())
              .tempoFor(title, artist);
        } catch (_) {
          resolved = null; // transient — never let a lookup kill the engine
        }
        // Stale? (the song moved on while we looked) — loop for a newer
        // request if one queued, otherwise leave the grid unloaded.
        if (probe.currentSong.value?.id != target.id) continue;
        if (resolved != null && resolved > 0) {
          // Keep the grid haptic-friendly: ≤ 240 bpm (250 ms) never stutters,
          // ≥ 50 bpm never feels like a dead pause.
          _bpm = resolved.clamp(50.0, 240.0).toDouble();
          _gridSongId = target.id;
          unawaited(BpmCache().put(title, artist, _bpm));
        } else {
          // Every source missed — pulse the neutral 120 grid so the
          // toggle still does something. In-memory only: the next
          // session retries the sources.
          _bpm = 120;
          _gridSongId = target.id;
        }
        if (_active) _scheduleNext();
      }
    } finally {
      _resolving = false;
    }
  }

  /// (Re)anchor the metronome on the CURRENT position.
  void _scheduleNext() {
    _timer?.cancel();
    if (!_active) return;
    final offset = BeatClock.nextBeatOffset(probe.position(), _bpm);
    _timer = Timer(offset, _tick);
  }

  void _tick() {
    if (!_active) return;
    _timer = null;
    // Strength is read at fire time, so changes apply from the next beat.
    onBeat(beatStrengthFromIndex(AppearancePrefs.beatStrength.value));
    _scheduleNext();
  }
}
