// ZenMusic · vorlon-dev
//
// Saved data for the web player (favourites, history, playlists, theme).
// Stored in the browser through Hive (IndexedDB). If storage is blocked the
// player still works; data just lasts for the session.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/web/web_models.dart';

class WebStore extends ChangeNotifier {
  WebStore._(this._box);

  /// A store that keeps everything in memory only (used by tests).
  WebStore.memory() : _box = null;

  final Box<String>? _box;

  static const int maxHistory = 60;

  static Future<WebStore> open() async {
    try {
      await Hive.initFlutter();
      final box = await Hive.openBox<String>('zen_web');
      final store = WebStore._(box);
      store._load();
      return store;
    } catch (_) {
      return WebStore.memory();
    }
  }

  List<WebSong> _favourites = [];
  List<WebSong> _history = [];
  final Map<String, List<WebSong>> _playlists = {};
  ThemeMode _theme = ThemeMode.dark;

  List<WebSong> get favourites => List.unmodifiable(_favourites);
  List<WebSong> get history => List.unmodifiable(_history);
  List<String> get playlistNames => List.unmodifiable(_playlists.keys);
  ThemeMode get themeMode => _theme;

  List<WebSong> playlist(String name) =>
      List.unmodifiable(_playlists[name] ?? const <WebSong>[]);

  bool isFavourite(String id) => _favourites.any((s) => s.id == id);

  // ---- mutations -------------------------------------------------------

  void toggleFavourite(WebSong song) {
    if (isFavourite(song.id)) {
      _favourites = [for (final s in _favourites) if (s.id != song.id) s];
    } else {
      _favourites = [song, ..._favourites];
    }
    _save('favourites', _favourites);
    notifyListeners();
  }

  void addToHistory(WebSong song) {
    final next = <WebSong>[
      song,
      for (final s in _history)
        if (s.id != song.id) s,
    ];
    _history = next.length > maxHistory ? next.sublist(0, maxHistory) : next;
    _save('history', _history);
    notifyListeners();
  }

  void clearHistory() {
    _history = [];
    _save('history', _history);
    notifyListeners();
  }

  /// Creates an empty playlist. Returns false if the name is empty or taken.
  bool createPlaylist(String name) {
    final n = name.trim();
    if (n.isEmpty || _playlists.containsKey(n)) return false;
    _playlists[n] = [];
    _savePlaylists();
    notifyListeners();
    return true;
  }

  void deletePlaylist(String name) {
    if (_playlists.remove(name) != null) {
      _savePlaylists();
      notifyListeners();
    }
  }

  void addToPlaylist(String name, WebSong song) {
    final list = _playlists[name];
    if (list == null || list.any((s) => s.id == song.id)) return;
    _playlists[name] = [...list, song];
    _savePlaylists();
    notifyListeners();
  }

  void removeFromPlaylist(String name, String songId) {
    final list = _playlists[name];
    if (list == null) return;
    _playlists[name] = [for (final s in list) if (s.id != songId) s];
    _savePlaylists();
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _theme = mode;
    _put('theme', mode.name);
    notifyListeners();
  }

  // ---- persistence -----------------------------------------------------

  void _load() {
    _favourites = _readSongs('favourites');
    _history = _readSongs('history');
    final raw = _box?.get('playlists');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            _playlists['$k'] = _songsFrom(v);
          });
        }
      } catch (_) {}
    }
    final t = _box?.get('theme');
    for (final m in ThemeMode.values) {
      if (m.name == t) _theme = m;
    }
  }

  List<WebSong> _readSongs(String key) {
    final raw = _box?.get(key);
    if (raw == null) return [];
    try {
      return _songsFrom(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  static List<WebSong> _songsFrom(Object? v) {
    final out = <WebSong>[];
    if (v is List) {
      for (final e in v) {
        final s = WebSong.fromStored(e);
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  void _save(String key, List<WebSong> songs) =>
      _put(key, jsonEncode([for (final s in songs) s.toJson()]));

  void _savePlaylists() => _put(
        'playlists',
        jsonEncode({
          for (final e in _playlists.entries)
            e.key: [for (final s in e.value) s.toJson()],
        }),
      );

  void _put(String key, String value) {
    try {
      _box?.put(key, value);
    } catch (_) {}
  }
}
