import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/song.dart';

/// Qobuz lossless tier via the self-hosted matcher microservice
/// (github.com/vorlon-dev/qobuz-api — MIT, based on
/// Anattana-Labs/qobuz-api).
///
/// Contract: GET /?id=<youtubeVideoId> →
/// {
///   status: "success",
///   ytmusic:    { videoId, title, artist, duration },
///   matched_track: { id, title, artist, album, duration, hires,
///                    maximum_bit_depth, maximum_sampling_rate },
///   streams: { <name>: { label, format_id, mime_type, bit_depth,
///                        sampling_rate, url } }
/// }
///
/// The service does its own strict matching (title normalization,
/// Jaccard artist similarity, ±3s duration) against YouTube metadata.
/// This client adds a loose second line of defense — duration vs the
/// song (±15s) and artist word overlap — then picks the best stream
/// generically: FLAC preferred, then highest bit_depth × sample_rate.
/// No stream key names are hardcoded (the service may add tiers).
///
/// Any failure → null and the caller falls through its normal chain.
/// Misses are negative-cached 30 min so a catalog miss costs at most
/// one bounded stall per song.
///
/// Bitrate reporting: a real 24/88.2 stream once reported "9kbps"
/// because the chosen stream entry lacked depth/rate fields. kbps is
/// now only computed when BOTH fields are present; otherwise the tier
/// estimate (FLAC ≈ 900 kbps) is used, and any implausible value
/// (<100 kbps) is replaced by it. Matched-track metadata (which
/// reliably carries bit depth / sample rate) is preferred in logs.
class QobuzService {
  /// Kill switch — flip in code if the service misbehaves. A settings
  /// toggle can replace this in a later round if the miss latency
  /// bothers daily use.
  static bool serviceEnabled = true;

  static const _serviceBase = 'https://qobuz-api.antideploy.app';
  static const _requestTimeout = Duration(seconds: 8);
  static const _negativeTtl = Duration(minutes: 30);
  static const _durationToleranceSec = 15;

  /// Fallback tier estimate when a stream entry omits depth/rate:
  /// stereo FLAC averages roughly 800–1000 kbps. Used for the badge
  /// instead of garbage.
  static const _flacKbpsEstimate = 900;

  final http.Client _client = http.Client();
  final Map<String, DateTime> _negativeCache = {};

  void dispose() => _client.close();

