// ZenMusic · vorlon-dev
//
// ZenDb — read-only client for YOUR own Firebase Realtime Database song store.
// Feeds: song_id, lyrics, spotify_canvas_url, song_cdn_url (jiosaavn 320/FLAC),
// youtube_url. No auth, no keys — the DB is public-read by design.
//
// URL resolution order:
//   1. manualUrl below — your Firebase URL (already set, drag-and-drop setup)
//   2. SharedPreferences key 'zendb_db_url'  (set at runtime via setDbUrl)
//   3. --dart-define=ZENDB_URL=https://xxxx-default-rtdb.<region>.firebasedatabase.app
//   4. empty → disabled, the app behaves exactly like without this file.
//
// Used by the player: DB-first audio (media_player._getAudioSource) and
// DB-first canvas (player_page._maybeLoadVideoBackdrop).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ZenDbService {
  ZenDbService._();
  static final ZenDbService instance = ZenDbService._();

  // ┌─────────────────────────────────────────────────────────────────────┐
  // │  YOUR FIREBASE DATABASE URL (already set — change it here if you    │
  // │  ever want to use a different database).                            │
  // └─────────────────────────────────────────────────────────────────────┘
  static const manualUrl = 'https://qobuz-6cf7d-default-rtdb.firebaseio.com';

  static const _prefKey = 'zendb_db_url';
  static const _defineUrl = String.fromEnvironment('ZENDB_URL');

  final _client = http.Client();

  /// One GET per song per session — audio + canvas hooks share this cache.
  final _cache = <String, Map<String, dynamic>?>{};

  String? _url;
  bool _urlLoaded = false;
  Future<SharedPreferences>? _prefsLoad;

  /// The resolved database URL (null = disabled).
  String? get dbUrl => _url;

  Future<SharedPreferences> get _prefs =>
      (_prefsLoad ??= SharedPreferences.getInstance());

  Future<String?> _resolveUrl() async {
    if (_urlLoaded) return _url;
    // 1. hardcoded manualUrl (drag-and-drop setup) wins.
    if (manualUrl.trim().isNotEmpty) {
      _url = _normalize(manualUrl);
      _urlLoaded = true;
      return _url;
    }
    // 2. saved app URL, then 3. dart-define.
    try {
      final v = (await _prefs).getString(_prefKey);
      if (v != null && v.trim().isNotEmpty) {
        _url = _normalize(v);
      }
    } catch (_) {
      // prefs unavailable (e.g. early startup) — fall through to define.
    }
    _url ??= _defineUrl.isNotEmpty ? _normalize(_defineUrl) : null;
    _urlLoaded = true;
    return _url;
  }

  /// Persists the database URL and clears the per-session song cache.
  Future<void> setDbUrl(String url) async {
    final clean = _normalize(url);
    _url = clean.isEmpty ? null : clean;
    _urlLoaded = true;
    _cache.clear();
    try {
      await (await _prefs).setString(_prefKey, clean);
    } catch (_) {
      // prefs write failed — in-memory URL still active for this session.
    }
  }

  String _normalize(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// Full song map (flat fields) or null: not fed / disabled / unreachable.
  /// Never throws — a DB error must never block or crash playback.
  Future<Map<String, dynamic>?> fetch(String songId,
      {Duration timeout = const Duration(seconds: 4)}) async {
    final base = await _resolveUrl();
    if (base == null || base.isEmpty) return null;
    final id = songId.trim();
    if (id.isEmpty) return null;
    if (_cache.containsKey(id)) return _cache[id];
    try {
      final r =
          await _client.get(Uri.parse('$base/songs/$id.json')).timeout(timeout);
      if (r.statusCode != 200) {
        _cache[id] = null;
        return null;
      }
      final body = r.body;
      if (body == 'null' || body.isEmpty) {
        _cache[id] = null;
        return null;
      }
      final v = jsonDecode(body);
      _cache[id] = v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
    return _cache[id];
  }

  /// Direct play link from the DB: song_cdn_url (jiosaavn 320kbps / FLAC).
  Future<String?> streamUrlFor(String songId) async {
    final s = await fetch(songId);
    return s?['song_cdn_url'] as String?;
  }

  /// Looping canvas video from the DB: spotify_canvas_url.
  Future<String?> canvasUrlFor(String songId) async {
    final s = await fetch(songId);
    return s?['spotify_canvas_url'] as String?;
  }

  /// Lyrics text from the DB (plain, already stored inline).
  Future<String?> lyricsFor(String songId) async {
    final s = await fetch(songId);
    return s?['lyrics'] as String?;
  }

  /// Cheap id-only listing (shallow read) — browse screens.
  Future<List<String>> allIds() async {
    final base = await _resolveUrl();
    if (base == null || base.isEmpty) return [];
    try {
      final r = await _client
          .get(Uri.parse('$base/songs.json?shallow=true'))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.body == 'null') return [];
      final v = jsonDecode(r.body);
      if (v is! Map<String, dynamic>) return [];
      final ids = v.keys.map((k) => k.toString()).toList()..sort();
      return ids;
    } catch (_) {
      return [];
    }
  }

  // ── WRITE SIDE (auto-capture) ────────────────────────────────────────
  //
  // Every song the app plays flows INTO your Firebase DB. Rules:
  //   * fire-and-forget — a DB write can never slow or block playback
  //   * only EMPTY fields get filled — links you fed by hand are never
  //     overwritten
  //   * song_cdn_url only stores permanent links (jiosaavn aac.saavncdn.com
  //     320kbps). Signed/expiring streams (YouTube, Spotify DRM, mirrors)
  //     are never stored — a dead link in the DB would only hurt you.

  final _audioCaptured = <String>{}; // one audio capture per song per session

  /// Store a played song. Called by the player on every playback start.
  Future<void> captureSong(Map<String, dynamic> song) async {
    final id = (song['videoId'] ?? '').toString().trim();
    if (id.isEmpty) return;
    if (_audioCaptured.contains(id)) return;
    _audioCaptured.add(id);
    try {
      final existing = await fetch(id);
      bool emptyIn(Map<String, dynamic>? e, String field) =>
          e == null || ((e[field] as String?)?.trim().isEmpty ?? true);
      final updates = <String, dynamic>{'song_id': id};
      if (emptyIn(existing, 'song_cdn_url')) {
        final cdn =
            (song['jiosaavnStreamUrl'] ?? song['song_cdn_url']) as String?;
        if (cdn != null && cdn.trim().isNotEmpty) {
          updates['song_cdn_url'] = cdn;
        }
      }
      final isSaavn = song['type'] == 'JIOSAAVN';
      if (!isSaavn && emptyIn(existing, 'youtube_url')) {
        updates['youtube_url'] = 'https://music.youtube.com/watch?v=$id';
      }
      if (updates.length > 1) {
        await _patch('songs/$id.json', updates);
      }
    } catch (_) {
      // DB write failed — playback is never affected.
    }
  }

  /// Store a resolved canvas video (only if the DB has none for this song).
  Future<void> captureCanvas(String songId, String canvasUrl) async {
    final id = songId.trim();
    final url = canvasUrl.trim();
    if (id.isEmpty || url.isEmpty) return;
    try {
      final existing = await fetch(id);
      if (existing != null &&
          (existing['spotify_canvas_url'] as String?)?.trim().isNotEmpty ==
              true) {
        return;
      }
      await _patch(
          'songs/$id.json', {'song_id': id, 'spotify_canvas_url': url});
    } catch (_) {}
  }

  /// Store plain lyrics text (only if the DB has none for this song).
  Future<void> captureLyrics(String songId, String lyrics) async {
    final id = songId.trim();
    final text = lyrics.trim();
    if (id.isEmpty || text.isEmpty) return;
    try {
      final existing = await fetch(id);
      if (existing != null &&
          (existing['lyrics'] as String?)?.trim().isNotEmpty == true) {
        return;
      }
      await _patch('songs/$id.json', {'song_id': id, 'lyrics': text});
    } catch (_) {}
  }

  /// REST PATCH = merge keys into the song node, keeping the rest intact.
  Future<void> _patch(String path, Map<String, dynamic> data) async {
    final base = await _resolveUrl();
    if (base == null || base.isEmpty) return;
    try {
      await _client
          .patch(
            Uri.parse('$base/$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      // network hiccup — ignore, next play tries again
    }
  }

  void dispose() {
    _client.close();
  }
}
