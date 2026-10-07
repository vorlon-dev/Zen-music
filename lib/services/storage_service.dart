import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import 'dsp_service.dart';

class StorageService {
  static const _historyBoxName = 'search_history';
  static const _queriesBoxName = 'search_queries';
  static const _lastSessionBoxName = 'last_session';
  static const _urlCacheBoxName = 'url_cache';
  static const _likesBoxName = 'liked_songs';
  static const _userPlaylistsBoxName = 'user_playlists';
  static const _listeningStatsBoxName = 'listening_stats';
  // EQ (parametric) profiles — new box; 'search_history' untouched.
  static const _eqProfilesBoxName = 'eq_profiles';

  static const _maxHistory = 50;
  static const _maxQueries = 10;
  static const _urlCacheTtl = Duration(hours: 5);

  late Box<String> _historyBox;
  late Box<String> _queriesBox;
  late Box<String> _lastSessionBox;
  late Box<String> _urlCacheBox;
  late Box<String> _likesBox;
  late Box<String> _userPlaylistsBox;
  late Box<String> _listeningStatsBox;
  late Box<String> _eqProfilesBox;

  /// Must be called once at startup.
  Future<void> init() async {
    await Hive.initFlutter();
    _historyBox = await Hive.openBox<String>(_historyBoxName);
    _queriesBox = await Hive.openBox<String>(_queriesBoxName);
    _lastSessionBox = await Hive.openBox<String>(_lastSessionBoxName);
    _urlCacheBox = await Hive.openBox<String>(_urlCacheBoxName);
    _likesBox = await Hive.openBox<String>(_likesBoxName);
    _userPlaylistsBox = await Hive.openBox<String>(_userPlaylistsBoxName);
    _listeningStatsBox = await Hive.openBox<String>(_listeningStatsBoxName);
    _eqProfilesBox = await Hive.openBox<String>(_eqProfilesBoxName);
  }

  // ═════════════════════════════════════════════
  // SETTINGS (audio quality, offline mode, update checks)
  // ═════════════════════════════════════════════

  String getAudioQuality() =>
      _historyBox.get('audioQuality', defaultValue: 'high') ?? 'high';

  Future<void> setAudioQuality(String quality) =>
      _historyBox.put('audioQuality', quality);

  bool getOfflineMode() =>
      _historyBox.get('offlineMode', defaultValue: 'false') == 'true';

  Future<void> setOfflineMode(bool value) =>
      _historyBox.put('offlineMode', value ? 'true' : 'false');

  bool getCheckUpdates() =>
      _historyBox.get('checkUpdates', defaultValue: 'true') == 'true';

  Future<void> setCheckUpdates(bool value) =>
      _historyBox.put('checkUpdates', value ? 'true' : 'false');

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
  // USER PLAYLISTS
  // ═════════════════════════════════════════════

  Future<String> createUserPlaylist(String name) async {
    final id = 'up_${DateTime.now().millisecondsSinceEpoch}';
    await _userPlaylistsBox.put(
      id,
      jsonEncode({'name': name, 'songs': <String>[]}),
    );
    return id;
  }

