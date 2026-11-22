// ZenMusic · vorlon-dev
//
// Free-lossless playback engine (the Antra pattern).
//
// Spotify's web token works on free accounts too, but Spotify's own CDN
// never serves FLAC to them — free caps out at 128 kbps AAC. The fix is
// what Antra does: keep Spotify / YouTube / JioSaavn as metadata and pull
// the actual audio from community mirrors that relay Tidal and Deezer
// lossless streams. No premium account anywhere:
//
//   Spotify free ─┐
//   YouTube ──────┼─ title/artist match ─→ Tidal mirror   (FLAC 16/44.1 … 24/192)
//   JioSaavn ─────┘                     └→ Deezer mirror  (FLAC 16/44.1 fallback)
//
// The mirror manifest endpoints (/api/track) hand out signed CDN URLs that
// support HTTP Range — those are relayed through a small loopback server
// (plain byte passthrough with full HTTP Range support) so players get a
// normal, seekable stream. Deezer CDN payloads are Blowfish-encrypted per
// 2048-byte block (every third block, fixed IV); the loopback decrypts
// in-flight so the player sees plain FLAC.
//
// Full-stream guarantee: before any manifest is served it is probed —
// the head of the CDN asset is fetched (Blowfish-decrypted for Deezer)
// and the REAL duration is read from the FLAC STREAMINFO header. 30-second
// preview cuts are rejected and the chain falls through to the next
// source, so only full tracks ever play.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'blowfish.dart';
import 'lossless_quality.dart';
import 'lossless_service.dart';
import 'mirror_config.dart';

/// Deezer frame geometry: every third 2048-byte block is encrypted.
const int _kDzBlockSize = 2048;

/// Fixed Blowfish IV used by Deezer's CDN encryption.
final Uint8List _kDzIv = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

class MirrorSource {
  MirrorSource._();
  static final MirrorSource instance = MirrorSource._();

  final http.Client _http = http.Client();

  // SP71b: these two live here, not in MirrorConfig, so mirror_config.dart
  // drift on either side can never break the build again (the user's tree
  // carries its own endpoint-fixed config — it is never overwritten).

  /// Search window per mirror host request.
  static const Duration _searchTimeout = Duration(seconds: 4);

  /// Whole-resolution budget for one tryBuildSource call (search + manifest
  /// + probe across both mirrors). Once spent the chain falls through.
  static const Duration _resolveBudget = Duration(seconds: 10);

  // --------------------------------------------------------------- entry

  /// Free-lossless AudioSource for [song] at the selected FLAC tier, or
  /// null when the track can't be served from a mirror (the caller then
  /// falls through to its normal source). Never throws.
  Future<AudioSource?> tryBuildSource(
      Map<String, dynamic> song, MediaItem tag) async {
    // MP3 tier is served by the normal chain; mirrors are FLAC-only.
    if (LosslessPrefs.current == LosslessQuality.mp3_320) return null;
    try {
      final identity = _identityFrom(song);
      if (identity == null) return null;

      final now = DateTime.now();
      // Circuit breaker: when the mirror pool is unreachable it is skipped
      // outright for a while so playback falls through instantly instead
      // of paying the timeouts on every single track.
      if (_openUntil != null && now.isBefore(_openUntil!)) return null;

      final failKey =
          '${identity.title}|${identity.artist}'.toLowerCase().trim();
      final failedAt = _failCache[failKey];
      if (failedAt != null && now.isBefore(failedAt)) return null;

      // Whole-resolution budget: mirrors are an upgrade, never a blocker.
      // Once spent, remaining stages are skipped and the chain falls
      // through to JioSaavn / cache / YouTube.
      final deadline = now.add(_resolveBudget);
      bool expired() => !DateTime.now().isBefore(deadline);

      final acquired = await _acquireSlot();
      if (!acquired) {
        print('[mirror] resolver busy — skipping mirrors for this track');
        return null;
      }
      try {
        // 1+2. Tidal and Deezer searches run IN PARALLEL. On a dead pool
        // both fail together — one search window per track instead of two
        // back-to-back timeouts (the "loads and loads, never plays" bug).
        // A Tidal match still wins: the pending Deezer search is simply
        // dropped (it never throws — all errors are handled inside).
        if (!expired()) {
          final tidalFuture = _resolveTidal(identity);
          final dzFuture = _resolveDeezer(identity);
          final tidal = await tidalFuture;
          if (tidal != null) {
            unawaited(dzFuture);
            final source = await _buildTidalSource(
                tidal, tag, identity.durationMs, deadline);
            if (source != null) {
              _noteNetOk();
              return source;
            }
          } else {
            final dz = await dzFuture;
            if (dz != null && !expired()) {
              final source = await _buildDeezerSource(
                  dz, tag, identity.durationMs, deadline);
              if (source != null) {
                _noteNetOk();
                return source;
              }
            }
          }
        }
      } finally {
        _releaseSlot();
      }

      if (expired()) {
        print('[mirror] resolution budget spent — falling through');
        _noteNetFail();
      }
      _failCache[failKey] = now.add(_failTtl);
      _evict(_failCache);
      return null;
    } catch (e) {
      print('[mirror] tryBuildSource error: $e');
      return null;
    }
  }

