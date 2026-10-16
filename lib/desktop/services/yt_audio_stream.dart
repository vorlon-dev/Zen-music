// ZenMusic Desktop — ported from Echo Music (GPL-3.0), services/yt_audio_stream.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// PORT DEVIATIONS (marked inline):
//  1. Client chain updated for our vendored fork (synced to yt-dlp 2026-08-18):
//     visionOs → ios → android. Echo used androidVr, which YouTube 403s since
//     2026-08-17 (yt-dlp#17456).
//  2. googlevideo binds a stream URL to the minting client's User-Agent and
//     403s mismatches. _getManifestWithFallback returns the client that
//     actually minted the manifest; the cache stores it and every byte
//     request replays its headers (_clientRequestHeaders, logic copied from
//     the fork's stream_client.dart).
//  3. sortByBitrate is a local extension — the fork does not export
//     helpers_extension.dart.
//  4. YTMusic-dependent paths (none here) are deferred to R5.
//
// R3 DEBUG: the [yt_audio] prints are temporary instrumentation for the
// playback investigation — strip or downgrade at R4.

import 'dart:async';
import 'dart:io';
import '../utils/enhanced_image.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Ordered fallback chain (see header, deviation 1).
final List<YoutubeApiClient> kYtClientPriority = [
  YoutubeApiClient.visionOs,
  YoutubeApiClient.ios,
  YoutubeApiClient.android,
];

/// Shared YoutubeExplode instance — one HTTP client pool for the whole app.
final YoutubeExplode ytExplode = YoutubeExplode();

/// Resolved-stream cache (short-lived: minting clients can be blocked anytime).
final Map<
    String,
    ({
    AudioOnlyStreamInfo info,
    YoutubeApiClient client,
    DateTime expiry
    })> _streamInfoCache = {};

/// True if the stream has a usable direct URL. Clients behind YouTube's
/// PO-token/SABR wall can return descriptors with empty URLs — skip those.
bool _hasUsableUrl(AudioOnlyStreamInfo s) => s.url.host.isNotEmpty;

/// Headers that must accompany requests to URLs minted by [client]
/// (copied from the fork's stream_client.dart — deviation 2).
Map<String, String> _clientRequestHeaders(YoutubeApiClient client) {
  final clientCtx = client.payload['context']?['client'];
  final userAgent = clientCtx is Map ? clientCtx['userAgent'] as String? : null;
  return {
    if (userAgent != null) 'user-agent': userAgent,
    for (final entry in client.headers.entries) entry.key: '${entry.value}',
  };
}

Map<String, String> _mintedHeaders(String videoId, String quality) {
  final cached = _streamInfoCache['$videoId:$quality'];
  if (cached != null && DateTime.now().isBefore(cached.expiry)) {
    return _clientRequestHeaders(cached.client);
  }
  return const {};
}

/// Tries every client in [kYtClientPriority] until one returns a manifest
/// that actually contains audio streams with usable URLs. Returns the
/// manifest AND the client that produced it (deviation 2).
Future<({StreamManifest manifest, YoutubeApiClient client})>
_getManifestWithFallback(String videoId) async {
  Object? lastError;
  for (final client in kYtClientPriority) {
    try {
      final manifest = await ytExplode.videos.streams.getManifest(
        videoId,
        ytClients: [client],
      );

      final usable = manifest.audioOnly.where(_hasUsableUrl).toList();
      if (usable.isNotEmpty) {
        final clientName = client.payload['context']?['client']?['clientName'];
        print('[yt_audio] $videoId resolved via $clientName');
        return (manifest: manifest, client: client);
      }
      // Manifest came back but every stream is URL-less (PO-token wall).
      lastError = Exception('$client returned no audio streams with URLs');
      print('[yt_audio] $client: $lastError');
    } catch (e) {
      print('[yt_audio] $client failed: $e');
      lastError = e;
    }
  }
  throw Exception(
      'All YouTube clients failed to resolve $videoId. Last error: $lastError');
}

extension _BitrateSort on Iterable<AudioOnlyStreamInfo> {
  List<AudioOnlyStreamInfo> sortByBitrate() => toList()
    ..sort((a, b) =>
        a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
}

AudioOnlyStreamInfo? _selectAudioStream(
    StreamManifest manifest,
    String quality,
    ) {
  Iterable<AudioOnlyStreamInfo> supported =
  manifest.audioOnly.where(_hasUsableUrl);

  // Prefer mp4/m4a containers on Apple platforms for codec compatibility.
  if (Platform.isMacOS || Platform.isIOS) {
    final mp4Streams = supported
        .where((s) => s.container.name == 'mp4' || s.container.name == 'm4a')
        .toList();
    if (mp4Streams.isNotEmpty) supported = mp4Streams;
  }

  final sorted = supported.sortByBitrate(); // ascending bitrate
  return quality == 'high' ? sorted.lastOrNull : sorted.firstOrNull;
}

/// Resolves the best audio stream for [videoId], trying every client in
/// [kYtClientPriority]. Results are cached briefly.
Future<AudioOnlyStreamInfo> resolveAudioStreamInfo(
    String videoId,
    String quality,
    ) async {
  final key = '$videoId:$quality';
  final cached = _streamInfoCache[key];
  if (cached != null && DateTime.now().isBefore(cached.expiry)) {
    return cached.info;
  }

  final resolved = await _getManifestWithFallback(videoId);
  final info = _selectAudioStream(resolved.manifest, quality);
  if (info == null) {
    throw Exception('No audio stream available for this video.');
  }

  // Remember WHICH client minted this stream (deviation 2).
  _streamInfoCache[key] = (
  info: info,
  client: resolved.client,
  expiry: DateTime.now().add(const Duration(minutes: 10)),
  );
  return info;
}

// ----------------------------------------------------------------------------
// just_audio source
// ----------------------------------------------------------------------------

class YouTubeAudioSource extends StreamAudioSource {
  final String videoId;
  final String quality; // 'high' or 'low'

