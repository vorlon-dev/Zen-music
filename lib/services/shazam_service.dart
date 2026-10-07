import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Shazam zen recognition — Dart port of Echo's ShazamKit network
/// layer (Shazam.kt). Rate-limited, exponential-backoff retries on 429,
/// 5-minute result cache keyed by signature.
///
/// IMPORTANT: [recognize] expects a Shazam DejaVu signature string
/// produced by a DSP fingerprinter (Echo uses native code for this).
/// The fingerprinter is NOT part of this port yet.
class ShazamService {
  ShazamService._();
  static final ShazamService instance = ShazamService._();

  static const _maxRetries = 3;
  static const _initialRetryDelayMs = 2000;
  static const _minRequestIntervalMs = 1000;
  static const _cacheTtl = Duration(minutes: 5);

  final http.Client _client = http.Client();
  final Map<String, _CachedResult> _cache = {};
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _userAgents = [
    'Dalvik/2.1.0 (Linux; U; Android 5.0.2; VS980 4G Build/LRX22G)',
    'Dalvik/1.6.0 (Linux; U; Android 4.4.2; SM-T210 Build/KOT49H)',
    'Dalvik/2.1.0 (Linux; U; Android 5.1.1; SM-P905V Build/LMY47X)',
    'Dalvik/2.1.0 (Linux; U; Android 6.0.1; SM-G920F Build/MMB29K)',
    'Dalvik/2.1.0 (Linux; U; Android 5.0; SM-G900F Build/LRX21T)',
  ];

  static const _timezones = [
    'Europe/Paris', 'Europe/London', 'America/New_York',
    'America/Los_Angeles', 'Asia/Tokyo', 'Asia/Dubai',
  ];

  /// Recognize zen from a DejaVu audio signature.
  Future<ShazamResult> recognize(
      String signature, int sampleDurationMs) async {
    final cacheKey = signature.hashCode.toString();
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.result;
    }