  // ------------------------------------------------------ circuit breaker

  /// Consecutive network-level failures (timeouts / dropped sockets).
  /// TWO in a row open the breaker for 2 minutes: with the parallel Tidal +
  /// Deezer searches, one dead track produces exactly two failures, so the
  /// very first track on a dead pool flips the breaker and every track
  /// after it falls through to the regular chain instantly. tryBuildSource
  /// returns null immediately while the breaker is open — and in strict
  /// lossless mode the breaker closing after 2 min re-tests the pool
  /// regularly instead of locking FLAC out for 5.
  int _netFailStreak = 0;
  DateTime? _openUntil;

  void _noteNetFail() {
    _netFailStreak++;
    if (_netFailStreak >= 2 && _openUntil == null) {
      _openUntil = DateTime.now().add(const Duration(minutes: 2));
      print('[mirror] pool unreachable — bypassing mirrors for 2 min');
    }
  }

  void _noteNetOk() {
    _netFailStreak = 0;
    _openUntil = null;
  }

  /// Strict lossless: forget everything that would make the next attempt
  /// skip the pool (open breaker, 10-min fail cache, cached manifests that
  /// may hold an expired URL) so a retry really talks to the mirrors again.
  void clearBlocksFor(Map<String, dynamic> song) {
    _netFailStreak = 0;
    _openUntil = null;
    final id = _identityFrom(song);
    if (id != null) {
      _failCache.remove('${id.title}|${id.artist}'.toLowerCase().trim());
    }
    _tidalManifestCache.clear();
    _dzManifestCache.clear();
    _dzTotalCache.clear();
  }

  static bool _isNetError(Object e) =>
      e is TimeoutException || e is SocketException || e is HttpException;

  // ------------------------------------------------------------ identity

