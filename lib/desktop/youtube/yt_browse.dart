// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/services/youtube_video_search.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';


/// One video-shaped entry harvested from any YouTube browse surface.
class YtFeedVideo {
  final String id;
  final String title;
  final String author;
  final String authorId;
  final String? views; // "1.2M views" as YouTube displays it
  final String? published; // "3 days ago"
  final String? length; // "12:34" (null for live / shorts)
  final String thumb;
  final bool live;
  final bool isShort;

  const YtFeedVideo({
    required this.id,
    required this.title,
    required this.author,
    required this.authorId,
    required this.thumb,
    this.views,
    this.published,
    this.length,
    this.live = false,
    this.isShort = false,
  });

  static String _thumbOf(Map r) {
    final t = r['thumbnail'];
    if (t is Map) {
      final list = t['thumbnails'];
      if (list is List && list.isNotEmpty) {
        // Highest-resolution variant last, per YouTube convention.
        final best = list.last;
        if (best is Map && best['url'] is String) {
          return best['url'] as String;
        }
      }
    }
    return '';
  }

  static String? _textOf(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is Map) {
      final simple = v['simpleText'];
      if (simple is String) return simple;
      final runs = v['runs'];
      if (runs is List && runs.isNotEmpty) {
        final first = runs.first;
        if (first is Map && first['text'] is String) {
          return first['text'] as String;
        }
      }
      final content = v['content'];
      if (content is String) return content;
    }
    return null;
  }

  /// videoRenderer / gridVideoRenderer / compactVideoRenderer shapes.
  factory YtFeedVideo.fromVideoRenderer(Map r, {bool isShort = false}) {
    final id = r['videoId'];
    String title = _textOf(r['title']) ?? '';
    if (title.isEmpty) title = _textOf(r['headline']) ?? '';

    String author = '';
    String authorId = '';
    for (final key in const ['ownerText', 'shortBylineText', 'longBylineText']) {
      if (author.isNotEmpty) break;
      final v = r[key];
      if (v is Map) {
        final runs = v['runs'];
        if (runs is List && runs.isNotEmpty && runs.first is Map) {
          final run = runs.first as Map;
          author = (run['text'] as String?) ?? '';
          final nav = run['navigationEndpoint'];
          if (nav is Map) {
            final browse = nav['browseEndpoint'];
            if (browse is Map && browse['browseId'] is String) {
              authorId = browse['browseId'] as String;
            }
          }
        }
      }
    }

    bool live = false;
    final badges = r['badges'];
    if (badges is List) {
      for (final b in badges) {
        final md = b is Map ? b['metadataBadgeRenderer'] : null;
        final style = md is Map ? md['style'] : null;
        final label = md is Map ? md['label'] : null;
        if (style == 'BADGE_STYLE_TYPE_LIVE' ||
            (label is String && label.toUpperCase().contains('LIVE'))) {
          live = true;
        }
      }
    }
    final overlay = r['thumbnailOverlays'];
    if (overlay is List) {
      for (final o in overlay) {
        final ob = o is Map ? o['thumbnailOverlayBadgeViewModel'] : null;
        final bv = ob is Map ? ob['thumbnailBadges'] : null;
        if (bv is List) {
          for (final b in bv) {
            final vm = b is Map ? b['thumbnailBadgeViewModel'] : null;
            final t = vm is Map ? vm['text'] : null;
            if (t is String && t.toUpperCase().contains('LIVE')) live = true;
          }
        }
      }
    }

    final lengthText = _textOf(r['lengthText']);
    final isShortResolved =
        isShort || (lengthText != null && _looksShort(lengthText));

    return YtFeedVideo(
      id: id is String ? id : '',
      title: title,
      author: author,
      authorId: authorId,
      views: _textOf(r['viewCountText']),
      published: _textOf(r['publishedTimeText']),
      length: lengthText,
      thumb: _thumbOf(r),
      live: live,
      isShort: isShortResolved,
    );
  }

  /// 0:xx lengths (≤ 0:60) found on ordinary renderers are shorts too.
  static bool _looksShort(String lengthText) {
    final m = RegExp(r'^(\d+):(\d{2})$').firstMatch(lengthText.trim());
    if (m == null) return false;
    final minutes = int.tryParse(m.group(1) ?? '') ?? -1;
    return minutes == 0;
  }

  /// shortsLockupViewModel (the modern shorts grid cell).
  factory YtFeedVideo.fromShortsLockup(Map vm) {
    final thumbVm = vm['thumbnailViewModel'];
    String thumb = '';
    if (thumbVm is Map) {
      final th = thumbVm['thumbnail'];
      if (th is Map) {
        final sources = th['sources'];
        if (sources is List && sources.isNotEmpty) {
          final last = sources.last;
          if (last is Map && last['url'] is String) {
            thumb = last['url'] as String;
          }
        }
      }
    }

    final overlay = vm['overlayMetadata'];
    String title = '';
    String author = '';
    if (overlay is Map) {
      title = _textOf(overlay['primaryText']) ?? '';
      author = _textOf(overlay['secondaryText']) ?? '';
    }
    if (title.isEmpty) {
      title = _textOf(vm['accessibilityText']) ?? '';
    }

    // videoId lives deep in onTap → innertubeCommand → reelWatchEndpoint.
    String id = '';
    void digForReel(dynamic node) {
      if (id.isNotEmpty || node == null) return;
      if (node is Map) {
        final reel = node['reelWatchEndpoint'];
        if (reel is Map && reel['videoId'] is String) {
          id = reel['videoId'] as String;
          return;
        }
        for (final v in node.values) {
          digForReel(v);
          if (id.isNotEmpty) return;
        }
      } else if (node is List) {
        for (final v in node) {
          digForReel(v);
          if (id.isNotEmpty) return;
        }
      }
    }

    digForReel(vm['onTap']);

    return YtFeedVideo(
      id: id,
      title: title,
      author: author,
      authorId: '',
      thumb: thumb,
      isShort: true,
    );
  }

  static YtFeedVideo? fromYtmSong(Map raw) {
    final id = raw['videoId']?.toString() ?? '';
    if (id.length != 11) return null;
    final title = raw['title']?.toString() ?? '';
    if (title.isEmpty) return null;

    String thumb = '';
    final thumbs = raw['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map && last['url'] != null) {
        thumb = last['url'].toString();
      }
    }
    thumb = thumb.isEmpty
        ? 'https://i.ytimg.com/vi/$id/mqdefault.jpg'
        : thumb;

    final authors = raw['artists'];
    String author = '';
    if (authors is List && authors.isNotEmpty && authors.first is Map) {
      author = authors.first['name']?.toString() ?? '';
    }
    author = author.isNotEmpty
        ? author
        : raw['artist']?.toString() ??
            raw['subtitle']?.toString() ??
            'YouTube Music';

    return YtFeedVideo(
      id: id,
      title: title,
      author: author,
      authorId: '',
      thumb: thumb,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'author': author,
        'authorId': authorId,
        'views': views,
        'published': published,
        'length': length,
        'thumb': thumb,
        'live': live,
        'isShort': isShort,
      };
}

