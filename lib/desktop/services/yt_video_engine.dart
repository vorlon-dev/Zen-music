import 'dart:async';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Public surface of yt_audio_stream.dart: shared YoutubeExplode instance
// (one HTTP client pool for the whole app), the client priority chain, and
// the proven /audio byte proxy.
import 'yt_audio_stream.dart'
    show ytExplode, handleAudioRequest, kYtClientPriority;

// ------------------------------------------------------------- result types

/// Same shape the watch page already consumes (was ItxVideoStreams).
class YtVideoStreams {
  /// Local proxy URL of the video (muxed file or adaptive video track).
  final String? videoUrl;

  /// Local proxy URL of the audio track, or null for muxed streams.
  final String? audioUrl;

  /// Always empty: upstream headers are added by the local proxy. Kept so
  /// the page's Media(...) call stays shape-compatible.
  final Map<String, String> headers;

  /// Resolved height actually served (matches videoUrl's &h= parameter).
  final int height;

  const YtVideoStreams({
    required this.videoUrl,
    required this.audioUrl,
    required this.headers,
    required this.height,
  });
}

/// Same shape the watch page already consumes (was ItxVideoQuality).
class YtVideoQuality {
  final int height;
  const YtVideoQuality(this.height);
}

// ------------------------------------------------------------- candidates

/// One playable video candidate minted by a specific client.
class _Res {
  final int height;
  final bool muxed; // true → audio+video in one file
  final Uri url; // upstream googlevideo URL
  final YoutubeApiClient client; // client that minted [url]
  final String mime; // video/mp4 | video/webm
  final int totalBytes;

  const _Res({
    required this.height,
    required this.muxed,
    required this.url,
    required this.client,
    required this.mime,
    required this.totalBytes,
  });
}

/// Per-videoId candidate cache (URLs stay valid ~6 h, clients can be blocked
/// anytime — short TTL + in-flight dedupe, same policy as yt_audio_stream).
final Map<String, ({Future<List<_Res>> f, DateTime at})> _resCache = {};
const Duration _resTtl = Duration(minutes: 10);

Future<List<_Res>> _candidates(String videoId) {
  final cached = _resCache[videoId];
  if (cached != null && DateTime.now().difference(cached.at) < _resTtl) {
    return cached.f;
  }
  if (_resCache.length > 24) _resCache.remove(_resCache.keys.first);

  final f = _resolveCandidates(videoId).then((list) {
    if (list.isEmpty) _resCache.remove(videoId); // don't cache failures
    return list;
  });
  _resCache[videoId] = (f: f, at: DateTime.now());
  return f;
}

/// Tries every client in [kYtClientPriority] until one returns a manifest
/// with usable video/muxed streams. Returns the candidates AND remembers
/// which client minted each (header replay — deviation 1).
Future<List<_Res>> _resolveCandidates(String videoId) async {
  Object? lastError;
  for (final client in kYtClientPriority) {
    try {
      final manifest = await ytExplode.videos.streams.getManifest(
        videoId,
        ytClients: [client],
      );

      final res = <_Res>[
        for (final s in manifest.muxed)
          if (s.url.host.isNotEmpty)
            _Res(
              height: s.videoResolution.height,
              muxed: true,
              url: s.url,
              client: client,
              mime: s.container.name.toLowerCase().contains('webm')
                  ? 'video/webm'
                  : 'video/mp4',
              totalBytes: s.size.totalBytes,
            ),
        for (final s in manifest.videoOnly)
          if (s.url.host.isNotEmpty)
            _Res(
              height: s.videoResolution.height,
              muxed: false,
              url: s.url,
              client: client,
              mime: s.container.name.toLowerCase().contains('webm')
                  ? 'video/webm'
                  : 'video/mp4',
              totalBytes: s.size.totalBytes,
            ),
      ];

      if (res.isNotEmpty) {
        final name = client.payload['context']?['client']?['clientName'];
        print('[yt_video] $videoId resolved via $name '
            '(${res.length} streams, muxed: ${res.any((r) => r.muxed)})');
        return res;
      }
      lastError = Exception('$client returned no video streams with URLs');
      print('[yt_video] $client: $lastError');
    } catch (e) {
      print('[yt_video] $client failed for $videoId: $e');
      lastError = e;
    }
  }
  throw Exception(
      'All YouTube clients failed to resolve video for $videoId. '
          'Last error: $lastError');
}

