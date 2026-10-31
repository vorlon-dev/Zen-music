// ZenMusic Desktop — synced lyrics via LRCLIB + YouTube metadata cleaner.
//
// PORTED FROM Echo Music (https://github.com/EchoMusicApp/Echo-Music),
// modules: metadata/src/.../cleaner/MetadataCleaner.kt + CleanerRules.kt and
// lrclib/src/main/kotlin/com/music/lrclib/LrcLib.kt. Dart port, faithful to
// the original strategies:
//   * 5-stage fallback search (cleaned title+primary artist → full artist →
//     title only → "artist title" query → title-only query → raw paste)
//   * ±5 s duration gate for synced picks (relaxed), similarity scoring
//     (contains → 0.8, else Levenshtein ratio), synced preferred over plain
//   * channel-junk scrub ("- Topic", "VEVO", " Records", " Official"),
//     bracket-tag extraction (junk vs feat vs version), artist splitting
//
// LRCLIB (https://lrclib.net) is a free, open, key-less lyrics database.
// Politeness: descriptive User-Agent, bounded strategies, Hive cache,
// inflight dedupe per track, session negative cache.
//
// ZERO new pubspec deps (dart:io HttpClient, dart:convert, hive — all present).
// R5 print policy: all debug prints use the [yt_lyrics] prefix.
//
// LEDGER: imports exactly ONE other ZenMusic file — kugou_lyrics.dart
// (SP-68 fallback provider, one-way; that file never imports back).
// Nothing else needs editing for it to compile.

import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';

import 'kugou_lyrics.dart'; // SP-68: KuGou fallback provider (one-way dep)

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// One timed lyric line (per-line timing for v1; word-sync is a v2 hook).
class LyricLine {
  const LyricLine(this.timeMs, this.text);

  /// Line start in milliseconds (already includes the file's [offset:] tag).
  final int timeMs;

  final String text;
}

/// Result of a lyrics lookup.
class LyricsData {
  const LyricsData({
    required this.trackName,
    required this.artistName,
    required this.synced,
    required this.plain,
    required this.instrumental,
    required this.wordSync,
  });

  final String trackName;
  final String artistName;

  /// Parsed timed lines, sorted by [LyricLine.timeMs]. Null = no synced LRC.
  final List<LyricLine>? synced;

  /// Untimed full text. Null = LRCLIB had none.
  final String? plain;

  final bool instrumental;

  /// LRCLIB reports word-level timestamps exist (v2 rendering hook).
  final bool wordSync;

  bool get hasSynced => synced != null && synced!.isNotEmpty;
  bool get hasAny => hasSynced || (plain != null && plain!.trim().isNotEmpty);

  Map<String, dynamic> toMap() => <String, dynamic>{
    'v': 1,
    'track': trackName,
    'artist': artistName,
    'synced': synced == null
        ? null
        : synced!.map((l) => '${l.timeMs}\u0001${l.text}').join('\u0002'),
    'plain': plain,
    'instrumental': instrumental,
    'wordSync': wordSync,
  };

