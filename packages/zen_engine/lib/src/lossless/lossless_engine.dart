import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum LosslessQuality {
  mp3_320('MP3 320 kbps', 'Compressed — lightest on data', 'mp3_320'),
  flacCd('Lossless CD', 'FLAC 16-bit / 44.1 kHz — CD quality', 'flac_cd'),
  flacHiRes96('Hi-Res Lossless', 'FLAC 24-bit / up to 96 kHz', 'flac_hires_96'),
  flacHiResMax('Hi-Res Max', 'FLAC 24-bit / up to 192 kHz — studio master', 'flac_hires_192');

  const LosslessQuality(this.label, this.detail, this.tierKey);
  final String label;
  final String detail;
  final String tierKey;
}

/// Lossless stream resolver with fallback ladder (Hi-Res Max -> Hi-Res 96 -> FLAC CD -> MP3 320).
class LosslessEngine {
  LosslessEngine({this.endpoint = 'https://jobfolw.antideploy.app/'});

  final String endpoint;
  LosslessQuality preferredQuality = LosslessQuality.flacCd;

  final Map<String, ({Map<String, String> streams, DateTime expiry})> _streamCache = {};
  final Map<String, DateTime> _failCache = {};

  static const _positiveTtl = Duration(minutes: 8);
  static const _negativeTtl = Duration(minutes: 5);

  /// Resolves direct stream URL for a given YouTube video ID based on quality preferences.
  Future<String?> resolveStreamUrl(String videoId, {LosslessQuality? targetQuality}) async {
    final streams = await resolveStreams(videoId);
    if (streams == null || streams.isEmpty) return null;

    final wanted = targetQuality ?? preferredQuality;
    for (final tier in _ladderFrom(wanted)) {
      final url = streams[tier.tierKey];
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  /// Resolves raw streams mapping (tierKey -> streamUrl) for a track.
  Future<Map<String, String>?> resolveStreams(String videoId) async {
    final now = DateTime.now();

    final hit = _streamCache[videoId];
    if (hit != null && now.isBefore(hit.expiry)) return hit.streams;

    final failedAt = _failCache[videoId];
    if (failedAt != null && now.isBefore(failedAt)) return null;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      client.userAgent = 'ZenEngine/1.0 (lossless)';
      final request = await client
          .getUrl(Uri.parse('$endpoint?id=$videoId'))
          .timeout(const Duration(seconds: 12));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        _failCache[videoId] = now.add(_negativeTtl);
        return null;
      }

      final data = jsonDecode(body);
      if (data is! Map || data['status'] != 'success') {
        _failCache[videoId] = now.add(_negativeTtl);
        return null;
      }

      final streams = <String, String>{};
      final raw = data['streams'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = '${entry.key}';
          final url = entry.value is Map ? entry.value['url'] as String? : null;
          if (url != null && url.isNotEmpty) streams[key] = url;
        }
      }

      if (streams.isEmpty) {
        _failCache[videoId] = now.add(_negativeTtl);
        return null;
      }

      _streamCache[videoId] = (streams: streams, expiry: now.add(_positiveTtl));
      return streams;
    } catch (_) {
      _failCache[videoId] = now.add(_negativeTtl);
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  List<LosslessQuality> _ladderFrom(LosslessQuality wanted) {
    final all = LosslessQuality.values;
    final start = all.indexOf(wanted);
    return [for (var i = start; i >= 0; i--) all[i]];
  }
}
