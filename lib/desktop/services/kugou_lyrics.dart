// ZenMusic — SP-68: KuGou lyrics — synced-LRC fallback after LRCLIB.
//
// LRCLIB misses most of the Chinese/Asian long tail; KuGou's public
// lyrics library (mobileservice.kugou.com + lyrics.kugou.com, no keys,
// no auth) covers it well. This provider ports the proven three-hop
// pipeline used by PixelMusic-class clients (originally the ViMusic
// KuGou module family):
//
//   1. song search      GET /api/v3/search/song  (top 8, keyword =
//                       "title - artist [album]") → song hash + duration
//   2. duration gate    ±8 s against the playing track (skipped when
//                       the duration is unknown)
//   3. lyrics search    GET lyrics.kugou.com/search by hash, then by
//                       keyword+duration → candidates {id, accesskey}
//   4. download         GET lyrics.kugou.com/download?fmt=lrc →
//                       Base64(utf8 LRC)
//   5. normalize        keep timed lines only; strip the credit block
//                       ("作词/作曲/Lyrics/Composer…" lines) that KuGou
//                       pads onto the head and tail of the file
//
// The provider returns the NORMALIZED LRC TEXT; the caller (lyrics_service)
// parses it through the standard LrcParser → LyricsData path, so it is
// cached in the same Hive box as LRCLIB results and rendered by the same
// synced view. This file must NOT import lyrics_service.dart — the
// dependency stays one-way (the service imports this file).
// ZERO new pubspec deps (dart:io HttpClient + dart:convert).

import 'dart:convert';
import 'dart:io';

class KugouLyrics {
  KugouLyrics._();

  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  static const int _pageSize = 8;
  static const int _durationToleranceSec = 8;
  static const int _headCutLimit = 30;

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[kugou] $m');

