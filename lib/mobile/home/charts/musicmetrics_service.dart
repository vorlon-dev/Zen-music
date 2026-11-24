// ZenMusic · vorlon-dev
//
// MusicMetrics chart service — MOBILE Echo home only.
//
// Loads the charts from musicmetrics.net (endpoints in chart_config.dart):
//   * cache-first: whatever was loaded last time paints instantly from the
//     Hive disk cache, the network only freshens it in the background;
//   * never-stall: every fetch is timeout-guarded, every failure returns
//     null and the shelf simply keeps its cached rows / stays hidden;
//   * never-jank: HTML parsing runs inside a background isolate (compute),
//     so the UI thread never touches a 300 KB page;
//   * region-aware: the Spotify chart URL uses the user's country, detected
//     from their IP (with device-region and fallback fallbacks), exactly
//     like the musicmetrics.net country pages.
//
// Playback never happens here: chart rows are plain `isChart` maps and the
// established Zen pipeline (YTMusic.search → MediaPlayer.playSong/playAll)
// resolves and plays them from YouTube Music only.

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;

import 'chart_config.dart';

/// One row of a MusicMetrics chart (song, or album on the albums chart).
class MusicChartEntry {
  final int rank;
  final String title;
  final String artist;
  final String imageUrl;
  final bool isAlbum;

  const MusicChartEntry({
    required this.rank,
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.isAlbum = false,
  });

  Map<String, dynamic> toJson() => {
        'rank': rank,
        'title': title,
        'artist': artist,
        'image': imageUrl,
        'album': isAlbum,
      };

  factory MusicChartEntry.fromJson(Map<String, dynamic> json) =>
      MusicChartEntry(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        imageUrl: json['image']?.toString() ?? '',
        isAlbum: json['album'] == true,
      );

  /// The map shape the established chart-playback pipeline expects
  /// (`isChart: true` → YTM search → play, see MediaPlayer.playAll and the
  /// Echo song row). No videoId is ever set: YouTube Music resolves it.
  Map<String, dynamic> toSongMap() => {
        'title': title,
        'subtitle': artist,
        'isChart': true,
        'thumbnails': [
          if (imageUrl.isNotEmpty)
            {'url': imageUrl, 'width': 200, 'height': 200},
        ],
      };
}

/// A parsed MusicMetrics chart page.
class MusicChartPage {
  final String title; // page <h1>, e.g. "Spotify Weekly Top Songs · India"
  final List<MusicChartEntry> items;
  final bool isAlbum;

  const MusicChartPage({
    required this.title,
    required this.items,
    required this.isAlbum,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'items': [for (final e in items) e.toJson()],
        'album': isAlbum,
      };

  factory MusicChartPage.fromJson(Map<String, dynamic> json) =>
      MusicChartPage(
        title: json['title']?.toString() ?? '',
        isAlbum: json['album'] == true,
        items: [
          for (final e in (json['items'] as List?) ?? const [])
            if (e is Map) MusicChartEntry.fromJson(Map<String, dynamic>.from(e)),
        ],
      );
}

class MusicMetricsService {
  final Map<MusicChartId, DateTime> _lastFetch = {};
  String? _cachedRegion;
  DateTime? _regionAt;

