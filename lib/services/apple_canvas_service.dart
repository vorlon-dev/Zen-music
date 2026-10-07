import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Apple Music animated artwork (canvas) provider — Dart port of Echo's
/// AppleMusicCanvasProvider + AppleMusicTokenProvider.
///
/// Strategy: AMP catalog search → per-result scoring (Echo's algorithm:
/// playlist blacklisting, strict artist match, name/album/edition
/// scoring) → `editorialVideo` HLS extraction (direct in the search
/// result, or via the full album lookup). Results cached 24h — but
/// ONLY genuine misses ("no canvas exists"); API/token failures are
/// never cached, so recovery is instant.
///
/// TOKEN HISTORY (do not regress): Apple's web player migrated from
/// WebPlayKit JWTs (kid "WebPlayKit", iss "AMPWebPlay", served from
/// amp-api.music.apple.com) to a NEW issuer (kid rotates, e.g.
/// "LT2ZDZSXNQ", iss "5IKPP2IECQ") served from
/// amp-api-edge.music.apple.com. Every scraper anchored to the old
/// header went 401 at once. The provider below hunts BOTH formats and
/// holds a manual override token (exp ~Dec 2026).
///
/// If a fresh-format token ever 401s on the primary host, flip
/// [_ampBase] to 'https://amp-api-edge.music.apple.com' — the edge
/// host serves the new issuer's tokens natively.
class AppleCanvasService {
  AppleCanvasService._();
  static final AppleCanvasService instance = AppleCanvasService._();

  static const _ampBase = 'https://amp-api.music.apple.com';
  static const _ttl = Duration(hours: 24);
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  final http.Client _client = http.Client();
  final Map<String, _CacheEntry> _cache = {};

  /// Storefront from the device locale (Echo uses Locale country).
  static String get _storefront {
    try {
      final locale = Platform.localeName; // e.g. en_US
      final parts = locale.split('_');
      if (parts.length > 1 && parts.last.length == 2) {
        return parts.last.toLowerCase();
      }
    } catch (_) {}
    return 'us';
  }

  // ── Public API ──