  /// Lossless attempt for a default-chain song. Returns null when the
  /// tier is off, the service can't be reached, no confident match
  /// exists, or no full-quality stream is available.
  Future<({String url, Map<String, String> headers, int? kbps})?>
  tryLossless(Song song) async {
    if (!serviceEnabled) return null;
    // JioSaavn songs have a non-YouTube id and their own 320kbps tier.
    if (song.isFromJiosaavn) return null;

    final neg = _negativeCache[song.id];
    if (neg != null && DateTime.now().difference(neg) < _negativeTtl) {
      return null;
    }

    try {
      final uri = Uri.parse('$_serviceBase/')
          .replace(queryParameters: {'id': song.id});
      final resp = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_requestTimeout);

      if (resp.statusCode != 200) {
        return _miss(song.id);
      }
      final body = resp.body;
      // Cold-start 5xx pages and HTML error pages are not JSON.
      if (body.trimLeft().startsWith('<')) {
        return _miss(song.id);
      }
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return _miss(song.id);
      if (decoded['status'] != 'success') return _miss(song.id);

      final matched = decoded['matched_track'];
      if (matched is! Map) return _miss(song.id);
      final mt = Map<String, dynamic>.from(matched);

      // ── Loose re-validation (the service matched against YouTube
      // metadata; this guards against a bad deploy or drift) ──
      final matchDur = (mt['duration'] as num?)?.toInt() ?? 0;
      final songDur = song.duration.inSeconds;
      if (songDur > 0 && matchDur > 0 &&
          (matchDur - songDur).abs() > _durationToleranceSec) {
        return _miss(song.id);
      }
      if (!_artistPlausible(song.artist, '${mt['artist'] ?? ''}')) {
        return _miss(song.id);
      }

      // ── Best stream pick (generic over key names) ──
      final streams = decoded['streams'];
      if (streams is! Map) return _miss(song.id);
      ({String url, int? kbps, int score})? best;
      streams.forEach((key, value) {
        if (value is! Map) return;
        final m = Map<String, dynamic>.from(value);
        final url = '${m['url'] ?? ''}';
        if (url.isEmpty) return;
        final mime = '${m['mime_type'] ?? ''}'.toLowerCase();
        final depth = (m['bit_depth'] as num?)?.toInt() ?? 0;
        final rate = (m['sampling_rate'] as num?)?.toInt() ?? 0;
        var score = 0;
        if (mime.contains('flac')) score += 100000;
        score += depth * 1000 + rate;
        // Stereo bitrate estimate: depth(bits) × rate(Hz) × 2ch → kbps.
        // GUARD: only when BOTH fields are present — a missing field
        // must not produce garbage (a real 24/88.2 stream once printed
        // "9kbps" because its entry lacked them).
        final kbps = depth > 0 && rate > 0
            ? ((depth * rate * 2) / 1000).round()
            : (mime.contains('flac') ? _flacKbpsEstimate : null);
        if (best == null || score > best!.score) {
          best = (url: url, kbps: kbps, score: score);
        }
      });
      final pick = best;
      if (pick == null) return _miss(song.id);

      // Plausibility floor: the picked stream's computed kbps may
      // still be absent or nonsense; the matched-track metadata is
      // the more reliable source, and the tier estimate is the floor.
      final mtDepth = (mt['maximum_bit_depth'] as num?)?.toInt() ?? 0;
      final mtRate = (mt['maximum_sampling_rate'] as num?)?.toInt() ?? 0;
      int? kbpsOut;
      if (pick.kbps != null && pick.kbps! >= 100) {
        kbpsOut = pick.kbps;
      } else if (mtDepth > 0 && mtRate > 0) {
        kbpsOut = ((mtDepth * mtRate * 2) / 1000).round();
      } else if (pick.url.toLowerCase().contains('flac')) {
        kbpsOut = _flacKbpsEstimate;
      }

      print('🎵 Qobuz lossless: "${song.title}" → '
          '${mt['title']} '
          '(${mt['maximum_bit_depth'] ?? '?'}-bit/'
          '${mt['maximum_sampling_rate'] ?? '?'}kHz)'
          '${kbpsOut != null ? ' ≈${kbpsOut}kbps' : ''}');
      return (
      url: pick.url,
      headers: const <String, String>{},
      kbps: kbpsOut,
      );
    } catch (_) {
      // Network errors count as a miss too — a down service must not
      // be hammered on every play.
      return _miss(song.id);
    }
  }

  /// Records a negative-cache entry and returns the null result the
  /// caller propagates. Typed as the record so `return _miss(id);`
  /// compiles everywhere it's used.
  ({String url, Map<String, String> headers, int? kbps})? _miss(
      String songId) {
    _negativeCache[songId] = DateTime.now();
    return null;
  }

  /// Artist sanity: at least one meaningful word in common. Both
  /// directions checked; empty data never blocks.
  static bool _artistPlausible(String expected, String found) {
    final e = expected.toLowerCase();
    final f = found.toLowerCase();
    if (e.isEmpty || f.isEmpty) return true;
    final eWords = e
        .split(RegExp(r'[,;&\s]+'))
        .where((w) => w.length > 2)
        .toSet();
    final fWords = f
        .split(RegExp(r'[,;&\s]+'))
        .where((w) => w.length > 2)
        .toSet();
    if (eWords.isEmpty || fWords.isEmpty) return true;
    return eWords.any(fWords.contains) || fWords.any(eWords.contains);
  }
}