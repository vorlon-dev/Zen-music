import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

typedef _JsonMap = Map<String, dynamic>;

/// Artist-page header data (from the artist/channel browse response).
class YtmArtistHeader {
  final String name;
  final String imageUrl;
  final String? description;
  final String? subscriberCount;
  final String? monthlyListeners;

  const YtmArtistHeader({
    required this.name,
    required this.imageUrl,
    this.description,
    this.subscriberCount,
    this.monthlyListeners,
  });
}

/// One album/EP/single card from an artist-page carousel shelf.
class YtmAlbumCard {
  final String browseId;
  final String title;
  final String subtitle;
  final String imageUrl;

  const YtmAlbumCard({
    required this.browseId,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });
}

/// Full artist/channel page: header info, top songs (or, for plain
/// YouTube channels, the channel's videos) and album-style shelves.
class YtmArtistPage {
  final YtmArtistHeader? header;
  final List<Song> topSongs;
  final List<({String title, List<YtmAlbumCard> albums})> shelves;

  const YtmArtistPage({
    required this.header,
    required this.topSongs,
    required this.shelves,
  });
}

/// Self-contained YouTube Music artist/channel-page client. Deliberately
/// independent of YtMusicService: owns its own InnerTube plumbing and
/// row parsers (copied verbatim from the verified shared service) so
/// artist-page parsing never destabilizes search. Do not merge the two
/// files — the isolation is the point.
class YtmArtistService {
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

  // Artists-only search filter (WEB_REMIX).
  static const _artistsFilter = 'EgWKAQIgAWoMEA4QChADEAQQCRAF';

