import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

typedef _JsonMap = Map<String, dynamic>;

class YtMusicService {
  static const _base = 'https://music.youtube.com/youtubei/v1';
  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  final _client = http.Client();

  static const _context = {
    'context': {
      'client': {
        'clientName': 'WEB_REMIX',
        'clientVersion': '1.20240101.01.00',
        'hl': 'en',
      },
    },
  };

  // Search filter params (WEB_REMIX): songs shelf / artists only.
  static const _songsFilter = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';
  static const _artistsFilter = 'EgWKAQIgAWoMEA4QChADEAQQCRAF';

  /// Set when the last InnerTube response was rate-limited (429).
  static bool lastSearchRateLimited = false;

  Future<_JsonMap?> _post(String endpoint, _JsonMap body) async {
    try {
      final uri = Uri.parse('$_base/$endpoint?key=$_apiKey&prettyPrint=false');
      final resp = await _client
          .post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(body),
      )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 429) {
        lastSearchRateLimited = true;
        return null;
      }
      if (resp.statusCode != 200) {
        print('YtMusic.$endpoint: status ${resp.statusCode}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      print('YtMusic.$endpoint failed: $e');
      return null;
    }
  }

  /// Songs-shelf search — real track rows from YouTube Music.
  Future<List<Song>> searchSongs(String query, {int limit = 20}) async {
    lastSearchRateLimited = false;
    final root = await _post('search', {
      ..._context,
      'query': query.trim(),
      'params': _songsFilter,
    });
    if (root == null) return [];

    final songs = <Song>[];
    final seen = <String>{};
    for (final item
    in findRenderers(root, 'musicResponsiveListItemRenderer')) {
      final videoId = _videoIdOf(item);
      if (videoId == null || !seen.add(videoId)) continue;
      final song = _songFromRow(item, videoId);
      if (song != null) songs.add(song);
      if (songs.length >= limit) break;
    }
    return songs;
  }

  /// Canonical artist channel ids (UC...) matching a name.
  Future<List<String>> searchArtistIds(String query, {int limit = 3}) async {
    lastSearchRateLimited = false;
    final root = await _post('search', {
      ..._context,
      'query': query.trim(),
      'params': _artistsFilter,
    });
    if (root == null) return [];

    final ids = <String>[];
    for (final item
    in findRenderers(root, 'musicResponsiveListItemRenderer')) {
      final id = item
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint')
          ?.getValue<String>('browseId');
      if (id == null || !id.startsWith('UC')) continue;
      final pageType = item
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint')
          ?.getMap('browseEndpointContextSupportedConfigs')
          ?.getMap('browseEndpointContextMusicConfig')
          ?.getValue<String>('pageType');
      if (pageType != 'MUSIC_PAGE_TYPE_ARTIST') continue;
      if (!ids.contains(id)) ids.add(id);
      if (ids.length >= limit) break;
    }
    return ids;
  }

  /// The artist page "Top songs" shelf — real, YouTube-ranked hits.
  Future<List<Song>> getArtistTopSongs(String channelId,
      {int limit = 10}) async {
    final root = await _post('browse', {
      ..._context,
      'browseId': channelId,
    });
    if (root == null) return [];

    final shelf = firstRenderer(root, 'musicShelfRenderer');
    if (shelf == null) return [];

    final songs = <Song>[];
    final seen = <String>{};
    for (final item
    in findRenderers(shelf, 'musicResponsiveListItemRenderer')) {
      final videoId = _videoIdOf(item);
      if (videoId == null || !seen.add(videoId)) continue;
      final song = _songFromRow(item, videoId);
      if (song != null) songs.add(song);
      if (songs.length >= limit) break;
    }
    return songs;
  }

