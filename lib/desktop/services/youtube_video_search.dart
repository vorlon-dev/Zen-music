// ZenMusic — standalone YouTube *video* search (pure Dart, every platform).
// Uses YouTube's public Innertube search endpoint with the "Videos" filter,
// so results are real YouTube videos (covers, live, interviews, lyric
// videos...), not only YouTube Music songs.
//
// Put at: lib/desktop/services/youtube_video_search.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class YtVideoPage {
  const YtVideoPage(this.items, this.token);
  final List<Map<String, dynamic>> items;

  /// Continuation token for the next page (null = no more results).
  final String? token;
}

class YouTubeVideoSearch {
  YouTubeVideoSearch._();
  static final YouTubeVideoSearch instance = YouTubeVideoSearch._();

  static const _key = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  // Older WEB client version keeps the classic `videoRenderer` response.
  static const _clientVersion = '2.20240101.00.00';
  static const _videosOnly = 'EgIQAQ=='; // search filter: type = video

  Future<YtVideoPage> search(String query) =>
      _call({'query': query, 'params': _videosOnly});

  Future<YtVideoPage> more(String token) => _call({'continuation': token});

  Future<YtVideoPage> _call(Map<String, dynamic> body) async {
    body['context'] = {
      'client': {
        'clientName': 'WEB',
        'clientVersion': _clientVersion,
        'hl': 'en',
      },
    };
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.postUrl(Uri.parse(
          'https://www.youtube.com/youtubei/v1/search?key=$_key&prettyPrint=false'));
      req.headers
        ..set('content-type', 'application/json')
        ..set('x-youtube-client-name', '1')
        ..set('x-youtube-client-version', _clientVersion)
        ..set('origin', 'https://www.youtube.com')
        ..set('user-agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0 Safari/537.36');
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 15));
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw HttpException('YouTube search failed (${res.statusCode})');
      }
      final items = <Map<String, dynamic>>[];
      final tokenBox = <String>[];
      _walk(jsonDecode(text), items, tokenBox);
      return YtVideoPage(items, tokenBox.isEmpty ? null : tokenBox.last);
    } finally {
      client.close(force: true);
    }
  }

  // Walks the whole response, so it survives small layout changes.
  void _walk(dynamic node, List<Map<String, dynamic>> out, List<String> tok) {
    if (node is Map) {
      final v = node['videoRenderer'];
      if (v is Map) {
        final item = _video(v);
        if (item != null) out.add(item);
        return;
      }
      final c = node['continuationItemRenderer'];
      if (c is Map) {
        final t = c['continuationEndpoint']?['continuationCommand']?['token'];
        if (t is String) tok.add(t);
      }
      for (final value in node.values) {
        _walk(value, out, tok);
      }
    } else if (node is List) {
      for (final e in node) {
        _walk(e, out, tok);
      }
    }
  }

  String _text(dynamic t) {
    if (t is! Map) return '';
    if (t['simpleText'] is String) return t['simpleText'];
    final runs = t['runs'];
    if (runs is List) return runs.map((r) => r['text'] ?? '').join();
    return '';
  }

  Map<String, dynamic>? _video(Map v) {
    final id = v['videoId']?.toString() ?? '';
    if (id.length != 11) return null;
    final title = _text(v['title']);
    if (title.isEmpty) return null;
    final channel = _text(v['ownerText'] ?? v['longBylineText']);
    final views = _text(v['shortViewCountText'] ?? v['viewCountText']);
    final published = _text(v['publishedTimeText']);
    var duration = _text(v['lengthText']);
    if (duration.isEmpty) duration = 'LIVE';
    return {
      'videoId': id,
      'title': title,
      'subtitle': [channel, views, published]
          .where((e) => e.isNotEmpty)
          .join(' • '),
      'artist': channel,
      'duration': duration,
      'thumbnails': [
        {'url': 'https://i.ytimg.com/vi/$id/mqdefault.jpg'},
      ],
      'type': 'VIDEO',
      'isYtVideo': true,
    };
  }
}