// ------------------------------------------------------------- selection

/// Picks the candidate for [ask]: 0 = auto (best available), else the
/// highest height ≤ ask (or the smallest available if nothing is below).
/// At the chosen height: muxed wins (single file), then mp4 over webm,
/// then the larger file (≈ higher bitrate).
_Res? _pick(List<_Res> pool, int ask) {
  if (pool.isEmpty) return null;
  final cands = pool.where((r) => r.height > 0).toList();
  if (cands.isEmpty) cands.addAll(pool);

  int target;
  if (ask <= 0) {
    target = cands.map((r) => r.height).reduce((a, b) => a > b ? a : b);
  } else {
    final below = cands.where((r) => r.height <= ask).toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    target = below.isNotEmpty
        ? below.first.height
        : cands.map((r) => r.height).reduce((a, b) => a < b ? a : b);
  }

  final atTarget = cands.where((r) => r.height == target).toList()
    ..sort((a, b) {
      if (a.muxed != b.muxed) return a.muxed ? -1 : 1;
      final am = a.mime == 'video/mp4' ? 0 : 1;
      final bm = b.mime == 'video/mp4' ? 0 : 1;
      if (am != bm) return am - bm;
      return b.totalBytes.compareTo(a.totalBytes);
    });
  return atTarget.first;
}

// ------------------------------------------------------------- public API

class YtVideoEngine {
  YtVideoEngine._();

  /// Resolves playback URLs for [videoId] at [maxHeight] (0 = best).
  /// Returned URLs are LOCAL proxy URLs — see the header for why.
  static Future<YtVideoStreams?> extractVideo(
      String videoId, {
        int maxHeight = 0,
      }) async {
    try {
      final base = await _serverBase();
      final pool = await _candidates(videoId);
      final picked = _pick(pool, maxHeight);
      if (picked == null) return null;
      return YtVideoStreams(
        videoUrl: '$base/video?id=$videoId&h=${picked.height}',
        audioUrl: picked.muxed ? null : '$base/audio?id=$videoId&q=high',
        headers: const {},
        height: picked.height,
      );
    } catch (e) {
      print('[yt_video] extractVideo($videoId, $maxHeight) failed: $e');
      return null;
    }
  }

  /// Distinct available heights, highest first (page sorts again anyway).
  static Future<List<YtVideoQuality>> videoQualities(String videoId) async {
    try {
      final pool = await _candidates(videoId);
      final heights = pool
          .map((r) => r.height)
          .where((h) => h > 0)
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));
      return [for (final h in heights) YtVideoQuality(h)];
    } catch (e) {
      print('[yt_video] videoQualities($videoId) failed: $e');
      return const [];
    }
  }

  /// v1 related list (deviation 2): title search, self excluded.
  /// The page renders an empty list gracefully if this fails.
  static Future<List<Map<String, dynamic>>> relatedSongs(
      String videoId) async {
    try {
      final v = await ytExplode.videos.get(videoId);
      final q = v.title.trim();
      if (q.isEmpty) return const [];
      final results = (await ytExplode.search.search(q)).toList();
      final out = <Map<String, dynamic>>[];
      for (final r in results) {
        final rid = r.id.value;
        if (rid == videoId || rid.length != 11) continue;
        final title = r.title.trim();
        if (title.isEmpty) continue;
        out.add({'videoId': rid, 'title': title, 'subtitle': r.author});
        if (out.length >= 20) break;
      }
      return out;
    } catch (e) {
      print('[yt_video] relatedSongs($videoId) failed: $e');
      return const [];
    }
  }
}

// ------------------------------------------------------------- byte proxy

HttpServer? _srv;
String? _base;