  /// Best single-track match for a query, validated loosely against the
  /// expected artist/title. Used by the Spotify CSV import.
  Future<Song?> searchSongMatch(
      String query, {
        String? expectedArtist,
        String? expectedTitle,
      }) async {
    lastSearchRateLimited = false;
    final root = await _post('search', {
      ..._context,
      'query': query.trim(),
      'params': _songsFilter,
    });
    if (root == null) return null;

    for (final item
    in findRenderers(root, 'musicResponsiveListItemRenderer')) {
      final videoId = _videoIdOf(item);
      if (videoId == null) continue;

      final song = _songFromRow(item, videoId);
      if (song == null) continue;

      final subtitle = flexColumnText(item, 1) ?? '';
      final parts = subtitle
          .split('•')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
      final artist = parts.isNotEmpty ? parts.first : '';

      if (_looselyMatches(artist, expectedArtist) &&
          _looselyMatches(song.title, expectedTitle)) {
        return song;
      }
    }
    return null;
  }

  bool _looselyMatches(String candidate, String? expected) {
    if (expected == null || expected.trim().isEmpty) return true;
    Set<String> words(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    final a = words(candidate);
    final b = words(expected);
    if (a.isEmpty || b.isEmpty) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = identical(shorter, a) ? b : a;
    return shorter.every(longer.contains);
  }

  // ── row → Song ──

  Song? _songFromRow(_JsonMap item, String videoId) {
    final title = flexColumnText(item, 0)?.trim();
    if (title == null || title.isEmpty) return null;

    final subtitle = flexColumnText(item, 1) ?? '';
    final parts = subtitle
        .split('•')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final artist = parts.isNotEmpty ? parts.first : 'Unknown';

    return Song(
      id: videoId,
      title: title,
      artist: artist,
      thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      duration: _parseDuration(fixedColumnText(item)) ?? Duration.zero,
    );
  }

  String? _videoIdOf(_JsonMap item) {
    // Primary: play-button overlay path.
    final overlay = item
        .getMap('overlay')
        ?.getMap('musicItemThumbnailOverlayRenderer')
        ?.getMap('content')
        ?.getMap('musicPlayButtonRenderer')
        ?.getMap('playNavigationEndpoint')
        ?.getMap('watchEndpoint')
        ?.getValue<String>('videoId');
    if (overlay != null) return overlay;
    // Fallback: row navigation endpoint.
    return item
        .getMap('navigationEndpoint')
        ?.getMap('watchEndpoint')
        ?.getValue<String>('videoId');
  }

  Duration? _parseDuration(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    var seconds = 0;
    for (final part in parts) {
      final n = int.tryParse(part.trim());
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return Duration(seconds: seconds);
  }

  // ── generic deep-JSON traversal ──

  String? flexColumnText(_JsonMap item, int index) {
    final columns = item.getList('flexColumns');
    if (columns == null || columns.length <= index) return null;
    final column = columns[index];
    if (column is! Map) return null;
    return runsText((_JsonMap.from(column))
        .getMap('musicResponsiveListItemFlexColumnRenderer')
        ?.getMap('text'));
  }

  String? fixedColumnText(_JsonMap item) {
    final columns = item.getList('fixedColumns');
    if (columns == null || columns.isEmpty) return null;
    final last = columns.last;
    if (last is! Map) return null;
    return runsText((_JsonMap.from(last))
        .getMap('musicResponsiveListItemFixedColumnRenderer')
        ?.getMap('text'));
  }

  String? runsText(_JsonMap? node) {
    final runs = node?.getList('runs');
    if (runs == null || runs.isEmpty) return null;
    return runs
        .map((r) => r is Map ? (r['text']?.toString() ?? '') : '')
        .join();
  }

  Iterable<_JsonMap> findRenderers(dynamic node, String key) sync* {
    if (node is Map) {
      final match = node[key];
      if (match is Map) yield _JsonMap.from(match);
      for (final value in node.values) {
        yield* findRenderers(value, key);
      }
    } else if (node is List) {
      for (final value in node) {
        yield* findRenderers(value, key);
      }
    }
  }

  _JsonMap? firstRenderer(dynamic node, String key) {
    for (final r in findRenderers(node, key)) {
      return r;
    }
    return null;
  }
}

extension _Read on _JsonMap {
  _JsonMap? getMap(String key) {
    final v = this[key];
    return v is Map ? _JsonMap.from(v) : null;
  }

  List<dynamic>? getList(String key) {
    final v = this[key];
    return v is List ? v : null;
  }

  T? getValue<T>(String key) {
    final v = this[key];
    return v is T ? v : null;
  }
}