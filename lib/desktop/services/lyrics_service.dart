// ZenMusic · vorlon-dev

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:hive/hive.dart';

import 'better_lyrics.dart';
import 'kugou_lyrics.dart';
import 'lyrics_providers/lyric_doc.dart';
import 'lyrics_providers/lyrics_repository.dart';


class LyricWord {
  const LyricWord({
    required this.timeMs,
    required this.durationMs,
    required this.text,
  });

  /// Word start in milliseconds.
  final int timeMs;

  /// Word duration in milliseconds (0 = unknown).
  final int durationMs;

  /// Word text (trailing spacing included where the source carries it).
  final String text;
}

class LyricLine {
  const LyricLine(this.timeMs, this.text,
      {this.durationMs = 0, this.words = const []});

  /// Line start in milliseconds (already includes the file's [offset:] tag).
  final int timeMs;

  final String text;

  /// Line duration in milliseconds (0 = unknown — legacy cache rows;
  /// [LyricsData.hydrate] fills it from the next line).
  final int durationMs;

  /// Word timings. REAL stamps when the source is word-synced (TTML
  /// spans / karaoke rows / enhanced LRC); proportional interpolation
  /// when the source is plain line-synced (karaoke wipe sugar); empty
  /// only for legacy un-hydrated rows.
  final List<LyricWord> words;

  bool get hasWords => words.isNotEmpty;

  /// End of the line's timed content in ms (words may run past text).
  int get endMs {
    var e = timeMs + durationMs;
    for (final w in words) {
      final we = w.timeMs + w.durationMs;
      if (we > e) e = we;
    }
    return e;
  }
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

  /// True when any synced line carries REAL word timings.
  bool get hasWordTimings => synced?.any((l) => l.hasWords) ?? false;

