import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-song "play with video" preference. Persisted as a compact
/// JSON set of song ids so the player can auto-enter video mode.
class VideoPreferenceService {
  VideoPreferenceService._();
  static final VideoPreferenceService instance = VideoPreferenceService._();

  static const _key = 'video_pref_songs';
  Set<String> _ids = {};
  bool _loaded = false;

  /// Live flag so the player can react immediately.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        _ids = list.toSet();
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_ids.toList()));
    revision.value++;
  }

  Future<void> _ensureLoadedAnd(Future<void> Function() action) async {
    await _ensureLoaded();
    await action();
  }

  bool isVideoPreferredSync(String songId) => _ids.contains(songId);

  Future<bool> isVideoPreferred(String songId) async {
    await _ensureLoaded();
    return _ids.contains(songId);
  }

  Future<void> setPreferred(String songId, bool preferred) async {
    await _ensureLoadedAnd(() async {
      final changed =
      preferred ? _ids.add(songId) : _ids.remove(songId);
      if (changed) await _persist();
    });
  }

  Future<void> toggle(String songId) async {
    await _ensureLoadedAnd(() async {
      if (!_ids.remove(songId)) {
        _ids.add(songId);
      }
      await _persist();
    });
  }

  Future<void> clearAll() async {
    await _ensureLoadedAnd(() async {
      _ids.clear();
      await _persist();
    });
  }
}