/// Loopback server singleton, app-lifetime. /audio delegates to the proven
/// handleAudioRequest; /video is implemented here for adaptive streams.
Future<String> _serverBase() async {
  final b = _base;
  if (b != null) return b;
  final srv = _srv ?? await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _srv = srv;
  srv.listen(_route, onError: (Object e) => print('[yt_video] server: $e'));
  _base = 'http://127.0.0.1:${srv.port}';
  print('[yt_video] proxy started on $_base');
  return _base!;
}

Future<void> _route(HttpRequest request) async {
  switch (request.uri.path) {
    case '/audio':
      await handleAudioRequest(request); // proven path from yt_audio_stream
      return;
    case '/video':
      await _serveVideo(request);
      return;
    default:
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('404 Not Found');
      await request.response.close();
  }
}

Future<void> _serveVideo(HttpRequest request) async {
  final response = request.response;
  final videoId = request.uri.queryParameters['id'] ?? '';
  final ask = int.tryParse(request.uri.queryParameters['h'] ?? '') ?? 0;

  if (videoId.length != 11) {
    response.statusCode = HttpStatus.badRequest;
    response.write('Missing/invalid id');
    await response.close();
    return;
  }

  try {
    final picked = _pick(await _candidates(videoId), ask);
    if (picked == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final total = picked.totalBytes;
    var start = 0;
    var end = total - 1;
    var isPartial = false;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final range = _parseRange(rangeHeader, total);
      if (range != null) {
        start = range.$1;
        end = range.$2;
        isPartial = true;
      }
    }

    final upstream = await _openUpstream(
      picked.url,
      start,
      end,
      _replayHeaders(picked.client),
    );

    response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.parse(picked.mime);
    if (isPartial) {
      response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$total');
    }
    response.headers.contentLength = end - start + 1;
    response.bufferOutput = false;

    if (request.method == 'HEAD') {
      await upstream.drain<void>().catchError((_) {});
      await response.close();
      return;
    }

    try {
      await for (final chunk in upstream) {
        response.add(chunk);
      }
    } catch (streamError) {
      print('[yt_video] upstream stall for $videoId: $streamError');
    }
    await response.close();
    print('[yt_video] $videoId h=${picked.height} served '
        '${isPartial ? 'partial' : 'full'} [$start-$end]');
  } catch (e) {
    print('[yt_video] /video error for $videoId: $e');
    try {
      response.statusCode = HttpStatus.badGateway;
      response.write('Error: $e');
      await response.close();
    } catch (_) {}
  }
}

Future<HttpClientResponse> _openUpstream(
    Uri url, int start, int end, Map<String, String> headers) async {
  final client = HttpClient();
  final req = await client.getUrl(url);
  req.headers.add(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  headers.forEach(req.headers.add);
  final resp = await req.close();
  print('[yt_video] GET ${url.host} [$start-$end] -> ${resp.statusCode}');
  return resp;
}

/// Headers that must accompany requests to URLs minted by [client].
/// COPIED from yt_audio_stream.dart (_clientRequestHeaders) — KEEP IN SYNC.
Map<String, String> _replayHeaders(YoutubeApiClient client) {
  final clientCtx = client.payload['context']?['client'];
  final userAgent = clientCtx is Map ? clientCtx['userAgent'] as String? : null;
  return {
    if (userAgent != null) 'user-agent': userAgent,
    for (final entry in client.headers.entries) entry.key: '${entry.value}',
  };
}

/// COPIED from yt_audio_stream.dart — KEEP IN SYNC.
(int, int)? _parseRange(String rangeHeader, int totalLength) {
  if (!rangeHeader.startsWith('bytes=')) return null;
  final parts = rangeHeader.substring(6).split('-');
  if (parts.length != 2) return null;
  final start = int.tryParse(parts[0]) ?? 0;
  final end = parts[1].isEmpty ? totalLength - 1 : int.tryParse(parts[1]);
  if (end == null ||
      end >= totalLength ||
      start >= totalLength ||
      start > end) {
    return null;
  }
  return (start, end);
}