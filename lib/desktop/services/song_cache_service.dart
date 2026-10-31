// ZenMusic Desktop — offline song cache (download → Hive → file replay).
//
// Every song that plays gets silently downloaded to a local file (best
// audio-only stream). All later plays of that song come straight from disk:
// no proxy, no headers, works with zero internet.
//
// Pipeline (mirrors the PROVEN yt_video_engine.dart paths):
//   ytExplode.videos.streams.getManifest(videoId, ytClients: [client])
//     → best manifest.audioOnly by bitrate
//     → ranged GET with per-client header replay (_replayHeaders)
//     → <videoId>.part  →  atomic rename  →  <videoId>.<ext>
//     → artwork to <videoId>.jpg (non-fatal)
//     → Hive box 'song_cache' (plain Map records, no new adapter)
//
// ZERO unverified fork calls: this file only uses the exact API surface
// already proven by yt_video_engine.dart in a running build
// (getManifest/ytClients, YoutubeApiClient, .url, .container.name,
// .size.totalBytes, .bitrate, videos.get). Codec is DERIVED from container
// (m4a→aac, webm→opus) instead of touching unverified codec fields.
//
// LEDGER: _replayHeaders is a COPY of yt_video_engine.dart's (which itself
// copies yt_audio_stream.dart's _clientRequestHeaders) — KEEP ALL IN SYNC.
//
// ZERO new pubspec deps (path_provider, hive, youtube_explode_dart all present).
// R5 print policy: all debug prints use the [yt_cache] prefix.

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Public surface of yt_audio_stream.dart (same import the engine uses).
import 'yt_audio_stream.dart' show ytExplode, kYtClientPriority;

// ---------------------------------------------------------------------------
// Record
// ---------------------------------------------------------------------------

/// One cached song. Hive-stored as a plain Map (v1 format) — no adapter.
class CachedSong {
  const CachedSong({
    required this.videoId,
    required this.filePath,
    required this.artPath,
    required this.title,
    required this.author,
    required this.codec,
    required this.container,
    required this.bitrateBps,
    required this.bytes,
    required this.durationMs,
    required this.cachedAt,
  });

  final String videoId;

  /// Absolute path of the downloaded audio file.
  final String filePath;

  /// Absolute path of the downloaded artwork, or '' when unavailable.
  final String artPath;

  final String title;
  final String author;

  /// Derived codec label for badges: 'aac' (m4a) or 'opus' (webm).
  final String codec;

  /// Upstream container name ('m4a' | 'webm' | …).
  final String container;

  final int bitrateBps;
  final int bytes;
  final int durationMs;