  YouTubeAudioSource({
    required this.videoId,
    required this.quality,
    super.tag,
  });

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    try {
      final audioStream = await resolveAudioStreamInfo(videoId, quality);

      start ??= 0;
      end ??= audioStream.isThrottled
          ? start + 10379935
          : audioStream.size.totalBytes;
      if (end > audioStream.size.totalBytes) {
        end = audioStream.size.totalBytes;
      }

      final stream = await _downloadStream(
        audioStream.url,
        start,
        end - 1,
        headers: _mintedHeaders(videoId, quality),
      );
      return StreamAudioResponse(
        sourceLength: audioStream.size.totalBytes,
        contentLength: end - start,
        offset: start,
        stream: stream,
        contentType: audioStream.codec.mimeType,
      );
    } catch (e) {
      print('[yt_audio] request($start,$end) failed: $e');
      throw Exception('Failed to load audio: $e');
    }
  }
}

// ----------------------------------------------------------------------------
// Generic HTTP streaming server
// ----------------------------------------------------------------------------

/// Starts a generic HTTP server that listens for requests to stream YouTube
/// audio. Clients must pass 'id' and 'quality' as URL query parameters.
/// The server binds to a random available port.
Future<String> createAudioStreamServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  server.listen((HttpRequest request) {
    handleAudioRequest(request);
  });

  final url = 'http://${server.address.host}:${server.port}/audio';

  print(
      'Generic streaming server started on $url. Use ?id=...&quality=... to stream.');

  return url;
}

Future<void> handleAudioRequest(HttpRequest request) async {
  final response = request.response;

  if (request.uri.path != '/audio') {
    response.statusCode = HttpStatus.notFound;
    response.write('404 Not Found');
    await response.close();
    return;
  }

  final queryParams = request.uri.queryParameters;
  final videoId = queryParams['id'];
  final quality = queryParams['quality'] ?? 'high';

  if (videoId == null || videoId.isEmpty) {
    response.statusCode = HttpStatus.badRequest;
    response.write('Missing required query parameter: id');
    await response.close();
    return;
  }

  print('Processing request for video ID: $videoId (Quality: $quality)');

  try {
    final audioStreamInfo = await resolveAudioStreamInfo(videoId, quality);
    final totalLength = audioStreamInfo.size.totalBytes;
    final reqHeaders = _mintedHeaders(videoId, quality);

    (int start, int end)? parseRange(String rangeHeader, int totalLength) {
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

    int start = 0;
    int end = totalLength - 1;
    bool isPartial = false;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      final range = parseRange(rangeHeader, totalLength);
      if (range != null) {
        start = range.$1;
        end = range.$2;
        isPartial = true;
      }
    }

    final stream = await _downloadStream(audioStreamInfo.url, start, end,
        headers: reqHeaders);

    final mimeType = audioStreamInfo.codec.mimeType;

    response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.parse(mimeType);
    if (isPartial) {
      response.headers.set(
          HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalLength');
    }
    response.bufferOutput = false;

    try {
      await for (final chunk in stream) {
        response.add(chunk);
      }
    } catch (streamError) {
      print('Stream error for $videoId: $streamError');
    }

    await response.close();
    print(
        '[$videoId] Served ${isPartial ? 'partial' : 'full'} stream: bytes $start-$end');
  } catch (e) {
    print('Error serving audio for ID $videoId: $e');
    try {
      response.statusCode = HttpStatus.internalServerError;
      response.write('Error: $e');
      await response.close();
    } catch (_) {}
  }
}

// ----------------------------------------------------------------------------
// Direct URL source (with caching)
// ----------------------------------------------------------------------------

final Map<String, ({String url, DateTime expiry})> _urlCache = {};

Future<AudioSource> getDirectUrlAudioSource(
    String videoId, String quality, dynamic tag) async {
  if (_urlCache.containsKey(videoId)) {
    final cached = _urlCache[videoId]!;
    if (DateTime.now().isBefore(cached.expiry)) {
      return AudioSource.uri(Uri.parse(cached.url),
          tag: tag, headers: _mintedHeaders(videoId, quality));
    }
    _urlCache.remove(videoId); // Expired
  }

  try {
    final audioStream = await resolveAudioStreamInfo(videoId, quality);

    _urlCache[videoId] = (
    url: audioStream.url.toString(),
    expiry: DateTime.now().add(const Duration(minutes: 10)),
    );

    return AudioSource.uri(audioStream.url,
        tag: tag, headers: _mintedHeaders(videoId, quality));
  } catch (e) {
    print('Error fetching URL for $videoId: $e');
    rethrow;
  }
}

// ----------------------------------------------------------------------------
// Byte transport
// ----------------------------------------------------------------------------

Future<HttpClientResponse> _downloadStream(Uri url, int start, int end,
    {Map<String, String> headers = const {}}) async {
  final client = HttpClient();
  final request = await client.getUrl(url);
  request.headers.add(HttpHeaders.rangeHeader, 'bytes=$start-$end');
  headers.forEach(request.headers.add);
  final response = await request.close();
  print('[yt_audio] GET ${url.host} [$start-$end] -> ${response.statusCode}');
  return response;
}