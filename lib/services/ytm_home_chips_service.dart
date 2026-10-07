import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import 'innertubex_bridge.dart';
import '../utilities/format_utils.dart';

typedef _JsonMap = Map<String, dynamic>;

/// One home-filter chip ("Energy", "Chill", "Workout"…).
class YtmHomeChip {
  const YtmHomeChip({required this.title, required this.params});

  final String title;
  final String params;
}

/// Standalone YouTube Music home-chips client (InnerTube).
///
/// VERIFIED ON DEVICE (census + dump): chip responses carry songs as
/// musicMultiRowListItemRenderer (~23 items, each with a menu of ~3
/// items = ~69 menu renderers). The playable videoId is NOT on the
/// item's navigationEndpoint (browseEndpoint only) and the overlay is
/// NOT at the assumed direct path. The reliable extraction: deep-scan
/// the WHOLE response for musicPlayButtonRenderer nodes (each has
/// playNavigationEndpoint → watchEndpoint → videoId) and pair with
/// musicMultiRowListItemRenderer titles by order (counts match 1:1).
///
/// STATUS: DORMANT — the chips UI was rolled back; this client is
/// kept for a future revival. Titles are format-cleaned via
/// formatSongTitle at both song-creation points.
class YtmHomeChipsService {
  static const _base = 'https://music.youtube.com/youtubei/v1';
  static const _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  static const _clientDefaults = {
    'clientName': 'WEB_REMIX',
    'clientVersion': '1.20240101.01.00',
    'hl': 'en',
  };

  final _client = http.Client();

  String? _visitorData;

  /// Builds a CORRECT InnerTube body (context single-nested).
  Future<_JsonMap?> _post(String endpoint, _JsonMap body) async {
    try {
      _visitorData ??= await InnertubexBridge.getVisitorData();

      final client = Map<String, dynamic>.from(_clientDefaults);
      if (_visitorData != null) client['visitorData'] = _visitorData;

      final fullBody = {
        ...body,
        'context': {
          'client': client,
        },
      };

      final uri = Uri.parse('$_base/$endpoint?key=$_apiKey&prettyPrint=false');
      final resp = await _client
          .post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(fullBody),
      )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        print('🎛 Chips: $endpoint status ${resp.statusCode}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      print('🎛 Chips: $endpoint request failed — $e');
      return null;
    }
  }

  /// The home filter chips (WEB_REMIX home browse → chipCloudChipRenderer).
  Future<List<YtmHomeChip>> getChips() async {
    final root = await _post('browse', {
      'browseId': 'FEmusic_home',
    });
    if (root == null) return [];

    final chips = <YtmHomeChip>[];
    for (final c in findRenderers(root, 'chipCloudChipRenderer')) {
      final title =
          c.getValue<String>('simpleText') ?? runsText(c.getMap('text')) ?? '';
      if (title.isEmpty || title.toLowerCase() == 'all') continue;
      final params = c.getValue<String>('params') ??
          c
              .getMap('navigationEndpoint')
              ?.getMap('browseEndpoint')
              ?.getValue<String>('params') ??
          '';
      if (chips.any((x) => x.title == title)) continue;
      chips.add(YtmHomeChip(title: title, params: params));
      if (chips.length >= 20) break;
    }
    print('🎛 Chips: ${chips.length} chips fetched');
    return chips;
  }