  /// Main entry. Returns the normalized LRC text, or null when KuGou has
  /// nothing for this track. Never throws.
  static Future<String?> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    try {
      final query = _searchQuery(title, artist, album);
      final songs = await _searchSongs(query);
      // Hop 1: song search → hash of a same-length version.
      for (final song in songs) {
        if (durationMs != null &&
            (song.duration - durationMs / 1000).abs() >
                _durationToleranceSec) {
          continue;
        }
        final cands = await _searchLyricsByHash(song.hash);
        final cand = cands.isNotEmpty ? cands.first : null;
        if (cand != null) {
          final lrc = await _download(cand.$1, cand.$2);
          if (lrc != null) return lrc;
        }
      }
      // Hop 2: keyword search on the lyrics host itself.
      for (final cand in await _searchLyricsByKeyword(
          query, durationMs == null ? null : (durationMs ~/ 1000))) {
        final lrc = await _download(cand.$1, cand.$2);
        if (lrc != null) return lrc;
      }
      return null;
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  // ── keyword building (CJK-aware title/artist normalization) ──────────

  static String _searchQuery(String title, String artist, String? album) {
    final q = StringBuffer('${_normTitle(title)} - ${_normArtist(artist)}');
    final a = album?.trim() ?? '';
    if (a.isNotEmpty) q.write(' $a');
    return q.toString();
  }

  /// Strips decoration brackets — ASCII and full-width CJK variants.
  static String _normTitle(String t) => t
      .replaceAll(RegExp(r'\(.*\)'), '')
      .replaceAll(RegExp(r'（.*）'), '')
      .replaceAll(RegExp(r'「.*」'), '')
      .replaceAll(RegExp(r'『.*』'), '')
      .replaceAll(RegExp(r'<.*>'), '')
      .replaceAll(RegExp(r'《.*》'), '')
      .replaceAll(RegExp(r'〈.*〉'), '')
      .replaceAll(RegExp(r'＜.*＞'), '');

  static String _normArtist(String a) => a
      .replaceAll(', ', '、')
      .replaceAll(' & ', '、')
      .replaceAll('.', '')
      .replaceAll('和', '、')
      .replaceAll(RegExp(r'\(.*\)'), '')
      .replaceAll(RegExp(r'（.*）'), '');

  // ── the three KuGou endpoints ────────────────────────────────────────

  static Future<List<({String hash, num duration})>> _searchSongs(
      String query) async {
    final body = await _getJson(Uri.https(
      'mobileservice.kugou.com',
      '/api/v3/search/song',
      {
        'version': '9108',
        'plat': '0',
        'pagesize': '$_pageSize',
        'showtype': '0',
        'keyword': query,
      },
    ));
    final info = ((body?['data'] as Map?)?['info'] as List?) ?? const [];
    final out = <({String hash, num duration})>[];
    for (final item in info) {
      if (item is! Map) continue;
      final hash = item['hash']?.toString() ?? '';
      if (hash.isEmpty) continue;
      out.add((
        hash: hash,
        duration: (item['duration'] as num?) ?? 0,
      ));
    }
    return out;
  }

  /// Returns (id, accesskey) candidates from the lyrics search host.
  static Future<List<(String, String)>> _searchLyricsByHash(
      String hash) async {
    return _lyricsCandidates({
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      'hash': hash,
    });
  }

  static Future<List<(String, String)>> _searchLyricsByKeyword(
      String query, int? durationSec) {
    return _lyricsCandidates({
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      if (durationSec != null) 'duration': '${durationSec * 1000}',
      'keyword': query,
    });
  }

  static Future<List<(String, String)>> _lyricsCandidates(
      Map<String, String> params) async {
    final body = await _getJson(
        Uri.https('lyrics.kugou.com', '/search', params));
    final cands = (body?['candidates'] as List?) ?? const [];
    final out = <(String, String)>[];
    for (final c in cands) {
      if (c is! Map) continue;
      final id = c['id']?.toString() ?? '';
      final key = c['accesskey']?.toString() ?? '';
      if (id.isEmpty || key.isEmpty) continue;
      out.add((id, key));
    }
    return out;
  }

  static Future<String?> _download(String id, String accessKey) async {
    final body = await _getJson(Uri.https('lyrics.kugou.com', '/download', {
      'fmt': 'lrc',
      'charset': 'utf8',
      'client': 'pc',
      'ver': '1',
      'id': id,
      'accesskey': accessKey,
    }));
    final content = body?['content']?.toString() ?? '';
    if (content.isEmpty) return null;
    try {
      final lrc = utf8.decode(base64.decode(content.replaceAll('\n', '')));
      final normalized = _normalize(lrc);
      if (normalized.trim().isEmpty) return null;
      return normalized;
    } catch (e) {
      _log('download decode failed: $e');
      return null;
    }
  }

  // ── LRC hygiene — port of the KuGou normalizer ───────────────────────

  static final RegExp _acceptedRe =
      RegExp(r'\[(\d\d):(\d\d)\.(\d{2,3})\].*');
  static final RegExp _bannedRe = RegExp(r'.+].+[:：].+');

  /// Keeps timed lines only, then trims the credit block: KuGou pads the
  /// head and tail with lines like "[00:00.00]作词：xxx" / "Composer：yyy"
  /// — any banned-pattern line inside the first/last [_headCutLimit] lines
  /// ends that block.
  static String _normalize(String lrc) {
    final lines = lrc
        .split('\n')
        .map((l) => l.trim())
        .where((l) => _acceptedRe.hasMatch(l))
        .toList();
    if (lines.isEmpty) return '';

    var headCut = 0;
    final headScan = lines.length < _headCutLimit
        ? lines.length - 1
        : _headCutLimit;
    for (var i = headScan; i >= 0; i--) {
      if (_bannedRe.hasMatch(lines[i])) {
        headCut = i + 1;
        break;
      }
    }
    final kept = lines.sublist(headCut);

    var tailCut = 0;
    final tailScan = kept.length - _headCutLimit;
    for (var i = tailScan > 0 ? tailScan : 0; i >= 0; i--) {
      if (_bannedRe.hasMatch(kept[kept.length - 1 - i])) {
        tailCut = i + 1;
        break;
      }
    }
    return kept.sublist(0, kept.length - tailCut).join('\n');
  }

  static Future<Map?> _getJson(Uri uri) async {
    try {
      final req = await _client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        _log('HTTP ${res.statusCode} from ${uri.host}');
        return null;
      }
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map?;
    } catch (e) {
      _log('${uri.host} failed: $e');
      return null;
    }
  }
}