  /// Instant paint: the last successfully parsed chart from disk, or null.
  MusicChartPage? cached(MusicChartId id) {
    try {
      final raw =
          Hive.box(ChartConfig.hiveBox).get('${ChartConfig.cacheKeyPrefix}${id.name}');
      if (raw is! String) return null;
      return MusicChartPage.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetches and parses a chart. NEVER throws, NEVER blocks longer than
  /// [ChartConfig.fetchTimeout]. Returns null on any failure; [force] (pull
  /// to refresh) bypasses the in-memory throttle. If the IP-detected Spotify
  /// region has no chart on MusicMetrics, the fallback region is tried once
  /// so the Spotify shelf always has data.
  Future<MusicChartPage?> fetch(MusicChartId id, {bool force = false}) async {
    final last = _lastFetch[id];
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < ChartConfig.refetchThrottle) {
      return cached(id);
    }
    try {
      final url = await _urlFor(id);
      MusicChartPage? page = await _fetchAndParse(url);
      if (page == null && id == MusicChartId.spotify) {
        final fallbackUrl = '${ChartConfig.musicMetricsBase}'
            '${ChartConfig.spotifyCountryBasePath}'
            '${ChartConfig.fallbackRegion}/';
        if (fallbackUrl != url) page = await _fetchAndParse(fallbackUrl);
      }
      _lastFetch[id] = DateTime.now();
      if (page == null || page.items.isEmpty) return null;
      try {
        await Hive.box(ChartConfig.hiveBox).put(
          '${ChartConfig.cacheKeyPrefix}${id.name}',
          jsonEncode(page.toJson()),
        );
      } catch (_) {/* cache is best-effort only */}
      return page;
    } catch (e) {
      log('MusicMetrics fetch failed: ${id.name} — $e', name: 'MusicMetrics');
      return null;
    }
  }

  /// One guarded GET + background-isolate parse. Returns null on any
  /// failure instead of throwing — callers never need to handle errors.
  Future<MusicChartPage?> _fetchAndParse(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': ChartConfig.userAgent})
          .timeout(ChartConfig.fetchTimeout);
      if (response.statusCode != 200) return null;
      // Parse OFF the UI thread — a 300 KB page must never jank the phone.
      final page = await compute(_parseChartPage, response.body);
      return page.items.isEmpty ? null : page;
    } catch (_) {
      return null;
    }
  }

  Future<String> _urlFor(MusicChartId id) async {
    switch (id) {
      case MusicChartId.global:
        return ChartConfig.musicMetricsBase + ChartConfig.globalChartPath;
      case MusicChartId.youtube:
        return ChartConfig.musicMetricsBase + ChartConfig.youtubeChartPath;
      case MusicChartId.appleMusic:
        return ChartConfig.musicMetricsBase + ChartConfig.appleMusicChartPath;
      case MusicChartId.itunes:
        return ChartConfig.musicMetricsBase + ChartConfig.itunesChartPath;
      case MusicChartId.deezer:
        return ChartConfig.musicMetricsBase + ChartConfig.deezerChartPath;
      case MusicChartId.spotify:
        // The Spotify chart follows the user's IP/location.
        final region = await _resolveRegion();
        return '${ChartConfig.musicMetricsBase}${ChartConfig.spotifyCountryBasePath}$region/';
      case MusicChartId.albums:
        return ChartConfig.musicMetricsBase + ChartConfig.albumsChartPath;
    }
  }

  /// Country code for the regional Spotify chart:
  /// 1) IP geolocation (keyless endpoints from config, first one that answers),
  /// 2) the device region from the system locale,
  /// 3) the configured fallback region.
  /// The resolved code is remembered for [ChartConfig.regionCacheTtl].
  Future<String> _resolveRegion() async {
    final now = DateTime.now();
    if (_cachedRegion != null &&
        _regionAt != null &&
        now.difference(_regionAt!) < ChartConfig.regionCacheTtl) {
      return _cachedRegion!;
    }
    try {
      final raw = Hive.box(ChartConfig.hiveBox).get(ChartConfig.regionCacheKey);
      if (raw is String) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final cc = m['cc']?.toString();
        final ts = DateTime.tryParse(m['ts']?.toString() ?? '');
        if (cc != null && cc.length == 2 && ts != null &&
            now.difference(ts) < ChartConfig.regionCacheTtl) {
          _cachedRegion = cc;
          _regionAt = now;
          return cc;
        }
      }
    } catch (_) {/* fall through to live detection */}