  /// Epoch milliseconds when the record was written.
  final int cachedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'v': 1,
    'videoId': videoId,
    'filePath': filePath,
    'artPath': artPath,
    'title': title,
    'author': author,
    'codec': codec,
    'container': container,
    'bitrateBps': bitrateBps,
    'bytes': bytes,
    'durationMs': durationMs,
    'cachedAt': cachedAt,
  };

  static CachedSong? fromMap(Map<dynamic, dynamic> m) {
    try {
      if ((m['v'] ?? 0) != 1) return null;
      final path = m['filePath'] as String?;
      if (path == null || path.isEmpty) return null;
      return CachedSong(
        videoId: (m['videoId'] as String?) ?? '',
        filePath: path,
        artPath: (m['artPath'] as String?) ?? '',
        title: (m['title'] as String?) ?? '',
        author: (m['author'] as String?) ?? '',
        codec: (m['codec'] as String?) ?? '',
        container: (m['container'] as String?) ?? '',
        bitrateBps: (m['bitrateBps'] as num?)?.toInt() ?? 0,
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        cachedAt: (m['cachedAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Resolution (verified fork surface only)
// ---------------------------------------------------------------------------

class _Resolved {
  final Uri url;
  final YoutubeApiClient client;
  final String ext; // 'm4a' | 'webm' | …
  final int totalBytes;
  final int bitrateBps;
  final String title;
  final String author;
  final int durationMs;
  final String thumbUrl;

  const _Resolved({
    required this.url,
    required this.client,
    required this.ext,
    required this.totalBytes,
    required this.bitrateBps,
    required this.title,
    required this.author,
    required this.durationMs,
    required this.thumbUrl,
  });
}

/// Video metadata (title/author/duration/thumb) — same call the engine's
/// relatedSongs uses. Non-fatal: empty strings if it fails.
Future<({String title, String author, int durationMs, String thumbUrl})>
_videoMeta(String videoId) async {
  try {
    final v = await ytExplode.videos.get(videoId);
    return (
    title: v.title.trim(),
    author: v.author.trim(),
    durationMs: v.duration?.inMilliseconds ?? 0,
    thumbUrl: v.thumbnails.highResUrl,
    );
  } catch (e) {
    print('[yt_cache] meta($videoId) failed (non-fatal): $e');
    return (title: '', author: '', durationMs: 0, thumbUrl: '');
  }
}

/// Tries every client in [kYtClientPriority] — identical loop to the engine's
/// _resolveCandidates — and returns the HIGHEST-BITRATE audio-only stream.
Future<_Resolved?> _resolveBest(String videoId) async {
  final meta = await _videoMeta(videoId);

  Object? lastError;
  for (final client in kYtClientPriority) {
    try {
      final manifest = await ytExplode.videos.streams.getManifest(
        videoId,
        ytClients: [client],
      );

      final pool = manifest.audioOnly
          .where((s) => s.url.host.isNotEmpty)
          .toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(
            a.bitrate.bitsPerSecond));
      if (pool.isEmpty) {
        lastError = Exception('$client returned no audio-only streams');
        continue;
      }

      final best = pool.first;
      final raw = best.container.name.toLowerCase().trim();
      final ext = raw.contains('.') ? raw.substring(raw.lastIndexOf('.') + 1) : raw;
      final name = client.payload['context']?['client']?['clientName'];
      print('[yt_cache] $videoId resolved via $name '
          '(${pool.length} audio streams, ${best.bitrate.bitsPerSecond} bps, '
          '$ext)');
      return _Resolved(
        url: best.url,
        client: client,
        ext: ext.isEmpty ? 'm4a' : ext,
        totalBytes: best.size.totalBytes,
        bitrateBps: best.bitrate.bitsPerSecond,
        title: meta.title,
        author: meta.author,
        durationMs: meta.durationMs,
        thumbUrl: meta.thumbUrl,
      );
    } catch (e) {
      print('[yt_cache] $client failed for $videoId: $e');
      lastError = e;
    }
  }
  print('[yt_cache] all clients failed for $videoId: $lastError');
  return null;
}

/// Headers that must accompany requests to URLs minted by [client].
/// COPIED from yt_video_engine.dart (which copies yt_audio_stream.dart) —
/// LEDGER: KEEP ALL COPIES IN SYNC.
Map<String, String> _replayHeaders(YoutubeApiClient client) {
  final clientCtx = client.payload['context']?['client'];
  final userAgent = clientCtx is Map ? clientCtx['userAgent'] as String? : null;
  return {
    if (userAgent != null) 'user-agent': userAgent,
    for (final entry in client.headers.entries) entry.key: '${entry.value}',
  };
}

// ---------------------------------------------------------------------------
// SongCache
// ---------------------------------------------------------------------------

class SongCache {
  SongCache._();

  static Box? _box;
  static HttpClient? _http;

  /// Inflight dedupe: one download per videoId even if called repeatedly.
  static final Map<String, Future<CachedSong?>> _inflight =
  <String, Future<CachedSong?>>{};

  static final Set<String> _downloading = <String>{};

  static HttpClient get _client =>
      _http ??= HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static Future<Box> _cacheBox() async {
    _box ??= await Hive.openBox('song_cache');
    return _box!;
  }

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}audio_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Cached record for [videoId], or null. Verifies the file still exists —
  /// stale records (file deleted by the user) are evicted on sight.
  static Future<CachedSong?> lookup(String videoId) async {
    try {
      final box = await _cacheBox();
      final raw = box.get(videoId);
      if (raw is! Map) return null;
      final rec = CachedSong.fromMap(Map<String, dynamic>.from(raw));
      if (rec == null) return null;
      final f = File(rec.filePath);
      if (!await f.exists()) {
        await box.delete(videoId);
        return null;
      }
      return rec;
    } catch (e) {
      print('[yt_cache] lookup($videoId) failed: $e');
      return null;
    }
  }

  /// True while a download for [videoId] is in flight.
  static bool isDownloading(String videoId) => _downloading.contains(videoId);

  /// Downloads [videoId] if not already cached. Safe to call on every play —
  /// concurrent calls for the same videoId share one download.
  /// [onProgress] reports 0.0–1.0 (only when the size is known).
  static Future<CachedSong?> ensureCached(
      String videoId, {
        void Function(double progress)? onProgress,
      }) {
    final existing = _inflight[videoId];
    if (existing != null) return existing;
    final fut = _ensure(videoId, onProgress).whenComplete(() {
      _inflight.remove(videoId);
      _downloading.remove(videoId);
    });
    _inflight[videoId] = fut;
    _downloading.add(videoId);
    return fut;
  }

  static Future<CachedSong?> _ensure(
      String videoId,
      void Function(double)? onProgress,
      ) async {
    try {
      final cached = await lookup(videoId);
      if (cached != null) {
        onProgress?.call(1.0);
        return cached;
      }

      final r = await _resolveBest(videoId);
      if (r == null) return null;

      final dir = await _cacheDir();
      final target = File(
          '${dir.path}${Platform.pathSeparator}$videoId.${r.ext}');
      final part = File('${target.path}.part');
      if (await part.exists()) await part.delete(); // leftovers from a crash

      // ── download: ranged GET with header replay (engine pattern) ──
      final req = await _client.getUrl(r.url);
      req.headers.add(HttpHeaders.rangeHeader, 'bytes=0-');
      _replayHeaders(r.client).forEach(req.headers.add);
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok &&
          res.statusCode != HttpStatus.partialContent) {
        print('[yt_cache] download $videoId -> HTTP ${res.statusCode}');
        return null;
      }

      final expected = r.totalBytes > 0
          ? r.totalBytes
          : (res.contentLength > 0 ? res.contentLength : 0);
      final sink = part.openWrite();
      var received = 0;
      var lastPct = -1;
      try {
        await for (final chunk in res) {
          received += chunk.length;
          sink.add(chunk);
          if (expected > 0) {
            final pct = (received * 100 ~/ expected);
            if (pct != lastPct) {
              lastPct = pct;
              onProgress?.call(received / expected);
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (expected > 0 && received < expected * 0.98) {
        // Truncated body — don't keep a broken file.
        if (await part.exists()) await part.delete();
        print('[yt_cache] truncated download $videoId '
            '($received / $expected bytes)');
        return null;
      }
      if (await part.exists()) {
        await part.rename(target.path);
      } else {
        print('[yt_cache] part file missing for $videoId');
        return null;
      }

      // ── artwork (non-fatal) ──
      var artPath = '';
      if (r.thumbUrl.isNotEmpty) {
        try {
          final artReq = await _client.getUrl(Uri.parse(r.thumbUrl));
          final artRes = await artReq.close();
          if (artRes.statusCode == HttpStatus.ok) {
            final artFile = File(
                '${dir.path}${Platform.pathSeparator}$videoId.jpg');
            final bytes = <int>[];
            await for (final chunk in artRes) {
              bytes.addAll(chunk);
            }
            if (bytes.isNotEmpty) {
              await artFile.writeAsBytes(bytes, flush: true);
              artPath = artFile.path;
            }
          }
        } catch (e) {
          print('[yt_cache] artwork $videoId failed (non-fatal): $e');
        }
      }

      final rec = CachedSong(
        videoId: videoId,
        filePath: target.path,
        artPath: artPath,
        title: r.title,
        author: r.author,
        codec: r.ext.contains('webm') ? 'opus' : 'aac',
        container: r.ext,
        bitrateBps: r.bitrateBps,
        bytes: received,
        durationMs: r.durationMs,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final box = await _cacheBox();
      await box.put(videoId, rec.toMap());
      print('[yt_cache] cached $videoId '
          '(${(received / (1024 * 1024)).toStringAsFixed(1)} MB, '
          '${r.ext}, ${r.bitrateBps} bps)');
      return rec;
    } catch (e) {
      print('[yt_cache] ensureCached($videoId) failed: $e');
      return null;
    }
  }

  /// Deletes the cached file(s) + record for [videoId].
  static Future<void> delete(String videoId) async {
    try {
      final rec = await lookup(videoId);
      final box = await _cacheBox();
      await box.delete(videoId);
      if (rec != null) {
        for (final p in [rec.filePath, rec.artPath]) {
          if (p.isEmpty) continue;
          try {
            final f = File(p);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      print('[yt_cache] delete($videoId) failed: $e');
    }
  }

  /// All valid cached records (file-existence verified).
  static Future<List<CachedSong>> all() async {
    try {
      final box = await _cacheBox();
      final out = <CachedSong>[];
      for (final raw in box.values) {
        if (raw is! Map) continue;
        final rec = CachedSong.fromMap(Map<String, dynamic>.from(raw));
        if (rec == null) continue;
        if (!await File(rec.filePath).exists()) {
          await box.delete(rec.videoId);
          continue;
        }
        out.add(rec);
      }
      return out;
    } catch (e) {
      print('[yt_cache] all() failed: $e');
      return const [];
    }
  }

  /// Total bytes currently cached on disk.
  static Future<int> totalBytes() async {
    final allRecs = await all();
    var total = 0;
    for (final r in allRecs) {
      total += r.bytes;
    }
    return total;
  }
}