  LyricsData hydrate() {
    if (synced == null || synced!.isEmpty) return this;
    final lines = LrcParser.hydrateLines(synced!);
    if (identical(lines, synced)) return this;
    return LyricsData(
      trackName: trackName,
      artistName: artistName,
      synced: lines,
      plain: plain,
      instrumental: instrumental,
      wordSync: wordSync,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'v': 2,
    'track': trackName,
    'artist': artistName,
    'synced': synced == null
        ? null
        : synced!.map(_encodeLine).join('\u0002'),
    'plain': plain,
    'instrumental': instrumental,
    'wordSync': wordSync,
  };

  /// v2 row: timeMs \u0001 durMs \u0001 wordSpec \u0001 text — wordSpec is
  /// `start,dur,base64(text)` joined by `|` (empty when no words).
  /// v1 rows (timeMs \u0001 text) still parse.
  static String _encodeLine(LyricLine l) {
    final spec = l.words
        .map((w) => '${w.timeMs},${w.durationMs},'
            '${base64Encode(utf8.encode(w.text))}')
        .join('|');
    return '${l.timeMs}\u0001${l.durationMs}\u0001$spec\u0001${l.text}';
  }

  static LyricsData? fromMap(Map<dynamic, dynamic> m) {
    try {
      final v = (m['v'] ?? 1);
      if (v is! int || (v != 1 && v != 2)) return null;
      List<LyricLine>? synced;
      final raw = m['synced'] as String?;
      if (raw != null && raw.isNotEmpty) {
        synced = raw
            .split('\u0002')
            .map(_decodeLine)
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

  static LyricLine? _decodeLine(String e) {
    final f = e.split('\u0001');
    if (f.length >= 4) {
      final ms = int.tryParse(f[0]);
      if (ms == null) return null;
      final dur = int.tryParse(f[1]) ?? 0;
      final words = <LyricWord>[];
      if (f[2].isNotEmpty) {
        for (final ws in f[2].split('|')) {
          final p = ws.split(',');
          if (p.length != 3) continue;
          final wStart = int.tryParse(p[0]);
          final wDur = int.tryParse(p[1]);
          if (wStart == null || wDur == null) continue;
          try {
            words.add(LyricWord(
              timeMs: wStart,
              durationMs: wDur,
              text: utf8.decode(base64Decode(p[2])),
            ));
          } catch (_) {
            continue;
          }
        }
      }
      return LyricLine(ms, f[3], durationMs: dur, words: words);
    }
    // v1 row: timeMs \u0001 text.
    final i = e.indexOf('\u0001');
    if (i <= 0) return null;
    final ms = int.tryParse(e.substring(0, i));
    if (ms == null) return null;
    return LyricLine(ms, e.substring(i + 1));
  }
}


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


class LrcParser {
  LrcParser._();

  static final RegExp _tsRe =
  RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  static final RegExp _wsRe = RegExp(r'\s+');

  /// Enhanced-LRC inline word stamps: `<mm:ss.xx>`, `<mm:ss:xx>`.
  static final RegExp _wordStampRe =
      RegExp(r'<(\d{1,3}):(\d{2})[.:](\d{2,3})>');

  static List<LyricLine> parse(String lrc) {
    var offsetMs = 0;
    final entries = <({int timeMs, String body})>[];

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

      // Body = everything after the LAST [timestamp]; inline word
      // stamps (<mm:ss.xx>) survive in the body for the word run pass.
      var body = line.substring(matches.last.end).trim();
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
        entries.add((timeMs: ms < 0 ? 0 : ms, body: body));
      }
    }
    entries.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    final out = <LyricLine>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final nextTime = i + 1 < entries.length ? entries[i + 1].timeMs : null;

      // 1) real word stamps?
      final words = _parseWordRuns(e.body, e.timeMs, nextTime);
      if (words.isNotEmpty) {
        final lineStart = math.min(e.timeMs, words.first.timeMs);
        final dur = (nextTime != null
                ? (nextTime - lineStart)
                : 4000)
            .clamp(80, 20000);
        final display = e.body.replaceAll(_wordStampRe, '').trim();
        final joined = words.map((w) => w.text).join(' ').trim();
        out.add(LyricLine(
          lineStart,
          display.isNotEmpty && display.length >= joined.length
              ? display
              : joined,
          durationMs: dur,
          words: words,
        ));
        continue;
      }

      // 2) plain line — computed duration + interpolated word timings.
      final text = e.body.replaceAll(_wordStampRe, '').trim();
      if (text.isEmpty) continue;
      final dur = (nextTime != null ? (nextTime - e.timeMs) : 4000)
          .clamp(80, 20000);
      out.add(LyricLine(
        e.timeMs,
        text.replaceAll(_wsRe, ' '),
        durationMs: dur,
        words: interpolateLineWords(
          text: text,
          startTimeMs: e.timeMs,
          durationMs: dur,
        ),
      ));
    }
    return out;
  }

  static List<LyricWord> _parseWordRuns(
      String body, int lineStartMs, int? lineEndMs) {
    final marks = _wordStampRe.allMatches(body).toList();
    if (marks.isEmpty) return const <LyricWord>[];
    final words = <LyricWord>[];
    for (var i = 0; i < marks.length; i++) {
      final mark = marks[i];
      final until =
          i + 1 < marks.length ? marks[i + 1].start : body.length;
      final text = body.substring(mark.end, until).trim();
      if (text.isEmpty) continue;
      final startMs = _stampToMs(
        mark.group(1)!,
        mark.group(2)!,
        mark.group(3)!,
      );
      final endMs = i + 1 < marks.length
          ? _stampToMs(marks[i + 1].group(1)!, marks[i + 1].group(2)!,
              marks[i + 1].group(3)!)
          : (lineEndMs ?? (startMs + 800));
      words.add(LyricWord(
        timeMs: startMs.clamp(0, 1 << 31),
        durationMs: (endMs - startMs).clamp(0, 1 << 31),
        text: text,
      ));
    }
    return words;
  }

  static int _stampToMs(String minRaw, String secRaw, String fracRaw) {
    final min = int.tryParse(minRaw) ?? 0;
    final sec = int.tryParse(secRaw) ?? 0;
    var fracMs = 0;
    if (fracRaw.length == 1) {
      fracMs = (int.tryParse(fracRaw) ?? 0) * 100;
    } else if (fracRaw.length == 2) {
      fracMs = (int.tryParse(fracRaw) ?? 0) * 10;
    } else if (fracRaw.length >= 3) {
      fracMs = int.tryParse(fracRaw.substring(0, 3)) ?? 0;
    }
    return min * 60000 + sec * 1000 + fracMs;
  }

  static List<LyricWord> interpolateLineWords({
    required String text,
    required int startTimeMs,
    required int durationMs,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <LyricWord>[];
    final words = trimmed.split(_wsRe);
    var totalChars = 0;
    for (final w in words) {
      totalChars += w.length;
    }
    if (totalChars <= 0) return const <LyricWord>[];

    final safeDuration =
        durationMs > 0 ? durationMs : math.max(1500, words.length * 350);
    final syllables = <LyricWord>[];
    var currentMs = startTimeMs;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      final isLast = i == words.length - 1;
      final wordDur = math.max(
        120,
        ((word.length / totalChars) * safeDuration).round(),
      );
      syllables.add(LyricWord(
        timeMs: currentMs,
        durationMs: wordDur,
        text: isLast ? word : '$word ',
      ));
      currentMs += wordDur;
    }
    return syllables;
  }

  static List<LyricLine> hydrateLines(List<LyricLine> lines) {
    var anyChanged = false;
    final out = <LyricLine>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final nextTime = i + 1 < lines.length ? lines[i + 1].timeMs : null;
      var dur = l.durationMs;
      var lineChanged = false;
      if (dur <= 0) {
        dur = (nextTime != null ? (nextTime - l.timeMs) : 4000)
            .clamp(80, 20000);
        lineChanged = true;
      }
      var words = l.words;
      if (words.isEmpty && l.text.trim().isNotEmpty) {
        words = interpolateLineWords(
          text: l.text,
          startTimeMs: l.timeMs,
          durationMs: dur,
        );
        lineChanged = true;
      }
      out.add(lineChanged
          ? LyricLine(l.timeMs, l.text, durationMs: dur, words: words)
          : l);
      if (lineChanged) anyChanged = true;
    }
    return anyChanged ? out : lines;
  }

