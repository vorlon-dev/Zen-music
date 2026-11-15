// ZenMusic · vorlon-dev
//
// Keyless Instagram reel discovery through public search engines.
//
// The song drives everything: for the playing song this builds related-tag
// queries (song videos / edits / dance videos — the categories a song gets
// reels under) and searches them across Bing / DuckDuckGo in parallel. Both
// direct and engine-wrapped result links are decoded, every candidate's
// result text is fuzzy-scored against the song, and only the top matches
// come back. Best-effort by design: any engine failure simply yields fewer
// candidates — never an error, never a stall.
//
// Put at: lib/desktop/instagram_canvas/reel_discovery.dart

import 'dart:convert';
import 'dart:io';

import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fw;

import 'instagram_canvas_config.dart';

/// One discovered Instagram reel candidate.
class ReelCandidate {
  const ReelCandidate({
    required this.shortcode,
    required this.title,
    required this.score,
    this.isReel = true,
  });

  /// Instagram shortcode, e.g. `DfuUTROyNNV`.
  final String shortcode;

  /// Search-result text this candidate was found with (for scoring/debug).
  final String title;

  /// Fuzzy match score against the song (0-100).
  final int score;

  /// True when the source URL was a /reel/ (9:16 video). /p/ posts are
  /// accepted too (widens recall) — a photo post fails validation later and
  /// reel-kind candidates score slightly higher.
  final bool isReel;
}

class ReelDiscovery {
  ReelDiscovery._();

  static const _shortcodePattern =
      r'instagram\.com/(reels?|p)/([A-Za-z0-9_-]{5,25})';
  static final RegExp _shortcodeRe = RegExp(_shortcodePattern);
  static final RegExp _reelUrlInTextRe =
      RegExp('https?://(?:www\\.)?$_shortcodePattern');

  static final RegExp _bingWrappedRe2 =
      RegExp(r'&u=a1([A-Za-z0-9_\-%]{20,})');
  static final RegExp _ddgWrappedRe =
      RegExp(r'uddg=([A-Za-z0-9_%\-\.]{10,400})');

  /// A minimal browser-like mobile UA — search engines are friendlier to it.
  static const _ua =
      'Mozilla/5.0 (Linux; Android 11; Redmi Note 9) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// Build the per-song related-tag queries.
  ///
  /// Everything comes from the song itself — its title and artist — with
  /// the reel categories (edit / song video / dance video) as suffixes.
  /// No fixed keyword list: a different song always produces different
  /// queries.
  static List<String> buildQueries(String title, String artist) {
    final t = _searchTerm(title);
    final a = _searchTerm(artist);
    final queries = <String>[];
    void add(String site, String terms, String tag) {
      final core = '$terms $tag'.trim();
      final q = '$site "${core.replaceAll('"', ' ').trim()}"'
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (t.isNotEmpty && !queries.contains(q)) queries.add(q);
    }

    const site = 'site:instagram.com/reel';

    // Artist present -> artist-anchored queries first (most specific).
    if (a.isNotEmpty && !_sameText(t, a)) {
      add(site, '$t $a', 'edit');
      add(site, '$t $a', 'song video');
      add(site, '$t $a', 'dance video');
    }
    // Title-only variants (also cover noisy/unknown artist tags).
    add(site, t, 'edit');
    add(site, t, 'song video');
    add(site, t, 'dance video');

    // Two unquoted variants — engines that drop the site: operator still
    // see the domain words plus the song name.
    if (queries.length < InstagramCanvasConfig.maxDiscoveryQueries) {
      _addPlain(queries, '$t $a instagram reels edit');
    }
    if (queries.length < InstagramCanvasConfig.maxDiscoveryQueries) {
      _addPlain(queries, '$t instagram reels edit');
    }

    return queries.take(InstagramCanvasConfig.maxDiscoveryQueries).toList();
  }

  static void _addPlain(List<String> queries, String q) {
    final qq = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (qq.length >= 8 && !queries.contains(qq)) queries.add(qq);
  }

  /// Discover song-related public reel candidates. Never throws; returns an
  /// empty list when every engine fails or nothing scores high enough.
  static Future<List<ReelCandidate>> findReels({
    required String title,
    required String artist,
  }) async {
    if (!InstagramCanvasConfig.enabled) return const [];
    if (title.trim().isEmpty) return const [];

    final queries = buildQueries(title, artist);
    if (queries.isEmpty) return const [];

    final deadline =
        DateTime.now().add(InstagramCanvasConfig.discoveryBudget);

    // Queries run in small WAVES instead of all at once. Firing 8 parallel
    // searches per song (and Discover resolves many songs) flooded the
    // resolver service: it rate-limited its own search engines and answered
    // empty. Stop as soon as enough good candidates exist.
    final found = <String, ReelCandidate>{};
    const wave = 2;
    try {
      for (var i = 0; i < queries.length; i += wave) {
        if (DateTime.now().isAfter(deadline)) break;
        final slice = queries.skip(i).take(wave);
        final results = await Future.wait(
          slice.map((q) => _runQuery(q, title, artist, deadline)),
        ).timeout(InstagramCanvasConfig.discoveryBudget);
        for (final map in results) {
          map.forEach((code, cand) {
            final existing = found[code];
            if (existing == null || cand.score > existing.score) {
              found[code] = cand;
            }
          });
        }
        final good = found.values
            .where((c) => c.score >= InstagramCanvasConfig.minReelScore)
            .length;
        if (good >= InstagramCanvasConfig.maxReelResolutions) break;
      }
    } catch (_) {
      // Budget hit / network down — use whatever was found so far.
    }

    final list = found.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list.take(InstagramCanvasConfig.maxReelCandidates).toList();
  }

