import 'package:flutter/services.dart';

import '../models/song.dart';

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

/// Audio + video streams from one native extraction (video watch
/// page). [videoUrl] is null when the native response has no direct
/// video-only stream (callers fall back).
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

/// One selectable video quality for the watch page's picker
/// (YouTube-style): a height and its best bitrate.
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
/// legacy channel name, deliberately kept: every Dart call site
/// keeps working across the innertubex → :innertube migration).
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

  /// Audio + video extraction for the video watch page. [maxHeight]
  /// caps the video stream (quality picker; 0/null = default best
  /// ≤1080p pick). Returns null when extraction fails entirely;
  /// [ItxVideoStreams.videoUrl] is null when the native side has
  /// audio but no video stream.
  static Future<ItxVideoStreams?> extractVideo(
      String videoId, {
        int maxHeight = 0,
      }) async {
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

  /// Available video qualities for the picker (distinct heights,
  /// descending; empty when the quality cache is cold — the UI hides
  /// the picker in that case).
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

  /// Related songs from the native watch-next — the queue fallback
  /// when the radio service returns nothing. Durations are absent
  /// in the payload (zeros; the watch UI hides empty durations).
  static Future<List<Song>> relatedSongs(String videoId) async {
    try {
      final raw = await _channel.invokeMethod('relatedSongs', {
        'videoId': videoId,
      });
      if (raw is! List) return const [];
      return raw
          .map<Song>((e) {
        final m = e as Map;
        return Song(
          id: m['id']?.toString() ?? '',
          title: m['title']?.toString() ?? 'Video',
          artist: m['artist']?.toString() ?? 'YouTube',
          thumbnail: m['thumbnail']?.toString() ??
              'https://i.ytimg.com/vi/${m['id']}/mqdefault.jpg',
          duration: Duration.zero,
        );
      })
          .where((s) => s.id.isNotEmpty)
          .toList();
    } on MissingPluginException {
      _available = false;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Channel avatar URL for the video watch page (best-effort;
  /// null when unknown — the UI keeps its letter-avatar fallback).
  static Future<String?> channelThumb(String videoId) async {
    try {
      final v = await _channel.invokeMethod('channelThumb', {
        'videoId': videoId,
      });
      return v is String && v.isNotEmpty ? v : null;
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