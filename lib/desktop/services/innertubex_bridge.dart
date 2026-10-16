// ZenMusic Desktop — ported from the retired mobile stack's
// innertubex_bridge.dart. ZenMusic remains GPL-3.0.
// NATIVE ANDROID ONLY: talks to the zen/innertubex MethodChannel (Kotlin
// host, untouched on this branch). On Windows/other platforms every call
// reports available=false and returns null/empty — callers must gate.
// relatedSongs returns desktop song maps (was: retired Song model).

import 'package:flutter/services.dart';

/// One stream minted by the native extraction resolver.
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

/// Audio + video streams from one native extraction (video watch page).
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

/// One selectable video quality for the watch page's picker.
class ItxVideoQuality {
  const ItxVideoQuality({required this.height, required this.kbps});

  final int height;
  final int kbps;

  static ItxVideoQuality? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final h = (raw['height'] as num?)?.toInt() ?? 0;
    if (h <= 0) return null;
    return ItxVideoQuality(
      height: h,
      kbps: (raw['kbps'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Dart bridge to the native extraction resolver (zen/innertubex —
/// legacy channel name, deliberately kept).
class InnertubexBridge {
  InnertubexBridge._();

  static const _channel = MethodChannel('zen/innertubex');

  static bool? _available;
  static String? _visitorData;

  /// True once the native channel answered at least once (null until
  /// first probe; false after a MissingPluginException — non-Android).
  static bool? get available => _available;

  static Future<bool> warm() async {
    try {
      await _channel.invokeMethod('onSessionChanged');
      _available = true;
    } on MissingPluginException {
      _available = false;
    } catch (_) {
      _available = true;
    }
    return _available ?? false;
  }

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

  static Future<ItxStream?> extract(String videoId,
      {int maxKbps = 160,
        bool requireM4a = false,
        Set<String> skipClients = const {}}) async {
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

  static Future<ItxVideoStreams?> extractVideo(String videoId,
      {int maxHeight = 0}) async {
    try {
      final raw = await _channel.invokeMethod('extractVideo', {
        'videoId': videoId,
        'maxHeight': maxHeight,
      });
      return ItxVideoStreams.fromMap(raw);
    } on MissingPluginException {
      _available = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<ItxVideoQuality>> videoQualities(String videoId) async {
    try {
      final raw = await _channel.invokeMethod('videoQualities', {
        'videoId': videoId,
      });
      if (raw is! List) return const [];
      return raw
          .map<ItxVideoQuality?>((e) => ItxVideoQuality.fromMap(e))
          .whereType<ItxVideoQuality>()
          .toList();
    } on MissingPluginException {
      _available = false;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Related songs — desktop song maps (videoId/title/artists/thumbnails).
  static Future<List<Map<String, dynamic>>> relatedSongs(String videoId) async {
    try {
      final raw = await _channel.invokeMethod('relatedSongs', {
        'videoId': videoId,
      });
      if (raw is! List) return const [];
      return [
        for (final e in raw)
          if (e is Map && (e['id']?.toString() ?? '').isNotEmpty)
            {
              'videoId': e['id']?.toString() ?? '',
              'title': e['title']?.toString() ?? 'Video',
              'artist': e['artist']?.toString() ?? 'YouTube',
              'thumbnails': [
                {
                  'url': e['thumbnail']?.toString() ??
                      'https://i.ytimg.com/vi/${e['id']}/mqdefault.jpg',
                },
              ],
            },
      ];
    } on MissingPluginException {
      _available = false;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<String?> channelThumb(String videoId) async {
    try {
      final v = await _channel.invokeMethod('channelThumb', {
        'videoId': videoId,
      });
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> onRefused(String url) async {
    try {
      return await _channel.invokeMethod('onRefused', {'url': url}) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> onSessionChanged() async {
    try {
      await _channel.invokeMethod('onSessionChanged');
    } catch (_) {}
  }
}