/// A trending filter chip harvested from the response ("Now", "Music", ...).
class YtChip {
  final String title;
  final String continuation;

  const YtChip(this.title, this.continuation);
}

/// One page of a browse feed.
class YtFeedPage {
  final List<YtFeedVideo> items;
  final String? continuation;
  final List<YtChip> chips;

  const YtFeedPage(this.items, this.continuation, {this.chips = const []});
}

/// Browse request failed (network / YouTube refused / shape changed).
class YtBrowseException implements Exception {
  final String message;
  YtBrowseException(this.message);
  @override
  String toString() => 'YtBrowseException: $message';
}


class YtBrowse {
  YtBrowse._();

  /// The search query powering the Shorts tab (see [shortsIds]).
  static const _shortsQuery = '#shorts';

  static const String home = 'FEwhat_to_watch';
  static const String trending = 'FEtrending';
  static const String shortsStartup = 'FEshorts_startup';

  static const String _ytmHomeId = 'FEmusic_home';
  static const String _ytmChartsId = 'FEmusic_charts';

  static const String _kYtmHomePrefix = 'zenytmhome::';
  static const String _kYtmChartsPrefix = 'zenytmcharts::';

  static const String _endpoint = 'https://www.youtube.com/youtubei/v1/browse';
  static const String _clientName = 'WEB';
  static const String _clientVersion = '2.20240726.00.00';