  _Identity? _identityFrom(Map<String, dynamic> song) {
    final title = (song['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;

    String artist = '';
    final artists = song['artists'];
    if (artists is List && artists.isNotEmpty) {
      artist = ((artists[0] as Map?)?['name'] ?? '').toString();
    }
    if (artist.isEmpty) artist = '${song['artist'] ?? ''}';

    int? durationMs;
    final d = song['duration'];
    if (d is Duration) {
      durationMs = d.inMilliseconds;
    } else if (d is num && d > 0) {
      durationMs = (d * 1000).round();
    } else if (d is String) {
      final m = RegExp(r'^(\d+):(\d{1,2})$').firstMatch(d.trim());
      if (m != null) {
        durationMs =
            (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000;
      }
    }

    String? spotifyId;
    final uri = song['spotifyUri'] as String?;
    if (uri != null && uri.isNotEmpty) spotifyId = spotifyIdFromUri(uri);

    return _Identity(title, artist, durationMs, spotifyId);
  }

  /// `spotify:track:ID`, `https://open.spotify.com/track/ID` or
  /// `.../tracks/ID` → the 22-char id.
  static String? spotifyIdFromUri(String uri) {
    final m = RegExp(r'(?:spotify[:/]track[:/]|/tracks/)([A-Za-z0-9]{22})')
        .firstMatch(uri);
    return m?.group(1);
  }

  // ----------------------------------------------------------- matching

  Set<String> _tokens(String s) {
    final norm = s
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9\\u0900-\\u097F\\u4e00-\\u9fff'
            '\\u3040-\\u30ff\\uac00-\\ud7af]+'),
            ' ');
    return norm
        .split(' ')
        .where((w) => w.isNotEmpty && w.length > 1)
        .toSet();
  }

  double _dice(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    var inter = 0;
    for (final t in a) {
      if (b.contains(t)) inter++;
    }
    return 2 * inter / (a.length + b.length);
  }

  double _score(_Identity q, String title, String artist, int? durationMs) {
    var s = 0.65 * _dice(_tokens(q.title), _tokens(title)) +
        0.35 * _dice(_tokens(q.artist), _tokens(artist));
    if (q.durationMs != null && durationMs != null && durationMs > 0) {
      final delta = (q.durationMs! - durationMs).abs() / 1000;
      if (delta > 30) {
        s *= 0.5;
      } else if (delta > 10) {
        s *= 0.8;
      }
    }
    return s;
  }

  // --------------------------------------------------------------- tidal

  Future<_TidalMatch?> _resolveTidal(_Identity id) async {
    try {
      final query = '${id.title} ${id.artist}'.trim();
      final res = await _http
          .get(
              Uri.parse('${MirrorConfig.tidal}/search/')
                  .replace(queryParameters: {'s': query}),
              headers: MirrorConfig.jsonHeaders)
          .timeout(_searchTimeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final items =
          ((data is Map ? data['data'] : null) as Map?)?['items'];
      if (items is! List || items.isEmpty) return null;

      _TidalMatch? best;
      var bestScore = 0.0;
      for (final raw in items) {
        if (raw is! Map) continue;
        final artist = ((raw['artist'] as Map?)?['name'] ?? '').toString();
        final duration = raw['duration'];
        final durMs = duration is num && duration > 0
            ? (duration * 1000).round()
            : null;
        final score =
            _score(id, '${raw['title'] ?? ''}', artist, durMs);
        if (score > bestScore) {
          bestScore = score;
          best = _TidalMatch(
            '${raw['id'] ?? ''}',
            '${raw['audioQuality'] ?? ''}'
                .toUpperCase()
                .contains('HI_RES'),
          );
        }
      }
      if (best == null || best.trackId.isEmpty) return null;
      // Mirrors relay best-effort catalog matches — a weak text match is
      // worse than falling through to Deezer / the regular chain.
      return bestScore >= 0.62 ? best : null;
    } catch (e) {
      print('[mirror] tidal search error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    }
  }

  Future<AudioSource?> _buildTidalSource(_TidalMatch match, MediaItem tag,
      int? expectedMs, DateTime deadline) async {
    final wanted = LosslessPrefs.current;
    final wantsHiRes = wanted == LosslessQuality.flacHiRes96 ||
        wanted == LosslessQuality.flacHiResMax;

    // strict_24 when the user picked a Hi-Res tier; the server answers 409
    // when the track has no 24-bit master — then we still serve CD
    // lossless instead of giving up.
    final attempts = wantsHiRes ? ['strict_24=1', 'prefer_16=1'] : ['prefer_16=1'];

    for (final param in attempts) {
      if (!DateTime.now().isBefore(deadline)) return null;
      final manifest = await _tidalManifest(match.trackId, param);
      if (manifest == null) continue;
      // Full-stream guarantee: a manifest that failed the duration probe
      // (preview cut / AAC preview / unparseable) is never served.
      if (!MirrorSource.isFullTrack(manifest.seconds, expectedMs)) {
        print('[mirror] tidal ${match.trackId} preview/short cut '
            'rejected (${manifest.seconds}s)');
        continue;
      }

      await _ensureServer();
      final playUrl = Uri.parse('$_baseUrl/tide?u='
          '${Uri.encodeComponent(base64Url.encode(utf8.encode(manifest.url)))}');
      LosslessService.instance.noteMirrorServed(
          tag.id, param.startsWith('strict') ? wanted : LosslessQuality.flacCd);
      return AudioSource.uri(playUrl, tag: tag);
    }
    return null;
  }

  Future<_TidalManifest?> _tidalManifest(String trackId, String param) async {
    final now = DateTime.now();
    final cacheKey = '$trackId|$param';
    final hit = _tidalManifestCache[cacheKey];
    if (hit != null && now.isBefore(hit.$2)) return hit.$1;

    try {
      final res = await _http
          .get(Uri.parse('${MirrorConfig.tidal}/api/track/$trackId?$param'),
              headers: MirrorConfig.jsonHeaders)
          .timeout(MirrorConfig.manifestTimeout);
      if (res.statusCode != 200) {
        print('[mirror] tidal manifest $trackId ($param): HTTP ${res.statusCode}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      final urls = data['streamUrls'];
      final url = (urls is List && urls.isNotEmpty)
          ? urls.first.toString()
          : '${data['streamUrl'] ?? ''}';
      if (url.isEmpty) return null;
      // Refuse anything that is not plain FLAC (fake-lossless AAC guard).
      final codec = '${data['codec'] ?? ''}'.toLowerCase();
      if (codec.isNotEmpty && !codec.contains('flac')) return null;
      // Static preview markers straight from the manifest payload.
      final quality = '${data['audioQuality'] ?? data['audio_quality'] ?? ''}'
          .toUpperCase();
      if (quality.contains('PREVIEW')) return null;
      if (MirrorSource.looksLikePreviewUrl(url)) return null;
      // Full-stream guarantee: probe the CDN bytes and read the real
      // duration out of the FLAC STREAMINFO header. Previews (30-s cuts)
      // never make it into the cache.
      final seconds = await _probeFlacSeconds(url);
      if (seconds == null) {
        print('[mirror] tidal manifest $trackId ($param): not a verifiable '
            'full FLAC — rejected');
        return null;
      }
      final manifest = _TidalManifest(url, seconds);
      _tidalManifestCache[cacheKey] = (manifest, now.add(_manifestTtl));
      _evict(_tidalManifestCache);
      return manifest;
    } catch (e) {
      print('[mirror] tidal manifest error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    }
  }

  // -------------------------------------------------------------- deezer

  Future<_DeezerMatch?> _resolveDeezer(_Identity id) async {
    try {
      final res = await _http
          .get(
              Uri.parse('${MirrorConfig.deezer}/api/search').replace(
                  queryParameters: {
                    'title': id.title,
                    'artist': id.artist,
                    'limit': '5',
                  }),
              headers: MirrorConfig.jsonHeaders)
          .timeout(_searchTimeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final results = data is Map ? data['results'] : null;
      if (results is! List || results.isEmpty) return null;

      _DeezerMatch? best;
      var bestScore = 0.0;
      for (final raw in results) {
        if (raw is! Map) continue;
        final durMs = raw['duration_ms'];
        final score = _score(
            id,
            '${raw['title'] ?? ''}',
            '${raw['artist'] ?? ''}',
            durMs is num && durMs > 0 ? durMs.round() : null);
        if (score > bestScore) {
          bestScore = score;
          best = _DeezerMatch('${raw['track_id'] ?? ''}');
        }
      }
      if (best == null || best.trackId.isEmpty) return null;
      return bestScore >= 0.70 ? best : null;
    } catch (e) {
      print('[mirror] deezer search error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    }
  }

  Future<AudioSource?> _buildDeezerSource(_DeezerMatch match, MediaItem tag,
      int? expectedMs, DateTime deadline) async {
    if (!DateTime.now().isBefore(deadline)) return null;
    // Fetch + validate the manifest NOW (not lazily in the loopback
    // handler): a preview/short cut must fall through to the next source,
    // not play 30 seconds.
    final manifest = await _deezerManifest(match.trackId);
    if (manifest == null) return null;
    if (!MirrorSource.isFullTrack(manifest.seconds, expectedMs)) {
      print('[mirror] deezer ${match.trackId} preview/short cut rejected '
          '(${manifest.seconds}s)');
      return null;
    }

    await _ensureServer();
    LosslessService.instance.noteMirrorServed(tag.id, LosslessQuality.flacCd);
    return AudioSource.uri(
        Uri.parse(
            '$_baseUrl/dz?id=${Uri.encodeComponent(match.trackId)}'),
        tag: tag);
  }

  Future<_DeezerManifest?> _deezerManifest(String id) async {
    final now = DateTime.now();
    final hit = _dzManifestCache[id];
    if (hit != null && now.isBefore(hit.$2)) return hit.$1;
    try {
      final res = await _http
          .get(Uri.parse('${MirrorConfig.deezer}/api/track/$id'),
              headers: MirrorConfig.jsonHeaders)
          .timeout(MirrorConfig.manifestTimeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      final url = '${data['streamUrl'] ?? ''}';
      final key = '${data['decryptionKey'] ?? ''}';
      if (url.isEmpty || key.isEmpty) return null;
      if (MirrorSource.looksLikePreviewUrl(url)) return null;
      // The mirror returns the final Blowfish key as raw ASCII bytes.
      final keyBytes = Uint8List.fromList(key.codeUnits);
      // Full-stream guarantee: decrypt the first CDN blocks and read the
      // real duration from the FLAC STREAMINFO header. Deezer 30-s
      // previews (usually 128 kbps mp3 cuts) never reach the cache.
      final seconds = await _probeFlacSeconds(url, blowfishKey: keyBytes);
      if (seconds == null) {
        print('[mirror] deezer manifest $id: not a verifiable full FLAC '
            '— rejected');
        return null;
      }
      final manifest = _DeezerManifest(url, keyBytes, seconds);
      _dzManifestCache[id] = (manifest, now.add(_manifestTtl));
      _evict(_dzManifestCache);
      return manifest;
    } catch (e) {
      print('[mirror] deezer manifest error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    }
  }

  // ----------------------------------------------------------- loopback

  HttpServer? _server;
  String? _baseUrl;

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _baseUrl = 'http://${server.address.host}:${server.port}';
    server.listen(_handle, onError: (Object e) {
      print('[mirror] loopback error: $e');
    });
    print('[mirror] loopback listening on $_baseUrl');
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/tide':
          await _servePlain(request);
          break;
        case '/dz':
          await _serveDeezer(request);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (e) {
      print('[mirror] loopback handler error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// GET /tide?u=<base64 upstream>
  ///
  /// Plain Range-forwarding passthrough for the Tidal mirror's signed CDN
  /// URL (raw FLAC, accept-ranges confirmed). If upstream ever ignores the
  /// Range header we skip-stream the window instead so players can still
  /// seek.
  Future<void> _servePlain(HttpRequest request) async {
    final u = request.uri.queryParameters['u'] ?? '';
    final response = request.response;
    if (u.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    final upstreamUrl = utf8.decode(base64Url.decode(u));
    final client = HttpClient()
      ..connectionTimeout = MirrorConfig.streamConnectTimeout;
    try {
      final req = await client.getUrl(Uri.parse(upstreamUrl));
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      // Fail fast with 504 when the upstream CDN won't open — the player
      // errors out immediately instead of hanging on "loading" forever.
      HttpClientResponse upstream;
      try {
        upstream =
            await req.close().timeout(MirrorConfig.streamConnectTimeout);
      } catch (_) {
        response.statusCode = HttpStatus.gatewayTimeout;
        await response.close();
        return;
      }

      if (upstream.statusCode == HttpStatus.partialContent) {
        response.statusCode = HttpStatus.partialContent;
        final cr = upstream.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null) response.headers.set(HttpHeaders.contentRangeHeader, cr);
        final ct = upstream.headers.value(HttpHeaders.contentTypeHeader);
        if (ct != null) response.headers.set(HttpHeaders.contentTypeHeader, ct);
        final len = upstream.contentLength;
        if (len >= 0) response.contentLength = len;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.bufferOutput = false;
        await upstream.pipe(response);
        return;
      }

      // Upstream ignored Range: full body — emulate the requested window.
      final total = upstream.contentLength;
      if (total <= 0) {
        response.statusCode = upstream.statusCode;
        response.bufferOutput = false;
        await upstream.pipe(response);
        return;
      }
      int start = 0;
      int end = total - 1;
      bool partial = false;
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring(6).split('-');
        final s = int.tryParse(parts[0]);
        final e = parts.length > 1 && parts[1].isNotEmpty
            ? int.tryParse(parts[1])
            : null;
        if (s != null && s < total) {
          start = s;
          end = (e == null || e >= total) ? total - 1 : e;
          partial = true;
        }
      }
      response.statusCode =
          partial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (partial) {
        response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }
      response.headers.contentType = ContentType.parse('audio/flac');
      response.contentLength = end - start + 1;
      response.bufferOutput = false;

      var pos = 0; // absolute offset of the next incoming byte
      var written = 0;
      final want = end - start + 1;
      await for (final chunk in upstream) {
        if (written >= want) break;
        final chunkEnd = pos + chunk.length; // exclusive
        if (chunkEnd <= start || pos > end) {
          pos = chunkEnd;
          continue;
        }
        final from = start > pos ? start - pos : 0;
        final to =
            end < chunkEnd - 1 ? (end - pos + 1) : chunk.length;
        if (to > from) {
          response.add(Uint8List.fromList(chunk.sublist(from, to)));
          written += to - from;
        }
        pos = chunkEnd;
      }
      await response.close();
    } catch (e) {
      print('[mirror] tidal passthrough error: $e');
      if (_isNetError(e)) _noteNetFail();
      try {
        await response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  /// GET /dz?id=<deezer track id>
  ///
  /// Deezer CDN payload: every third 2048-byte block (3rd, 6th, …) is
  /// Blowfish-CBC encrypted with a fixed IV, the rest is plain. The read
  /// is aligned to the 2048-byte grid so decryption stays deterministic
  /// no matter where the player seeks.
  Future<void> _serveDeezer(HttpRequest request) async {
    final id = request.uri.queryParameters['id'] ?? '';
    final response = request.response;
    if (id.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    final manifest = await _deezerManifest(id);
    if (manifest == null) {
      response.statusCode = HttpStatus.notFound;
      response.write('mirror stream expired — retry the track');
      await response.close();
      return;
    }

    final total = await _deezerTotal(manifest.url);
    if (total == null || total <= 0) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    int start = 0;
    int end = total - 1;
    bool partial = false;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final parts = rangeHeader.substring(6).split('-');
      final s = int.tryParse(parts[0]);
      final e = parts.length > 1 && parts[1].isNotEmpty
          ? int.tryParse(parts[1])
          : null;
      if (s != null && s < total) {
        start = s;
        end = (e == null || e >= total) ? total - 1 : e;
        partial = true;
      }
    }

    final startBlock = start ~/ _kDzBlockSize;
    final readFrom = startBlock * _kDzBlockSize;
    final skip = start - readFrom;

    final client = HttpClient()
      ..connectionTimeout = MirrorConfig.streamConnectTimeout;
    _BlockReader? reader;
    try {
      final req = await client.getUrl(Uri.parse(manifest.url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=$readFrom-');
      HttpClientResponse upstream;
      try {
        upstream =
            await req.close().timeout(MirrorConfig.streamConnectTimeout);
      } catch (_) {
        response.statusCode = HttpStatus.gatewayTimeout;
        await response.close();
        return;
      }
      if (upstream.statusCode != HttpStatus.partialContent &&
          upstream.statusCode != HttpStatus.ok) {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
        return;
      }

      response.statusCode =
          partial ? HttpStatus.partialContent : HttpStatus.ok;
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (partial) {
        response.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }
      response.headers.contentType = ContentType.parse('audio/flac');
      response.contentLength = end - start + 1;
      response.bufferOutput = false;

      reader = _BlockReader(upstream);
      var blockNo = startBlock;
      var served = 0;
      var skipped = 0;
      final want = end - start + 1;

      while (served < want) {
        final block = await reader.nextBlock();
        if (block == null || block.isEmpty) break;
        var out = block;
        if (block.length == _kDzBlockSize && blockNo % 3 == 0) {
          out = _blowfishDecrypt(block, manifest.keyBytes);
        }
        blockNo++;

        var from = 0;
        if (skipped < skip) {
          final take = skip - skipped;
          from = take > out.length ? out.length : take;
          skipped += from;
        }
        if (from >= out.length) continue;
        final avail = out.length - from;
        final take =
            avail < (want - served) ? avail : (want - served);
        response.add(Uint8List.sublistView(out, from, from + take));
        served += take;
      }
      await response.close();
    } catch (e) {
      print('[mirror] deezer stream error: $e');
      if (_isNetError(e)) _noteNetFail();
      try {
        await response.close();
      } catch (_) {}
    } finally {
      reader?.cancel();
      client.close(force: true);
    }
  }

  /// Total stream size via a 1-byte Range probe. Cached per CDN URL —
  /// ExoPlayer re-opens the stream on every seek and the probe must never
  /// repeat (it would stall the loopback and kill playback).
  Future<int?> _deezerTotal(String url) async {
    final now = DateTime.now();
    final hit = _dzTotalCache[url];
    if (hit != null && now.isBefore(hit.$2)) return hit.$1;
    final client = HttpClient()
      ..connectionTimeout = MirrorConfig.streamConnectTimeout;
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close().timeout(MirrorConfig.probeTimeout);
      try {
        final cr = res.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null) {
          final m = RegExp(r'/(\d+)$').firstMatch(cr);
          if (m != null) {
            final total = int.parse(m.group(1)!);
            _dzTotalCache[url] = (total, now.add(_manifestTtl));
            _evict(_dzTotalCache);
            return total;
          }
        }
        if (res.statusCode == HttpStatus.ok && res.contentLength > 0) {
          _dzTotalCache[url] = (res.contentLength, now.add(_manifestTtl));
          _evict(_dzTotalCache);
          return res.contentLength;
        }
        return null;
      } finally {
        await res.drain<void>().timeout(const Duration(seconds: 10),
            onTimeout: () {});
      }
    } catch (e) {
      print('[mirror] deezer probe error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Blowfish-CBC over a whole encrypted 2048-byte block: the upstream
  /// scheme CBC-encrypts each 2048-byte block independently with the fixed
  /// IV, so the chain restarts at every block boundary.
  static Uint8List _blowfishDecrypt(Uint8List block, Uint8List key) {
    final dec = BlowfishCbcDecryptor(key, _kDzIv);
    final out = Uint8List(block.length);
    for (var off = 0; off + 8 <= block.length; off += 8) {
      out.setRange(
          off, off + 8, dec.decryptBlock(Uint8List.sublistView(block, off)));
    }
    return out;
  }

  // ------------------------------------------------- full-stream guard
  //
  // Mirrors hand out their best effort — for some tracks that is a
  // 30-second preview cut instead of the full asset. Both manifests are
  // therefore probed before they are ever served: fetch the first CDN
  // bytes, (Blowfish-decrypt for Deezer) and read the REAL duration from
  // the FLAC STREAMINFO header. Anything that is not a verifiable full
  // FLAC is rejected and the chain falls through to the next source.

  /// URL shapes that are always previews (AAC preview cuts, /preview/ CDNs).
  static final RegExp _previewUrlPattern = RegExp(
      r'preview|cdn[-_]?preview|lowkey|\.mp4($|\?)|\.m4a($|\?)|\.aac($|\?)',
      caseSensitive: false);

  static bool looksLikePreviewUrl(String url) =>
      _previewUrlPattern.hasMatch(url);

  /// Decision: does a verified duration represent the FULL track?
  ///
  /// [expectedMs] comes from the search result that produced the match.
  /// Rules:
  ///  - no verified duration  -> reject (force-full policy)
  ///  - < 45 s while the track should be longer -> 30-s preview, reject
  ///  - verified shorter than 60% of expected -> short cut, reject
  static bool isFullTrack(int? seconds, int? expectedMs) {
    if (seconds == null) return false;
    final expected = (expectedMs ?? 0) ~/ 1000;
    if (expected >= 100 && seconds * 1000 < expectedMs! * 0.6) return false;
    if (seconds < 45 && expected >= 100) return false;
    if (seconds < 45 && expectedMs == null) return false;
    return true;
  }

  /// Fetch the head of the CDN asset and return the FLAC duration in
  /// seconds, or null when the bytes are not a verifiable FLAC stream.
  /// [blowfishKey] enables the Deezer first-blocks decryption (the first
  /// 2048-byte block of the payload is always encrypted).
  Future<int?> _probeFlacSeconds(String url, {Uint8List? blowfishKey}) async {
    final client = HttpClient()
      ..connectionTimeout = MirrorConfig.streamConnectTimeout;
    try {
      final wantEnd = blowfishKey == null ? 65535 : 6143;
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-$wantEnd');
      final res = await req.close().timeout(MirrorConfig.probeTimeout);
      if (res.statusCode != HttpStatus.partialContent &&
          res.statusCode != HttpStatus.ok) {
        return null;
      }
      final head = BytesBuilder();
      // The response is a single-subscription stream: once `await for`
      // cancels it, drain() throws StateError and rejects every valid
      // FLAC — so never drain here.
      await for (final chunk
          in res.timeout(MirrorConfig.probeTimeout, onTimeout: (sink) {
        sink.close();
      })) {
        head.add(chunk);
        if (head.length > wantEnd) break;
      }
      var bytes = head.toBytes();
      if (blowfishKey != null) bytes = MirrorSource.decryptHead(bytes, blowfishKey);
      return MirrorSource.flacDurationSeconds(bytes);
    } catch (e) {
      print('[mirror] flac probe error: $e');
      if (_isNetError(e)) _noteNetFail();
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Blowfish-decrypt every third 2048-byte block of a head buffer
  /// (same scheme as _serveDeezer, but on a small in-memory buffer).
  static Uint8List decryptHead(Uint8List raw, Uint8List key) {
    final out = Uint8List.fromList(raw);
    for (var off = 0;
        off + _kDzBlockSize <= out.length;
        off += _kDzBlockSize) {
      if ((off ~/ _kDzBlockSize) % 3 == 0) {
        out.setRange(off, off + _kDzBlockSize,
            _blowfishDecrypt(Uint8List.sublistView(out, off, off + _kDzBlockSize), key));
      }
    }
    return out;
  }

  /// FLAC STREAMINFO: `fLaC` magic + the first metadata block (always
  /// STREAMINFO per spec). Layout at file offset 8: min/max blocksize
  /// (2+2), min/max framesize (3+3), then 20 bits sample rate | 3 bits
  /// channels-1 | 5 bits bits-per-sample-1 | 36 bits total samples.
  ///
  /// SP71 FIX: total samples are the low nibble of b[21] plus b[22..25]
  /// (the 36-bit field starts AFTER the 20+3+5 = 28 rate/channel/bps
  /// bits). The old b[20..24] indexing consumed the bits-per-sample bits
  /// and produced astronomically wrong durations — which made every
  /// 30-second preview parse as "hours long" and slip through the
  /// full-stream gate. Cross-checked against qobuz manifest metadata
  /// (48000 Hz / 24-bit) and STREAMINFO bytes.
  static int? flacDurationSeconds(Uint8List b) {
    if (b.length < 34) return null;
    if (b[0] != 0x66 || b[1] != 0x4C || b[2] != 0x61 || b[3] != 0x43) {
      return null; // 'fLaC'
    }
    if ((b[4] & 0x7F) != 0) return null; // first block must be STREAMINFO
    final sr = (b[18] << 12) | (b[19] << 4) | (b[20] >> 4);
    if (sr <= 0) return null;
    final totalSamples = ((b[21] & 0x0F) << 32) |
        (b[22] << 24) |
        (b[23] << 16) |
        (b[24] << 8) |
        b[25];
    if (totalSamples <= 0) return null;
    return (totalSamples / sr).round();
  }

  // ------------------------------------------------------- caches & gate

  static const _failTtl = Duration(minutes: 10);
  static const _manifestTtl = Duration(minutes: 4);
  static const _maxCacheEntries = 64;

  final Map<String, DateTime> _failCache = {};
  final Map<String, (_TidalManifest, DateTime)> _tidalManifestCache = {};
  final Map<String, (_DeezerManifest, DateTime)> _dzManifestCache = {};
  final Map<String, (int, DateTime)> _dzTotalCache = {};

  static const _maxConcurrent = 2;
  int _inFlight = 0;

  /// Bounded slot wait: queued preloads must never make the on-demand
  /// play wait forever behind other resolutions. False on timeout.
  /// 3 s — after that the track falls through to the regular chain.
  Future<bool> _acquireSlot() async {
    // Strict lossless waits longer for a free slot instead of dropping to a
    // lossy stream while a background preload holds the resolver.
    final deadline = DateTime.now()
        .add(Duration(seconds: LosslessPrefs.strict ? 20 : 3));
    while (true) {
      if (_inFlight < _maxConcurrent) {
        _inFlight++;
        return true;
      }
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  void _releaseSlot() {
    if (_inFlight > 0) _inFlight--;
  }

  void _evict(Map map) {
    while (map.length > _maxCacheEntries) {
      map.remove(map.keys.first);
    }
  }
}

// ------------------------------------------------------------------ types

class _Identity {
  _Identity(this.title, this.artist, this.durationMs, this.spotifyId);
  final String title;
  final String artist;
  final int? durationMs;
  final String? spotifyId;
}

class _TidalMatch {
  _TidalMatch(this.trackId, this.hiRes);
  final String trackId;
  final bool hiRes;
}

class _TidalManifest {
  _TidalManifest(this.url, this.seconds);
  final String url;

  /// Real FLAC duration from the STREAMINFO probe (null = unverified).
  final int? seconds;
}

class _DeezerMatch {
  _DeezerMatch(this.trackId);
  final String trackId;
}

class _DeezerManifest {
  _DeezerManifest(this.url, this.keyBytes, this.seconds);
  final String url;
  final Uint8List keyBytes;

  /// Real FLAC duration from the STREAMINFO probe (null = unverified).
  final int? seconds;
}

/// Reads the upstream stream in exact 2048-byte blocks (the last block may
/// be short) so the every-third-block decryption stays aligned.
class _BlockReader {
  _BlockReader(Stream<List<int>> stream) : _it = StreamIterator(stream);

  final StreamIterator<List<int>> _it;
  final List<int> _buf = <int>[];
  bool _eof = false;

  Future<Uint8List?> nextBlock() async {
    while (_buf.length < _kDzBlockSize && !_eof) {
      final has = await _it.moveNext();
      if (!has) {
        _eof = true;
        break;
      }
      _buf.addAll(_it.current);
    }
    if (_buf.isEmpty) return null;
    if (_buf.length <= _kDzBlockSize) {
      final out = Uint8List.fromList(_buf);
      _buf.clear();
      return out;
    }
    final out = Uint8List.fromList(_buf.sublist(0, _kDzBlockSize));
    _buf.removeRange(0, _kDzBlockSize);
    return out;
  }

  Future<void> cancel() => _it.cancel();
}
