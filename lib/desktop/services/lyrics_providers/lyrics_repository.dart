// ZenMusic · vorlon-dev
//
// Multi-source lyrics resolution, modelled on BitChord's LyricsRepository
// (GPL-3.0, https://github.com/kushagrasinghx/BitChord): every enabled
// source is asked at once, but the answers are read in the user's order, and
// a word-timed answer beats a line-timed one.

import 'dart:async';

import 'package:hive/hive.dart';

import '../better_lyrics.dart';
import '../kugou_lyrics.dart';
import '../lyrics_service.dart';
import 'bini_lyrics.dart';
import 'genius.dart';
import 'lrc_red.dart';
import 'lyric_doc.dart';
import 'lyrics_plus.dart';
import 'megalobiz.dart';
import 'musixmatch.dart';
import 'paxsenix.dart';
import 'unison.dart';

/// User choices for which sources run and in what order (Hive 'SETTINGS').
class LyricSourcePrefs {
  LyricSourcePrefs._();

  static const String _orderKey = 'LYRIC_SOURCE_ORDER';
  static const String _offKey = 'LYRIC_SOURCES_OFF';
  static const String _syllableFirstKey = 'LYRIC_SYLLABLE_FIRST';

  static Box? get _box {
    try {
      return Hive.isBoxOpen('SETTINGS') ? Hive.box('SETTINGS') : null;
    } catch (_) {
      return null;
    }
  }

  /// Saved order, with any source added since appended in default order.
  static List<LyricSourceId> order() {
    final saved = _box?.get(_orderKey);
    final out = <LyricSourceId>[];
    if (saved is List) {
      for (final n in saved) {
        for (final s in LyricSourceId.values) {
          if (s.name == n && !out.contains(s)) out.add(s);
        }
      }
    }
    for (final s in LyricSourceId.values) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  static Set<LyricSourceId> disabled() {
    final saved = _box?.get(_offKey);
    if (saved is! List) return <LyricSourceId>{};
    return {
      for (final s in LyricSourceId.values)
        if (saved.contains(s.name)) s,
    };
  }

  static List<LyricSourceId> enabledInOrder() {
    final off = disabled();
    return [
      for (final s in order())
        if (!off.contains(s)) s,
    ];
  }

  static Future<void> setOrder(List<LyricSourceId> v) async =>
      _box?.put(_orderKey, [for (final s in v) s.name]);

  static Future<void> setEnabled(LyricSourceId id, bool on) async {
    final off = disabled();
    on ? off.remove(id) : off.add(id);
    await _box?.put(_offKey, [for (final s in off) s.name]);
  }

  /// When on, a word-timed answer from a lower-priority source still beats
  /// a line-timed answer from a higher one (this is the default).
  static bool get syllableFirst =>
      (_box?.get(_syllableFirstKey, defaultValue: true) as bool?) ?? true;

  static Future<void> setSyllableFirst(bool v) async =>
      _box?.put(_syllableFirstKey, v);
}

/// What the repository found, split by timing quality.
class RepoResult {
  const RepoResult({this.wordSynced, this.lineSynced, this.plain});

  final LyricsData? wordSynced;
  final LyricsData? lineSynced;
  final LyricsData? plain;
}

class LyricsRepository {
  LyricsRepository._();

  /// Asks every enabled source concurrently; reads the answers in order.
  /// The first word-timed answer ends the wait (later sources are ignored).
  static Future<RepoResult> resolve({
    required LyricQuery query,
    required String trackName,
    required String artistName,
  }) async {
    final sources = LyricSourcePrefs.enabledInOrder()
        .where((s) => s != LyricSourceId.lrclib) // LRCLIB keeps its own flow
        .toList();

    // ISRC lets lrc.red / BiniLyrics name the exact recording.
    final futures = <LyricSourceId, Future<LyricDoc?>>{
      for (final s in sources) s: _ask(s, query),
    };

    LyricsData? line;
    LyricsData? plain;
    for (final s in sources) {
      final doc = await futures[s];
      if (doc == null || doc.payload.trim().isEmpty) continue;
      final data = _toData(doc, trackName, artistName, query.durationMs);
      if (data == null) continue;
      if (data.hasWordTimings) {
        print('[lyrics] ${s.label}: word-synced');
        return RepoResult(wordSynced: data, lineSynced: line, plain: plain);
      }
      if (data.hasSynced) {
        line ??= data;
        if (!LyricSourcePrefs.syllableFirst) {
          return RepoResult(lineSynced: line, plain: plain);
        }
      } else if (data.hasAny) {
        plain ??= data;
      }
    }
    return RepoResult(lineSynced: line, plain: plain);
  }

  static Future<LyricDoc?> _ask(LyricSourceId s, LyricQuery q) async {
    try {
      final Future<LyricDoc?> f;
      switch (s) {
        case LyricSourceId.lrcRed:
          f = LrcRed.lookup(q);
        case LyricSourceId.biniLyrics:
          f = BiniLyrics.lookup(q);
        case LyricSourceId.betterLyrics:
          f = BetterLyrics.lookup(
            title: q.title,
            artist: q.artist,
            durationMs: q.durationMs,
            album: q.album,
          ).then((d) => d == null
              ? null
              : LyricDoc(payload: d.payload, wordSynced: d.wordSynced));
        case LyricSourceId.paxSenix:
          f = PaxSenix.lookup(q);
        case LyricSourceId.lyricsPlus:
          f = LyricsPlus.lookup(q);
        case LyricSourceId.unison:
          f = Unison.lookup(q);
        case LyricSourceId.musixmatch:
          f = Musixmatch.lookup(q);
        case LyricSourceId.kugou:
          f = KugouLyrics.lookup(
            title: q.title,
            artist: q.artist,
            durationMs: q.durationMs,
            album: q.album,
          ).then((lrc) => lrc == null
              ? null
              : LyricDoc(payload: lrc, wordSynced: false, lineSynced: true));
        case LyricSourceId.megalobiz:
          f = Megalobiz.lookup(q);
        case LyricSourceId.genius:
          f = Genius.lookup(q);
        case LyricSourceId.lrclib:
          return null;
      }
      return await f.timeout(const Duration(seconds: 15), onTimeout: () => null);
    } catch (e) {
      print('[lyrics] ${s.label} failed: $e');
      return null;
    }
  }

  static LyricsData? _toData(
    LyricDoc doc,
    String trackName,
    String artistName,
    int? durationMs,
  ) {
    if (doc.isPlain) {
      return LyricsData(
        trackName: trackName,
        artistName: artistName,
        synced: null,
        plain: doc.payload.trim(),
        instrumental: false,
        wordSync: false,
      );
    }
    final words = doc.wordSynced
        ? LyricsService.parseWordDocument(doc.payload)
        : const <LyricLine>[];
    if (words.isNotEmpty && words.any((l) => l.hasWords)) {
      if (!LrcParser.plausibleDuration(words, durationMs)) return null;
      return LyricsData(
        trackName: trackName,
        artistName: artistName,
        synced: words,
        plain: null,
        instrumental: false,
        wordSync: true,
      );
    }
    final lines = LrcParser.parse(doc.payload);
    if (lines.isEmpty || !LrcParser.plausibleDuration(lines, durationMs)) {
      return null;
    }
    return LyricsData(
      trackName: trackName,
      artistName: artistName,
      synced: lines,
      plain: null,
      instrumental: false,
      wordSync: false,
    );
  }
}