  static final http.Client _http = http.Client();

  /// The next shorts continuation after the most recent [shortsIds] call
  /// (null = exhausted). The shorts feed stores it between pages.
  static String? lastShortsContinuation;

  @visibleForTesting
  static Future<Map<String, dynamic>> Function(
          String browseId, String? ytmContinuation)? ytmFetchForTest;
  @visibleForTesting
  static Future<List> Function(String playlistId)? ytmPlaylistForTest;
  @visibleForTesting
  static Future<List<String>> Function(String? continuation)?
      shortsFetchForTest;

  static Map<String, String> get _headers => const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'X-Youtube-Client-Name': '1',
        'X-Youtube-Client-Version': _clientVersion,
      };

  static Map<String, dynamic> get _context => const {
        'context': {
          'client': {
            'clientName': _clientName,
            'clientVersion': _clientVersion,
            'hl': 'en',
            'gl': 'US',
          },
        },
      };


  /// One feed page. [browseId] is one of [home]/[trending]; [continuation]
  /// is a self-describing token handed out by a previous page.
  static Future<YtFeedPage> fetch({
    String? browseId,
    String? params,
    String? continuation,
  }) async {
    // Self-describing continuations route back to their own engine.
    if (continuation != null && continuation.isNotEmpty) {
      if (continuation.startsWith(_kYtmHomePrefix)) {
        return _ytmMusicPage(_ytmHomeId, continuation.substring(_kYtmHomePrefix.length),
            homePrefix: _kYtmHomePrefix);
      }
      if (continuation.startsWith(_kYtmChartsPrefix)) {
        // The trending page is one-shot (a whole chart playlist); a stale
        // token resolves to "no more".
        return const YtFeedPage([], null);
      }
      // Anything else is a legacy WEB-browse continuation.
      return _legacyPage(continuation: continuation, params: params);
    }

    if (browseId == home) return _ytmMusicPage(_ytmHomeId, null, homePrefix: _kYtmHomePrefix);
    if (browseId == trending) return _ytmTrendingPage();
    return _legacyPage(browseId: browseId, params: params);
  }


  /// One YTMusic browse page, flattened to videos. Cold visitors (fresh
  /// install) sometimes get an empty-shell first response WITH a valid
  /// continuation — one follow-through turns it into real content.
  static Future<YtFeedPage> _ytmMusicPage(
    String browseId,
    String? ytmContinuation, {
    required String homePrefix,
  }) async {
    var res = await _ytm(browseId, ytmContinuation);
    var items = _harvestYtmSections(res);
    var cont = _ytmContinuationOf(res);
    if (items.isEmpty && cont != null) {
      res = await _ytm(browseId, cont);
      final nextItems = _harvestYtmSections(res);
      if (nextItems.isNotEmpty) {
        items = nextItems;
        cont = _ytmContinuationOf(res);
      }
    }
    final next = cont != null ? '$homePrefix$cont' : null;
    return YtFeedPage(items, next);
  }

  static List<YtFeedVideo> _harvestYtmSections(dynamic res) {
    final items = <YtFeedVideo>[];
    final seen = <String>{};
    final sections = res is Map ? res['sections'] : null;
    if (sections is List) {
      for (final section in sections) {
        final contents = section is Map ? section['contents'] : null;
        if (contents is! List) continue;
        for (final raw in contents) {
          if (raw is! Map) continue;
          final v = YtFeedVideo.fromYtmSong(raw);
          if (v == null || !seen.add(v.id)) continue;
          items.add(v);
        }
      }
    }
    return items;
  }

  static String? _ytmContinuationOf(dynamic res) {
    final cont = res is Map ? res['continuation'] : null;
    return cont is String && cont.isNotEmpty ? cont : null;
  }

  /// Trending: charts → the region's trending VIDEO chart playlist → songs.
  static Future<YtFeedPage> _ytmTrendingPage() async {
    final charts = await _ytm(_ytmChartsId, null);
    String? playlistId;
    final sections = charts['sections'];
    if (sections is List) {
      for (final section in sections) {
        if (section is! Map) continue;
        final shelfTitle = section['title']?.toString().toLowerCase() ?? '';
        for (final raw in (section['contents'] as List? ?? [])) {
          if (raw is! Map) continue;
          final pid = raw['playlistId']?.toString() ?? '';
          if (pid.isEmpty) continue;
          if (playlistId == null || shelfTitle.contains('video')) {
            playlistId = pid;
          }
          if (shelfTitle.contains('video')) break;
        }
        if (playlistId != null && shelfTitle.contains('video')) break;
      }
    }
    if (playlistId == null) {
      throw YtBrowseException('charts carried no video-chart playlist');
    }
    final songs = await _ytmPlaylist(playlistId);
    final items = <YtFeedVideo>[];
    final seen = <String>{};
    for (final raw in songs) {
      if (raw is! Map) continue;
      final v = YtFeedVideo.fromYtmSong(raw);
      if (v == null || !seen.add(v.id)) continue;
      items.add(v);
    }
    return YtFeedPage(items, null);
  }

  static Future<Map<String, dynamic>> _ytm(
      String browseId, String? ytmContinuation) {
    final f = ytmFetchForTest;
    if (f != null) return f(browseId, ytmContinuation);
    final ytm = GetIt.I<YTMusic>();
    return (ytmContinuation == null || ytmContinuation.isEmpty)
        ? ytm.browse(body: {'browseId': browseId}, limit: 1)
        : ytm.browse(
            body: {'browseId': browseId}, additionalParams: ytmContinuation);
  }

  static Future<List> _ytmPlaylist(String playlistId) {
    final f = ytmPlaylistForTest;
    if (f != null) return f(playlistId);
    return GetIt.I<YTMusic>().getPlaylistSongs(playlistId);
  }


  static Future<List<String>> shortsIds({String? continuation}) async {
    final f = shortsFetchForTest;
    if (f != null) {
      final ids = await f(continuation);
      lastShortsContinuation = null;
      return ids;
    }
    var page = (continuation == null || continuation.isEmpty)
        ? await YouTubeVideoSearch.instance
            .search(_shortsQuery)
            .timeout(const Duration(seconds: 15))
        : await YouTubeVideoSearch.instance
            .more(continuation)
            .timeout(const Duration(seconds: 15));

    final ids = <String>[];
    var token = continuation == null || continuation.isEmpty ? null : continuation;
    // One search page carries only a handful of plain videos (the rest are
    // shelves/playlists) — walk pages until the feed has enough shorts.
    for (var hops = 0; hops < 4 && ids.length < 12 && page.items.isNotEmpty; hops++) {
      for (final e in page.items) {
        final id = e['videoId']?.toString() ?? '';
        if (id.length != 11 || ids.contains(id)) continue;
        final dur = e['duration']?.toString() ?? '';
        // Shorts results usually carry no length chip at all (they read as
        // "LIVE" in the raw map) — only exclude videos that are EXPLICITLY
        // longer than the shorts limit.
        if (!_withinShortsOrUnknown(dur)) continue;
        ids.add(id);
      }
      if (ids.length >= 12 || page.token == null) {
        token = page.token;
        break;
      }
      token = page.token;
      page = await YouTubeVideoSearch.instance
          .more(page.token!)
          .timeout(const Duration(seconds: 15));
    }
    lastShortsContinuation = token;
    return ids;
  }

  /// False only for durations that clearly exceed the shorts limit.
  static bool _withinShortsOrUnknown(String durationText) {
    if (durationText.isEmpty || durationText == 'LIVE') return true;
    final parts = durationText.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return true;
    var secs = 0;
    for (final p in parts) {
      final v = int.tryParse(p.trim());
      if (v == null) return true; // unknown shape — keep it
      secs = secs * 60 + v;
    }
    return secs <= _kShortsMaxSeconds;
  }

  static const int _kShortsMaxSeconds = 181;


  /// POST one browse call. [browseId] OR [continuation] must be given.
  /// Returns the raw decoded JSON (shape-agnostic — the harvester walks it).
  static Future<dynamic> raw({
    String? browseId,
    String? params,
    String? continuation,
  }) async {
    final body = <String, dynamic>{..._context};
    if (browseId != null && browseId.isNotEmpty) body['browseId'] = browseId;
    if (params != null && params.isNotEmpty) body['params'] = params;
    if (continuation != null && continuation.isNotEmpty) {
      body.remove('browseId');
      body.remove('params');
      body['continuation'] = continuation;
    }

    try {
      final res = await _http
          .post(Uri.parse(_endpoint), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw YtBrowseException('browse HTTP ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw YtBrowseException('browse returned a non-object body');
      }
      return decoded;
    } on YtBrowseException {
      rethrow;
    } on TimeoutException {
      throw YtBrowseException('browse timed out');
    } catch (e) {
      throw YtBrowseException('browse failed: $e');
    }
  }

  static Future<YtFeedPage> _legacyPage({
    String? browseId,
    String? params,
    String? continuation,
  }) async {
    final json =
        await raw(browseId: browseId, params: params, continuation: continuation);
    return parseFeed(json);
  }


  /// Walks ANY InnerTube browse/next payload and collects every video-shaped
  /// renderer, the filter-chip bar (if any) and the page continuation token.
  static YtFeedPage parseFeed(dynamic node) {
    final items = <YtFeedVideo>[];
    final chips = <YtChip>[];
    String? continuation;

    void walk(dynamic n) {
      if (n is Map) {
        // Filter-chip bar (trending categories) — the chips' own
        // continuationCommand tokens must NOT become the page continuation.
        final chipBar = n['feedFilterChipBarRenderer'];
        if (chipBar is Map && chipBar['chips'] is List) {
          for (final c in (chipBar['chips'] as List)) {
            if (c is! Map) continue;
            final title = YtFeedVideo._textOf(c['text']);
            final nav = c['navigationEndpoint'];
            final cmd = nav is Map ? nav['continuationCommand'] : null;
            final token = cmd is Map ? cmd['token'] : null;
            if (title is String && title.isNotEmpty && token is String) {
              chips.add(YtChip(title, token));
            }
          }
        }

        // Page continuation lives ONLY in continuationItemRenderer.
        final cont = n['continuationItemRenderer'];
        if (cont is Map && continuation == null) {
          final endpoint = cont['continuationEndpoint'];
          final cmd = endpoint is Map ? endpoint['continuationCommand'] : null;
          final token = cmd is Map ? cmd['token'] : null;
          if (token is String) continuation = token;
        }

        // Video renderers.
        for (final key in const [
          'videoRenderer',
          'gridVideoRenderer',
          'compactVideoRenderer',
        ]) {
          final r = n[key];
          if (r is Map) {
            final v = YtFeedVideo.fromVideoRenderer(r);
            if (v.id.isNotEmpty) items.add(v);
            return; // the renderer subtree is consumed
          }
        }

        // Shorts renderers.
        final reel = n['reelItemRenderer'];
        if (reel is Map) {
          final v = YtFeedVideo.fromVideoRenderer(reel, isShort: true);
          if (v.id.isNotEmpty) items.add(v);
          return;
        }
        final lockup = n['shortsLockupViewModel'];
        if (lockup is Map) {
          final v = YtFeedVideo.fromShortsLockup(lockup);
          if (v.id.isNotEmpty) items.add(v);
          return;
        }

        for (final v in n.values) {
          walk(v);
        }
      } else if (n is List) {
        for (final v in n) {
          walk(v);
        }
      }
    }

    walk(node);
    return YtFeedPage(items, continuation, chips: chips);
  }
}