  static bool plausibleDuration(List<LyricLine> lines, int? durationMs) {
    if (durationMs == null || durationMs <= 0) return true;
    if (lines.length < 3) return true;
    final expectedMs = durationMs;
    if (expectedMs < 60000) return true;
    var endMs = 0;
    for (final l in lines) {
      final e = l.endMs;
      if (e > endMs) endMs = e;
    }
    if (endMs <= 0) return true;
    if (endMs > expectedMs + 45000) return false;
    if (endMs < expectedMs * 0.45 && expectedMs - endMs > 90000) {
      return false;
    }
    return true;
  }
}


class _SpanHit {
  const _SpanHit(this.attrs, this.content, this.trailing);
  final String attrs;
  final String content;
  final String trailing;
}

class TtmlParser {
  TtmlParser._();

  static final RegExp _pTag = RegExp(
      r'<(?:[a-zA-Z0-9_-]+:)?p\b([^>]*?)>(.*?)</(?:[a-zA-Z0-9_-]+:)?p>',
      dotAll: true,
      caseSensitive: false);
  static final RegExp _anySpanTag = RegExp(
      r'<(/?)(?:[a-zA-Z0-9_-]+:)?span\b([^>]*?)(/?)>',
      caseSensitive: false);
  static final RegExp _xmlTag = RegExp(r'<[^>]+>');
  static final RegExp _beginRe = RegExp(
      r'''(?:begin|start|startTime|from)=["']([^"']+)["']''',
      caseSensitive: false);
  static final RegExp _endRe = RegExp(
      r'''(?:end|endTime|to)=["']([^"']+)["']''',
      caseSensitive: false);
  static final RegExp _interSpanSpaces = RegExp(r'</span>\s+<span');

