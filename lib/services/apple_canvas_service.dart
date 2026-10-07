import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Apple Music animated artwork (canvas) provider — Dart port of Echo's
/// AppleMusicCanvasProvider + AppleMusicTokenProvider.
///
/// Strategy: AMP catalog search → per-result scoring (Echo's algorithm:
/// playlist blacklisting, strict artist match, name/album/edition
/// scoring) → `editorialVideo` HLS extraction (direct in the search
/// result, or via the full album lookup). Results cached 24h.
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
    final value =
    await _searchAndFetch(_norm(song), _norm(artist), album, 'songs');
    _cache[key] = _CacheEntry(value, DateTime.now().add(_ttl));
    return value;
  }

  Future<CanvasArtwork?> getByAlbumArtist(String album, String artist) async {
    final key = 'album|${_norm(album)}|${_norm(artist)}|$_storefront';
    final hit = _cache[key];
    if (hit != null && hit.expires.isAfter(DateTime.now())) {
      return hit.value;
    }
    final value =
    await _searchAndFetch(_norm(album), _norm(artist), album, 'albums');
    _cache[key] = _CacheEntry(value, DateTime.now().add(_ttl));
    return value;
  }

  // ── Search + resolve (Echo's searchAndFetchMotion) ──

  Future<CanvasArtwork?> _searchAndFetch(
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
      if (resp.statusCode != 200) {
        print('AppleCanvas: search failed ${resp.statusCode}');
        return null;
      }

      final root = jsonDecode(resp.body) as Map<String, dynamic>;
      final results =
      ((root['results'] as Map?)?[type] as Map?)?['data'] as List?;
      if (results == null || results.isEmpty) return null;

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
          // (zen.apple.com/region/album/name/ID?i=songId).
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
            return CanvasArtwork(
              name: resultName,
              artist: resultArtist,
              albumId: albumId,
              albumName: resolvedAlbum,
              animated: hls,
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
        if (fetched != null) return fetched;
      }
      print('AppleCanvas: no canvas for "$term" after ${scored.length} results');
      return null;
    } catch (e) {
      print('AppleCanvas: search error for "$term": $e');
      return null;
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
        'apple zen', "today's hits", 'session',
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
    'Origin': 'https://zen.apple.com',
    'Referer': 'https://zen.apple.com/',
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
      'apple zen', "today's hits", 'session',
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

/// Echo's AppleMusicTokenProvider: scrapes the web player's index.js for
/// the public unauthenticated JWT, caches it, falls back to a pinned
/// token on failure.
class _AppleTokenProvider {
  static String? _cached;
  static final _client = http.Client();

  static const _fallback =
      'eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ.eyJpc3MiOiJBTVBXZWJQbGF5IiwiaWF0IjoxNzc0NDU2MzgyLCJleHAiOjE3ODE3MTM5ODIsInJvb3RfaHR0cHNfb3JpZ2luIjpbImFwcGxlLmNvbSJdfQ.4n8qYF4qa18sL1E0G9A3qX35cD8wQ-IJcS9Bh8ZT8JV_yLBtVq46B-9-2ZS3EvWHuw3yK9BYFYAhAdTaDm38vQ';

  static Future<String> getToken() async {
    if (_cached != null) return _cached!;
    try {
      final html = await _client
          .get(Uri.parse('https://beta.music.apple.com'))
          .timeout(const Duration(seconds: 15));
      final m =
      RegExp(r'src="(/assets/index-[^"]+\.js)"').firstMatch(html.body);
      if (m == null) throw Exception('index.js not found');
      final js = await _client
          .get(Uri.parse('https://beta.music.apple.com${m.group(1)}'))
          .timeout(const Duration(seconds: 15));
      final tm = RegExp(
          r'eyJ[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+')
          .firstMatch(js.body);
      if (tm == null) throw Exception('token not found');
      _cached = tm.group(0)!;
      print('AppleCanvas: token acquired');
      return _cached!;
    } catch (e) {
      print('AppleCanvas: token scrape failed, using pinned fallback ($e)');
      return _fallback;
    }
  }
}