  static LyricsData? fromMap(Map<dynamic, dynamic> m) {
    try {
      if ((m['v'] ?? 0) != 1) return null;
      List<LyricLine>? synced;
      final raw = m['synced'] as String?;
      if (raw != null && raw.isNotEmpty) {
        synced = raw
            .split('\u0002')
            .map((e) {
          final i = e.indexOf('\u0001');
          if (i <= 0) return null;
          final ms = int.tryParse(e.substring(0, i));
          if (ms == null) return null;
          return LyricLine(ms, e.substring(i + 1));
        })
            .whereType<LyricLine>()
            .toList()
          ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
        if (synced.isEmpty) synced = null;
      }
      return LyricsData(
        trackName: (m['track'] as String?) ?? '',
        artistName: (m['artist'] as String?) ?? '',
        synced: synced,
        plain: m['plain'] as String?,
        instrumental: (m['instrumental'] as bool?) ?? false,
        wordSync: (m['wordSync'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Metadata cleaner — port of Echo's MetadataCleaner (Kotlin) to Dart.
// ---------------------------------------------------------------------------

/// Result of cleaning a raw YouTube title/artist pair.
class CleanedMetadata {
  const CleanedMetadata({
    required this.rawTitle,
    required this.rawArtist,
    required this.cleanTitle,
    required this.primaryArtist,
    required this.cleanArtist,
    required this.featuredArtists,
    required this.versionLabel,
  });

  final String rawTitle;
  final String rawArtist;
  final String cleanTitle;
  final String primaryArtist;
  final String cleanArtist;
  final List<String> featuredArtists;

  /// Detected version tag ("Live", "Remix", "Slowed", …) or ''.
  final String versionLabel;
}

class MetadataCleaner {
  MetadataCleaner._();

  static final RegExp _junkWordRe = RegExp(
    r'(official\s+music\s+video|official\s+video|official\s+audio|music\s+video|'
    r'lyric\s+video|lyrics\s+video|official\s+visualizer|visualizer|video|audio|'
    r'mv|pv|hd|hq|4k|1080p|720p|60fps|uhd)',
    caseSensitive: false,
  );

  /// Junk words that may appear after a pipe/slash separator.
  static final RegExp _pipeTrailingJunkRe = RegExp(
    r'\b(official|video|visualizer|audio|mv|pv|lyrics?|remaster|hd|4k)\b',
    caseSensitive: false,
  );

  static final RegExp _versionRe = RegExp(
    r'\b(remix|flip|bootleg|vip|re-edit|club mix|dub|live|session|unplugged|'
    r'in concert|acoustic|orchestral|symphonic|remaster|remastered|deluxe|'
    r'anniversary|instrumental|karaoke|cover|radio edit|edit|extended|'
    r'slowed|reverb|sped up|nightcore)\b',
    caseSensitive: false,
  );

  static final RegExp _bracketRe = RegExp(
    r'\(([^()]*)\)|\[([^\[\]]*)\]|【([^【】]*)】|「([^「」]*)」',
  );

  static final RegExp _featPrefixRe = RegExp(
    r'^(?:feat\.?|ft\.?|featuring)\s+(.+)$',
    caseSensitive: false,
  );

  static final RegExp _inlineFeatRe = RegExp(
    r'(?:\s+|^)(?:feat\.?|ft\.?|featuring)\s+([^()\[\]\-|]+)',
    caseSensitive: false,
  );

  static final RegExp _pipeSepRe = RegExp(r'\s*(?:\||//)\s*(.*)$');
  static final RegExp _hashRe = RegExp(r'\s*#\w+');
  static final RegExp _artistTitleSplitRe = RegExp(r'\s+-\s+');
  static final RegExp _wsRe = RegExp(r'\s+');

  static const List<String> _artistSeparators = <String>[
    ' & ',
    ', ',
    ' feat. ',
    ' feat ',
    ' ft. ',
    ' ft ',
    ' featuring ',
    ' and ',
    ' x ',
  ];

  /// Port of [MetadataCleaner.clean].
  static CleanedMetadata clean(String rawTitle, [String rawArtist = '']) {
    final junkTags = <String>[];
    final featured = <String>[];

    var title = _sanitizeUnicode(rawTitle);
    var artist = _sanitizeUnicode(rawArtist);

    // Stage 1: "Artist - Title" prefix extraction from the title itself.
    final split = _splitArtistTitle(title, artist);
    title = split[0];
    if (split[1].trim().isNotEmpty) artist = split[1];

    // Stage 2: pipe/hashtag junk, bracket tags (feat / version / junk).
    final junkAndTitle = _extractTags(title, junkTags, featured);
    title = junkAndTitle[0];
    final version = _versionOf(rawTitle);

    // Stage 3: scrub channel junk from the artist, split multi-artists.
    artist = _scrubChannelJunk(artist);
    final artists = _splitArtists(artist);
    final primary = artists[0];
    featured.addAll(artists.skip(1));

    title = _normalizeTitle(title);

    return CleanedMetadata(
      rawTitle: rawTitle,
      rawArtist: rawArtist,
      cleanTitle: title,
      primaryArtist: primary,
      cleanArtist: artist.trim().isNotEmpty ? artist.trim() : primary,
      featuredArtists: featured
          .map((a) => a.trim())
          .where((a) =>
      a.isNotEmpty &&
          a.toLowerCase() != primary.trim().toLowerCase())
          .toList(),
      versionLabel: version,
    );
  }

  // --- stages --------------------------------------------------------------

  static String _sanitizeUnicode(String input) {
    var text = input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'[‘’´`]'), "'")
        .replaceAll(RegExp(r'[“”]'), '"');
    text = _stripSymbols(text);
    return text.trim();
  }

  /// Dart RegExp has no \p{So} — strip emoji/symbol planes via rune ranges.
  static String _stripSymbols(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      final strip = (r >= 0x1F000 && r <= 0x1FAFF) || // emoji, flags
          (r >= 0x2600 && r <= 0x27BF) || // misc symbols + dingbats
          (r >= 0x2B00 && r <= 0x2BFF) || // stars/arrows block
          (r >= 0xFE00 && r <= 0xFE0F) || // variation selectors
          r == 0x200D; // ZWJ
      if (!strip) sb.writeCharCode(r);
    }
    return sb.toString();
  }

  /// Returns [title, artist]; may move an "Artist - Title" prefix out of title.
  static List<String> _splitArtistTitle(String title, String artist) {
    final parts = title.split(_artistTitleSplitRe);
    if (parts.length < 2) return <String>[title, artist];

    final potentialArtist = parts.first.trim();
    final potentialTitle = parts.sublist(1).join(' - ').trim();
    if (potentialTitle.isEmpty) return <String>[title, artist];

    final rightIsJunkOrVersion = potentialTitle.startsWith('(') ||
        potentialTitle.startsWith('[') ||
        potentialTitle.startsWith('【') ||
        potentialTitle.startsWith('「') ||
        _junkWordRe.hasMatch(potentialTitle) ||
        _versionRe.hasMatch(potentialTitle);

    if (rightIsJunkOrVersion) return <String>[title, artist];

    if (artist.trim().isNotEmpty) {
      final related = potentialArtist.toLowerCase()
          .contains(artist.trim().toLowerCase()) ||
          artist.trim().toLowerCase().contains(potentialArtist.toLowerCase()) ||
          artist.trim().toLowerCase().contains('topic') ||
          artist.trim().toLowerCase().contains('vevo');
      if (!related) return <String>[title, artist];
    }
    // Both sides look like real names (or artist was empty) → adopt split.
    return <String>[potentialTitle, potentialArtist];
  }

  /// Returns [cleanedTitle, '']; appends to junkTags/featured.
  static List<String> _extractTags(
      String title, List<String> junkTags, List<String> featured) {
    var working = title;

    // "Song | Official Visualizer" / "Song // something" trailing junk.
    final pipe = _pipeSepRe.firstMatch(working);
    if (pipe != null) {
      final trailing = pipe.group(1)?.trim() ?? '';
      final isJunk = _junkWordRe.hasMatch(trailing) ||
          _pipeTrailingJunkRe.hasMatch(trailing);
      if (isJunk) {
        junkTags.add(trailing);
        working = working.substring(0, pipe.start).trim();
      }
    }

    // Hashtags: "#shorts" etc.
    working = working.replaceAll(_hashRe, ' ').trim();

    // Bracketed groups: (..), [..], 【..】, 「..」.
    for (final m in _bracketRe.allMatches(working).toList()) {
      final content =
      (m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
      if (content.isEmpty) continue;

      // (feat. Someone) / [ft. Someone]
      final feat = _featPrefixRe.firstMatch(content);
      if (feat != null) {
        featured.addAll(_splitArtists(feat.group(1)!.trim()));
        working = _replaceFirst(working, m.group(0)!, ' ');
        continue;
      }

      // (Live) / (Remix) / [Slowed + Reverb] …
      if (_versionRe.hasMatch(content)) {
        working = _replaceFirst(working, m.group(0)!, ' ');
        continue;
      }

      // (Official Music Video) / (Audio) / [4K] …
      if (_junkWordRe.hasMatch(content) || _junkWordRe.hasMatch(m.group(0)!)) {
        junkTags.add(content);
        working = _replaceFirst(working, m.group(0)!, ' ');
      }
    }

    // Inline "Song feat. Artist" without brackets.
    final inline = _inlineFeatRe.firstMatch(working);
    if (inline != null) {
      featured.addAll(_splitArtists((inline.group(1) ?? '').trim()));
      working = working.replaceRange(inline.start, inline.end, ' ').trim();
    }

    return <String>[working.trim(), ''];
  }

  /// Version label is taken from the ORIGINAL title (Echo keeps the first
  /// detected version even after stripping the bracket).
  static String _versionOf(String title) {
    final m = _versionRe.firstMatch(title);
    return m?.group(0)?.trim() ?? '';
  }

  static String _replaceFirst(String src, String from, String to) {
    final i = src.indexOf(from);
    if (i < 0) return src;
    return src.replaceRange(i, i + from.length, to);
  }

  static String _scrubChannelJunk(String artist) {
    var cleaned = artist.trim();
    if (cleaned.toLowerCase().endsWith('- topic')) {
      cleaned = cleaned.substring(0, cleaned.length - 7).trim();
    } else if (cleaned.toLowerCase().endsWith(' - topic')) {
      cleaned = cleaned.substring(0, cleaned.length - 8).trim();
    }
    if (cleaned.toLowerCase().endsWith('vevo')) {
      cleaned = _splitCamelCase(cleaned.substring(0, cleaned.length - 4).trim());
    }
    if (cleaned.toLowerCase().endsWith(' records')) {
      cleaned = cleaned.substring(0, cleaned.length - 8).trim();
    } else if (cleaned.toLowerCase().endsWith(' official')) {
      cleaned = cleaned.substring(0, cleaned.length - 9).trim();
    }
    return cleaned.trim();
  }

  static String _splitCamelCase(String text) {
    if (text.contains(' ') ||
        text == text.toUpperCase() ||
        text == text.toLowerCase()) {
      return text;
    }
    final sb = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (i > 0 && _isUpper(c) && _isLower(text[i - 1])) {
        sb.write(' ');
      }
      sb.write(c);
    }
    return sb.toString();
  }

  static bool _isUpper(String c) =>
      c != c.toLowerCase() && c == c.toUpperCase();
  static bool _isLower(String c) =>
      c != c.toUpperCase() && c == c.toLowerCase();

  /// Returns [primaryArtist, ...others].
  static List<String> _splitArtists(String artistString) {
    if (artistString.trim().isEmpty) return <String>[''];
    var tokens = <String>[artistString];
    for (final sep in _artistSeparators) {
      final next = <String>[];
      for (final t in tokens) {
        next.addAll(t.split(sep));
      }
      tokens = next;
    }
    final cleaned =
    tokens.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    if (cleaned.isEmpty) return <String>[''];
    return cleaned;
  }

  static String _normalizeTitle(String title) {
    var t = title.replaceAll(_wsRe, ' ').trim();
    while (t.isNotEmpty &&
        (t.endsWith('-') ||
            t.endsWith('–') ||
            t.endsWith('—') ||
            t.endsWith('|') ||
            t.endsWith('/'))) {
      t = t.substring(0, t.length - 1).trim();
    }
    return t;
  }
}

// ---------------------------------------------------------------------------
// LRC text parser
// ---------------------------------------------------------------------------

class LrcParser {
  LrcParser._();

  static final RegExp _tsRe =
  RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static final RegExp _wsRe = RegExp(r'\s+');

  /// Parses an LRC file body into sorted [LyricLine]s.
  /// Handles: multiple timestamps per line, `mm:ss` / `mm:ss.xx` / `mm:ss.xxx`,
  /// and the `[offset:±ms]` metadata tag.
  static List<LyricLine> parse(String lrc) {
    var offsetMs = 0;
    final out = <LyricLine>[];

    for (var raw in lrc.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final off = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false)
          .firstMatch(line);
      if (off != null) {
        final v = int.tryParse(off.group(1)!);
        if (v != null) offsetMs = v;
        continue;
      }

      final matches = _tsRe.allMatches(line).toList();
      if (matches.isEmpty) continue;

      // Text = everything after the LAST timestamp on the line.
      var text = line.substring(matches.last.end).trim();
      text = text.replaceAll(_wsRe, ' ');
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        var frac = 0;
        final fs = m.group(3);
        if (fs != null) {
          if (fs.length == 1) {
            frac = int.parse(fs) * 100; // ".x" → tenths of a second
          } else if (fs.length == 2) {
            frac = int.parse(fs) * 10; // ".xx" → hundredths
          } else {
            frac = int.parse(fs); // ".xxx" → milliseconds
          }
        }
        final ms = min * 60000 + sec * 1000 + frac - offsetMs;
        out.add(LyricLine(ms < 0 ? 0 : ms, text));
      }
    }
    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }
}

// ---------------------------------------------------------------------------
// LRCLIB client — port of Echo's LrcLib object.
// ---------------------------------------------------------------------------

class LyricsService {
  LyricsService._();