  static List<_SpanHit> _scanSpans(String xml) {
    final hits = <_SpanHit>[];
    final open = <(String, int)>[]; // (attrs, contentStart)
    for (final m in _anySpanTag.allMatches(xml)) {
      if (m.group(1) == '/') {
        if (open.isEmpty) continue; // stray close tag
        final (attrs, contentStart) = open.removeLast();
        if (open.isNotEmpty) continue; // nested — the parent recursion owns it
        var tEnd = m.end;
        while (tEnd < xml.length &&
            (xml.codeUnitAt(tEnd) == 0x20 ||
                xml.codeUnitAt(tEnd) == 0x09 ||
                xml.codeUnitAt(tEnd) == 0x0A ||
                xml.codeUnitAt(tEnd) == 0x0D)) {
          tEnd++;
        }
        hits.add(_SpanHit(
            attrs, xml.substring(contentStart, m.start),
            xml.substring(m.end, tEnd)));
      } else if (m.group(3) == '/') {
        continue; // self-closing: no content, ignored (parity with old regex)
      } else {
        open.add((m.group(2) ?? '', m.end));
      }
    }
    return hits;
  }

  static List<LyricLine> parse(String ttml) {
    var raw = ttml;
    if (raw.contains(r'\n') && !raw.contains('\n')) {
      raw = raw.replaceAll(r'\r\n', '\n').replaceAll(r'\n', '\n');
    }
    final lines = <LyricLine>[];

    for (final p in _pTag.allMatches(raw)) {
      final pAttrs = p.group(1) ?? '';
      final inner = p.group(2) ?? '';
      final start = _time(_beginRe.firstMatch(pAttrs)?.group(1) ?? '');
      final end = _time(_endRe.firstMatch(pAttrs)?.group(1) ?? '');
      final duration = (end - start).clamp(0, 1 << 31);
      final spans = _scanSpans(inner);

      if (spans.isEmpty) {
        final text = _unescape(inner.replaceAll(_xmlTag, '').trim());
        if (text.isEmpty) continue;
        lines.add(LyricLine(
          start,
          text,
          durationMs: duration > 0 ? duration : 4000,
        ));
        continue;
      }

      final words = <LyricWord>[];
      final buf = StringBuffer();
      final hasExplicitSpaces = _interSpanSpaces.hasMatch(inner);

      void emit(List<_SpanHit> nodes, bool parentIsLast) {
        for (var i = 0; i < nodes.length; i++) {
          final n = nodes[i];
          final isLast = parentIsLast && i == nodes.length - 1;
          final beginMatch = _beginRe.firstMatch(n.attrs);
          final endMatch = _endRe.firstMatch(n.attrs);

          if (beginMatch == null || endMatch == null) {
            // Untimed container span (e.g. <span ttm:role="x-bg">) —
            // recurse into its directly nested spans.
            emit(_scanSpans(n.content), isLast);
            continue;
          }

          // Timed span that CONTAINS timed spans (timed x-bg wrapper
          // around per-word spans): prefer the finer inner timing —
          // collapsing it into one leaf word would kill word sync.
          final nested = _scanSpans(n.content);
          var nestedTimed = false;
          for (final c in nested) {
            if (_beginRe.firstMatch(c.attrs) != null &&
                _endRe.firstMatch(c.attrs) != null) {
              nestedTimed = true;
              break;
            }
          }
          if (nestedTimed) {
            emit(nested, isLast);
            continue;
          }

          // Leaf word.
          final ws = _time(beginMatch.group(1) ?? '');
          final we = _time(endMatch.group(1) ?? '');
          final wt = _unescape(n.content.replaceAll(_xmlTag, ''));
          final addSpace = hasExplicitSpaces
              ? (wt.endsWith(' ') || n.trailing.isNotEmpty)
              : (!isLast && !wt.endsWith(' '));
          final sylText = addSpace ? '${wt.trimRight()} ' : wt.trim();
          words.add(LyricWord(
            timeMs: ws,
            durationMs: (we - ws).clamp(0, 1 << 31),
            text: sylText,
          ));
          buf.write(sylText);
        }
      }

      emit(spans, true);

      final text = buf.toString().trim();
      if (text.isEmpty) continue;
      lines.add(LyricLine(
        start,
        text,
        durationMs: duration,
        words: words,
      ));
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  /// `<p begin="00:01:23.456">` / `12.3s` / `450ms` / `12.3` → ms.
  static int _time(String s) {
    var str = s.trim();
    if (str.isEmpty) return 0;
    try {
      if (str.endsWith('ms')) {
        final val = str.substring(0, str.length - 2).trim();
        if (!val.contains(':')) {
          return double.parse(val).round();
        }
        str = val;
      } else if (str.endsWith('s')) {
        str = str.substring(0, str.length - 1).trim();
      }
      if (str.contains(':')) {
        final parts = str.split(':');
        final nums = parts.map(double.parse).toList().reversed.toList();
        var total = 0.0;
        var mult = 1.0;
        for (final n in nums) {
          total += n * mult;
          mult *= 60.0;
        }
        return (total * 1000).round();
      }
      return (double.parse(str) * 1000).round();
    } catch (_) {
      return 0;
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'");
}


/// Parses QQ-karaoke rows: `[lineStart,lineDur](wStart,wDur[,?])word …`
/// (milliseconds). Empty when the payload carries no karaoke rows.
class KaraokeParser {
  KaraokeParser._();

  static final RegExp _lineRe = RegExp(r'^\[(\d{1,8}),(\d{1,8})](.*)$');
  static final RegExp _wordRe =
      RegExp(r'\((\d{1,8}),(\d{1,8})(?:,\d{1,8})?\)([^()]*)');
  static final RegExp _timeRe = RegExp(r'\(\d{1,8},\d{1,8}(?:,\d{1,8})?\)');

  static List<LyricLine> parse(String raw) {
    if (!raw.contains('[') || !raw.contains('(')) return const <LyricLine>[];
    final rows = <LyricLine>[];
    for (final source in raw.split('\n')) {
      final match = _lineRe.firstMatch(source.trim());
      if (match == null) continue;
      final lineStart = int.tryParse(match.group(1) ?? '');
      final lineDuration = int.tryParse(match.group(2) ?? '') ?? 0;
      if (lineStart == null) continue;
      final body = match.group(3) ?? '';
      final words = <LyricWord>[];
      for (final w in _wordRe.allMatches(body)) {
        final text = _decodeEntities(w.group(3) ?? '').trim();
        if (text.isEmpty) continue;
        final startMs = int.tryParse(w.group(1) ?? '');
        if (startMs == null) continue;
        final durMs = int.tryParse(w.group(2) ?? '') ?? 0;
        words.add(LyricWord(
          timeMs: startMs,
          durationMs: durMs.clamp(0, 1 << 31),
          text: text,
        ));
      }
      if (words.isEmpty) continue;
      final text = _decodeEntities(body.replaceAll(_timeRe, '')).trim();
      if (text.isEmpty) continue;
      rows.add(LyricLine(
        math.min(lineStart, words.first.timeMs),
        text,
        durationMs: lineDuration.clamp(0, 1 << 31),
        words: words,
      ));
    }
    rows.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return rows;
  }

  static String _decodeEntities(String raw) {
    if (!raw.contains('&')) return raw;
    var out = raw.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1)!, radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    return out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}


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
    String? isrc,
    String? videoId,
    bool forceRefresh = false,
  }) {
    final clean = MetadataCleaner.clean(title, artist);
    final key = 'v1|${clean.primaryArtist.toLowerCase()}|'
        '${clean.cleanTitle.toLowerCase()}|${album?.toLowerCase() ?? ''}';
    if (_inflight.containsKey(key)) return _inflight[key]!;
    final fut = _lookupImpl(clean, key, durationMs, album, forceRefresh, isrc, videoId)
        .whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = fut;
    return fut;
  }

  static Future<LyricsData?> _lookupImpl(
      CleanedMetadata clean,
      String key,
      int? durationMs,
      String? album,
      bool forceRefresh,
      String? isrc,
      String? videoId,
      ) async {
    try {
      if (!forceRefresh) {
        final box = await _cache();
        final cached = box.get(key);
        if (cached is Map) {
          final d = LyricsData.fromMap(Map<String, dynamic>.from(cached));
          if (d != null) {
            return d.hydrate();
          }
        }
      }
      if (_misses.contains(key)) return null;

      // Multi-source stage (BitChord-style): every enabled source asked at
      // once, read in the user's order, a word-timed answer wins.
      RepoResult? repo;
      try {
        repo = await LyricsRepository.resolve(
          query: LyricQuery(
            title: clean.cleanTitle,
            artist: clean.primaryArtist,
            album: album,
            durationMs: durationMs,
            videoId: videoId,
            isrc: isrc,
          ),
          trackName: clean.cleanTitle,
          artistName: clean.primaryArtist,
        );
        final w = repo.wordSynced;
        if (w != null) {
          final box = await _cache();
          await box.put(key, w.toMap());
          return w;
        }
      } catch (e) {
        print('[yt_lyrics] multi-source stage failed: $e');
      }

      LyricsData? betterLineSynced;
      try {
        final doc = await BetterLyrics.lookup(
          title: clean.cleanTitle,
          artist: clean.primaryArtist,
          durationMs: durationMs,
          album: album,
        );
        if (doc != null) {
          final lines = doc.wordSynced
              ? _parseWordDocument(doc.payload)
              : const <LyricLine>[];
          if (lines.isNotEmpty &&
              LrcParser.plausibleDuration(lines, durationMs)) {
            final data = LyricsData(
              trackName: clean.cleanTitle,
              artistName: clean.primaryArtist,
              synced: lines,
              plain: null,
              instrumental: false,
              wordSync: true,
            );
            final box = await _cache();
            await box.put(key, data.toMap());
            final wordLines = lines.where((l) => l.hasWords).length;
            print('[yt_lyrics] word-sync resolved "${data.trackName}" — '
                '${data.artistName} ($wordLines/${lines.length} word-timed '
                'lines, ${doc.wordSynced ? "word-sync source" : "line source"})');
            return data;
          }
          if (lines.isEmpty) {
            // Line-synced (or unparseable) document — keep as last resort.
            final fallback = LrcParser.parse(doc.payload);
            if (fallback.isNotEmpty &&
                LrcParser.plausibleDuration(fallback, durationMs)) {
              betterLineSynced = LyricsData(
                trackName: clean.cleanTitle,
                artistName: clean.primaryArtist,
                synced: fallback,
                plain: null,
                instrumental: false,
                wordSync: false,
              );
              print('[yt_lyrics] better_lyrics line-synced document kept '
                  'as last resort (${fallback.length} lines)');
            }
          } else {
            print('[yt_lyrics] better_lyrics word document rejected by the '
                'duration gate — falling through');
          }
        }
      } catch (e) {
        print('[yt_lyrics] better_lyrics stage failed: $e');
      }

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

      final repoFallback = repo?.lineSynced ?? repo?.plain;
      if (repoFallback != null && repoFallback.hasAny) {
        final box = await _cache();
        await box.put(key, repoFallback.toMap());
        return repoFallback;
      }

      if (betterLineSynced != null && betterLineSynced.hasAny) {
        final box = await _cache();
        await box.put(key, betterLineSynced.toMap());
        print('[yt_lyrics] resolved "${betterLineSynced.trackName}" from '
            'the better_lyrics last resort (synced: '
            '${betterLineSynced.hasSynced})');
        return betterLineSynced;
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

  /// Public hook for the multi-source repository.
  static List<LyricLine> parseWordDocument(String payload) =>
      _parseWordDocument(payload);

  static List<LyricLine> _parseWordDocument(String payload) {
    final lower = payload.toLowerCase();
    if (lower.contains('<tt') ||
        lower.contains('<p') ||
        lower.contains('http://www.w3.org/ns/ttml')) {
      final ttml = TtmlParser.parse(payload);
      if (ttml.isNotEmpty && ttml.any((l) => l.hasWords)) return ttml;
    }
    final karaoke = KaraokeParser.parse(payload);
    if (karaoke.isNotEmpty) return karaoke;
    final enhanced = LrcParser.parse(payload);
    if (enhanced.isNotEmpty && enhanced.any((l) => l.hasWords)) {
      // Only genuine enhanced-LRC stamps count (plain rows are
      // interpolated — those are display sugar, not word sync).
      return enhanced;
    }
    return const <LyricLine>[];
  }

  static Future<List<Map<String, dynamic>>> _search(
      Map<String, String> params) async {
    try {
      final uri = Uri.https(_host, '/api/search', params);
      final req = await _client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        // Drain the error body — undrained responses pin the socket for
        // the whole session (LRCLIB misses are routine).
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return const <Map<String, dynamic>>[];
      }
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
