// ZenMusic · vorlon-dev

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';
import 'package:zenmusic/desktop/spotify/spotify_library.dart';

/// One playable chart ("Top 50 - India", "Top 50 - Global", …).
class SpotifyChart {
  final String id; // e.g. 'regional-in'
  final String title; // real playlist name (oEmbed) or a fallback
  final List<Map<String, dynamic>> tracks;

  /// The playlist's own branded cover from oEmbed. Spotify's chart
  /// tiles are branded art — this reads better than the #1 track's
  /// artwork, which remains the fallback.
  final String coverOverride;

  const SpotifyChart({
    required this.id,
    required this.title,
    required this.tracks,
    this.coverOverride = '',
  });

  /// Cover = the playlist's branded art, else the #1 track's artwork.
  String get coverUrl {
    if (coverOverride.isNotEmpty) return coverOverride;
    if (tracks.isEmpty) return '';
    final thumbs = tracks.first['thumbnails'] as List?;
    if (thumbs == null || thumbs.isEmpty) return '';
    return (thumbs.first as Map)['url']?.toString() ?? '';
  }

  /// The #1 track's title, for the card overlay.
  String get topLine =>
      tracks.isEmpty ? '' : tracks.first['title']?.toString() ?? '';
}

/// Everything the Home section needs, fetched in one pass.
class SpotifyHomeSnapshot {
  final Map<String, dynamic>? account; // profile details (nullable)
  final List<Map<String, dynamic>> featured; // editorial playlists
  final List<SpotifyChart> charts; // Top 50 charts
  final String region; // lowercase country code used for charts

  final String greeting;
  final List<Map<String, dynamic>> homeSections;
  final List<Map<String, dynamic>> recent;

  const SpotifyHomeSnapshot({
    required this.account,
    required this.featured,
    required this.charts,
    required this.region,
    this.greeting = '',
    this.homeSections = const [],
    this.recent = const [],
  });

  /// The regional chart for the user's own country (the "hits at
  /// home" row). Falls back to the first chart available.
  SpotifyChart? get primaryChart {
    for (final c in charts) {
      if (c.id == 'regional-$region') return c;
    }
    return charts.isEmpty ? null : charts.first;
  }
}

class SpotifyHomeFeed {
  SpotifyHomeFeed._();
  static final SpotifyHomeFeed instance = SpotifyHomeFeed._();

  final _client = http.Client();

  Map<String, dynamic>? _accountCache;
  int _accountAtMs = 0;
  static const int _accountCacheMs = 6 * 3600 * 1000;
  bool _meDisabled = false;

  final Map<String, (String, String)?> _oembedCache = {};
  final Map<String, int> _oembedAtMs = {};
  static const int _oembedTtlMs = 30 * 60 * 1000;

  // Verified via oEmbed (HTTP 200 + real titles) before shipping.
  // Top 50 playlists ARE Spotify's daily charts — regional + viral in
  // one object; Viral 50 was retired by Spotify, so it is not listed.
  static const String _top50Global = '37i9dQZEVXbMDoHDwVN2tF';
  static const Map<String, String> _regionalChartIds = {
    'in': '37i9dQZEVXbLZ52XmnySJg', // Top 50 - India
    'mx': '37i9dQZEVXbO3qyFxbkOE1', // Top 50 - Mexico
    'global': _top50Global, // Top 50 - Global
  };

  static const List<(String, String)> _editorial = [
    ('37i9dQZF1DXcBWIGoYBM5M', 'Today\'s Top Hits'),
    ('37i9dQZF1DX0XUsuxWHRQd', 'RapCaviar'),
    ('37i9dQZF1DX4JAvHpjipBk', 'New Music Friday'),
    ('37i9dQZF1DX10zKzsJ2jva', 'Viva Latino'),
    ('37i9dQZF1DX1lVhptIYRda', 'Hot Country'),
    ('37i9dQZF1DX4dyzvuaRJ0n', 'mint'),
    ('37i9dQZF1DWTwnEm1IYyoj', 'Soft Pop Hits'),
    ('37i9dQZF1DX9tPFwDMOaN1', 'K-Pop ON!'),
  ];

  void _log(String m) => debugPrint('[spotify-home] $m');