    Exception? last;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        await _enforceRateLimit();
        final result = await _perform(signature, sampleDurationMs);
        _cache[cacheKey] = _CachedResult(result, DateTime.now());
        return result;
      } catch (e) {
        final msg = e.toString();
        final retryable =
            msg.contains('429') || msg.contains('Too many requests');
        if (!retryable) rethrow;
        last = e is Exception ? e : Exception(msg);
        if (attempt < _maxRetries - 1) {
          await Future.delayed(
              Duration(milliseconds: _initialRetryDelayMs * (1 << attempt)));
        }
      }
    }
    throw last ?? Exception('Recognition failed after $_maxRetries attempts');
  }

  Future<void> _enforceRateLimit() async {
    final since =
        DateTime.now().difference(_lastRequestAt).inMilliseconds;
    if (since < _minRequestIntervalMs) {
      await Future.delayed(
          Duration(milliseconds: _minRequestIntervalMs - since));
    }
    _lastRequestAt = DateTime.now();
  }

  Future<ShazamResult> _perform(
      String signature, int sampleDurationMs) async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final uuid1 = _uuid(uppercase: true);
    final uuid2 = _uuid();
    final rng = Random();

    final body = jsonEncode({
      'geolocation': {
        'altitude': rng.nextDouble() * 400 + 100,
        'latitude': rng.nextDouble() * 180 - 90,
        'longitude': rng.nextDouble() * 360 - 180,
      },
      'signature': {
        'samplems': sampleDurationMs,
        'timestamp': ts,
        'uri': signature,
      },
      'timestamp': ts,
      'timezone':
      _timezones[rng.nextInt(_timezones.length)],
    });

    final uri = Uri.parse(
        'https://amp.shazam.com/discovery/v5/en/US/android/-/tag/$uuid1/$uuid2')
        .replace(queryParameters: {
      'sync': 'true',
      'webv3': 'true',
      'sampling': 'true',
      'connected': '',
      'shazamapiversion': 'v3',
      'sharehub': 'true',
      'video': 'v3',
    });

    final resp = await _client
        .post(uri,
        headers: {
          'User-Agent': _userAgents[rng.nextInt(_userAgents.length)],
          'Content-Language': 'en_US',
          'Content-Type': 'application/json',
        },
        body: body)
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode == 404) {
      throw Exception('No match found');
    }
    if (resp.statusCode == 429) {
      throw Exception('Too many requests');
    }
    if (resp.statusCode >= 500) {
      throw Exception('Shazam service temporarily unavailable');
    }
    if (resp.statusCode != 200) {
      throw Exception('Recognition failed (error ${resp.statusCode})');
    }

    final result = _parse(jsonDecode(resp.body) as Map<String, dynamic>);
    if (result == null) throw Exception('No match found');
    return result;
  }

  /// Echo's response mapping.
  ShazamResult? _parse(Map<String, dynamic> root) {
    final track = root['track'];
    if (track is! Map) return null;
    final t = Map<String, dynamic>.from(track);

    String? str(dynamic v) => v is String ? v : null;

    // SONG section metadata: Album / Label / Released.
    String? album, label, releaseDate;
    List<String>? lyrics;
    final sections = t['sections'];
    if (sections is List) {
      for (final raw in sections) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        final type = str(s['type']) ?? '';
        if (type == 'SONG') {
          final meta = s['metadata'];
          if (meta is List) {
            for (final m in meta) {
              if (m is! Map) continue;
              final title = str(m['title']) ?? '';
              final text = str(m['text']);
              if (title == 'Album') album = text;
              if (title == 'Label') label = text;
              if (title == 'Released') releaseDate = text;
            }
          }
        }
        if (type == 'LYRICS') {
          final txt = s['text'];
          if (txt is List) {
            lyrics = txt.whereType<String>().toList();
          }
        }
      }
    }

    // Hub: Apple Music + Spotify + YouTube video actions.
    String? appleMusicUrl, spotifyUrl, youtubeVideoId;
    final hub = t['hub'];
    if (hub is Map) {
      final h = Map<String, dynamic>.from(hub);

      final options = h['options'];
      if (options is List) {
        for (final raw in options) {
          if (raw is! Map) continue;
          final o = Map<String, dynamic>.from(raw);
          final provider = (str(o['providername']) ?? '').toLowerCase();
          final oType = (str(o['type']) ?? '').toLowerCase();

          if (provider.contains('apple') && appleMusicUrl == null) {
            final actions = o['actions'];
            if (actions is List && actions.isNotEmpty) {
              final a = actions.first;
              if (a is Map) {
                appleMusicUrl = str((a as Map)['uri']);
              }
            }
          }
          if (oType.contains('video') && youtubeVideoId == null) {
            final actions = o['actions'];
            if (actions is List && actions.isNotEmpty) {
              final a = actions.first;
              if (a is Map) {
                final u = str((a as Map)['uri']) ?? '';
                youtubeVideoId = _videoIdFromUri(u);
              }
            }
          }
        }
      }

      final providers = h['providers'];
      if (providers is List && spotifyUrl == null) {
        for (final raw in providers) {
          if (raw is! Map) continue;
          final p = Map<String, dynamic>.from(raw);
          final caption = (str(p['caption']) ?? '').toLowerCase();
          if (caption.contains('spotify')) {
            final actions = p['actions'];
            if (actions is List && actions.isNotEmpty) {
              final a = actions.first;
              if (a is Map) {
                spotifyUrl = str((a as Map)['uri']);
              }
            }
          }
        }
      }
    }

    String? cover, coverHq;
    final images = t['images'];
    if (images is Map) {
      final im = Map<String, dynamic>.from(images);
      cover = str(im['coverart']);
      coverHq = str(im['coverarthq']);
    }

    String? genre;
    final genres = t['genres'];
    if (genres is Map) {
      genre = str((genres as Map)['primary']);
    }

    return ShazamResult(
      trackId: str(t['key']) ?? str(root['tagid']) ?? '',
      title: str(t['title']) ?? '',
      artist: str(t['subtitle']) ?? '',
      album: album,
      coverArtUrl: cover,
      coverArtHqUrl: coverHq,
      genre: genre,
      releaseDate: releaseDate,
      label: label,
      lyrics: lyrics,
      shazamUrl: str(t['url']),
      appleMusicUrl: appleMusicUrl,
      spotifyUrl: spotifyUrl,
      isrc: str(t['isrc']),
      youtubeVideoId: youtubeVideoId,
    );
  }

  String? _videoIdFromUri(String uri) {
    final afterV = uri.contains('v=') ? uri.split('v=').last : '';
    if (afterV.isNotEmpty) {
      final token = afterV.split('&').first;
      if (token.length == 11) return token;
    }
    final segs = uri.split('/');
    final last = segs.isNotEmpty ? segs.last : '';
    if (last.length == 11) return last;
    return null;
  }

  /// Dependency-free random UUID (v4-shaped) for the tag URLs.
  String _uuid({bool uppercase = false}) {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    final out =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
    return uppercase ? out.toUpperCase() : out;
  }

  void clearCache() => _cache.clear();
}

class _CachedResult {
  const _CachedResult(this.result, this.at);
  final ShazamResult result;
  final DateTime at;
}

class ShazamResult {
  const ShazamResult({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.coverArtUrl,
    this.coverArtHqUrl,
    this.genre,
    this.releaseDate,
    this.label,
    this.lyrics,
    this.shazamUrl,
    this.appleMusicUrl,
    this.spotifyUrl,
    this.isrc,
    this.youtubeVideoId,
  });

  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final String? coverArtUrl;
  final String? coverArtHqUrl;
  final String? genre;
  final String? releaseDate;
  final String? label;
  final List<String>? lyrics;
  final String? shazamUrl;
  final String? appleMusicUrl;
  final String? spotifyUrl;
  final String? isrc;

  /// YouTube video id from Shazam's video hub action — resolvable
  /// through the app's existing YouTube pipeline.
  final String? youtubeVideoId;
}