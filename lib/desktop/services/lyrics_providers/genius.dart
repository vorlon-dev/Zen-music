// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — Genius.kt

import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'lyric_doc.dart';

/// Genius: untimed text, scraped. A last-resort fallback for tracks no timed
/// provider has. Searches the open multi-search endpoint (no key), picks the
/// best song hit and reads the lyrics containers from the page.
///
/// The User-Agent is deliberately not a browser: Genius sits behind
/// Cloudflare, which challenges a browser UA whose TLS fingerprint does not
/// back the claim (BitChord measured a 403 for Chrome's UA and a 200 for a
/// plain one).
class Genius {
  Genius._();

  static const String _agent = 'ZenMusic (https://github.com/vorlon-dev/Zen-music)';

  static final RegExp _titleSeparator = RegExp(r'\s*[-–—:]\s*');
  static final RegExp _decorative = RegExp(r'[♪♫★☆【】《》「」~_]');
  static final RegExp _producerTags =
      RegExp(r'\b(?:prod(?:uced)?\.?(?:\s+by)?)\s+.*$', caseSensitive: false);
  static final RegExp _noise = RegExp(
    r'\s*[(\[]\s*(?:from|feat\.?|ft\.?|featuring|with|prod\.?|produced by|official|lyrical|video|audio|remix|music video|visualizer|mv|hd|4k|hq|full song)[^)\]]*[)\]]|'
    r'\s*\b(?:official\s+(?:music\s+)?(?:video|audio)|lyrical(?:\s+video)?|full\s+song|4k\s+video|hd\s+video|music\s+video)\b',
    caseSensitive: false,
  );
  static final RegExp _bracketed = RegExp(r'\s*[(\[].*?[)\]]');
  static final RegExp _nonAlnum = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _youMightAlsoLike =
      RegExp(r'\d*You might also like', caseSensitive: false);
  static final RegExp _trailingEmbed =
      RegExp(r'\d*Embed\s*$', caseSensitive: false);

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _agent
    ..connectionTimeout = const Duration(seconds: 4);

  static void _log(String m) => print('[genius] $m');

  /// Never throws; null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final text = await _scrape(q.title, q.artist);
      if (text == null || text.trim().isEmpty) return null;
      return LyricDoc(payload: text, wordSynced: false, isPlain: true);
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static Future<String?> _scrape(String title, String artist) async {
    final cleanTitle = _cleanQuery(title);
    final cleanArtist = _cleanQuery(artist);

    // "Artist - Title" in the title field: pull both parts apart.
    List<String>? parts;
    if (_titleSeparator.hasMatch(cleanTitle)) {
      final m = _titleSeparator.firstMatch(cleanTitle)!;
      parts = [
        cleanTitle.substring(0, m.start),
        cleanTitle.substring(m.end),
      ];
    }
    bool same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

    String extractedTitle;
    if (parts != null && same(parts[0], cleanArtist)) {
      extractedTitle = parts[1].trim();
    } else if (parts != null && same(parts[1], cleanArtist)) {
      extractedTitle = parts[0].trim();
    } else if (parts != null && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
      extractedTitle = parts[1].trim();
    } else {
      extractedTitle = cleanTitle;
    }

    String extractedArtist;
    if (parts != null && (same(parts[0], cleanArtist) || same(parts[1], cleanArtist))) {
      extractedArtist = cleanArtist;
    } else if (parts != null && cleanArtist.isEmpty) {
      extractedArtist = parts[0].trim();
    } else {
      extractedArtist = cleanArtist;
    }

    final withoutBrackets = extractedTitle
        .replaceAll(_bracketed, ' ')
        .replaceAll(_nonAlnum, ' ')
        .replaceAll(_spaces, ' ')
        .trim();

    final attempts = <_Attempt>[];
    if (extractedArtist.isNotEmpty && extractedTitle.isNotEmpty) {
      attempts.add(_Attempt('$extractedArtist $extractedTitle'.trim(),
          extractedTitle, extractedArtist));
    }
    if (extractedArtist.isNotEmpty &&
        withoutBrackets.isNotEmpty &&
        withoutBrackets != extractedTitle) {
      attempts.add(_Attempt('$extractedArtist $withoutBrackets'.trim(),
          withoutBrackets, extractedArtist));
    }
    if (cleanTitle != extractedTitle) {
      attempts.add(_Attempt('$cleanArtist $cleanTitle'.trim(), cleanTitle, cleanArtist));
      attempts.add(_Attempt(cleanTitle, extractedTitle, extractedArtist));
    }
    if (withoutBrackets.isNotEmpty) {
      attempts.add(_Attempt(withoutBrackets, withoutBrackets, extractedArtist));
    } else if (extractedTitle.isNotEmpty) {
      attempts.add(_Attempt(extractedTitle, extractedTitle, extractedArtist));
    }

    final seen = <String>{};
    String? songUrl;
    for (final a in attempts) {
      if (!seen.add(a.query)) continue;
      songUrl = await _searchSongUrl(a);
      if (songUrl != null) break;
    }
    if (songUrl == null) return null;

    final page = await _get(songUrl);
    if (page == null || page.trim().isEmpty) return null;
    return parseHtml(page);
  }

