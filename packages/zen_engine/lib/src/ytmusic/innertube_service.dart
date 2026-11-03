import 'dart:convert';
import 'package:http/http.dart' as http;
import 'potoken_service.dart';
import '../models/song_model.dart';

/// Full InnerTube API client with poToken support for searching, streaming, and related items.
class InnerTubeService {
  InnerTubeService({
    http.Client? client,
    PoTokenService? poTokenService,
  })  : _client = client ?? http.Client(),
        _poTokenService = poTokenService ?? PoTokenService();

  final http.Client _client;
  final PoTokenService _poTokenService;

  PoTokenService get poTokenService => _poTokenService;

  static const String _baseUrl = 'https://music.youtube.com/youtubei/v1';

  /// Get player response containing stream URLs with poToken injection
  Future<Map<String, dynamic>?> getPlayer(String videoId) async {
    try {
      final poToken = await _poTokenService.resolvePoToken();
      final visitorData = _poTokenService.currentVisitorData;

      final body = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
            if (visitorData != null) 'visitorData': visitorData,
          },
          if (poToken != null)
            'serviceIntegrityDimensions': {
              'poToken': poToken,
            },
        },
        'videoId': videoId,
      };

      final res = await _client.post(
        Uri.parse('$_baseUrl/player'),
        headers: {
          'Content-Type': 'application/json',
          'Origin': 'https://music.youtube.com',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  /// Extract highest quality audio stream from InnerTube player response
  Future<String?> getAudioStreamUrl(String videoId) async {
    final player = await getPlayer(videoId);
    if (player == null) return null;

    final streamingData = player['streamingData'] as Map<String, dynamic>?;
    if (streamingData == null) return null;

    final formats = (streamingData['adaptiveFormats'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/'))
        .toList();

    if (formats.isEmpty) return null;

    // Sort by highest bitrate
    formats.sort((a, b) => ((b['bitrate'] as num?) ?? 0).compareTo((a['bitrate'] as num?) ?? 0));
    return formats.first['url'] as String?;
  }

  /// Search InnerTube for songs
  Future<List<ZenSong>> search(String query, {int limit = 20}) async {
    try {
      final body = {
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'en',
          },
        },
        'query': query,
        'params': 'EgWKAQIIAWoQEAMQBBAJEAoQBRAREBAQFQ%3D%3D', // Songs filter
      };

      final res = await _client.post(
        Uri.parse('$_baseUrl/search'),
        headers: {
          'Content-Type': 'application/json',
          'Origin': 'https://music.youtube.com',
          'Referer': 'https://music.youtube.com/',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body);

      final songs = <ZenSong>[];
      final sectionList = data['contents']?['tabbedSearchResultsRenderer']?['tabs']?[0]
          ?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;

      if (sectionList == null) return [];

      for (final section in sectionList) {
        final items = section['musicShelfRenderer']?['contents'] as List?;
        if (items == null) continue;

        for (final item in items) {
          if (songs.length >= limit) break;
          final renderer = item['musicResponsiveListItemRenderer'];
          if (renderer == null) continue;

          final flexCols = renderer['flexColumns'] as List?;
          if (flexCols == null || flexCols.isEmpty) continue;

          final titleRun = flexCols[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?[0];
          final title = titleRun?['text'] as String? ?? 'Unknown';
          final videoId = titleRun?['navigationEndpoint']?['watchEndpoint']?['videoId'] as String? ??
              renderer['playlistItemData']?['videoId'] as String? ??
              '';

          if (videoId.isEmpty) continue;

          String artist = 'Unknown';
          if (flexCols.length > 1) {
            final artistRuns = flexCols[1]['musicResponsiveListItemFlexColumnRenderer']
                ?['text']?['runs'] as List?;
            if (artistRuns != null && artistRuns.isNotEmpty) {
              artist = artistRuns.map((r) => r['text']).join('');
            }
          }

          final thumbs = renderer['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
          final thumb = thumbs != null && thumbs.isNotEmpty ? thumbs.last['url'] as String? : null;

          songs.add(ZenSong(
            id: videoId,
            title: title,
            artist: artist,
            thumbnailUrl: thumb,
            source: ZenSongSource.youtube,
            raw: {
              'videoId': videoId,
              'title': title,
              'artist': artist,
              'thumbnails': [{'url': thumb}],
            },
          ));
        }
      }

      return songs;
    } catch (_) {
      return [];
    }
  }

  void dispose() {
    _client.close();
    _poTokenService.dispose();
  }
}
