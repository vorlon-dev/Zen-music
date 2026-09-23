import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import '../utilities/listening_stats_utils.dart';

/// Global enable flag (Settings toggle). Persisted, defaults to on.
final ValueNotifier<bool> wrappedEnabled = ValueNotifier<bool>(true);

Future<void> loadWrappedEnabledFlag() async {
  final prefs = await SharedPreferences.getInstance();
  wrappedEnabled.value = prefs.getBool('wrapped_enabled') ?? true;
}

Future<void> setWrappedEnabled(bool value) async {
  wrappedEnabled.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('wrapped_enabled', value);
}

final listeningStatsService = ListeningStatsService();

class ListeningStatsService {
  static const storageKey = 'wrappedListeningStats';

  Map<String, dynamic>? _stats;
  bool _dirty = false;
  Duration _listeningTimeRemainder = Duration.zero;

  Map<String, dynamic>? _sessionSong;
  String? _sessionSongId;
  Duration? _sessionDuration;
  Duration _sessionListened = Duration.zero;
  DateTime? _sessionLastTick;
  bool _sessionQualified = false;
  bool _sessionLastAudioPlayerPlaying = false;

  Box<String> get _box => Hive.box<String>('listening_stats');

  bool get hasStats {
    final now = DateTime.now();
    final stats = _readStats(now);
    final history = stats['history'] as Map<String, dynamic>;
    return hasDisplayableListeningStats(_asMap(stats['currentMonth'])) ||
        history.values
            .any((month) => hasDisplayableListeningStats(_asMap(month))) ||
        (isListeningStatsAnnualWindow(now) &&
            hasDisplayableAnnualListeningStats(stats, now));
  }

  bool get isAnnualRecapAvailable {
    final now = DateTime.now();
    if (!isListeningStatsAnnualWindow(now)) return false;
    return hasDisplayableAnnualListeningStats(_readStats(now), now);
  }

  int get year => listeningStatsAnnualYear(DateTime.now());

  int get yearTotalSeconds {
    final now = DateTime.now();
    return annualTotalSecondsFromStats(_readStats(now), now);
  }

  List<String> get availableMonthKeys {
    final now = DateTime.now();
    return visibleListeningStatsMonthKeys(_readStats(now), now);
  }

  Map<String, dynamic>? monthStats(String monthKey) {
    final stats = _readStats();
    if (monthKey == stats['currentMonthKey']?.toString()) {
      return _asMap(stats['currentMonth']);
    }
    final history = stats['history'] as Map<String, dynamic>;
    return _asMap(history[monthKey]);
  }

  List<Map<String, dynamic>> monthTopSongs(
      String monthKey, {
        int limit = wrappedMonthlyHistorySongsLimit,
      }) {
    final month = monthStats(monthKey);
    return sortedListeningSongs(_asMap(month?['songs']), limit: limit);
  }

  List<Map<String, dynamic>> yearTopSongs({
    int limit = wrappedAnnualSongsLimit,
  }) {
    final now = DateTime.now();
    final months = annualListeningMonthsFromStats(_readStats(now), now);
    return annualListeningSongsFromMonths(months, limit: limit);
  }

  void recordListeningTime(Duration listenedDuration, {DateTime? listenedAt}) {
    if (!wrappedEnabled.value) return;
    if (listenedDuration <= Duration.zero) return;

    _listeningTimeRemainder += listenedDuration;
    final wholeSeconds = _listeningTimeRemainder.inSeconds;
    if (wholeSeconds <= 0) return;
    _listeningTimeRemainder -= Duration(seconds: wholeSeconds);

    final now = listenedAt ?? DateTime.now();
    _stats = applyListeningTimeDelta(
      _readStats(now),
      listenedDuration: Duration(seconds: wholeSeconds),
      listenedAt: now,
    );
    _markDirty();
  }

  void recordListening(
      Map song,
      Duration listenedDuration, {
        bool incrementPlayCount = false,
        bool countTotalSeconds = true,
        DateTime? listenedAt,
      }) {
    if (!wrappedEnabled.value) return;

    final now = listenedAt ?? DateTime.now();
    _stats = applyListeningStatsDelta(
      _readStats(now),
      song: song,
      listenedDuration: listenedDuration,
      listenedAt: now,
      incrementPlayCount: incrementPlayCount,
      countTotalSeconds: countTotalSeconds,
    );
    if (incrementPlayCount || listenedDuration > Duration.zero) {
      _markDirty();
    }
  }

  void startListeningSession(
      Map song, {
        Duration? duration,
        DateTime? startedAt,
      }) {
    if (!wrappedEnabled.value) return;

    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return;

    _sessionSong = Map<String, dynamic>.from(song);
    _sessionSongId = ytid;
    _sessionDuration = duration ?? _durationFromSong(song);
    _sessionListened = Duration.zero;
    _sessionQualified = false;
    _sessionLastTick = startedAt ?? DateTime.now();
    _sessionLastAudioPlayerPlaying = true;
  }