  /// Run one query: the deployed service's search endpoint first (clean
  /// server IP, 30-min per-query cache), then the on-device engines until
  /// enough candidates came back. Everything fail-soft.
  static Future<Map<String, ReelCandidate>> _runQuery(
    String query,
    String title,
    String artist,
    DateTime deadline,
  ) async {
    final found = <String, ReelCandidate>{};

    // 1. Service-side search (v3 endpoint).
    if (InstagramCanvasConfig.serviceSearchEnabled) {
      try {
        final uri = '${InstagramCanvasConfig.serviceBase}'
            '/api/search?q=${Uri.encodeQueryComponent(query)}&limit=12';
        final body = await _fetchPlain(
            uri, InstagramCanvasConfig.serviceSearchTimeout);
        _collectServiceResults(body, title, artist, found);
      } catch (_) {
        // Service down / busy — on-device engines below take over.
      }
    }

    // 2. On-device engines (Bing, DDG html, DDG lite).
    for (final engineUrl in [
      InstagramCanvasConfig.bingSearchUrl,
      InstagramCanvasConfig.ddgHtmlSearchUrl,
      InstagramCanvasConfig.ddgLiteSearchUrl,
    ]) {
      if (DateTime.now().isAfter(deadline)) break;
      if (found.length >= InstagramCanvasConfig.candidatesPerQuery) break;
      try {
        final uri =
            engineUrl.replaceAll('{query}', Uri.encodeQueryComponent(query));
        final body = await _fetch(uri, deadline);
        if (body.isEmpty) continue;
        _collectCandidates(body, title, artist, found);
      } catch (_) {
        // Engine failed — move to the next one, never stall.
      }
    }
    return found;
  }

