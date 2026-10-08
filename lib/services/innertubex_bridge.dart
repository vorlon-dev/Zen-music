import 'package:flutter/services.dart';

/// One stream minted by the native InnerTubeX resolver.
class ItxStream {
  const ItxStream({
    required this.videoId,
    required this.url,
    required this.kbps,
    required this.mimeType,
    required this.clientName,
    required this.profileId,
    required this.headers,
    this.loudnessDb,
  });

  final String videoId;
  final String url;
  final int kbps;
  final String mimeType;
  final String clientName;
  final String profileId;
  final Map<String, String> headers;
  final double? loudnessDb;

  static ItxStream? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return ItxStream(
      videoId: raw['videoId']?.toString() ?? '',
      url: url,
      kbps: (raw['kbps'] as num?)?.toInt() ?? 0,
      mimeType: raw['mimeType']?.toString() ?? '',
      clientName: raw['clientName']?.toString() ?? '',
      profileId: raw['profileId']?.toString() ?? '',
      loudnessDb: (raw['loudnessDb'] as num?)?.toDouble(),
      headers: (raw['headers'] as Map? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
    );
  }
}

/// Audio + video streams from one ITX extraction (video watch page).
/// [videoUrl] is ⚠️ UNVERIFIED — null when the native side has no
/// video stream for the video (callers then fall back).
class ItxVideoStreams {
  const ItxVideoStreams({
    required this.videoId,
    required this.headers,
    required this.clientName,
    this.audioUrl,
    this.videoUrl,
  });

  final String videoId;
  final String? audioUrl;
  final String? videoUrl;
  final Map<String, String> headers;
  final String clientName;

  static ItxVideoStreams? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return ItxVideoStreams(
      videoId: raw['videoId']?.toString() ?? '',
      audioUrl: raw['audioUrl']?.toString(),
      videoUrl: raw['videoUrl']?.toString(),
      headers: (raw['headers'] as Map? ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      clientName: raw['clientName']?.toString() ?? '',
    );
  }
}

/// Dart bridge to the native InnerTubeX resolver (zen/innertubex).
class InnertubexBridge {
  InnertubexBridge._();

  static const _channel = MethodChannel('zen/innertubex');

  static bool? _available;
  static String? _visitorData;

  /// True once the native channel answered at least once (null until
  /// first probe; false after a MissingPluginException — old APK).
  static bool? get available => _available;

  /// Warm-up probe; also primes the native resolver.
  static Future<bool> warm() async {
    try {
      await _channel.invokeMethod('onSessionChanged');
      _available = true;
    } on MissingPluginException {
      _available = false;
    } catch (_) {
      _available = true; // channel exists; the call itself failed benignly
    }
    return _available ?? false;
  }

  /// The InnerTube session identity (visitorData) bootstrapped natively.
  /// Required context for param-filtered home browse (chips) — without
  /// it YouTube returns an empty shell. Cached after the first fetch.
  static Future<String?> getVisitorData() async {
    if (_visitorData != null) return _visitorData;
    try {
      final v = await _channel.invokeMethod('getVisitorData');
      _visitorData = v is String && v.isNotEmpty ? v : null;
    } on MissingPluginException {
      _available = false;
    } catch (_) {}
    return _visitorData;
  }

  /// Extracts a stream for [videoId], or null when every client is
  /// refused/excluded.
  static Future<ItxStream?> extract(
      String videoId, {
        int maxKbps = 160,
        bool requireM4a = false,
        Set<String> skipClients = const {},
      }) async {
    try {
      final raw = await _channel.invokeMethod('extract', {
        'videoId': videoId,
        'maxKbps': maxKbps,
        'requireM4a': requireM4a,
        'skipClients': skipClients.toList(),
      });
      return ItxStream.fromMap(raw);
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Audio + video extraction for the video watch page. Returns null
  /// when extraction fails entirely; [ItxVideoStreams.videoUrl] is
  /// null when the native side has audio but no video stream.
  static Future<ItxVideoStreams?> extractVideo(String videoId) async {
    try {
      final raw = await _channel.invokeMethod('extractVideo', {
        'videoId': videoId,
      });
      return ItxVideoStreams.fromMap(raw);
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Reports a mid-playback refusal of [url]; returns the videoId it
  /// was minted for (null when the resolver didn't mint it), so the
  /// caller can re-extract excluding the offending client.
  static Future<String?> onRefused(String url) async {
    try {
      return await _channel.invokeMethod('onRefused', {'url': url}) as String?;
    } catch (_) {
      return null;
    }
  }

  /// Clears exclusions and re-warms.
  static Future<void> onSessionChanged() async {
    try {
      await _channel.invokeMethod('onSessionChanged');
    } catch (_) {}
  }
}