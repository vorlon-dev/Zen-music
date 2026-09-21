import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

class StorageService {
  static const _historyBoxName = 'search_history';
  static const _queriesBoxName = 'search_queries';
  static const _lastSessionBoxName = 'last_session';
  static const _urlCacheBoxName = 'url_cache';
  static const _likesBoxName = 'liked_songs';

  static const _maxHistory = 50;
  static const _maxQueries = 10;
  static const _urlCacheTtl = Duration(hours: 5);

  late Box<String> _historyBox;
  late Box<String> _queriesBox;
  late Box<String> _lastSessionBox;
  late Box<String> _urlCacheBox;
  late Box<String> _likesBox;

  /// Must be called once at startup.
  Future<void> init() async {
    await Hive.initFlutter();
    _historyBox = await Hive.openBox<String>(_historyBoxName);
    _queriesBox = await Hive.openBox<String>(_queriesBoxName);
    _lastSessionBox = await Hive.openBox<String>(_lastSessionBoxName);
    _urlCacheBox = await Hive.openBox<String>(_urlCacheBoxName);
    _likesBox = await Hive.openBox<String>(_likesBoxName);
  }

  // ═════════════════════════════════════════════
  // LIKED SONGS
  // ═════════════════════════════════════════════

  bool isLiked(String songId) => _likesBox.containsKey(songId);

  Future<void> setLiked(Song song, bool liked) async {
    if (liked) {
      await _likesBox.put(song.id, jsonEncode(song.toJson()));
    } else {
      await _likesBox.delete(song.id);
    }
  }

  List<Song> getLikedSongs() {
    final songs = <Song>[];
    for (final raw in _likesBox.values) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        songs.add(Song.fromJson(map));
      } catch (_) {}
    }
    return songs;
  }

  // ═════════════════════════════════════════════
  // SEARCH QUERIES
  // ═════════════════════════════════════════════

  Future<void> saveQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Remove existing entry if present
    final existing = _queriesBox.values.toList();
    final filtered = existing.where((q) => q != trimmed).toList();

    // Insert at front
    filtered.insert(0, trimmed);

    // Trim to max
    final trimmedList = filtered.take(_maxQueries).toList();

    await _queriesBox.clear();
    for (var i = 0; i < trimmedList.length; i++) {
      await _queriesBox.put(i.toString(), trimmedList[i]);
    }
  }

  List<String> getRecentQueries() {
    return _queriesBox.values.toList();
  }

  Future<void> clearQueries() async {
    await _queriesBox.clear();
  }

  // ═════════════════════════════════════════════
  // SONG HISTORY (played songs)
  // ═════════════════════════════════════════════

  Future<void> savePlayedSong(Song song) async {
    final json = jsonEncode(song.toJson());
    final existing = _historyBox.values.toList();

    // Remove existing same-id entry
    final filtered = existing.where((s) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        return map['id'] != song.id;
      } catch (_) {
        return false;
      }
    }).toList();

    filtered.insert(0, json);
    final trimmed = filtered.take(_maxHistory).toList();

    await _historyBox.clear();
    for (var i = 0; i < trimmed.length; i++) {
      await _historyBox.put(i.toString(), trimmed[i]);
    }
  }

  List<Song> getPlayedHistory() {
    final songs = <Song>[];
    for (final raw in _historyBox.values) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        songs.add(Song.fromJson(map));
      } catch (_) {}
    }
    return songs;
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  // ═════════════════════════════════════════════
  // LAST SESSION (playback state)
  // ═════════════════════════════════════════════

  /// Save the current queue + index so we can restore on next launch.
  Future<void> saveLastSession({
    required List<Song> queue,
    required int currentIndex,
    required Duration position,
  }) async {
    final data = {
      'queue': queue.map((s) => s.toJson()).toList(),
      'currentIndex': currentIndex,
      'positionSeconds': position.inSeconds,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _lastSessionBox.put('state', jsonEncode(data));
  }

  /// Returns the previously saved session, or null if none.
  LastSession? getLastSession() {
    final raw = _lastSessionBox.get('state');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final queueRaw = map['queue'] as List<dynamic>? ?? [];
      final queue = queueRaw
          .map((q) => Song.fromJson(q as Map<String, dynamic>))
          .toList();
      if (queue.isEmpty) return null;
      return LastSession(
        queue: queue,
        currentIndex: (map['currentIndex'] as num?)?.toInt() ?? 0,
        position: Duration(
          seconds: (map['positionSeconds'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearLastSession() async {
    await _lastSessionBox.clear();
  }

  // ═════════════════════════════════════════════
  // URL CACHE
  // ═════════════════════════════════════════════

  /// Store a resolved stream URL for fast re-playback.
  Future<void> cacheUrl(String songId, String url) async {
    final data = {
      'url': url,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await _urlCacheBox.put(songId, jsonEncode(data));
  }

  /// Returns the cached URL if it's still fresh (< 5 hours old).
  String? getCachedUrl(String songId) {
    final raw = _urlCacheBox.get(songId);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (map['timestamp'] as num?)?.toInt() ?? 0;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts));
      if (age > _urlCacheTtl) {
        _urlCacheBox.delete(songId); // expired
        return null;
      }
      return map['url'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUrlCache() async {
    await _urlCacheBox.clear();
  }

  Future<int> getUrlCacheSize() async => _urlCacheBox.length;
}

class LastSession {
  final List<Song> queue;
  final int currentIndex;
  final Duration position;

  LastSession({
    required this.queue,
    required this.currentIndex,
    required this.position,
  });
}