  Future<CanvasArtwork?> getBySongArtist(String song, String artist,
      {String? album}) async {
    final key =
        'song|${_norm(song)}|${_norm(artist)}|${album ?? ''}|$_storefront';
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(DateTime.now())) {
      return hit.value;
    }
    final result =
    await _searchAndFetch(_norm(song), _norm(artist), album, 'songs');
    // Cache ONLY genuine outcomes: a hit, or a real 200-search that
    // found no canvas. API/token failures are NOT cached — the next
    // song (or a retried one) must be able to succeed once the token
    // recovers.
    if (result.ok) {
      _cache[key] = _CacheEntry(result.art, DateTime.now().add(_ttl));
    }
    return result.art;
  }

  Future<CanvasArtwork?> getByAlbumArtist(String album, String artist) async {
    final key = 'album|${_norm(album)}|${_norm(artist)}|$_storefront';
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(DateTime.now())) {
      return hit.value;
    }
    final result =
    await _searchAndFetch(_norm(album), _norm(artist), album, 'albums');
    if (result.ok) {
      _cache[key] = _CacheEntry(result.art, DateTime.now().add(_ttl));
    }
    return result.art;
  }

  // ── Search + resolve (Echo's searchAndFetchMotion) ──

  /// (art, ok): ok=false means infrastructure failure (token/API) —
  /// never cached. ok=true + art=null means a genuine miss — cached.
  Future<({CanvasArtwork? art, bool ok})> _searchAndFetch(
      String term, String artist, String? album, String type) async {
    try {
      var query = term.toLowerCase().contains(artist.toLowerCase())
          ? term
          : '$artist $term';
      if (album != null &&
          album.isNotEmpty &&
          !query.toLowerCase().contains(album.toLowerCase())) {
        query = '$query $album';
      }
      print('AppleCanvas: searching $type "$query" ($_storefront)');

      final token = await _AppleTokenProvider.getToken();
      final uri = Uri.parse('$_ampBase/v1/catalog/$_storefront/search')
          .replace(queryParameters: {
        'term': query,
        'types': type,
        'limit': '10',
        'extend': 'editorialVideo',
        'include': 'albums',
      });
      final resp = await _client
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        // Token rejected — drop the cached token so the next attempt
        // re-scrapes instead of reusing the dead one.
        _AppleTokenProvider.invalidate();
        print('AppleCanvas: search rejected (${resp.statusCode}) — '
            'token invalidated for re-scrape');
        return (art: null, ok: false);
      }
      if (resp.statusCode != 200) {
        print('AppleCanvas: search failed ${resp.statusCode}');
        return (art: null, ok: false);
      }

      final root = jsonDecode(resp.body) as Map<String, dynamic>;
      final results =
      ((root['results'] as Map?)?[type] as Map?)?['data'] as List?;
      if (results == null || results.isEmpty) {
        return (art: null, ok: true);
      }

      // Score results, best first.
      final scored = <MapEntry<int, Map<String, dynamic>>>[];
      for (final item in results) {
        if (item is! Map) continue;
        final obj = Map<String, dynamic>.from(item);
        if (obj['attributes'] is! Map) continue;
        final attr = Map<String, dynamic>.from(obj['attributes'] as Map);
        final resultArtist = (attr['artistName'] ?? '') as String;
        final resultName = (attr['name'] ?? '') as String;
        final resultCollection = (attr['collectionName'] ?? '') as String;
        final score = _score(
          term: term,
          artist: artist,
          album: album,
          resultName: resultName,
          resultArtist: resultArtist,
          resultCollection: resultCollection,
        );
        if (score == -999) {
          print('AppleCanvas: skipping "$resultName" (blacklist/mismatch)');
          continue;
        }
        print('AppleCanvas: candidate "$resultName" score $score');
        scored.add(MapEntry(score, obj));
      }
      scored.sort((a, b) => b.key.compareTo(a.key));

      for (final entry in scored) {
        if (entry.key < 12) {
          print('AppleCanvas: stopping at low score ${entry.key}');
          break;
        }
        final obj = entry.value;
        final attributes = Map<String, dynamic>.from(obj['attributes'] as Map);
        final resultName = (attributes['name'] ?? '') as String;
        final resultArtist = (attributes['artistName'] ?? '') as String;
        final objType = (obj['type'] ?? '') as String;

        // 1. Resolve the album id.
        String? albumId;
        if (objType == 'songs') {
          final rel = obj['relationships'];
          final albumsData =
          (((rel is Map ? rel : null)?['albums'] as Map?)?['data'] as List?);
          if (albumsData != null && albumsData.isNotEmpty) {
            albumId = ((albumsData.first as Map)['id'] ?? '') as String;
          }
          albumId ??= attributes['collectionId'] as String?;
          // Fallback: parse from the item URL
          // (music.apple.com/region/album/name/ID?i=songId).
          if (albumId == null || albumId.isEmpty) {
            final url = attributes['url'] as String?;
            if (url != null) {
              final albumPart = _after(_before(url, '?'), '/album/');
              final id = albumPart.substring(albumPart.lastIndexOf('/') + 1);
              if (id.isNotEmpty && int.tryParse(id) != null) albumId = id;
            }
          }
        } else if (objType == 'albums') {
          albumId = obj['id'] as String?;
        }

        if (albumId == null || albumId.isEmpty || albumId.startsWith('pl.')) {
          print('AppleCanvas: skipping null/playlist albumId "$resultName"');
          continue;
        }

        // 2. Direct editorialVideo in the search result.
        final ev = attributes['editorialVideo'];
        if (ev is Map) {
          final hls = _extractVideoUrl(Map<String, dynamic>.from(ev));
          if (hls != null && hls.isNotEmpty) {
            final collName = (attributes['collectionName'] ?? '') as String;
            final resolvedAlbum = objType == 'songs' ? collName : resultName;
            print('AppleCanvas: direct editorialVideo for "$resultName"');
            return (
            art: CanvasArtwork(
              name: resultName,
              artist: resultArtist,
              albumId: albumId,
              albumName: resolvedAlbum,
              animated: hls,
            ),
            ok: true,
            );
          }
        }

        // 3. Full album lookup.
        final fetched = await _fetchAlbumMotion(
          albumId,
          fallbackArtist: resultArtist,
          titleOverride: objType == 'songs' ? resultName : null,
          artistOverride: objType == 'songs' ? resultArtist : null,
        );
        if (fetched != null) return (art: fetched, ok: true);
      }
      print(
          'AppleCanvas: no canvas for "$term" after ${scored.length} results');
      return (art: null, ok: true);
    } catch (e) {
      print('AppleCanvas: search error for "$term": $e');
      return (art: null, ok: false);
    }
  }

  // ── Album lookup (Echo's fetchMotionArtwork) ──

  Future<CanvasArtwork?> _fetchAlbumMotion(
      String albumId, {
        String? fallbackArtist,
        String? titleOverride,
        String? artistOverride,
      }) async {
    if (albumId.startsWith('pl.')) return null;
    try {
      print('AppleCanvas: fetching album $albumId');
      final token = await _AppleTokenProvider.getToken();
      final uri = Uri.parse('$_ampBase/v1/catalog/$_storefront/albums/$albumId')
          .replace(queryParameters: {
        'extend': 'editorialVideo',
        'include': 'tracks',
      });
      final resp = await _client
          .get(uri, headers: _headers(token))
          .timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) {
        print('AppleCanvas: album fetch failed $albumId (${resp.statusCode})');
        if (resp.statusCode == 401 || resp.statusCode == 403) {
          _AppleTokenProvider.invalidate();
        }
        return null;
      }
      final root = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = root['data'] as List?;
      if (data == null || data.isEmpty) return null;
      final albumObj = Map<String, dynamic>.from(data.first as Map);
      final attributes = albumObj['attributes'] is Map
          ? Map<String, dynamic>.from(albumObj['attributes'] as Map)
          : <String, dynamic>{};
      final albumName = (attributes['name'] ?? '') as String;
      final artistName =
          (attributes['artistName'] as String?) ?? fallbackArtist ?? '';

      final nameLower = albumName.toLowerCase();
      const blacklist = [
        'playlist', 'set list', 'essentials', 'dj mix', 'mixed',
        'apple music', "today's hits", 'session',
      ];
      for (final b in blacklist) {
        if (nameLower.contains(b)) {
          print('AppleCanvas: ignoring blacklisted album "$albumName"');
          return null;
        }
      }

      final finalTitle = titleOverride ?? albumName;
      final finalArtist = artistOverride ?? artistName;

      final ev = attributes['editorialVideo'];
      if (ev is Map) {
        final url = _extractVideoUrl(Map<String, dynamic>.from(ev));
        if (url != null && url.isNotEmpty) {
          print(
              'AppleCanvas: editorialVideo for "$finalTitle" (album "$albumName")');
          return CanvasArtwork(
            name: finalTitle,
            artist: finalArtist,
            albumId: albumId,
            albumName: albumName,
            animated: url,
          );
        }
      }
      print('AppleCanvas: no editorialVideo for $albumId');
      return null;
    } catch (e) {
      print('AppleCanvas: album fetch error $albumId: $e');
      return null;
    }
  }

  // ── Helpers ──

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
    'Origin': 'https://music.apple.com',
    'Referer': 'https://music.apple.com/',
    'User-Agent': _ua,
  };

  /// Echo's asset walk: raw → square → tall → static, trying
  /// video / videoUrl / hlsUrl / url keys.
  String? _extractVideoUrl(Map<String, dynamic> ev) {
    for (final key in [
      'motionDetailRaw',
      'motionDetailSquare',
      'motionDetailTall',
      'motionDetailStatic',
    ]) {
      final asset = ev[key];
      if (asset is! Map) continue;
      for (final vk in ['video', 'videoUrl', 'hlsUrl', 'url']) {
        final v = asset[vk];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    print('AppleCanvas: editorialVideo present but no video link');
    return null;
  }

  /// Echo's scoring. Returns -999 for rejected candidates.
  int _score({
    required String term,
    required String artist,
    required String? album,
    required String resultName,
    required String resultArtist,
    required String resultCollection,
  }) {
    final n = resultName.toLowerCase();
    final c = resultCollection.toLowerCase();
    const blacklist = [
      'playlist', 'set list', 'essentials', 'dj mix', 'mixed',
      'apple music', "today's hits", 'session',
    ];
    for (final b in blacklist) {
      if (n.contains(b) || c.contains(b)) return -999;
    }

    final a = artist.toLowerCase();
    final ra = resultArtist.toLowerCase();
    final artistMatch = ra == a;
    final artistFuzzy = ra.contains(a) || a.contains(ra);
    if (!artistFuzzy) return -999;

    var score = artistMatch ? 10 : 5;

    final t = term.toLowerCase();
    final nameMatch = n == t;
    final nameFuzzy = n.contains(t) || t.contains(n);
    if (nameMatch) {
      score += 15;
    } else if (nameFuzzy) {
      score += 7;
    } else {
      score -= 10;
    }

    const editionWords = [
      'deluxe', 'expanded', 'remastered', 'remix', 'version', 'edit', 'mix', 'bonus',
    ];
    for (final w in editionWords) {
      final inTerm = t.contains(w);
      final inResult = n.contains(w);
      if (inTerm && inResult) {
        score += 5;
      } else if (inTerm != inResult && inResult) {
        score -= 3;
      }
    }

    if (album != null && album.isNotEmpty && resultCollection.isNotEmpty) {
      final al = album.toLowerCase();
      final albumMatch = c == al;
      final albumFuzzy = c.contains(al) || al.contains(c);
      if (albumMatch) {
        score += 20;
      } else if (albumFuzzy) {
        score += 10;
      }
    }
    return score;
  }

  static String _norm(String s) => s.trim();

  static String _after(String s, String sep) {
    final i = s.indexOf(sep);
    return i < 0 ? '' : s.substring(i + sep.length);
  }

  static String _before(String s, String sep) {
    final i = s.indexOf(sep);
    return i < 0 ? s : s.substring(0, i);
  }

  void dispose() => _client.close();
}

class CanvasArtwork {
  final String name;
  final String artist;
  final String albumId;
  final String? albumName;

  /// HLS URL for the animated canvas.
  final String animated;

  const CanvasArtwork({
    required this.name,
    required this.artist,
    required this.albumId,
    this.albumName,
    required this.animated,
  });
}

/// 24h cache entry for canvas lookups.
class _CacheEntry {
  const _CacheEntry(this.value, this.expires);
  final CanvasArtwork? value;
  final DateTime expires;
}

/// Apple web-player JWT provider.
///
/// FORMAT MIGRATION (Oct 2026): the web player stopped using WebPlayKit
/// JWTs (kid "WebPlayKit", iss "AMPWebPlay") and moved to a rotating-kid
/// issuer ("LT2ZDZSXNQ" era, iss "5IKPP2IECQ") served via
/// amp-api-edge.music.apple.com. The scrape below matches BOTH header
/// shapes:
///   1. Legacy: {"alg":"ES256","typ":"JWT","kid":"WebPlayKit"}
///   2. Current: {"typ":"JWT","alg":"ES256","kid":"<rotating>"} —
///      anchored on the stable typ/alg/kid-key prefix, so future kid
///      rotations keep matching. Payload validated for an apple.com
///      root origin + future exp.
///
/// The manual override holds a fresh-format token (exp ~Dec 11 2026)
/// captured from the live web player — it takes precedence over
/// scraping while valid.
class _AppleTokenProvider {
  /// Manual override: a fresh JWT captured from beta.music.apple.com
  /// (DevTools → Network → amp-api → Authorization header). Expires
  /// ~Dec 11, 2026 — when it does, the validator drops it and the
  /// scrape strategies take over automatically.
  static String? _manualToken =
      'eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IkxUMlpEWlNYTlEifQ.eyJpc3MiOiI1SUtQUDJJRUNRIiwiaWF0IjoxNzkwODk0NTM2LCJleHAiOjE3OTY5NDI1MzYsInJvb3RfaHR0cHNfb3JpZ2luIjpbImFwcGxlLmNvbSJdfQ.KJTFfyPQziYsFmwsSChaikYjjlnSwgXlrH4Y9YkO8DgwSwQWakhXtEfMwXssA6gbhG69Mqigy3pofEH_7MQQAg';

  static String? _cached;
  static DateTime _scrapeBlockedUntil =
  DateTime.fromMillisecondsSinceEpoch(0);
  static final _client = http.Client();

  static const _hosts = [
    'https://beta.music.apple.com',
    'https://music.apple.com',
  ];

  /// Legacy WebPlayKit JWTs — fixed base64url header.
  static final RegExp _jwtLegacyRe = RegExp(
      r'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ\.eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+');

  /// Current (rotating-kid) JWTs — the header's typ/alg/kid-key prefix
  /// is stable across kid rotations:
  /// {"typ":"JWT","alg":"ES256","kid":"..."}
  static final RegExp _jwtEdgeRe = RegExp(
      r'eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6I[A-Za-z0-9\-_]+\.eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+');

  /// Any /assets/*.js script reference (src or href, quoted either way).
  static final RegExp _scriptRe =
  RegExp(r'''(?:src|href)=["']([^"']*?/assets/[^"']+?\.js)["']''');

  static Future<String> getToken() async {
    final manual = _validate(_manualToken);
    if (manual != null) return manual;

    if (_cached != null) {
      final still = _validate(_cached);
      if (still != null) return still;
      _cached = null; // expired (or expiring) — re-scrape
    }

    if (DateTime.now().isBefore(_scrapeBlockedUntil)) {
      throw Exception('token scrape backing off (recent failure)');
    }

    try {
      final token = await _scrape();
      _cached = token;
      print('AppleCanvas: token acquired (valid '
          '${_expiryOf(token) != null ? "until ${_expiryOf(token)}" : "— expiry unknown"})');
      return token;
    } catch (e) {
      _scrapeBlockedUntil =
          DateTime.now().add(const Duration(minutes: 10));
      rethrow;
    }
  }

  /// Called by the service on a 401/403 — the token looked valid but
  /// was rejected, so drop it and let the next attempt re-scrape.
  /// NOTE: with a valid manual token, a 401 here most likely means
  /// Apple requires the EDGE host for this issuer — flip _ampBase in
  /// AppleCanvasService to amp-api-edge.music.apple.com.
  static void invalidate() {
    _cached = null;
  }

  static Future<String> _scrape() async {
    for (final host in _hosts) {
      String? html;
      try {
        final resp = await _client
            .get(Uri.parse(host))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) html = resp.body;
      } catch (_) {}

      if (html == null) continue;

      // 1. Token embedded in the HTML itself (either format).
      final direct = _validate(_findJwt(html));
      if (direct != null) return direct;

      // 2. Enumerate asset bundles from this page.
      final scripts = <String>[];
      for (final m in _scriptRe.allMatches(html)) {
        final raw = m.group(1)!;
        scripts.add(raw.startsWith('http') ? raw : '$host$raw');
      }
      scripts.sort((a, b) {
        final ai = a.contains('index') ? 0 : 1;
        final bi = b.contains('index') ? 0 : 1;
        return ai.compareTo(bi);
      });

      var fetched = 0;
      for (final url in scripts) {
        if (fetched >= 8) break;
        fetched++;
        try {
          final js = await _client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          final t = _validate(_findJwt(js.body));
          if (t != null) return t;
        } catch (_) {}
      }
    }
    throw Exception(
        'no Apple Music JWT found on any web player host '
            '(legacy + edge patterns tried)');
  }

  static String? _findJwt(String body) {
    return _jwtEdgeRe.firstMatch(body)?.group(0) ??
        _jwtLegacyRe.firstMatch(body)?.group(0);
  }

  /// Returns [jwt] only if it is plausibly valid for another 24h AND
  /// (for the edge format) carries an apple.com root origin. Unparseable
  /// expiry → accepted; a 401 invalidates it at runtime.
  static String? _validate(String? jwt) {
    if (jwt == null || jwt.isEmpty) return null;
    // Sanity: the payload must reference apple.com (both eras do).
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final map = jsonDecode(utf8.decode(base64.decode(payload))) as Map;
      final origins = map['root_https_origin'];
      if (origins is! List || !origins.contains('apple.com')) {
        return null;
      }
    } catch (_) {
      return null;
    }
    final exp = _expiryOf(jwt);
    if (exp != null &&
        exp.isBefore(DateTime.now().add(const Duration(hours: 24)))) {
      return null;
    }
    return jwt;
  }

  static DateTime? _expiryOf(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final json = utf8.decode(base64.decode(payload));
      final exp = (jsonDecode(json) as Map)['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      }
    } catch (_) {}
    return null;
  }
}