  static const String _host = 'lrclib.net';
  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  static HttpClient? _http;
  static Box? _box;

  /// Inflight dedupe: one network round per track even if the UI rebuilds.
  static final Map<String, Future<LyricsData?>> _inflight =
  <String, Future<LyricsData?>>{};

  /// Session negative cache: track keys already known to have no lyrics.
  static final Set<String> _misses = <String>{};

  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static Future<Box> _cache() async {
    _box ??= await Hive.openBox('lyrics_cache');
    return _box!;
  }

  /// Main entry. Safe to call on every rebuild — deduped + cached.
  ///
  /// [title]/[artist] may be raw YouTube strings; they are cleaned first.
  /// [durationMs] (track length) improves match quality via the ±5 s gate;
  /// pass null if unknown.
  static Future<LyricsData?> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
    bool forceRefresh = false,
  }) {
    final clean = MetadataCleaner.clean(title, artist);
    final key = 'v1|${clean.primaryArtist.toLowerCase()}|'
        '${clean.cleanTitle.toLowerCase()}|${album?.toLowerCase() ?? ''}';
    if (_inflight.containsKey(key)) return _inflight[key]!;
    final fut = _lookupImpl(clean, key, durationMs, album, forceRefresh)
        .whenComplete(() => _inflight.remove(key));
    _inflight[key] = fut;
    return fut;
  }

  static Future<LyricsData?> _lookupImpl(
      CleanedMetadata clean,
      String key,
      int? durationMs,
      String? album,
      bool forceRefresh,
      ) async {
    try {
      if (!forceRefresh) {
        final box = await _cache();
        final cached = box.get(key);
        if (cached is Map) {
          final d = LyricsData.fromMap(Map<String, dynamic>.from(cached));
          if (d != null) {
            return d;
          }
        }
      }
      if (_misses.contains(key)) return null;

      // Echo's 5-stage fallback chain (+ final stage: raw paste as-is).
      final strategies = <Map<String, String>>[
        if (album != null && album.trim().isNotEmpty)
          <String, String>{
            'track_name': clean.cleanTitle,
            'artist_name': clean.primaryArtist,
            'album_name': album.trim(),
          },
        <String, String>{
          'track_name': clean.cleanTitle,
          'artist_name': clean.primaryArtist,
        },
        if (clean.cleanArtist.toLowerCase() !=
            clean.primaryArtist.toLowerCase())
          <String, String>{
            'track_name': clean.cleanTitle,
            'artist_name': clean.cleanArtist,
          },
        <String, String>{'track_name': clean.cleanTitle},
        <String, String>{'q': '${clean.primaryArtist} ${clean.cleanTitle}'},
        <String, String>{'q': clean.cleanTitle},
        if (clean.rawTitle.trim().isNotEmpty)
          <String, String>{
            'track_name': clean.rawTitle.trim(),
            'artist_name': clean.rawArtist.trim(),
          },
      ];

      for (final params in strategies) {
        final tracks = await _search(params);
        if (tracks.isEmpty) continue;
        final best =
        _pickBest(tracks, durationMs, clean.cleanTitle, clean.primaryArtist);
        if (best == null) continue;
        final data = _toLyricsData(best);
        if (data != null && data.hasAny) {
          final box = await _cache();
          await box.put(key, data.toMap());
          print('[yt_lyrics] resolved "${data.trackName}" — '
              '${data.artistName} (synced: ${data.hasSynced}, '
              'wordSync: ${data.wordSync})');
          return data;
        }
      }

      // SP-68: KuGou fallback — the Chinese/Asian long tail LRCLIB
      // misses. Same cache box, same parser; a miss here finally lands
      // in the session negative cache below.
      try {
        final lrc = await KugouLyrics.lookup(
          title: clean.cleanTitle,
          artist: clean.primaryArtist,
          durationMs: durationMs,
          album: album,
        );
        if (lrc != null) {
          final synced = LrcParser.parse(lrc);
          if (synced.isNotEmpty) {
            final data = LyricsData(
              trackName: clean.cleanTitle,
              artistName: clean.primaryArtist,
              synced: synced,
              plain: null,
              instrumental: false,
              wordSync: false,
            );
            final box = await _cache();
            await box.put(key, data.toMap());
            print('[yt_lyrics] kugou fallback resolved '
                '"${data.trackName}" — ${data.artistName} '
                '(${synced.length} synced lines)');
            return data;
          }
        }
      } catch (e) {
        print('[yt_lyrics] kugou fallback failed: $e');
      }

      _misses.add(key);
      print('[yt_lyrics] no lyrics found for "${clean.cleanTitle}" / '
          '"${clean.primaryArtist}"');
      return null;
    } catch (e) {
      print('[yt_lyrics] lookup failed: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _search(
      Map<String, String> params) async {
    try {
      final uri = Uri.https(_host, '/api/search', params);
      final req = await _client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return const <Map<String, dynamic>>[];
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! List) return const <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final synced = (m['syncedLyrics'] as String?)?.trim() ?? '';
        final plain = (m['plainLyrics'] as String?)?.trim() ?? '';
        if (synced.isEmpty && plain.isEmpty) continue; // Echo: lyrics-only filter
        out.add(m);
      }
      return out;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// Echo scoring: duration gate (±5 s relaxed) + similarity + synced bonus.
  static Map<String, dynamic>? _pickBest(
      List<Map<String, dynamic>> tracks,
      int? durationMs,
      String cleanTitle,
      String cleanArtist,
      ) {
    Map<String, dynamic>? best;
    var bestScore = -1.0;
    var bestDiff = 1 << 30;

    for (final t in tracks) {
      final tDurMs = (((t['duration'] as num?) ?? 0).round()) * 1000;
      final diff = durationMs == null ? 0 : (tDurMs - durationMs).abs();
      if (durationMs != null && diff > 15000) continue; // wrong-song guard

      final hasSynced = ((t['syncedLyrics'] as String?) ?? '').trim().isNotEmpty;
      final sim = (_similarity(cleanTitle, (t['trackName'] as String?) ?? '') +
          _similarity(cleanArtist, (t['artistName'] as String?) ?? '')) /
          2.0;
      var score = sim + (hasSynced ? 0.25 : 0.0);
      if (durationMs != null) {
        if (diff <= 5000) {
          score += 0.6;
        } else if (diff <= 12000) {
          score += 0.1;
        }
      }

      if (score > bestScore + 1e-9 ||
          ((score - bestScore).abs() <= 1e-9 && diff < bestDiff)) {
        best = t;
        bestScore = score;
        bestDiff = diff;
      }
    }
    return best;
  }

  static LyricsData? _toLyricsData(Map<String, dynamic> t) {
    try {
      final syncedRaw = (t['syncedLyrics'] as String?)?.trim();
      final plainRaw = (t['plainLyrics'] as String?)?.trim();
      final synced = (syncedRaw == null || syncedRaw.isEmpty)
          ? null
          : LrcParser.parse(syncedRaw);
      return LyricsData(
        trackName: (t['trackName'] as String?) ?? '',
        artistName: (t['artistName'] as String?) ?? '',
        synced: (synced != null && synced.isNotEmpty) ? synced : null,
        plain: (plainRaw == null || plainRaw.isEmpty) ? null : plainRaw,
        instrumental: (t['instrumental'] as bool?) ?? false,
        wordSync: (t['hasWordSync'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static double _similarity(String a, String b) {
    final s1 = a.trim().toLowerCase();
    final s2 = b.trim().toLowerCase();
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    if (s1.contains(s2) || s2.contains(s1)) return 0.8;
    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    return 1.0 - (_levenshtein(s1, s2) / maxLen);
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    final cur = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      cur[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        var minVal = prev[j + 1] + 1;
        if (cur[j] + 1 < minVal) minVal = cur[j] + 1;
        if (prev[j] + cost < minVal) minVal = prev[j] + cost;
        cur[j + 1] = minVal;
      }
      prev = List<int>.of(cur);
    }
    return prev[b.length];
  }
}