  /// Songs for a selected chip. STRATEGY: deep-scan the ENTIRE response
  /// for musicPlayButtonRenderer nodes → extract videoIds from
  /// playNavigationEndpoint → watchEndpoint → videoId. Pair with
  /// musicMultiRowListItemRenderer titles/thumbnails by order (counts
  /// match 1:1 on device). Falls back to title-only songs if the
  /// play-button count doesn't match.
  Future<List<Song>> getChipSongs(String params, {int limit = 25}) async {
    final root = await _post('browse', {
      'browseId': 'FEmusic_home',
      if (params.isNotEmpty) 'params': params,
    });
    if (root == null) {
      print('🎛 Chips: browse failed for params=$params');
      return [];
    }

    // 1. All play-button videoIds, anywhere in the tree.
    final videoIds = <String>[];
    for (final pb in findRenderers(root, 'musicPlayButtonRenderer')) {
      final vid = pb
          .getMap('playNavigationEndpoint')
          ?.getMap('watchEndpoint')
          ?.getValue<String>('videoId');
      if (vid != null && vid.isNotEmpty && videoIds.length < limit) {
        videoIds.add(vid);
      }
    }

    // 2. All multi-row items — titles + thumbnails.
    final items = <_JsonMap>[];
    for (final item in findRenderers(root, 'musicMultiRowListItemRenderer')) {
      items.add(item);
      if (items.length >= limit) break;
    }

    // 3. Also scan shelf rows (some chips use this layout).
    final rowItems = <_JsonMap>[];
    final rowIds = <String>[];
    for (final item
    in findRenderers(root, 'musicResponsiveListItemRenderer')) {
      final vid = item
          .getMap('overlay')
          ?.getMap('musicItemThumbnailOverlayRenderer')
          ?.getMap('content')
          ?.getMap('musicPlayButtonRenderer')
          ?.getMap('playNavigationEndpoint')
          ?.getMap('watchEndpoint')
          ?.getValue<String>('videoId') ??
          item
              .getMap('navigationEndpoint')
              ?.getMap('watchEndpoint')
              ?.getValue<String>('videoId');
      if (vid == null || vid.isEmpty) continue;
      rowItems.add(item);
      rowIds.add(vid);
      if (rowItems.length >= limit) break;
    }

    // 4. Build songs — pair play-button videoIds with item titles.
    final songs = <Song>[];
    final seen = <String>{};

    if (videoIds.length >= items.length && items.isNotEmpty) {
      // Play-button count ≥ item count — pair by order.
      for (var i = 0; i < items.length && songs.length < limit; i++) {
        final vid = videoIds[i];
        if (!seen.add(vid)) continue;
        final item = items[i];
        final title = runsText(item.getMap('title'))?.trim() ?? '';
        if (title.isEmpty) continue;
        final subtitle = runsText(item.getMap('subtitle')) ?? 'Unknown';
        final artist = subtitle.split('•').first.trim();
        final art = _bestThumbFrom(
          item
              .getMap('thumbnailRenderer')
              ?.getMap('musicThumbnailRenderer')
              ?.getMap('thumbnail'),
        ) ??
            _bestThumbFrom(
              item
                  .getMap('thumbnail')
                  ?.getMap('musicThumbnailRenderer')
                  ?.getMap('thumbnail'),
            ) ??
            '';
        songs.add(Song(
          id: vid,
          title: formatSongTitle(title),
          artist: artist.isNotEmpty ? artist : 'Unknown',
          thumbnail: art.isNotEmpty
              ? art
              : 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
          duration: Duration.zero,
        ));
      }
      print('🎛 Chips: ${items.length} items + ${videoIds.length} play '
          'buttons → ${songs.length} songs (paired)');
    }

    // 5. Shelf-row layout fallback.
    if (songs.isEmpty && rowItems.isNotEmpty) {
      for (var i = 0; i < rowItems.length && songs.length < limit; i++) {
        final vid = rowIds[i];
        if (!seen.add(vid)) continue;
        final song = _songFromRow(rowItems[i], vid);
        if (song != null) songs.add(song);
      }
      if (songs.isNotEmpty) {
        print('🎛 Chips: ${rowItems.length} shelf rows → ${songs.length} songs');
      }
    }

    // 6. Last resort: videoIds without titles (bare-bones songs).
    if (songs.isEmpty && videoIds.isNotEmpty) {
      for (final vid in videoIds) {
        if (!seen.add(vid)) continue;
        songs.add(Song(
          id: vid,
          title: 'Chip song',
          artist: 'YouTube Music',
          thumbnail: 'https://i.ytimg.com/vi/$vid/hqdefault.jpg',
          duration: Duration.zero,
        ));
      }
      if (songs.isNotEmpty) {
        print('🎛 Chips: ${videoIds.length} bare play buttons → '
            '${songs.length} songs (no titles)');
      }
    }

    if (songs.isEmpty) {
      final counts = <String, int>{};
      _countRenderers(root, counts);
      final top = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      print('🎛 Chips: response renderers — '
          '${top.take(10).map((e) => "${e.key}:${e.value}").join(", ")}');
    } else {
      print('🎛 Chips: ${songs.length} songs for '
          'params=${params.isEmpty ? "(none)" : params}');
    }
    return songs;
  }

  void _countRenderers(dynamic node, Map<String, int> counts) {
    if (node is Map) {
      for (final key in node.keys) {
        final v = node[key];
        if (v is Map && key.toString().endsWith('Renderer')) {
          counts[key.toString()] = (counts[key.toString()] ?? 0) + 1;
        }
        _countRenderers(v, counts);
      }
    } else if (node is List) {
      for (final v in node) {
        _countRenderers(v, counts);
      }
    }
  }

  // ── row → Song (verbatim from the shared service) ──

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
      title: formatSongTitle(title),
      artist: artist,
      thumbnail: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      duration: _parseDuration(fixedColumnText(item)) ?? Duration.zero,
    );
  }

  /// Picks the highest-resolution thumbnail URL from a node holding a
  /// `thumbnails` list. Protocol-relative URLs upgraded to https.
  String? _bestThumbFrom(_JsonMap? container) {
    final thumbs = container?.getList('thumbnails');
    if (thumbs == null || thumbs.isEmpty) return null;
    Map? best;
    var bestW = -1;
    for (final t in thumbs) {
      if (t is! Map) continue;
      final w = (t['width'] as num?)?.toInt() ?? 0;
      if (w >= bestW) {
        bestW = w;
        best = t;
      }
    }
    final url = best?['url']?.toString();
    if (url == null || url.isEmpty) return null;
    return url.startsWith('//') ? 'https:$url' : url;
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

  // ── generic deep-JSON traversal (verbatim from the shared service) ──

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
}

// Deep-JSON read helpers — every standalone service file carries its
// own private copy of this extension (library-private by design).
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