    final valid = RegExp(r'^[a-z]{2}$');
    for (final geoUrl in ChartConfig.geoLookupUrls) {
      try {
        final r = await http
            .get(Uri.parse(geoUrl), headers: {'User-Agent': ChartConfig.userAgent})
            .timeout(ChartConfig.geoTimeout);
        if (r.statusCode == 200) {
          final body = jsonDecode(r.body);
          // Providers differ: ipwho.is/ipapi.co use "country_code",
          // freeipapi.com uses "countryCode".
          final cc = (body is Map
                  ? (body['country_code'] ?? body['countryCode'])
                  : null)
              ?.toString()
              .toLowerCase();
          if (cc != null && valid.hasMatch(cc)) return _rememberRegion(cc, now);
        }
      } catch (_) {/* try the next source */}
    }
    try {
      // dart:io exposes the OS locale as Platform.localeName (e.g. "en_IN",
      // "en-IN" or "en_IN.UTF-8"). Scan the subtags after the language for
      // the first 2-letter country code (zh_Hans_CN -> cn).
      final locale = Platform.localeName;
      final parts = locale.split(RegExp(r'[-_.]'));
      for (final part in parts.skip(1)) {
        final cc = part.toLowerCase();
        if (valid.hasMatch(cc)) return _rememberRegion(cc, now);
      }
    } catch (_) {}
    return _rememberRegion(ChartConfig.fallbackRegion, now);
  }

  String _rememberRegion(String cc, DateTime now) {
    _cachedRegion = cc;
    _regionAt = now;
    try {
      Hive.box(ChartConfig.hiveBox).put(
        ChartConfig.regionCacheKey,
        jsonEncode({'cc': cc, 'ts': now.toIso8601String()}),
      );
    } catch (_) {}
    return cc;
  }
}

/// Runs inside a background isolate (compute) — pure Dart, no UI access.
/// Handles every MusicMetrics layout:
///   * song charts (global / youtube / apple-music / itunes / deezer and the
///     regional Spotify pages): `<li class="row">` rows with rank, art,
///     `a.row__title` and `span.row__artist`;
///   * the albums chart: a `<tbody id="album-list">` table with
///     `td.r.big` rank, art, `<strong>` album name and muted artist link.
MusicChartPage _parseChartPage(String body) {
  final doc = parse(body);
  final h1 = doc.querySelector('h1')?.text.trim() ?? '';

  // ── Albums page ───────────────────────────────────────────────────────────
  final tbody = doc.querySelector('tbody#album-list');
  if (tbody != null) {
    final items = <MusicChartEntry>[];
    for (final tr in tbody.querySelectorAll('tr')) {
      final rankText = tr.querySelector('td.r.big')?.text.trim() ?? '';
      final img = tr.querySelector('img')?.attributes['src'] ?? '';
      final title = tr.querySelector('strong')?.text.trim() ?? '';
      final artist = tr.querySelector('span.muted.small a')?.text.trim() ?? '';
      if (title.isEmpty) continue;
      items.add(MusicChartEntry(
        rank: int.tryParse(rankText) ?? items.length + 1,
        title: title,
        artist: artist,
        imageUrl: img,
        isAlbum: true,
      ));
      if (items.length >= ChartConfig.maxRowsPerChart) break;
    }
    return MusicChartPage(title: h1, items: items, isAlbum: true);
  }

  // ── Song chart pages ──────────────────────────────────────────────────────
  final items = <MusicChartEntry>[];
  for (final row in doc.querySelectorAll('li.row')) {
    final rankText = row.querySelector('.row__rank')?.text.trim() ?? '';
    final img = row.querySelector('img.row__art')?.attributes['src'] ?? '';
    final title = row.querySelector('a.row__title')?.text.trim() ?? '';
    final artist = row.querySelector('span.row__artist')?.text.trim() ?? '';
    if (title.isEmpty) continue;
    items.add(MusicChartEntry(
      rank: int.tryParse(rankText) ?? items.length + 1,
      title: title,
      artist: artist,
      imageUrl: img,
      isAlbum: false,
    ));
    if (items.length >= ChartConfig.maxRowsPerChart) break;
  }
  return MusicChartPage(title: h1, items: items, isAlbum: false);
}