  Future<void> addUserPlaylistSongs(String id, List<Song> songs) async {
    final raw = _userPlaylistsBox.get(id);
    if (raw == null) return;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['songs'] as List<dynamic>? ?? []).cast<String>();
    final existing = <String>{};
    for (final s in list) {
      try {
        existing.add((jsonDecode(s) as Map<String, dynamic>)['id'] as String);
      } catch (_) {}
    }
    for (final song in songs) {
      if (existing.add(song.id)) list.add(jsonEncode(song.toJson()));
    }
    map['songs'] = list;
    await _userPlaylistsBox.put(id, jsonEncode(map));
  }

  List<({String id, String name, int count})> getUserPlaylists() {
    final out = <({String id, String name, int count})>[];
    for (final key in _userPlaylistsBox.keys) {
      try {
        final map = jsonDecode(_userPlaylistsBox.get(key) as String)
        as Map<String, dynamic>;
        out.add((
        id: key as String,
        name: map['name'] as String? ?? 'Playlist',
        count: (map['songs'] as List<dynamic>? ?? []).length,
        ));
      } catch (_) {}
    }
    return out;
  }

  List<Song> getUserPlaylistSongs(String id) {
    final raw = _userPlaylistsBox.get(id);
    if (raw == null) return [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final songs = <Song>[];
      for (final s in map['songs'] as List<dynamic>? ?? []) {
        try {
          songs.add(Song.fromJson(jsonDecode(s as String)));
        } catch (_) {}
      }
      return songs;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteUserPlaylist(String id) => _userPlaylistsBox.delete(id);

  // ═════════════════════════════════════════════
  // SEARCH QUERIES
  // ═════════════════════════════════════════════

  Future<void> saveQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final existing = _queriesBox.values.toList();
    final filtered = existing.where((q) => q != trimmed).toList();
    filtered.insert(0, trimmed);
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
    final existing = _historyBox.values.toList();

    final filtered = existing.where((s) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        return map['id'] != song.id;
      } catch (_) {
        return false;
      }
    }).toList();

    // Stamp the current play time (used by the History screen's date
    // groups); previously saved entries keep their original stamp.
    final entry = jsonEncode({
      ...song.toJson(),
      'playedAt': DateTime.now().millisecondsSinceEpoch,
    });
    filtered.insert(0, entry);
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

  /// History with play timestamps (History screen date groups).
  /// Newest first. Entries saved before this field existed return
  /// playedAt: null (they land in the "Earlier" bucket).
  List<({Song song, DateTime? playedAt})> getPlayedHistoryDetailed() {
    final out = <({Song song, DateTime? playedAt})>[];
    for (final raw in _historyBox.values) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final song = Song.fromJson(map);
        final ts = (map['playedAt'] as num?)?.toInt();
        out.add((
        song: song,
        playedAt: ts == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(ts),
        ));
      } catch (_) {}
    }
    return out;
  }

  /// Removes a single song from the played history.
  Future<void> removePlayedSong(String songId) async {
    final existing = _historyBox.values.toList();
    final kept = <String>[];
    for (final s in existing) {
      try {
        final map = jsonDecode(s) as Map<String, dynamic>;
        if (map['id'] != songId) kept.add(s);
      } catch (_) {}
    }
    await _historyBox.clear();
    for (var i = 0; i < kept.length; i++) {
      await _historyBox.put(i.toString(), kept[i]);
    }
  }

  Future<void> clearHistory() async {
    await _historyBox.clear();
  }

  // ═════════════════════════════════════════════
  // LAST SESSION (playback state)
  // ═════════════════════════════════════════════

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
  // STREAM CACHE (url + client headers + quality info)
  // ═════════════════════════════════════════════

  Future<void> cacheStream(String songId, String url,
      Map<String, String> headers,
      {String? audioType, int? bitrateKbps}) async {
    final data = {
      'url': url,
      'headers': headers,
      if (audioType != null) 'audioType': audioType,
      if (bitrateKbps != null) 'bitrateKbps': bitrateKbps,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await _urlCacheBox.put(songId, jsonEncode(data));
  }

  ({String url, Map<String, String> headers, String? audioType, int? bitrateKbps})?
  getCachedStream(String songId) {
    final raw = _urlCacheBox.get(songId);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ts = (map['timestamp'] as num?)?.toInt() ?? 0;
      final age = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ts));
      if (age > _urlCacheTtl) {
        _urlCacheBox.delete(songId);
        return null;
      }
      final url = map['url'] as String?;
      if (url == null || url.isEmpty) return null;
      final headers = (map['headers'] as Map<dynamic, dynamic>? ?? {})
          .map((k, v) => MapEntry(k.toString(), v.toString()));
      return (
      url: url,
      headers: headers,
      audioType: map['audioType'] as String?,
      bitrateKbps: (map['bitrateKbps'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUrlCache() async {
    await _urlCacheBox.clear();
  }

  Future<int> getUrlCacheSize() async => _urlCacheBox.length;

  // ═════════════════════════════════════════════
  // LISTENING STATS (annual-recap data)
  // ═════════════════════════════════════════════

  Map<String, dynamic>? getListeningStats() {
    final raw = _listeningStatsBox.get('stats');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveListeningStats(Map<String, dynamic> stats) =>
      _listeningStatsBox.put('stats', jsonEncode(stats));

  Future<void> clearListeningStats() => _listeningStatsBox.clear();

  // ═════════════════════════════════════════════
  // PARAMETRIC EQ PROFILES (eq_profiles box)
  // ═════════════════════════════════════════════

  List<EqProfile> getEqProfiles() {
    final out = <EqProfile>[];
    for (final key in _eqProfilesBox.keys) {
      try {
        final map = jsonDecode(_eqProfilesBox.get(key) as String)
        as Map<String, dynamic>;
        out.add(EqProfile.fromJson(map, fallbackId: key as String));
      } catch (_) {}
    }
    return out;
  }

  Future<void> saveEqProfile(EqProfile profile) =>
      _eqProfilesBox.put(profile.id, jsonEncode(profile.toJson()));

  Future<void> deleteEqProfile(String id) => _eqProfilesBox.delete(id);

  EqProfile? getActiveEqProfile() {
    for (final p in getEqProfiles()) {
      if (p.isActive) return p;
    }
    return null;
  }

  /// Marks [id] as the single active profile; null deactivates all.
  Future<void> setActiveEqProfile(String? id) async {
    for (final key in _eqProfilesBox.keys) {
      final raw = _eqProfilesBox.get(key);
      if (raw == null) continue;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final isActive = id != null && key == id;
        if ((map['isActive'] as bool? ?? false) != isActive) {
          map['isActive'] = isActive;
          await _eqProfilesBox.put(key as String, jsonEncode(map));
        }
      } catch (_) {}
    }
  }
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