  /// Simple bounded GET (used for the service's JSON search endpoint).
  static Future<String> _fetchPlain(String uri, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = _ua;
    try {
      final req = await client
          .getUrl(Uri.parse(uri))
          .timeout(timeout);
      req.headers.set('accept', 'application/json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>().catchError((_) {});
        return '';
      }
      final chunks = <String>[];
      await for (final chunk
          in res.transform(utf8.decoder).timeout(timeout)) {
        chunks.add(chunk);
      }
      return chunks.join();
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  /// Parse + score the service /api/search JSON response.
  static void _collectServiceResults(
    String body,
    String title,
    String artist,
    Map<String, ReelCandidate> out,
  ) {
    if (body.isEmpty) return;
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return;
    }
    if (json is! Map || json['results'] is! List) return;
    for (final entry in json['results'] as List) {
      if (entry is! Map) continue;
      final code = entry['code']?.toString() ?? '';
      if (code.length < 5) continue;
      final text = entry['text']?.toString() ?? '';
      final isReel = entry['isReel'] == true;
      var score = _scoreSong(_cleanText(text), title, artist);
      if (!isReel) score -= 6; // /p/ posts: photo posts fail validation later
      final existing = out[code];
      if (existing == null || score > existing.score) {
        out[code] = ReelCandidate(
          shortcode: code,
          title: text.length > 140 ? text.substring(0, 140) : text,
          score: score,
          isReel: isReel,
        );
      }
    }
  }

  /// Fetch one engine page within the stage deadline.
  static Future<String> _fetch(String uri, DateTime deadline) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..userAgent = _ua;
    try {
      final req = await client
          .getUrl(Uri.parse(uri))
          .timeout(InstagramCanvasConfig.searchTimeout);
      req.headers.set('accept',
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
      req.headers.set('accept-language', 'en-US,en;q=0.9');
      final res = await req.close().timeout(InstagramCanvasConfig.searchTimeout);
      if (res.statusCode != 200) {
        await res.drain<void>().catchError((_) {});
        return '';
      }
      final remaining = deadline.difference(DateTime.now());
      final budget = remaining > Duration.zero
          ? remaining
          : const Duration(milliseconds: 200);
      final chunks = <String>[];
      // Budget exceeded -> TimeoutException -> caught below -> ''.
      await for (final chunk
          in res.transform(utf8.decoder).timeout(budget)) {
        chunks.add(chunk);
      }
      return chunks.join();
    } catch (_) {
      return '';
    } finally {
      client.close(force: true);
    }
  }

  /// Extract + score candidates from one engine's HTML.
  static void _collectCandidates(
    String body,
    String title,
    String artist,
    Map<String, ReelCandidate> out,
  ) {
    final textSpots = <String>[];

    // 1. Direct reel URLs in hrefs / text.
    for (final m in _reelUrlInTextRe.allMatches(body)) {
      textSpots.add(_contextText(body, m.start, m.end));
    }

    // 2. Bing-wrapped links: /ck/a?...&u=a1<base64url of the real URL>.
    for (final m in _bingWrappedRe2.allMatches(body)) {
      final decoded = _tryDecodeBase64Url(m.group(1) ?? '');
      if (decoded == null) continue;
      final reel = _reelUrlInTextRe.firstMatch(decoded);
      if (reel == null) continue;
      textSpots.add(_wrappedContextText(body, m.start, decoded, reel.group(1)!));
    }

    // 3. DDG-wrapped links: ...uddg=<url-encoded real url>&rut=...
    for (final m in _ddgWrappedRe.allMatches(body)) {
      final decoded = Uri.decodeComponent(m.group(1) ?? '');
      final reel = _reelUrlInTextRe.firstMatch(decoded);
      if (reel == null) continue;
      textSpots.add(_wrappedContextText(body, m.start, decoded, reel.group(1)!));
    }

    // Score every spot once per shortcode (keep the best score).
    for (final spot in textSpots) {
      final reel = _reelUrlInTextRe.firstMatch(spot) ??
          _shortcodeRe.firstMatch(spot);
      if (reel == null) continue;
      // group(1) = kind (reel/reels/p), group(2) = the shortcode itself.
      final isReel = (reel.group(1) ?? 'reel').startsWith('reel');
      final code = reel.group(2)!;
      if (code.length < 5) continue;

      // Strip the URL itself from the scoring text so the shortcode's
      // base36 characters cannot inflate the score.
      final scoringText = _cleanText(
          spot.replaceAll(_reelUrlInTextRe, ' ').replaceAll(_shortcodeRe, ' '));

      var score = _scoreSong(scoringText, title, artist);
      if (!isReel) score -= 6; // /p/ posts: photo posts fail validation later
      final existing = out[code];
      if (existing == null || score > existing.score) {
        out[code] = ReelCandidate(
          shortcode: code,
          title: scoringText.length > 140
              ? scoringText.substring(0, 140)
              : scoringText,
          score: score,
          isReel: isReel,
        );
      }
    }
  }

  /// Raw HTML window around a match (for context/title extraction).
  static String _contextText(String body, int start, int end) {
    final from = (start - 400).clamp(0, body.length);
    final to = (end + 400).clamp(0, body.length);
    return body.substring(from, to);
  }

  /// Context around a wrapped link: prefer the decoded URL + nearby anchors.
  static String _wrappedContextText(
      String body, int start, String decodedUrl, String code) {
    final from = (start - 400).clamp(0, body.length);
    final to = (start + 400).clamp(0, body.length);
    return '$decodedUrl ${body.substring(from, to)}';
  }

  /// Strip tags/entities and squash whitespace.
  static String _cleanText(String raw) {
    final noTags = raw.replaceAll(RegExp(r'<[^>]{1,200}>'), ' ');
    final decoded = noTags
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return decoded
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Fuzzy score of the song against a candidate's result text.
  static int _scoreSong(String text, String title, String artist) {
    if (text.isEmpty) return 0;
    final t = _searchTerm(title);
    final a = _searchTerm(artist);
    final query = (t + ' ' + a).trim().toLowerCase();
    final lower = text.toLowerCase();

    // Result text is usually a long caption / page title, so a plain
    // ratio() against the short song query scored real matches far below
    // minReelScore. partial / token-set ratios compare the song AGAINST
    // the part of the text that matches it.
    var best = fw.ratio(query, lower);
    final partial = fw.partialRatio(query, lower);
    if (partial > best) best = partial;
    final tokenSet = fw.tokenSetRatio(query, lower);
    if (tokenSet > best) best = tokenSet;
    if (t.isNotEmpty) {
      final tl = t.toLowerCase();
      final titleOnly = fw.partialRatio(tl, lower);
      // Title found verbatim in the result text: strong signal, but only
      // trust it for titles long enough not to match by accident.
      if (tl.length >= 5 && lower.contains(tl)) {
        if (best < 78) best = 78;
      } else if (titleOnly > best) {
        best = titleOnly;
      }
    }
    // Artist presence is a strong relevance signal.
    if (a.isNotEmpty && lower.contains(a.toLowerCase())) {
      best += 8;
    }
    return best.clamp(0, 100).toInt();
  }

  /// Search-engine-safe term: drop noise (brackets, feats, quotes).
  static String _searchTerm(String raw) {
    var s = raw;
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), ' ');
    s = s.replaceAll(RegExp(r'\b(feat|ft|official|video|audio|lyrics?|hd|4k)\b',
            caseSensitive: false),
        ' ');
    s = s.replaceAll('"', ' ').trim();
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _sameText(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Bing encodes real result URLs as base64url after the `a1` prefix.
  static String? _tryDecodeBase64Url(String raw) {
    var s = raw.replaceAll('-', '+').replaceAll('_', '/');
    final pad = s.length % 4;
    if (pad > 0) s += '=' * (4 - pad);
    try {
      return utf8.decode(base64.decode(s), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}
