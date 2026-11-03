import 'dart:convert';
import 'package:http/http.dart' as http;
import 'lyrics_model.dart';

/// Kugou lyrics provider for rich Asian / global song lyrics fallback.
class KugouLyricsService {
  KugouLyricsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _headCutLimit = 30;
  static final RegExp _acceptedRe = RegExp(r'\[(\d\d):(\d\d)\.(\d{2,3})\].*');
  static final RegExp _bannedRe = RegExp(r'.+].+[:：].+');

  Future<Lyrics?> lookup({
    required String title,
    required String artist,
    int? durationMs,
    String? album,
  }) async {
    try {
      final query = '$title - $artist';
      final uri = Uri.https('mobileservice.kugou.com', '/api/v3/search/song', {
        'version': '9108',
        'plat': '0',
        'pagesize': '8',
        'showtype': '0',
        'keyword': query,
      });

      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>?;
      final info = ((body?['data'] as Map?)?['info'] as List?) ?? const [];

      for (final item in info) {
        if (item is! Map) continue;
        final hash = item['hash']?.toString() ?? '';
        if (hash.isEmpty) continue;

        final candUri = Uri.https('lyrics.kugou.com', '/search', {
          'ver': '1',
          'man': 'yes',
          'client': 'pc',
          'hash': hash,
        });
        final candRes = await _client.get(candUri).timeout(const Duration(seconds: 10));
        if (candRes.statusCode != 200) continue;
        final candBody = jsonDecode(candRes.body) as Map<String, dynamic>?;
        final cands = (candBody?['candidates'] as List?) ?? const [];
        if (cands.isEmpty) continue;

        final first = cands.first as Map;
        final id = first['id']?.toString() ?? '';
        final accessKey = first['accesskey']?.toString() ?? '';
        if (id.isEmpty || accessKey.isEmpty) continue;

        final dlUri = Uri.https('lyrics.kugou.com', '/download', {
          'fmt': 'lrc',
          'charset': 'utf8',
          'client': 'pc',
          'ver': '1',
          'id': id,
          'accesskey': accessKey,
        });
        final dlRes = await _client.get(dlUri).timeout(const Duration(seconds: 10));
        if (dlRes.statusCode != 200) continue;
        final dlBody = jsonDecode(dlRes.body) as Map<String, dynamic>?;
        final content = dlBody?['content']?.toString() ?? '';
        if (content.isEmpty) continue;

        final lrc = utf8.decode(base64.decode(content.replaceAll('\n', '')));
        final normalized = _normalize(lrc);
        if (normalized.trim().isNotEmpty) {
          return Lyrics(
            id: id,
            artist: artist,
            title: title,
            lyricsPlain: normalized.replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '').trim(),
            lyricsSynced: normalized,
            provider: LyricsProvider.kugou,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _normalize(String lrc) {
    final lines = lrc
        .split('\n')
        .map((l) => l.trim())
        .where((l) => _acceptedRe.hasMatch(l))
        .toList();
    if (lines.isEmpty) return '';

    var headCut = 0;
    final headScan = lines.length < _headCutLimit ? lines.length - 1 : _headCutLimit;
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

  void dispose() {
    _client.close();
  }
}