  static Future<String?> _searchSongUrl(_Attempt a) async {
    final body = await _get(
        'https://genius.com/api/search/multi?q=${Uri.encodeQueryComponent(a.query)}');
    if (body == null) return null;
    try {
      final root = jsonDecode(body);
      if (root is! Map) return null;
      final response = root['response'];
      if (response is! Map) return null;
      final sections = response['sections'];
      if (sections is! List) return null;
      Map? songSection;
      for (final s in sections) {
        if (s is Map && s['type'] == 'song') {
          songSection = s;
          break;
        }
      }
      final hits = songSection?['hits'];
      if (hits is! List) return null;
      final candidates = <Map>[
        for (final h in hits)
          if (h is Map && h['result'] is Map) h['result'] as Map,
      ];
      final best = _bestMatch(candidates, a.title, a.artist);
      final url = best?['url'];
      return url is String ? url : null;
    } catch (e) {
      _log('search parse failed: $e');
      return null;
    }
  }

  static Map? _bestMatch(List<Map> candidates, String targetTitle, String targetArtist) {
    final nt = targetTitle.toLowerCase();
    final na = targetArtist.toLowerCase();
    Map? best;
    var bestScore = 0;
    for (final item in candidates) {
      final title = ((item['title'] as String?) ?? '').toLowerCase();
      final artist = ((item['artist_names'] as String?) ?? '').toLowerCase();
      final titleMatches =
          nt.isNotEmpty && (title == nt || title.contains(nt) || nt.contains(title));
      final artistMatches =
          na.isNotEmpty && (artist == na || artist.contains(na) || na.contains(artist));
      if (!titleMatches && !artistMatches) continue;

      var score = 0;
      if (title == nt) {
        score += 50;
      } else if (titleMatches) {
        score += 25;
      }
      if (artistMatches) score += artist == na ? 40 : 20;

      final path = ((item['path'] as String?) ?? '').toLowerCase();
      if (path.contains('translation') && !nt.contains('translation')) score -= 30;
      if (path.contains('türkçe') || path.contains('polskie-tlumaczenie')) score -= 40;
      if (path.contains('tracklist') || path.contains('album-art')) score -= 50;
      if (score <= 0) continue;
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best;
  }

  /// Reads the lyrics containers out of a Genius song page, keeping stanza
  /// breaks and `[Verse 1]`-style headers. Null when none are found.
  static String? parseHtml(String page) {
    try {
      final doc = html_parser.parse(page);
      var containers = doc.querySelectorAll('div[data-lyrics-container="true"]');
      if (containers.isEmpty) containers = doc.querySelectorAll('div.lyrics');
      if (containers.isEmpty) return null;

      final out = StringBuffer();
      for (final c in containers) {
        for (final junk in c.querySelectorAll(
            '[data-exclude-from-selection="true"], .LyricsHeader__Container, '
            '.SongBioPreview__Container, .InreadAd__Container, button, script, style')) {
          junk.remove();
        }
        final text = _textWithBreaks(c);
        if (text.trim().isNotEmpty) out.write('$text\n');
      }
      final raw = out.toString();
      if (raw.trim().isEmpty) return null;
      final text = textToLines(stripArtifacts(raw));
      return text.isEmpty ? null : text;
    } catch (e) {
      _log('parse failed: $e');
      return null;
    }
  }

  static String _textWithBreaks(dom.Node node) {
    final b = StringBuffer();
    void walk(dom.Node n) {
      if (n is dom.Text) {
        b.write(n.text);
      } else if (n is dom.Element) {
        if (n.localName == 'br') {
          b.write('\n');
          return;
        }
        if (n.localName == 'p') b.write('\n');
        for (final child in n.nodes) {
          walk(child);
        }
      }
    }

    walk(node);
    return b.toString();
  }

  static String stripArtifacts(String raw) => raw
      .replaceAll(' ', ' ')
      .replaceAll('​', ' ')
      .replaceAll('﻿', ' ')
      .replaceAll(_youMightAlsoLike, '')
      .trim()
      .replaceAll(_trailingEmbed, '')
      .trim();

  /// Trims lines, collapses runs of blanks to one gap, drops edge gaps.
  static String textToLines(String text) {
    final result = <String>[];
    var lastWasGap = false;
    for (final raw in text.split('\n')) {
      final line = raw.trim().replaceAll(_trailingEmbed, '').trim();
      if (line.isEmpty) {
        if (!lastWasGap && result.isNotEmpty) {
          result.add('');
          lastWasGap = true;
        }
      } else {
        result.add(line);
        lastWasGap = false;
      }
    }
    while (result.isNotEmpty && result.last.isEmpty) {
      result.removeLast();
    }
    return result.join('\n');
  }

  static String _cleanQuery(String text) {
    final cleaned = text
        .replaceAll(_decorative, ' ')
        .replaceAll(_noise, ' ')
        .replaceAll(_producerTags, ' ');
    final cut = cleaned.split(' | ').first.replaceAll(_spaces, ' ').trim();
    return cut.isEmpty ? text.trim() : cut;
  }

  static Future<String?> _get(String url) async {
    try {
      final req = await _client.getUrl(Uri.parse(url));
      req.headers
        ..set(HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    } catch (e) {
      _log('GET failed: $e');
      return null;
    }
  }
}

class _Attempt {
  const _Attempt(this.query, this.title, this.artist);
  final String query;
  final String title;
  final String artist;
}
