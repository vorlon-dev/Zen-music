// ZenMusic — Spotify Canvas (SP-9, extended in SP-76).
// SP-9: the short looping videos behind a track, fetched from Spotify's
// internal `canvaz-cache` service (Protobuf, hand-encoded/decoded to avoid
// a protobuf runtime dependency). Reuses the web-player access token.
//
// SP-76: while a Spotify session is up, EVERY playing track gets a canvas —
// not only songs that already carry a `spotifyUri`. The track is matched on
// Spotify by title/artist (Pathfinder searchTracks → official Web API
// search), then its canvas is fetched via the protobuf route first and the
// web player's own `canvas` GraphQL operation second, with the persisted-
// query hash re-read from the web player script when the baked-in one has
// been retired. An anonymous session answers null with the reason said out
// loud, so the player falls through to its normal backdrop instead of
// silently showing nothing.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyCanvas {
  SpotifyCanvas._();
  static final SpotifyCanvas instance = SpotifyCanvas._();

  static const _endpoint =
      'https://spclient.wg.spotify.com/canvaz-cache/v0/canvases';

  /// The `canvas` operation's hash as of the last time it was read off the
  /// web player. Only used when the live script cannot be read; the answer
  /// a retired hash produces is refused, which is why the failure is logged.
  static const _knownCanvasHash =
      '575138ab27cd5c1b3e54da54d0a7cc8d85485402de26340c2145f0f6bb5e7a9f';

  /// SimpMusic's proven `searchTracks` hash — second try after the repo's
  /// own [SpotifyConfig.searchTracksHash] (the two builds name the same
  /// operation with different hashes).
  static const _simpMusicSearchHash =
      'bc1ca2fcd0ba1013a0fc88e6cc4f190af501851e3dafd3e1ef85840297694428';

  /// The canvaz-cache endpoint answers to the mobile player, not the web
  /// one — its answers key off a mobile User-Agent.
  static const _canvazUa = 'Spotify/9.0.34.593 iOS/18.4 (iPhone15,3)';

  /// A canvas URL must be a plain video file, exactly like the web player's
  /// own answer check.
  static final RegExp _mp4Suffix =
      RegExp(r'\.mp4(?:[?#]|$)', caseSensitive: false);

  /// Last-resort scan for the protobuf answer: some canvases carry the URL
  /// under a field tag the hand-rolled decoder does not map — a plain scan
  /// of the raw bytes for an `https…mp4` URL still finds it.
  static final RegExp _mp4Any =
      RegExp(r'https://[^\x00-\x20"\x27]+\.mp4[^\x00-\x20"\x27]*');

  // url → '' (definitive miss) or the canvas URL. Misses are cached so a
  // track without a canvas costs one lookup per session, not one per
  // widget rebuild. Network failures are NOT cached — they are transient.
  final Map<String, String> _cache = {};

  /// Whether the last `_canvasForTrack` ended with a definitive
  /// "this track has no canvas" (both routes answered successfully) rather
  /// than with a network/auth failure. Only misses that are definitive get
  /// cached — a refused session must not poison the cache.
  bool _lastLookupWasDefinitive = false;

  // 'title|artist' → spotify track id ('' = nothing matched).
  final Map<String, String> _trackIdCache = {};

  // Web player script cache (persisted-query hashes). The player is
  // rebuilt every few weeks; the script is several megabytes — read at
  // most once per 6 h, and only when the baked-in hashes stop working.
  String? _playerScript;
  DateTime _playerScriptAt = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String?>? _scriptFetch;

  // ── public surface ──────────────────────────────────────────────────

  /// The canvas for a track that already carries a Spotify id/uri.
  /// SP-9 entry point, kept for direct callers.
  Future<String?> fetchCanvasUrl(String trackIdOrUri) async {
    final cleanId = trackIdOrUri.split(':').last;
    if (cleanId.isEmpty) return null;

    if (_cache.containsKey(cleanId)) {
      final cached = _cache[cleanId]!;
      return cached.isEmpty ? null : cached;
    }

    final url = await _canvasForTrack('spotify:track:$cleanId');
    debugPrint('[spotify-canvas] $cleanId -> ${url ?? "none"}');
    if (url != null || _lastLookupWasDefinitive) _cache[cleanId] = url ?? '';
    _trimCaches();
    return url;
  }

  /// SP-76: the canvas for the playing song, or null.
  ///
  /// [spotifyUri] short-circuits the search when the song already carries a
  /// Spotify id. Without one the track is matched by title/artist — so
  /// YTM-sourced songs get canvases too. Requires a Spotify session: an
  /// anonymous run says so once per track and answers null, and the player
  /// keeps whatever backdrop it had.
  Future<String?> resolveCanvasUrl({
    String? spotifyUri,
    required String title,
    required String artist,
    String? album,
    int? durationMs,
  }) async {
    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);
    if (cleanTitle.isEmpty || cleanArtist.isEmpty) return null;

    if (spotifyUri != null && spotifyUri.isNotEmpty) {
      return fetchCanvasUrl(spotifyUri);
    }

    final key = '$cleanTitle|$cleanArtist'.toLowerCase();
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      return cached.isEmpty ? null : cached;
    }

    try {
      final token = await SpotifyAuth.instance.getAccessToken();
      if (token == null) {
        debugPrint('[spotify-canvas] no Spotify session for "$cleanTitle" — '
            'sign in to Spotify for canvases');
        return null; // not logged in is not a miss — nothing was asked
      }

      final trackId = await _resolveTrackId(token, cleanTitle, cleanArtist,
          durationMs);
      if (trackId == null || trackId.isEmpty) {
        debugPrint('[spotify-canvas] no Spotify track matched '
            '"$cleanTitle" — "$cleanArtist"');
        _cache[key] = '';
        _trimCaches();
        return null;
      }
      final url = await _canvasForTrack('spotify:track:$trackId');
      debugPrint('[spotify-canvas] "$cleanTitle" -> $trackId -> '
          '${url ?? "no canvas"}');
      if (url != null || _lastLookupWasDefinitive) _cache[key] = url ?? '';
      _trimCaches();
      return url;
    } catch (e) {
      debugPrint('[spotify-canvas] resolve error for "$cleanTitle": $e');
      return null; // transient — leave the miss uncached
    }
  }



  // ── canvas fetch: protobuf route, then the web player's own query ────

  Future<String?> _canvasForTrack(String trackUri, {String? token}) async {
    _lastLookupWasDefinitive = false;
    final bearer = token ?? await SpotifyAuth.instance.getAccessToken();
    if (bearer == null) {
      debugPrint('[spotify-canvas] no session — canvas skipped for '
          '$trackUri');
      return null;
    }
    final clientToken = await SpotifyAuth.instance.getClientToken();

    final viaProto =
        await _canvasViaProtobuf(bearer, clientToken, trackUri, 0);
    if (viaProto != null) {
      _lastLookupWasDefinitive = true;
      return viaProto;
    }

    final viaQuery = await _canvasViaQuery(bearer, clientToken, trackUri);
    if (viaQuery != null) {
      _lastLookupWasDefinitive = true;
      return viaQuery;
    }
    return null;
  }

  /// The canvas from the protobuf endpoint. One re-mint + retry on a
  /// refused session, exactly like the app's own pathfinder calls.
  Future<String?> _canvasViaProtobuf(
    String token,
    String clientToken,
    String trackUri,
    int attempt,
  ) async {
    try {
      final r = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/protobuf',
          'Content-Type': 'application/protobuf',
          'User-Agent': _canvazUa,
          'app-platform': SpotifyConfig.appPlatform,
          if (clientToken.isNotEmpty) 'client-token': clientToken,
        },
        body: _encodeRequest(trackUri),
      )
          .timeout(const Duration(seconds: 8));

      if (r.statusCode == 401 || r.statusCode == 403) {
        debugPrint('[spotify-canvas] canvaz HTTP ${r.statusCode} for '
            '$trackUri — the session was refused');
        if (attempt == 0) {
          SpotifyAuth.instance.invalidateAccessToken();
          final fresh = await SpotifyAuth.instance.getAccessToken(force: true);
          if (fresh != null) {
            return await _canvasViaProtobuf(fresh, clientToken, trackUri, 1);
          }
        }
        return null;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('[spotify-canvas] canvaz HTTP ${r.statusCode} for '
            '$trackUri');
        return null;
      }

      // The protobuf decoder is authoritative; the byte scan only catches
      // answers whose canvas tag the hand-rolled reader does not map.
      return _decodeFirstUrl(r.bodyBytes) ?? _scanMp4(r.bodyBytes);
    } catch (e) {
      debugPrint('[spotify-canvas] canvaz error for $trackUri: $e');
      return null;
    }
  }

  /// The canvas as the web player itself asks for it: the `canvas`
  /// operation on Pathfinder v2. A retired persisted-query hash reads as
  /// "persisted query not found" — the hash is re-read from the web
  /// player's script once before giving up.
  Future<String?> _canvasViaQuery(
    String token,
    String clientToken,
    String trackUri, {
    bool isRetry = false,
  }) async {
    try {
      final hash = await _canvasHash(forceRefresh: isRetry);
      final payload = jsonEncode(<String, dynamic>{
        'operationName': 'canvas',
        'variables': <String, dynamic>{'trackUri': trackUri},
        'extensions': <String, dynamic>{
          'persistedQuery': <String, dynamic>{'version': 1, 'sha256Hash': hash},
        },
      });

      final r = await http
          .post(
        Uri.parse(SpotifyConfig.pathfinderUrl),
        headers: {
          'authorization': 'Bearer $token',
          'client-token': clientToken,
          'content-type': 'application/json;charset=UTF-8',
          'app-platform': SpotifyConfig.appPlatform,
          'spotify-app-version': SpotifyConfig.spotifyAppVersion,
          'origin': 'https://open.spotify.com',
          'referer': 'https://open.spotify.com/',
          'user-agent': SpotifyConfig.userAgent,
        },
        body: payload,
      )
          .timeout(const Duration(seconds: 10));

      if (r.statusCode == 401 || r.statusCode == 403) {
        debugPrint('[spotify-canvas] canvas query HTTP ${r.statusCode} for '
            '$trackUri — the session was refused, sign in again');
        return null;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('[spotify-canvas] canvas query HTTP ${r.statusCode} for '
            '$trackUri');
        return null;
      }
      return await _parseCanvasQuery(r.body, trackUri, isRetry: isRetry);
    } catch (e) {
      debugPrint('[spotify-canvas] canvas query error for $trackUri: $e');
      return null;
    }
  }

  /// Reads the canvas out of a `canvas` operation answer. Returns null on
  /// NoCanvas / Failed; a stale hash retries once with a refreshed one.
  Future<String?> _parseCanvasQuery(String body, String trackUri,
      {required bool isRetry}) async {
    final Object? root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      debugPrint('[spotify-canvas] canvas query answer was not JSON');
      return null;
    }
    if (root is! Map<String, dynamic>) return null;

    final List<String> errors = (root['errors'] as List?)
            ?.map((e) => e is Map ? '${e['message'] ?? ''}' : '')
            .toList() ??
        const [];
    final data = root['data'];
    if (data is! Map<String, dynamic> || data.isEmpty) {
      final joined = errors.where((e) => e.isNotEmpty).join('; ').trim();
      final reason = joined.isEmpty ? 'no data' : joined;
      final stale = errors.any(
          (e) => e.toLowerCase().contains('persistedquerynotfound'));
      debugPrint('[spotify-canvas] canvas query failed for $trackUri: '
          '$reason');
      if (stale && !isRetry) {
        return await _canvasViaQueryStale(trackUri);
      }
      return null;
    }

    final canvas =
        ((data['trackUnion'] as Map<String, dynamic>?)?['canvas'])
            as Map<String, dynamic>?;
    final url = canvas?['url'];
    if (url is String && url.startsWith('https://')) {
      if (_mp4Suffix.hasMatch(url)) return url;
      debugPrint('[spotify-canvas] canvas for $trackUri is not a plain '
          'video: ${canvas?['type']} $url');
    }
    return null;
  }

  /// The stale-hash retry — the lookup itself is re-run with a fresh hash,
  /// which needs the current bearer again.
  Future<String?> _canvasViaQueryStale(String trackUri) async {
    try {
      final token = await SpotifyAuth.instance.getAccessToken();
      if (token == null) return null;
      final clientToken = await SpotifyAuth.instance.getClientToken();
      return await _canvasViaQuery(token, clientToken, trackUri, isRetry: true);
    } catch (_) {
      return null;
    }
  }

  // ── track resolution: find the Spotify id of the playing song ────────

  Future<String?> _resolveTrackId(
      String token, String title, String artist, int? durationMs) async {
    final key = '$title|$artist'.toLowerCase();
    if (_trackIdCache.containsKey(key)) {
      final id = _trackIdCache[key]!;
      return id.isEmpty ? null : id;
    }

    final credits = _splitArtists(artist);
    final primaryArtist = credits.isEmpty ? artist : credits.first;
    final queries = <String>[
      '$title $primaryArtist'.trim(),
      if ('$title $artist'.trim() != '$title $primaryArtist'.trim())
        '$title $artist'.trim(),
    ];

    // 1. Pathfinder searchTracks — the app's own hash first, SimpMusic's
    //    proven one second (the same operation under two builds).
    for (final hash in <String>[
      SpotifyConfig.searchTracksHash,
      _simpMusicSearchHash,
    ]) {
      for (final q in queries) {
        final items = await _searchTracksPathfinder(token, q, hash);
        final id = _pickTrack(items, title, durationMs);
        if (id != null) {
          _trackIdCache[key] = id;
          return id;
        }
      }
    }

    // 2. Official Web API search — the minted Bearer carries the search
    //    scope; this is the fallback when both Pathfinder hashes are retired.
    for (final q in queries) {
      final id = await _searchTrackWebApi(token, q, title, durationMs);
      if (id != null) {
        _trackIdCache[key] = id;
        return id;
      }
    }

    _trackIdCache[key] = '';
    return null;
  }

  Future<List<Map<String, dynamic>>> _searchTracksPathfinder(
      String token, String query, String hash) async {
    try {
      final clientToken = await SpotifyAuth.instance.getClientToken();
      final payload = jsonEncode(<String, dynamic>{
        'operationName': 'searchTracks',
        'variables': <String, dynamic>{
          'searchTerm': query,
          'offset': 0,
          'limit': 5,
          'numberOfTopResults': 5,
          'includeAudiobooks': false,
          'includePreReleases': false,
        },
        'extensions': <String, dynamic>{
          'persistedQuery': <String, dynamic>{'version': 1, 'sha256Hash': hash},
        },
      });

      Future<http.Response> call(String bearer, String ct) => http
          .post(
        Uri.parse(SpotifyConfig.pathfinderUrl),
        headers: {
          'authorization': 'Bearer $bearer',
          'client-token': ct,
          'content-type': 'application/json;charset=UTF-8',
          'app-platform': SpotifyConfig.appPlatform,
          'spotify-app-version': SpotifyConfig.spotifyAppVersion,
          'origin': 'https://open.spotify.com',
          'referer': 'https://open.spotify.com/',
          'user-agent': SpotifyConfig.userAgent,
        },
        body: payload,
      )
          .timeout(const Duration(seconds: 10));

      var resp = await call(token, clientToken);
      if (resp.statusCode == 401 && _simpMusicSearchHash != hash) {
        // A retired hash and a refused session both 401 here; drop the
        // credentials once and let the NEXT hash speak for itself.
        SpotifyAuth.instance.invalidateAccessToken();
        final fresh = await SpotifyAuth.instance.getAccessToken(force: true);
        if (fresh != null) resp = await call(fresh, clientToken);
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint('[spotify-canvas] searchTracks HTTP ${resp.statusCode} '
            '(hash ${hash.substring(0, 8)}…)');
        return const [];
      }
      final decoded = jsonDecode(resp.body);
      return _extractTracks(decoded);
    } catch (e) {
      debugPrint('[spotify-canvas] searchTracks error: $e');
      return const [];
    }
  }

  Future<String?> _searchTrackWebApi(
      String token, String query, String title, int? durationMs) async {
    try {
      final r = await http
          .get(
        Uri.parse(
            '${SpotifyConfig.restApiBase}/search?type=track&limit=5&q='
            '${Uri.encodeComponent(query)}'),
        headers: {
          'Authorization': 'Bearer $token',
          'User-Agent': SpotifyConfig.userAgent,
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('[spotify-canvas] web search HTTP ${r.statusCode}');
        return null;
      }
      final decoded = jsonDecode(r.body);
      final items = ((decoded is Map<String, dynamic>
                  ? decoded['tracks']
                  : null)
              as Map<String, dynamic>?)?['items'] as List?;
      if (items == null || items.isEmpty) return null;
      final mapped = items
          .whereType<Map<String, dynamic>>()
          .map((e) => <String, dynamic>{
                'id': e['id'],
                'name': e['name'],
                'durationMs': e['duration_ms'],
              })
          .toList();
      return _pickTrack(mapped, title, durationMs);
    } catch (e) {
      debugPrint('[spotify-canvas] web search error: $e');
      return null;
    }
  }

  /// Every track-shaped node in an arbitrary search answer: a map with a
  /// `spotify:track:` uri plus a name. Shape-tolerant on purpose — the
  /// search payloads move between web player rebuilds, the track nodes
  /// themselves do not.
  List<Map<String, dynamic>> _extractTracks(Object? node) {
    final out = <Map<String, dynamic>>[];
    void walk(Object? n) {
      if (n is Map) {
        final uri = n['uri'];
        final name = n['name'];
        if (uri is String &&
            uri.startsWith('spotify:track:') &&
            name is String &&
            name.isNotEmpty) {
          out.add(Map<String, dynamic>.from(n));
          return; // matched — do not descend into the track itself
        }
        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final e in n) {
          walk(e);
        }
      }
    }

    walk(node);
    return out;
  }

  /// The track that the search returned which is most likely the one being
  /// played. A running time settles it when both sides know one: the same
  /// recording is the same length. Without a duration the name decides.
  String? _pickTrack(
      List<Map<String, dynamic>> items, String title, int? durationMs) {
    if (items.isEmpty) return null;
    String? uriOf(Map<String, dynamic> n) {
      final u = n['uri'];
      if (u is String && u.startsWith('spotify:track:')) {
        return u.split(':').last;
      }
      final id = n['id'];
      return id is String && id.isNotEmpty ? id : null;
    }

    if (durationMs != null && durationMs > 0) {
      Map<String, dynamic>? best;
      var bestDelta = 1 << 60;
      for (final n in items) {
        final ms = _trackMs(n);
        final delta = ms <= 0 ? (1 << 59) : (ms - durationMs).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          best = n;
        }
      }
      // A studio take and a live one of the same song are not the same
      // recording: only trust the clock inside a 12 s window.
      if (best != null &&
          bestDelta <= const Duration(seconds: 12).inMilliseconds) {
        return uriOf(best);
      }
    }
    for (final n in items) {
      final name = n['name'];
      if (name is String && _namesMatch(name, title)) return uriOf(n);
    }
    return uriOf(items.first);
  }

  int _trackMs(Map<String, dynamic> n) {
    final d = n['duration'];
    if (d is Map) {
      final ms = d['totalMilliseconds'];
      if (ms is int) return ms;
      if (ms is num) return ms.round();
    }
    final ms = n['durationMs'] ?? n['duration_ms'];
    if (ms is int) return ms;
    if (ms is num) return ms.round();
    return 0;
  }

  bool _namesMatch(String a, String b) {
    final x = _normalize(a);
    final y = _normalize(b);
    if (x.isEmpty || y.isEmpty) return false;
    return x == y || x.startsWith(y) || y.startsWith(x);
  }

  // ── the web player's persisted-query hash ────────────────────────────

  /// The `canvas` operation's hash, read out of the web player's own
  /// script. The read is remembered for 6 h; [forceRefresh] (the stale-hash
  /// retry) reads it again. Falls back to the last known good hash.
  Future<String?> _canvasHash({bool forceRefresh = false}) async {
    final script = await _playerScriptCached(forceRefresh: forceRefresh);
    if (script != null) {
      for (final m in _opDeclaration.allMatches(script)) {
        if (m.group(1) == 'canvas') return m.group(2);
      }
    }
    return _knownCanvasHash;
  }

  Future<String?> _playerScriptCached({bool forceRefresh = false}) {
    final age = DateTime.now().difference(_playerScriptAt);
    if (!forceRefresh &&
        _playerScript != null &&
        age < const Duration(hours: 6)) {
      return Future.value(_playerScript);
    }
    return _scriptFetch ??= _readPlayerScript()
        .whenComplete(() => _scriptFetch = null);
  }

  Future<String?> _readPlayerScript() async {
    try {
      final page = await _get('https://open.spotify.com/');
      if (page == null) return null;
      final bundles = _webPlayerScript
          .allMatches(page)
          .map((m) => m.group(0)!)
          .toSet()
          .toList();
      for (final bundle in bundles.take(4)) {
        final body = await _get(bundle);
        if (body == null) continue;
        // The first bundle that declares an operation is the player's own.
        if (_opDeclaration.allMatches(body).any((m) => m.group(1) == 'canvas')) {
          _playerScript = body;
          _playerScriptAt = DateTime.now();
          debugPrint('[spotify-canvas] web player hash source refreshed');
          return body;
        }
      }
      debugPrint('[spotify-canvas] no player bundle carried the canvas hash');
    } catch (e) {
      debugPrint('[spotify-canvas] player script read failed: $e');
    }
    return null;
  }

  Future<String?> _get(String url) async {
    try {
      final r = await http
          .get(
        Uri.parse(url),
        headers: {
          'User-Agent': SpotifyConfig.userAgent,
          'Referer': 'https://open.spotify.com/',
        },
      )
          .timeout(const Duration(seconds: 12));
      return (r.statusCode >= 200 && r.statusCode < 300) ? r.body : null;
    } catch (_) {
      return null;
    }
  }

  // ── string hygiene ───────────────────────────────────────────────────

  /// Words a title picks up from packaging rather than from the song.
  static final RegExp _titleNoise = RegExp(
      r'\s*[\(\[](?:feat\.?|ft\.?|official|video|audio|remastered|lyric|lyrics|hd|4k)[^\)\]]*[\)\]]',
      caseSensitive: false);

  String _cleanTitle(String s) =>
      s.replaceAll(_titleNoise, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _cleanArtist(String s) =>
      s.split(' | ').first.replaceAll(RegExp(r'\s+'), ' ').trim();

  static final RegExp _artistSep = RegExp(
      r'\s*,\s*|\s*&\s*|\s+x\s+|\bfeat\.?(?=\s|$)|\bft\.?(?=\s|$)|\bfeaturing\b|\bwith\b',
      caseSensitive: false);

  List<String> _splitArtists(String raw) => raw
      .split(_artistSep)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _trimCaches() {
    if (_cache.length > 128) _cache.remove(_cache.keys.first);
    if (_trackIdCache.length > 128) _trackIdCache.remove(_trackIdCache.keys.first);
  }

  // ── test surface — pure logic, no network (SP-76) ────────────────────

  @visibleForTesting
  Uint8List encodeCanvazRequest(String uri) => _encodeRequest(uri);

  @visibleForTesting
  String? decodeCanvazResponse(Uint8List bytes) => _decodeFirstUrl(bytes);

  @visibleForTesting
  String? scanMp4Url(Uint8List bytes) => _scanMp4(bytes);

  @visibleForTesting
  Future<String?> parseCanvasQueryBody(String body, String trackUri,
          {bool isRetry = false}) =>
      _parseCanvasQuery(body, trackUri, isRetry: isRetry);

  @visibleForTesting
  List<Map<String, dynamic>> extractTracks(Object? node) =>
      _extractTracks(node);

  @visibleForTesting
  String? pickTrack(List<Map<String, dynamic>> items, String title,
          int? durationMs) =>
      _pickTrack(items, title, durationMs);

  @visibleForTesting
  String cleanTitle(String s) => _cleanTitle(s);

  @visibleForTesting
  String cleanArtist(String s) => _cleanArtist(s);

  @visibleForTesting
  List<String> splitArtists(String raw) => _splitArtists(raw);

  @visibleForTesting
  String normalizeForMatch(String s) => _normalize(s);

  @visibleForTesting
  bool namesMatch(String a, String b) => _namesMatch(a, b);

  @visibleForTesting
  int trackMs(Map<String, dynamic> n) => _trackMs(n);

  /// The persisted-query hash for the `canvas` operation as declared in a
  /// web player script — the same matcher [_canvasHash] uses.
  @visibleForTesting
  String? canvasHashFromScript(String script) {
    for (final m in _opDeclaration.allMatches(script)) {
      if (m.group(1) == 'canvas') return m.group(2);
    }
    return null;
  }

  @visibleForTesting
  List<String> playerScriptUrls(String html) => _webPlayerScript
      .allMatches(html)
      .map((m) => m.group(0)!)
      .toSet()
      .toList();

  // ── the web player's own declarations ────────────────────────────────

  /// The player declares its operations as `"<name>","query","<64 hex>"`.
  static final RegExp _opDeclaration = RegExp(
      r'''["'](\w+)["']\s*,\s*["']query["']\s*,\s*["']([0-9a-f]{64})["']''');

  static final RegExp _webPlayerScript = RegExp(
      r'https://open\.spotifycdn\.com/cdn/build/web-player/[A-Za-z0-9._~-]+\.(?:js|mjs)');

  // ── minimal protobuf wire encode/decode (SP-9, unchanged) ────────────

  Uint8List _encodeRequest(String uri) {
    final uriBytes = utf8.encode(uri);
    // Entity: field 1 (entity_uri), wire type 2 (length-delimited)
    final entityBuilder = BytesBuilder();
    _writeTag(entityBuilder, 1, 2);
    _writeVarint(entityBuilder, uriBytes.length);
    entityBuilder.add(uriBytes);
    final entity = entityBuilder.toBytes();

    // EntityCanvazRequest: field 1 (entities), wire type 2
    final reqBuilder = BytesBuilder();
    _writeTag(reqBuilder, 1, 2);
    _writeVarint(reqBuilder, entity.length);
    reqBuilder.add(entity);
    return reqBuilder.toBytes();
  }

  String? _decodeFirstUrl(Uint8List data) {
    final r = _Reader(data);
    while (r.hasMore()) {
      final tag = r.readTag();
      final field = tag.$1;
      final wire = tag.$2;
      if (field == 1 && wire == 2) {
        final canvaz = r.readBytes();
        final url = _readCanvazUrl(canvaz);
        if (url != null) return url;
      } else {
        r.skip(wire);
      }
    }
    return null;
  }

  String? _readCanvazUrl(Uint8List canvaz) {
    final r = _Reader(canvaz);
    while (r.hasMore()) {
      final tag = r.readTag();
      final field = tag.$1;
      final wire = tag.$2;
      if (field == 2 && wire == 2) {
        return utf8.decode(r.readBytes());
      }
      r.skip(wire);
    }
    return null;
  }

  String? _scanMp4(Uint8List bytes) {
    try {
      final text = latin1.decode(bytes, allowInvalid: true);
      return _mp4Any.firstMatch(text)?.group(0);
    } catch (_) {
      return null;
    }
  }

  void _writeTag(BytesBuilder b, int field, int wire) {
    _writeVarint(b, (field << 3) | wire);
  }

  void _writeVarint(BytesBuilder b, int value) {
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.addByte(v & 0x7F);
  }
}

class _Reader {
  // (SP-76 canvas resolver helpers live above; the wire reader is SP-9.)
  final Uint8List data;
  int pos = 0;
  _Reader(this.data);
  bool hasMore() => pos < data.length;

  (int, int) readTag() {
    final v = readVarint();
    return (v >> 3, v & 0x7);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (pos < data.length) {
      final b = data[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
      if (shift >= 64) break;
    }
    return result;
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (len <= 0) return Uint8List(0);
    final end = (pos + len).clamp(0, data.length);
    final out = data.sublist(pos, end);
    pos = end;
    return out;
  }

  void skip(int wire) {
    if (wire == 0) {
      readVarint();
    } else if (wire == 1) {
      pos = (pos + 8).clamp(0, data.length);
    } else if (wire == 2) {
      final len = readVarint();
      pos = (pos + len).clamp(0, data.length);
    } else if (wire == 5) {
      pos = (pos + 4).clamp(0, data.length);
    } else {
      pos = data.length;
    }
  }
}