  String _short(String s, [int n = 240]) =>
      s.length > n ? '${s.substring(0, n)}…' : s;


  Future<Map<String, dynamic>?> accountDetails() async {
    final cached = _accountCache;
    if (cached != null &&
        DateTime.now().millisecondsSinceEpoch - _accountAtMs <
            _accountCacheMs) {
      return cached;
    }
    final me = await SpotifyLibrary.instance.me();
    if (me != null && (me['display_name']?.toString() ?? '').isNotEmpty) {
      final account = <String, dynamic>{
        'display_name': me['display_name']?.toString() ?? '',
        'avatar': me['avatar']?.toString() ?? '',
        'country': '',
        'product': '',
        'followers': 0,
      };
      _accountCache = account;
      _accountAtMs = DateTime.now().millisecondsSinceEpoch;
      _log('account details: ${account['display_name']} (pathfinder)');
      return account;
    }
    // SECONDARY: /v1/me — avatar/plan/country extras only. Spotify
    // 429s api.spotify.com for Web-Player tokens — ONCE per session.
    if (_meDisabled) return _accountCache;
    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      _log('account skipped: ${SpotifyAuth.instance.lastError}');
      _meDisabled = true;
      return _accountCache;
    }
    try {
      var (status, body) = await _meCall(token);
      if (status == 401) {
        SpotifyAuth.instance.invalidateAccessToken();
        final fresh = await SpotifyAuth.instance.getAccessToken(force: true);
        if (fresh != null && fresh != token) {
          final retry = await _meCall(fresh);
          status = retry.$1;
          body = retry.$2;
          if (status >= 200 && status < 300) _log('me recovered after re-mint');
        } else {
          _log('me 401 with no recoverable session: '
              '${SpotifyAuth.instance.lastError}');
        }
      }
      if (status < 200 || status >= 300) {
        _meDisabled = true; // never retry this session (429 etc.)
        if (status == 429) {
          _log('me HTTP 429 — Spotify rate-limits the Web API for '
              'Web-Player tokens. Extras (avatar/plan/country) are '
              'skipped for this session; nothing else needs it.');
        } else {
          _log('me HTTP $status: ${_short(body)} '
              '(extras skipped for this session)');
        }
        return _accountCache;
      }
      final me = jsonDecode(body) as Map<String, dynamic>;
      final images = me['images'] as List? ?? const [];
      final account = <String, dynamic>{
        'display_name': me['display_name']?.toString() ?? '',
        'avatar': images.isNotEmpty
            ? ((images.first as Map)['url']?.toString() ?? '')
            : '',
        'country': me['country']?.toString() ?? '',
        'product': me['product']?.toString() ?? '',
        'followers':
            ((me['followers'] as Map?)?['total'] as num?)?.toInt() ?? 0,
      };
      _accountCache = account;
      _accountAtMs = DateTime.now().millisecondsSinceEpoch;
      _log('account details: ${account['display_name']} '
          '(${account['product']}, ${account['country']})');
      return account;
    } catch (e) {
      _meDisabled = true; // timeouts/sockets — not worth another shot
      _log('me error: $e (extras skipped for this session)');
      return _accountCache;
    }
  }

  Future<(int, String)> _meCall(String bearer) async {
    final r = await _client
        .get(
      Uri.parse('https://api.spotify.com/v1/me'),
      headers: {
        'authorization': 'Bearer $bearer',
        'accept': 'application/json',
        'user-agent': SpotifyConfig.userAgent,
      },
    )
        .timeout(const Duration(seconds: 12));
    return (r.statusCode, r.body);
  }


  /// (title, coverUrl) for a playlist, or null. 30-min in-memory
  /// cache; failures are cached too so a dead ID costs one lookup.
  Future<(String, String)?> _oembed(String playlistId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hit = _oembedCache[playlistId];
    final at = _oembedAtMs[playlistId] ?? 0;
    if (_oembedCache.containsKey(playlistId) && now - at < _oembedTtlMs) {
      return hit;
    }
    try {
      final url = Uri.parse('https://open.spotify.com/oembed?url='
          '${Uri.encodeComponent('spotify:playlist:$playlistId')}');
      final r = await _client.get(url, headers: {
        'accept': 'application/json',
        'user-agent': SpotifyConfig.userAgent,
      }).timeout(const Duration(seconds: 10));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final title = body['title']?.toString() ?? '';
        final thumb = body['thumbnail_url']?.toString() ?? '';
        final v = (title, thumb);
        _oembedCache[playlistId] = v;
        _oembedAtMs[playlistId] = now;
        return v;
      }
      _log('oembed HTTP ${r.statusCode} for $playlistId');
    } catch (e) {
      _log('oembed error for $playlistId: $e');
    }
    _oembedCache[playlistId] = null; // negative cache
    _oembedAtMs[playlistId] = now;
    return null;
  }

  Future<List<Map<String, dynamic>>> featuredPlaylists() async {
    final results = await Future.wait([
      for (final (id, _) in _editorial) _oembed(id),
    ]);
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < _editorial.length; i++) {
      final (id, fallback) = _editorial[i];
      final o = results[i];
      out.add({
        'id': 'spotify:playlist:$id',
        'title': (o?.$1.isNotEmpty == true) ? o!.$1 : fallback,
        'subtitle': '',
        'thumbnails': [
          {'url': o?.$2 ?? ''},
        ],
        'type': 'SPOTIFY_PLAYLIST',
      });
    }
    _log('featured: ${out.length} editorial playlists (oembed)');
    return out;
  }


  /// The playlist's tracks BECOME the chart. Every row is playable
  /// (spotifyUri from the shared parser), the cover is the playlist's
  /// branded art, the title is the playlist's real name.
  Future<SpotifyChart?> _chartFromPlaylist(
      String chartId, String playlistId, String fallbackTitle) async {
    try {
      final oembed = await _oembed(playlistId);
      final uri = 'spotify:playlist:$playlistId';
      final tracks = await SpotifyLibrary.instance
          .fetchPlaylistTracks(uri, limit: 50);
      if (tracks.isEmpty) {
        _log('$chartId: 0 tracks from fetchPlaylist — shelf skipped');
        return null;
      }
      _log('$chartId: ${tracks.length} tracks '
          '(${oembed?.$1 ?? fallbackTitle})');
      return SpotifyChart(
        id: chartId,
        title: (oembed?.$1.isNotEmpty == true)
            ? oembed!.$1
            : fallbackTitle,
        tracks: tracks,
        coverOverride: oembed?.$2 ?? '',
      );
    } catch (e) {
      _log('$chartId error: $e');
      return null;
    }
  }

  Future<List<SpotifyChart>> charts(String region) async {
    // The account country's Top 50 + the Global pair. Only IDs that
    // were oEmbed-verified are listed; unknown countries fall back to
    // Global (region == 'global' can't duplicate — handled below).
    final regionalId = _regionalChartIds[region] ?? _top50Global;
    final results = await Future.wait([
      _chartFromPlaylist(
          'regional-$region', regionalId, 'Top 50 - ${region.toUpperCase()}'),
      _chartFromPlaylist('regional-global', _top50Global,
          'Top 50 - Global'),
    ]);
    final out = <SpotifyChart>[];
    final seen = <String>{};
    for (final c in results) {
      if (c == null) continue;
      if (!seen.add(c.id)) continue;
      out.add(c);
    }
    return out;
  }


  Future<SpotifyHomeSnapshot> snapshot() async {
    final account = await accountDetails();
    final country = (account?['country'] as String?) ?? '';
    // Charts are keyed by lowercase country; unknown → India (this
    // app's audience) and Global is always fetched alongside anyway.
    final region = country.isNotEmpty ? country.toLowerCase() : 'in';
    final featuredFuture = featuredPlaylists();
    final chartsFuture = charts(region);
    final homeFuture = SpotifyLibrary.instance.homeSnapshot();
    final recentFuture = SpotifyLibrary.instance.recentlyPlayed();
    final featured = await featuredFuture;
    final chartList = await chartsFuture;
    final home = await homeFuture;
    final recent = await recentFuture;
    return SpotifyHomeSnapshot(
      account: account,
      featured: featured,
      charts: chartList,
      region: region,
      greeting: home?['greeting']?.toString() ?? '',
      homeSections:
          (home?['sections'] as List?)?.cast<Map<String, dynamic>>() ??
              const [],
      recent: recent,
    );
  }

  void dispose() => _client.close();
}
