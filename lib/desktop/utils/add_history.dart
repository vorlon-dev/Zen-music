// ZenMusic Desktop — ported from Echo Music (GPL-3.0), utils/add_history.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// PORT FIX (marked): the unified stack's song maps carry a Duration
// ('duration' key) and occasionally other non-primitives — Hive cannot
// serialize Duration and threw "unknown type: Duration" on every playback.
// _sanitize converts values to Hive-safe types before any box write.

import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

Box _box = Hive.box('SETTINGS');

/// Converts a song map to Hive-safe primitives. Duration -> milliseconds;
/// known non-serializable values are dropped.
Map<String, dynamic> _sanitize(Map song) {
  final out = <String, dynamic>{};
  song.forEach((key, value) {
    if (value == null ||
        value is String ||
        value is int ||
        value is double ||
        value is bool) {
      out[key] = value;
      return;
    }
    if (value is Duration) {
      out[key] = value.inMilliseconds;
      return;
    }
    // Lists (thumbnails, artists...) are kept only if every element is
    // itself Hive-safe; nested maps get recursed one level via _sanitize.
    if (value is Map) {
      out[key] = _sanitize(Map<String, dynamic>.from(value));
      return;
    }
    if (value is List) {
      final safe = value.where((e) =>
      e == null ||
          e is String ||
          e is int ||
          e is double ||
          e is bool ||
          e is Map);
      out[key] = List<dynamic>.from(safe);
      return;
    }
    // Everything else (Uri, objects...) dropped — thumbnails already
    // carry the URL string.
  });
  return out;
}

Future<void> addHistory(Map song) async {
  final safeSong = _sanitize(song);
  if (_box.get('PLAYBACK_HISTORY', defaultValue: true)) {
    await addLocalHistory(safeSong);
  }
  if (_box.get('PERSONALISED_CONTENT', defaultValue: true) &&
      safeSong['videoId'] != null &&
      safeSong['status'] != 'DOWNLOADED') {
    try {
      GetIt.I<YTMusic>().addYoutubeHistory('${safeSong['videoId']}');
    } catch (_) {}
  }
}

Future<void> addLocalHistory(Map song) async {
  Box box = Hive.box('SONG_HISTORY');
  Map? oldState = box.get(song['videoId']);
  int timestamp = DateTime.now().millisecondsSinceEpoch;
  if (oldState != null) {
    await box.put(song['videoId'],
        {...oldState, 'plays': oldState['plays'] + 1, 'updatedAt': timestamp});
  } else {
    await box.put(song['videoId'],
        {...song, 'plays': 1, 'CreatedAt': timestamp, 'updatedAt': timestamp});
  }
}