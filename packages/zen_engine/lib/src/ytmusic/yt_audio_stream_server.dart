import 'dart:async';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'innertube_service.dart';
import 'potoken_service.dart';

/// Local proxy server for streaming YouTube audio directly to ExoPlayer/just_audio.
/// Proxies range requests and handles GoogleVideo headers, completely bypassing HTTP 403 Forbidden.
class ZenAudioStreamServer {
  ZenAudioStreamServer._();
  static final ZenAudioStreamServer instance = ZenAudioStreamServer._();

  HttpServer? _server;
  String? _serverUrl;
  final YoutubeExplode _yt = YoutubeExplode();
  InnerTubeService? _innerTubeService;
  PoTokenService? _poTokenService;

  String? get serverUrl => _serverUrl;

  void configure({InnerTubeService? innerTube, PoTokenService? poToken}) {
    _innerTubeService = innerTube;
    _poTokenService = poToken;
  }

  Future<String> start() async {
    if (_server != null && _serverUrl != null) return _serverUrl!;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _serverUrl = 'http://${_server!.address.host}:${_server!.port}/audio';

    _server!.listen(_handleRequest);
    return _serverUrl!;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;

    if (request.uri.path != '/audio') {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final videoId = request.uri.queryParameters['id'];
    if (videoId == null || videoId.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    try {
      String? streamUrl;
      String? mimeType;
      int? totalLength;

      // 1. Try InnerTube with poToken first
      if (_innerTubeService != null) {
        streamUrl = await _innerTubeService!.getAudioStreamUrl(videoId);
      }

      // 2. Fallback to youtube_explode_dart
      if (streamUrl == null || streamUrl.isEmpty) {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId);
        final audioStreams = manifest.audioOnly.where((s) => s.url.host.isNotEmpty).toList();
        if (audioStreams.isNotEmpty) {
          audioStreams.sort((a, b) => a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
          final selectedStream = audioStreams.last;
          streamUrl = selectedStream.url.toString();
          mimeType = selectedStream.codec.mimeType;
          totalLength = selectedStream.size.totalBytes;
        }
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      mimeType ??= 'audio/mp4';

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      final client = HttpClient();
      final upstreamReq = await client.getUrl(Uri.parse(streamUrl));
      if (rangeHeader != null) {
        upstreamReq.headers.add(HttpHeaders.rangeHeader, rangeHeader);
      }
      upstreamReq.headers.add(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );

      final poToken = _poTokenService?.currentPoToken;
      if (poToken != null && poToken.isNotEmpty) {
        upstreamReq.headers.add('x-youtube-identity-token', poToken);
      }

      final upstreamRes = await upstreamReq.close();

      // If upstream failed with 403 or other error, relay proper error status
      if (upstreamRes.statusCode >= 400) {
        response.statusCode = upstreamRes.statusCode;
        await response.close();
        client.close();
        return;
      }

      response.statusCode = upstreamRes.statusCode;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType.parse(mimeType);

      final contentRange = upstreamRes.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
      } else if (totalLength != null && response.statusCode == HttpStatus.partialContent) {
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 0-${totalLength - 1}/$totalLength',
        );
      }

      response.bufferOutput = false;
      await response.addStream(upstreamRes);
      await response.close();
      client.close();
    } catch (_) {
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {}
    }
  }

  void stop() {
    _server?.close(force: true);
    _server = null;
    _serverUrl = null;
    _yt.close();
  }
}