  /// InnerTube browse params for a channel's VIDEOS tab (well-known
  /// constant across the InnerTube ecosystem). Only requested when the
  /// home tab yields no listings.
  static const _channelVideosTabParams = 'EgZ2aWRlb3PyBgQKAjoA';

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
        print('YtmArtist.$endpoint: status ${resp.statusCode}');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      print('YtmArtist.$endpoint failed: $e');
      return null;
    }
  }

  /// EXACT channel resolution: YouTube's public oEmbed endpoint returns
  /// author_url = https://www.youtube.com/channel/UC… for the channel
  /// that OWNS [videoId]. No fuzzy matching is involved — this is the
  /// uploader's real channel id, or null when it cannot be determined
  /// (caller then falls back to a name search).
  Future<String?> resolveVideoChannel(String videoId) async {
    try {
      final uri = Uri.https('www.youtube.com', '/oembed', {
        'url': 'https://www.youtube.com/watch?v=$videoId',
        'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return null;
      final authorUrl = decoded['author_url']?.toString() ?? '';
      final m = RegExp(r'channel/(UC[A-Za-z0-9_-]{22})').firstMatch(authorUrl);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Canonical artist channel ids (UC...) matching a name. FUZZY —
  /// used only as a fallback when no exact video→channel resolution
  /// is possible.
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

  /// Full artist OR plain-channel page. Strategy:
  ///   1. Home-tab browse (ONE call) — header, zen shelves, and any
  ///      videos the home layout carries.
  ///   2. Only when [videosTab] is set AND nothing was found, a second
  ///      browse requests the channel's Videos tab explicitly.
  Future<YtmArtistPage?> getArtistPage(String channelId,
      {bool videosTab = false}) async {
    final root = await _post('browse', {
      ..._context,
      'browseId': channelId,
    });
    if (root == null) return null;

    final header = _parseArtistHeader(root);
    var topSongs = _parseShelfSongs(root, limit: 25);
    if (topSongs.isEmpty) {
      // Not a YT Music artist page (no zen shelf) — try the plain
      // YouTube-channel shapes in this same response.
      topSongs = _scanChannelVideos(root, header?.name ?? '');
    }

    // Plain channel and the home tab listed nothing — pull the Videos
    // tab explicitly (second request only in this case).
    if (videosTab && topSongs.isEmpty) {
      final vids = await _post('browse', {
        ..._context,
        'browseId': channelId,
        'params': _channelVideosTabParams,
      });
      if (vids != null) {
        final scanned = _scanChannelVideos(vids, header?.name ?? '');
        if (scanned.isNotEmpty) topSongs = scanned;
      }
    }

    return YtmArtistPage(
      header: header,
      topSongs: topSongs,
      shelves: _parseAlbumShelves(root),
    );
  }

  /// Album page → its track list (browseId is the MPREb_... album id).
  Future<List<Song>> getAlbumTracks(String albumBrowseId) async {
    final root = await _post('browse', {
      ..._context,
      'browseId': albumBrowseId,
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
    }
    return songs;
  }

  // ── header parsing (defensive: missing fields come back null) ──

  YtmArtistHeader? _parseArtistHeader(_JsonMap root) {
    // Shapes 1 & 2: YT Music artist headers.
    final header = firstRenderer(root, 'musicImmersiveHeaderRenderer') ??
        firstRenderer(root, 'musicDetailHeaderRenderer');
    if (header != null) {
      final parsed = _headerFromMusicHeader(root, header);
      if (parsed != null) return parsed;
    }

    // Shape 3: plain YouTube channel (c4TabbedHeaderRenderer).
    final c4 = firstRenderer(root, 'c4TabbedHeaderRenderer');
    if (c4 != null) {
      final name =
          _textOf(c4.getMap('title')) ?? c4.getValue<String>('title') ?? '';
      if (name.isNotEmpty) {
        final art = _bestThumbFrom(c4.getMap('avatar')) ??
            _bestThumbFrom(
              c4.getMap('avatar')?.getMap('thumbnails'),
            ) ??
            '';
        return YtmArtistHeader(name: name, imageUrl: art);
      }
    }

    // Shape 4 (last-ditch): microformatDataRenderer.
    final micro = firstRenderer(root, 'microformatDataRenderer');
    if (micro != null) {
      final name = micro.getValue<String>('title') ??
          _textOf(micro.getMap('title')) ??
          '';
      if (name.isNotEmpty) {
        final art = _bestThumbFrom(micro.getMap('thumbnail')) ?? '';
        return YtmArtistHeader(name: name, imageUrl: art);
      }
    }
    return null;
  }

  YtmArtistHeader? _headerFromMusicHeader(_JsonMap root, _JsonMap header) {
    final name = runsText(header.getMap('title')) ?? '';
    if (name.isEmpty) return null;

    // Artwork: thumbnail.musicThumbnailRenderer.thumbnail.thumbnails,
    // with a direct thumbnail.thumbnails fallback.
    final art = _bestThumbFrom(
      header
          .getMap('thumbnail')
          ?.getMap('musicThumbnailRenderer')
          ?.getMap('thumbnail'),
    ) ??
        _bestThumbFrom(header.getMap('thumbnail')) ??
        '';

    final description = runsText(header.getMap('description'));

    // Subscriber count — scan the whole response for the subscribe
    // button (robust against header-shape changes).
    String? subscriberCount;
    for (final sub in findRenderers(root, 'subscribeButtonRenderer')) {
      final t = runsText(sub.getMap('subscriberCountText'));
      if (t != null && t.trim().isNotEmpty) {
        subscriberCount =
            t.replaceAll(RegExp(r'subscribers?', caseSensitive: false), '')
                .trim();
        break;
      }
    }

    // Monthly listeners — deep-scan the header for the phrase; the
    // number may ride in the same run or an adjacent one.
    String? monthlyListeners;
    final texts = <String>[];
    void collectRuns(dynamic node) {
      if (node is Map) {
        final runs = node['runs'];
        if (runs is List) {
          final joined = runs
              .map((r) => r is Map ? (r['text']?.toString() ?? '') : '')
              .join();
          if (joined.isNotEmpty) texts.add(joined);
        }
        for (final v in node.values) {
          collectRuns(v);
        }
      } else if (node is List) {
        for (final v in node) {
          collectRuns(v);
        }
      }
    }

    collectRuns(header);
    for (final t in texts) {
      final m = RegExp(r'([\d.,]+\s*[KMB]?)\s*monthly listeners',
          caseSensitive: false)
          .firstMatch(t);
      if (m != null) {
        monthlyListeners = m.group(1)?.trim();
        break;
      }
    }

    return YtmArtistHeader(
      name: name,
      imageUrl: art,
      description: (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : null,
      subscriberCount:
      (subscriberCount != null && subscriberCount.isNotEmpty)
          ? subscriberCount
          : null,
      monthlyListeners:
      (monthlyListeners != null && monthlyListeners.isNotEmpty)
          ? monthlyListeners
          : null,
    );
  }

  /// Scans a browse response for video items in either layout (rich
  /// grid → videoRenderer, older grid → gridVideoRenderer) and maps
  /// them to Songs. [channelName] fills the artist field.
  List<Song> _scanChannelVideos(_JsonMap root, String channelName) {
    final songs = <Song>[];
    final seen = <String>{};

    void collect(String rendererKey) {
      for (final v in findRenderers(root, rendererKey)) {
        final id = v.getValue<String>('videoId');
        if (id == null || id.isEmpty || !seen.add(id)) continue;
        final title = _textOf(v.getMap('title'));
        if (title == null || title.isEmpty) continue;
        songs.add(Song(
          id: id,
          title: title,
          artist: channelName.isNotEmpty ? channelName : 'Unknown',
          thumbnail: _bestThumbFrom(v.getMap('thumbnail')) ??
              'https://i.ytimg.com/vi/$id/hqdefault.jpg',
          duration:
          _parseDuration(_textOf(v.getMap('lengthText'))) ??
              Duration.zero,
        ));
      }
    }

    collect('videoRenderer');
    collect('gridVideoRenderer');
    return songs;
  }

  List<Song> _parseShelfSongs(_JsonMap root, {int limit = 25}) {
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

  List<({String title, List<YtmAlbumCard> albums})> _parseAlbumShelves(
      _JsonMap root) {
    final out = <({String title, List<YtmAlbumCard> albums})>[];
    for (final carousel in findRenderers(root, 'musicCarouselShelfRenderer')) {
      final title = (runsText(carousel
          .getMap('header')
          ?.getMap('musicCarouselShelfBasicHeaderRenderer')
          ?.getMap('title')) ??
          '')
          .trim();
      final normalized = title.toLowerCase();
      if (normalized != 'albums' &&
          normalized != 'singles' &&
          normalized != 'eps') {
        continue;
      }

      final cards = <YtmAlbumCard>[];
      final seen = <String>{};
      for (final raw in carousel.getList('contents') ?? []) {
        if (raw is! Map) continue;
        final two = _JsonMap.from(raw).getMap('musicTwoRowItemRenderer');
        if (two == null) continue;

        final browseId = two
            .getMap('navigationEndpoint')
            ?.getMap('browseEndpoint')
            ?.getValue<String>('browseId');
        if (browseId == null || !browseId.startsWith('MPRE')) continue;
        final pageType = two
            .getMap('navigationEndpoint')
            ?.getMap('browseEndpoint')
            ?.getMap('browseEndpointContextSupportedConfigs')
            ?.getMap('browseEndpointContextMusicConfig')
            ?.getValue<String>('pageType');
        if (pageType != null && pageType != 'MUSIC_PAGE_TYPE_ALBUM') continue;
        if (!seen.add(browseId)) continue;

        final cardTitle = runsText(two.getMap('title')) ?? '';
        if (cardTitle.isEmpty) continue;
        final subtitle = runsText(two.getMap('subtitle')) ?? '';
        final art = _bestThumbFrom(
          two
              .getMap('thumbnailRenderer')
              ?.getMap('musicThumbnailRenderer')
              ?.getMap('thumbnail'),
        ) ??
            _bestThumbFrom(
              two
                  .getMap('thumbnail')
                  ?.getMap('musicThumbnailRenderer')
                  ?.getMap('thumbnail'),
            ) ??
            '';

        cards.add(YtmAlbumCard(
          browseId: browseId,
          title: cardTitle,
          subtitle: subtitle,
          imageUrl: art,
        ));
        if (cards.length >= 12) break;
      }
      if (cards.isNotEmpty) out.add((title: title, albums: cards));
    }
    return out;
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

  /// Picks the highest-resolution thumbnail URL from a node holding a
  /// `thumbnails` list ({url,width,height} entries). Protocol-relative
  /// URLs (leading //) are upgraded to https.
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

  /// Text from either runs (joined) or simpleText — covers both the
  /// zen and plain-channel renderer vocabularies.
  String? _textOf(_JsonMap? node) {
    if (node == null) return null;
    final runs = runsText(node);
    if (runs != null && runs.isNotEmpty) return runs;
    return node.getValue<String>('simpleText');
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