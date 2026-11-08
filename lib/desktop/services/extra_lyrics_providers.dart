// ZenMusic · extra lyric providers (Unison + Lyrics+). Never throw.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lyrics_service.dart';

class ExtraLyricsProviders {
  ExtraLyricsProviders._();

  static const _unison = 'https://unison.boidu.dev';
  static const _lyricsPlus = <String>[
    'https://lyricsplus.prjktla.my.id',
    'https://lyricsplus.atomix.one',
    'https://lyricsplus.binimum.org',
    'https://lyricsplus-seven.vercel.app',
  ];
  static String? _lastGood; // remember the last Lyrics+ server that worked

  static Future<LyricsData?> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    // Lyrics+ first (word-by-word capable), then Unison.
    return await _lyricsPlusLookup(title, artist, durationMs, album) ??
        await _unisonLookup(title, artist, durationMs, album);
  }

  static Future<Map?> _getJson(Uri u) async {
    try {
      final r = await http.get(u, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------- Unison ----------------
  static Future<LyricsData?> _unisonLookup(
      String title, String artist, int? durationMs, String? album) async {
    final j = await _getJson(Uri.parse('$_unison/lyrics').replace(queryParameters: {
      'song': title,
      'artist': artist,
      if (album != null && album.trim().isNotEmpty) 'album': album.trim(),
      if (durationMs != null && durationMs > 0) 'duration': '${durationMs ~/ 1000}',
    }));
    final d = j?['data'];
    if (j?['success'] != true || d is! Map) return null;
    final text = (d['lyrics'] ?? '').toString();
    if (text.trim().isEmpty) return null;
    final syncType = (d['syncType'] ?? '').toString().toLowerCase();
    final looksSynced = syncType != 'plain' && RegExp(r'\[\d{1,3}:\d{2}').hasMatch(text);
    if (looksSynced) {
      final lines = LrcParser.parse(text);
      if (lines.isNotEmpty) {
        return LyricsData(
          trackName: title, artistName: artist, synced: lines, plain: null,
          instrumental: false, wordSync: lines.any((l) => l.hasWords),
        );
      }
    }
    return LyricsData(
      trackName: title, artistName: artist, synced: null, plain: text,
      instrumental: false, wordSync: false,
    );
  }

  // ---------------- Lyrics+ (KPoe) ----------------
  static Future<LyricsData?> _lyricsPlusLookup(
      String title, String artist, int? durationMs, String? album) async {
    final servers = [if (_lastGood != null) _lastGood!, ..._lyricsPlus.where((s) => s != _lastGood)];
    for (final s in servers) {
      final j = await _getJson(Uri.parse('$s/v2/lyrics/get').replace(queryParameters: {
        'title': title,
        'artist': artist,
        if (album != null && album.trim().isNotEmpty) 'album': album.trim(),
        if (durationMs != null && durationMs > 0) 'duration': '${durationMs ~/ 1000}',
      }));
      if (j == null) continue;
      final data = _fromLyricsPlus(j, title, artist);
      if (data != null) {
        _lastGood = s;
        return data;
      }
    }
    return null;
  }

  static LyricsData? _fromLyricsPlus(Map j, String title, String artist) {
    final items = j['lyrics'];
    if (items is List && items.isNotEmpty) {
      final lines = <LyricLine>[];
      for (final it in items) {
        if (it is! Map) continue;
        final t = (it['time'] as num?)?.toInt() ?? 0;
        final dur = (it['duration'] as num?)?.toInt() ?? 0;
        final words = <LyricWord>[];
        final syl = it['syllabus'];
        if (syl is List) {
          for (final w in syl) {
            if (w is! Map || w['isBackground'] == true) continue;
            words.add(LyricWord(
              timeMs: (w['time'] as num?)?.toInt() ?? t,
              durationMs: (w['duration'] as num?)?.toInt() ?? 0,
              text: (w['text'] ?? '').toString(),
            ));
          }
        }
        final text = (it['text'] ?? words.map((w) => w.text).join()).toString().trim();
        if (text.isEmpty) continue;
        lines.add(LyricLine(t, text, durationMs: dur, words: words));
      }
      if (lines.isNotEmpty) {
        return LyricsData(
          trackName: title, artistName: artist, synced: lines, plain: null,
          instrumental: false, wordSync: lines.any((l) => l.hasWords),
        );
      }
    }
    final lrc = (j['syncedLyrics'] ?? '').toString();
    if (lrc.trim().isNotEmpty) {
      final lines = LrcParser.parse(lrc);
      if (lines.isNotEmpty) {
        return LyricsData(
          trackName: title, artistName: artist, synced: lines,
          plain: null, instrumental: false, wordSync: false,
        );
      }
    }
    final plain = (j['plainLyrics'] ?? '').toString();
    if (plain.trim().isNotEmpty) {
      return LyricsData(
        trackName: title, artistName: artist, synced: null, plain: plain,
        instrumental: false, wordSync: false,
      );
    }
    return null;
  }
}