  void resumeListeningSession({Map? currentSong}) {
    if (!wrappedEnabled.value) return;
    final song = currentSong;
    if (song == null) return;

    final ytid = song['ytid']?.toString();
    if (ytid == null || ytid.isEmpty) return;

    if (_sessionSongId != ytid) {
      finishListeningSession(countCurrentTick: true, wasPlaying: true);
      startListeningSession(song);
      return;
    }

    _sessionLastTick = DateTime.now();
    _sessionLastAudioPlayerPlaying = true;
  }

  void recordListeningSessionProgress({bool? wasPlaying}) {
    final song = _sessionSong;
    if (song == null) return;

    final now = DateTime.now();
    final lastTick = _sessionLastTick;
    _sessionLastTick = now;
    if (lastTick == null) return;

    final shouldCount = wasPlaying ?? _sessionLastAudioPlayerPlaying;
    if (!shouldCount) return;

    final listenedDuration = now.difference(lastTick);
    if (listenedDuration <= Duration.zero) return;

    if (!wrappedEnabled.value) return;

    _sessionListened += listenedDuration;
    recordListeningTime(listenedDuration, listenedAt: now);

    if (!_sessionQualified) {
      if (_sessionListened >= qualifiedPlaybackThreshold(_sessionDuration)) {
        _sessionQualified = true;
        recordListening(
          song,
          _sessionListened,
          listenedAt: now,
          incrementPlayCount: true,
          countTotalSeconds: false,
        );
      }
      return;
    }

    recordListening(
      song,
      listenedDuration,
      listenedAt: now,
      countTotalSeconds: false,
    );
  }

  /// Mirrors their handlePlayerStateForListeningStats — we pass the
  /// playing flag directly instead of a just_audio PlayerState object.
  void handlePlayerPlaying(bool playing, {Map? currentSong}) {
    if (playing == _sessionLastAudioPlayerPlaying) return;

    if (playing) {
      resumeListeningSession(currentSong: currentSong);
    } else {
      recordListeningSessionProgress(
        wasPlaying: _sessionLastAudioPlayerPlaying,
      );
    }

    _sessionLastAudioPlayerPlaying = playing;
  }

  void finishListeningSession({
    bool countCurrentTick = false,
    bool flushStats = true,
    bool? wasPlaying,
  }) {
    if (_sessionSong == null) return;

    if (countCurrentTick) {
      recordListeningSessionProgress(wasPlaying: wasPlaying);
    }

    _sessionSong = null;
    _sessionSongId = null;
    _sessionDuration = null;
    _sessionListened = Duration.zero;
    _sessionLastTick = null;
    _sessionQualified = false;
    _sessionLastAudioPlayerPlaying = false;
    if (flushStats) {
      unawaited(flush());
    }
  }

  void startListeningSessionIfNeeded({
    Map? currentSong,
    bool isPlaying = false,
  }) {
    if (!wrappedEnabled.value || _sessionSong != null || !isPlaying) return;
    final song = currentSong;
    if (song != null) startListeningSession(song);
  }

  Duration? _durationFromSong(Map song) {
    final duration = song['duration'];
    if (duration is Duration) return duration;
    if (duration is int) return Duration(seconds: duration);
    if (duration is num) return Duration(seconds: duration.toInt());
    return null;
  }

  void reload() {
    _dirty = false;
    _listeningTimeRemainder = Duration.zero;
    _stats = null;
  }

  Future<void> clearStats() async {
    _dirty = false;
    _listeningTimeRemainder = Duration.zero;
    final now = DateTime.now();
    final cleared = createEmptyListeningStats(
      now.year,
      currentMonthKey: listeningStatsMonthKey(now),
    );
    _stats = cleared;
    await _box.delete(storageKey);
    if (identical(_stats, cleared)) {
      await _persist();
    }
  }

  Future<void> flush() => _persist();

  Map<String, dynamic> _readStats([DateTime? now]) {
    final currentDate = now ?? DateTime.now();
    final cached = _stats;
    if (cached != null) {
      final previousMonthKey = cached['currentMonthKey']?.toString();
      _stats = normalizeListeningStats(cached, currentDate);
      if (previousMonthKey != _stats!['currentMonthKey']?.toString()) {
        _markDirty();
      }
      return _stats!;
    }

    final raw = _box.get(storageKey);
    _stats = normalizeListeningStats(
      raw == null ? null : jsonDecode(raw),
      currentDate,
    );
    return _stats!;
  }

  void _markDirty() {
    _dirty = true;
  }

  Future<void> _persist() async {
    final stats = _stats;
    if (stats == null || !_dirty) return;
    try {
      await _box.put(storageKey, jsonEncode(stats));
      if (identical(_stats, stats)) {
        _dirty = false;
      }
    } catch (e) {
      print('Error persisting listening stats: $e');
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }
}

/// Converts a typed [Song] into the map shape the stats engine expects.
Map<String, dynamic> songToStatsMap(Song song) => {
  'ytid': song.id,
  'title': song.title,
  'artist': song.artist,
  'image': song.thumbnail,
  'duration': song.duration.inSeconds,
};