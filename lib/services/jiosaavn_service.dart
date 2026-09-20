import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';

class JiosaavnService {
  static const _baseUrl = 'https://jiosaavn-api.vorlon-revora.workers.dev';
  final _client = http.Client();

  Future<List<Song>> search(String query, {int limit = 15}) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/search/songs').replace(
        queryParameters: {
          'query': query,
          'limit': limit.toString(),
          'page': '0',
        },
      );

      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final results = data['data']?['results'] as List<dynamic>? ?? [];

      final songs = <Song>[];
      for (final item in results) {
        final map = item as Map<String, dynamic>;

        // ── Thumbnail (prefer 500×500) ──
        String thumb = '';
        final imageList = map['image'] as List<dynamic>? ?? [];
        for (final img in imageList) {
          final m = img as Map<String, dynamic>;
          if (m['quality'] == '500x500') {
            thumb = m['url'] as String? ?? '';
            break;
          }
        }
        if (thumb.isEmpty && imageList.isNotEmpty) {
          thumb = (imageList.last as Map<String, dynamic>)['url'] as String? ?? '';
        }

        // ── 320kbps stream URL (already present in search response!) ──
        String? stream320;
        final downloadUrls = map['downloadUrl'] as List<dynamic>? ?? [];
        for (final dl in downloadUrls) {
          final m = dl as Map<String, dynamic>;
          if (m['quality'] == '320kbps') {
            stream320 = m['url'] as String?;
            break;
          }
        }
        // Fallback: highest available
        if (stream320 == null && downloadUrls.isNotEmpty) {
          int bestBitrate = 0;
          for (final dl in downloadUrls) {
            final m = dl as Map<String, dynamic>;
            final q = m['quality'] as String? ?? '';
            final br = int.tryParse(q.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            if (br > bestBitrate) {
              bestBitrate = br;
              stream320 = m['url'] as String?;
            }
          }
        }

        // ── Primary artists ──
        final artists = map['artists']?['primary'] as List<dynamic>? ?? [];
        final artistNames = artists
            .map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .join(', ');

        songs.add(Song(
          id: map['id'] as String? ?? '',
          title: map['name'] as String? ?? 'Unknown',
          artist: artistNames.isNotEmpty
              ? artistNames
              : (map['primaryArtists'] as String? ?? 'Unknown'),
          thumbnail: thumb,
          duration: Duration(seconds: (map['duration'] as num?)?.toInt() ?? 0),
          jiosaavnId: map['id'] as String?,
          jiosaavnStreamUrl: stream320,
        ));
      }

      return _filterRelevant(songs, query);
    } catch (e) {
      print('JiosaavnService.search error: $e');
      return [];
    }
  }

  /// If we don't have a cached stream URL, fetch it from /api/songs/{id}.
  Future<String?> fetchStreamUrl(String songId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/songs/$songId');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final list = data['data'] as List<dynamic>? ?? [];
      if (list.isEmpty) return null;

      final dl = (list.first as Map<String, dynamic>)['downloadUrl']
      as List<dynamic>? ?? [];
      for (final d in dl) {
        final m = d as Map<String, dynamic>;
        if (m['quality'] == '320kbps') return m['url'] as String?;
      }
      return dl.isNotEmpty
          ? (dl.last as Map<String, dynamic>)['url'] as String?
          : null;
    } catch (e) {
      print('JiosaavnService.fetchStreamUrl error: $e');
      return null;
    }
  }

  // ═════════════════════════════════════════════
  // CLIENT-SIDE FILTERING
  // ═════════════════════════════════════════════

  /// Keeps songs where at least 2 non-trivial query tokens appear
  /// in the title or artist. Removes the "Ragasiya Kanavugal" noise
  /// when the user searched "raga of revenge".
  List<Song> _filterRelevant(List<Song> songs, String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return songs;

    final required = tokens.length >= 2 ? 2 : 1;

    return songs.where((s) {
      final text = '${s.title} ${s.artist}'.toLowerCase();
      int matches = 0;
      for (final t in tokens) {
        if (text.contains(t)) matches++;
      }
      return matches >= required;
    }).toList();
  }

  List<String> _tokens(String query) {
    const stopWords = {
      'the', 'and', 'for', 'from', 'with', 'feat', 'ft', 'of', 'a', 'an',
      'song', 'video', 'audio', 'lyrics', 'lyric',
    };
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !stopWords.contains(t))
        .toList();
  }

  void dispose() {
    _client.close();
  }
}