// ZenMusic · vorlon-dev
//
// SP71 — dual-engine arbiter (Dart mirror engine <-> Kotlin mirror engine).
//
// The Dart engine (mirror_source.dart) stays EXACTLY as it is — this file
// only decides WHO resolves a track and provides the loopback routes the
// Kotlin engine's results stream through. The alternation is what the
// user asked for, verbatim:
//
//   * Dart engine resolving fine  -> the Kotlin engine is never called
//     (standby: "when dart working Kotlin should be in cool down time").
//   * Dart engine stops (breaker open, timeouts, catalog misses)   -> the
//     Kotlin engine takes over the next track ("when other stop, other
//     start"). Two consecutive Dart failures wake it immediately, so a
//     dying mirror pool never locks FLAC out.
//   * Both engines failed for one track -> EMERGENCY (Android only): the
//     fixed endpoint is asked for a stream URL directly (manifest, then
//     its /api/stream relay). Rate-limited to once per 10 minutes —
//     emergency ONLY, never a primary path.
//
// On Windows / macOS the arbiter is simply the Dart engine — those
// platforms keep the exact pre-SP71 behaviour ("for windows and other
// platform keep as it's now working ok").
//
// Playback path for Kotlin-engine results: this file owns a small loopback
// server (`/kt` plain Range passthrough, `/kz` Blowfish-decrypting Deezer
// passthrough) so mirror_source.dart needs no changes at all. Sources are
// verified twice (Kotlin STREAMINFO probe + the same isFullTrack gate) so
// 30-second preview cuts can never reach the player.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'blowfish.dart';
import 'lossless_quality.dart';
import 'lossless_service.dart';
import 'mirror_config.dart';
import 'mirror_source.dart';

/// Deezer frame geometry: every third 2048-byte block is encrypted.
const int _kDzBlockSize = 2048;

/// Fixed Blowfish IV used by Deezer's CDN encryption.
final Uint8List _kDzIv = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

/// SP71b: search window handed to the Kotlin engine's resolver — matches
/// the Dart engine's mirror search timeout. Lives here, not in
/// MirrorConfig, so mirror_config.dart drift on either side can never
/// break the build again.
const int _kotlinSearchMs = 4000;

class MirrorArbiter {
  MirrorArbiter._();
  static final MirrorArbiter instance = MirrorArbiter._();

  static const MethodChannel _channel = MethodChannel('zen/mirror_engine');

  /// The fixed qobuz endpoint — the healthiest mirror host (search +
  /// manifest + /api/stream relay). Lives here, next to MirrorConfig's
  /// other hosts, so an endpoint redeploy is a one-line change.
  static const String _qobuzHost = 'https://qobuz.anandserver.cfd';

  // ------------------------------------------------- alternation state

  /// Consecutive tracks the Dart engine failed to serve. Two in a row
  /// wake the Kotlin engine immediately (same threshold as the Dart
  /// engine's own breaker, so the takeover lands exactly when the Dart
  /// engine starts resting).
  int _dartFailStreak = 0;

  /// While the Dart engine is healthy the Kotlin engine rests ("cool
  /// down time"). Refreshed on every Dart success.
  static const _kotlinStandby = Duration(minutes: 3);
  DateTime _kotlinStandbyUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// After a Kotlin failure the engine rests before being tried again —
  /// mirrors the Dart engine's own breaker so a dead native path can't
  /// burn budget on every track.
  DateTime _kotlinDownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// EMERGENCY ONLY: the fixed endpoint is touched at most once per 10
  /// minutes after a successful emergency rescue (5 min after a failed
  /// one), so it stays a last resort and never becomes a primary source.
  DateTime _emergencyDownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  bool _kotlinConfigured = false;
  bool _configurePermanentFail = false;
  Future<void>? _configuring;

  /// Deezer total sizes via the 1-byte Range probe, cached per upstream
  /// URL (TTL 4 min). ExoPlayer re-opens the stream on every seek - the
  /// probe must never repeat or it stalls the loopback and kills playback.
  final Map<String, (int, DateTime)> _kzTotalCache = {};

  // ------------------------------------------------------------- entry

  /// Lossless AudioSource for [song] — Dart engine first, then the Kotlin
  /// engine, then the emergency endpoint. Never throws; null makes the
  /// caller fall through to JioSaavn / cache / YouTube (never stalls).
  Future<AudioSource?> tryBuildSource(
      Map<String, dynamic> song, MediaItem tag) async {
    // MP3 tier is served by the normal chain; mirrors are FLAC-only.
    if (LosslessPrefs.current == LosslessQuality.mp3_320) return null;
    final startedAt = DateTime.now();
    try {
      final identity = _identityFrom(song);
      if (identity == null) return null;

      // 1) The Dart engine — untouched, exactly as the user shipped it.
      //    While its breaker is open this returns null in ~0 ms, so the
      //    handoff to Kotlin costs nothing.
      final dartSource = await MirrorSource.instance.tryBuildSource(song, tag);
      if (dartSource != null) {
        _dartFailStreak = 0;
        _kotlinStandbyUntil = DateTime.now().add(_kotlinStandby);
        return dartSource;
      }
      _dartFailStreak++;

      if (!Platform.isAndroid) return null; // Windows & co: unchanged.

      final now = DateTime.now();
      final kotlinAllowed = now.isAfter(_kotlinDownUntil) &&
          (now.isAfter(_kotlinStandbyUntil) || _dartFailStreak >= 2);

      bool kotlinAttempted = false;
      Map<String, dynamic>? desc;

      // 2) The Kotlin engine (hot standby).
      if (kotlinAllowed) {
        final left = const Duration(seconds: 8) -
            DateTime.now().difference(startedAt);
        if (left > const Duration(milliseconds: 1200)) {
          kotlinAttempted = true;
          desc = await _kotlinCall('resolve', identity, left);
          if (desc != null && desc['status'] == 'ok') {
            final source =
                await _buildSourceFromDescriptor(desc, tag, identity.durationMs);
            if (source != null) {
              _dartFailStreak = 0;
              print('[arbiter] kotlin engine served "${identity.title}"');
              return source;
            }
          }
        }
      }

      // 3) EMERGENCY — the endpoint gives a stream URL directly. Only
      //    when the Kotlin engine was actually attempted and also failed
      //    (a busy engine is alive, not failed — it gets no emergency).
      if (kotlinAttempted) {
        final status = desc?['status'];
        final failedForTrack = status != 'ok' && status != 'busy';
        if (failedForTrack && DateTime.now().isAfter(_emergencyDownUntil)) {
          final left = const Duration(seconds: 8) -
              DateTime.now().difference(startedAt);
          if (left > const Duration(milliseconds: 1500)) {
            final emergencyDesc = await _kotlinCall('emergency', identity, left);
            if (emergencyDesc != null && emergencyDesc['status'] == 'ok') {
              final source = await _buildSourceFromDescriptor(
                  emergencyDesc, tag, identity.durationMs);
              if (source != null) {
                _emergencyDownUntil =
                    DateTime.now().add(const Duration(minutes: 10));
                _dartFailStreak = 0;
                print('[arbiter] EMERGENCY endpoint rescued "${identity.title}"');
                return source;
              }
            }
            // Emergency attempted and did not rescue — rest the path.
            if (_emergencyDownUntil.isBefore(DateTime.now())) {
              _emergencyDownUntil =
                  DateTime.now().add(const Duration(minutes: 5));
            }
          }
        }
      }
      return null;
    } catch (e) {
      print('[arbiter] tryBuildSource error: $e');
      return null;
    }
  }

  // ------------------------------------------------------- kotlin bridge

  Future<void> _ensureConfigured() async {
    if (_kotlinConfigured || _configurePermanentFail) return;
    _configuring ??= _configureNow();
    await _configuring;
  }

  Future<void> _configureNow() async {
    try {
      final ok = await _channel
          .invokeMethod('configure', {
        'hosts': {
          'tidal': MirrorConfig.tidal,
          'deezer': MirrorConfig.deezer,
          'qobuz': _qobuzHost,
          'apiKey': MirrorConfig.apiKey,
        },
        'timeouts': {
          'searchMs': _kotlinSearchMs,
          'manifestMs': MirrorConfig.manifestTimeout.inMilliseconds,
          'probeMs': MirrorConfig.probeTimeout.inMilliseconds,
          'streamConnectMs': MirrorConfig.streamConnectTimeout.inMilliseconds,
        },
      })
          .timeout(const Duration(seconds: 4));
      _kotlinConfigured = ok == true;
      if (!_kotlinConfigured) _configurePermanentFail = true;
      print('[arbiter] kotlin mirror engine configured: $_kotlinConfigured');
    } on MissingPluginException {
      // Non-Android platform or older APK without the engine — the Dart
      // engine alone is the whole chain, exactly as before SP71.
      _configurePermanentFail = true;
    } catch (e) {
      print('[arbiter] kotlin configure failed (will retry): $e');
      _configuring = null; // transient — retry on the next resolve
    }
  }

  /// One MethodChannel round-trip with its own cooldown bookkeeping.
  /// Returns the reply map, or null when the engine is unusable.
  Future<Map<String, dynamic>?> _kotlinCall(
      String method, _ArbIdentity id, Duration budget) async {
    try {
      await _ensureConfigured();
      if (!_kotlinConfigured) return null;
      final remaining = budget - const Duration(milliseconds: 300);
      if (remaining <= Duration.zero) return null;
      final wantsHiRes = LosslessPrefs.current == LosslessQuality.flacHiRes96 ||
          LosslessPrefs.current == LosslessQuality.flacHiResMax;
      final reply = await _channel
          .invokeMethod(method, {
            'title': id.title,
            'artist': id.artist,
            'durationMs': id.durationMs,
            'wantsHiRes': wantsHiRes,
            'budgetMs': remaining.inMilliseconds,
          })
          .timeout(remaining, onTimeout: () => null);
      if (reply == null) {
        // Native side did not answer inside the budget — rest it briefly.
        _kotlinDownUntil = DateTime.now().add(const Duration(seconds: 90));
        print('[arbiter] kotlin $method timed out (${remaining.inMilliseconds} ms)');
        return null;
      }
      final map = Map<String, dynamic>.from(reply as Map);
      switch (map['status']) {
        case 'ok':
          return map;
        case 'breaker':
          _kotlinDownUntil = DateTime.now().add(const Duration(minutes: 2));
          return map;
        case 'busy':
          _kotlinDownUntil = DateTime.now().add(const Duration(seconds: 20));
          return map;
        case 'error':
          _kotlinDownUntil = DateTime.now().add(const Duration(seconds: 90));
          return map;
        default: // no_match — per-track, no global cooldown
          return map;
      }
    } on MissingPluginException {
      _configurePermanentFail = true;
      return null;
    } on PlatformException catch (e) {
      print('[arbiter] kotlin $method platform error: $e');
      _kotlinDownUntil = DateTime.now().add(const Duration(seconds: 90));
      return null;
    } catch (e) {
      print('[arbiter] kotlin $method error: $e');
      return null;
    }
  }

  // ---------------------------------------------------- source building

  /// Turn a verified Kotlin descriptor into a loopback AudioSource.
  /// Every descriptor passes the same isFullTrack gate the Dart engine
  /// uses — preview cuts are impossible to serve by accident.
  Future<AudioSource?> _buildSourceFromDescriptor(
      Map<String, dynamic> desc, MediaItem tag, int? expectedMs) async {
    try {
      final kind = '${desc['kind'] ?? ''}';
      final url = '${desc['url'] ?? ''}';
      if (url.isEmpty) return null;
      final seconds = desc['seconds'] is int ? desc['seconds'] as int : null;
      if (!MirrorSource.isFullTrack(seconds, expectedMs)) {
        print('[arbiter] descriptor for "$tag" rejected by the full-stream gate');
        return null;
      }
      await _ensureServer();

      if (kind == 'dz') {
        final key64 = '${desc['key64'] ?? ''}';
        if (key64.isEmpty) return null;
        final playUrl = Uri.parse('$_baseUrl/kz'
            '?u=${Uri.encodeComponent(base64Url.encode(utf8.encode(url)))}'
            '&k=${Uri.encodeComponent(base64Url.encode(utf8.encode(key64)))}');
        _noteServed(tag, desc);
        return AudioSource.uri(playUrl, tag: tag);
      }
      // 'tide' (signed CDN URL) and 'relay' (endpoint hands the FLAC
      // itself) are both plain byte streams — same passthrough route.
      final playUrl = Uri.parse('$_baseUrl/kt'
          '?u=${Uri.encodeComponent(base64Url.encode(utf8.encode(url)))}');
      _noteServed(tag, desc);
      return AudioSource.uri(playUrl, tag: tag);
    } catch (e) {
      print('[arbiter] descriptor build error: $e');
      return null;
    }
  }

  void _noteServed(MediaItem tag, Map<String, dynamic> desc) {
    final tier = '${desc['tier'] ?? 'cd'}' == 'hires'
        ? LosslessQuality.flacHiRes96
        : LosslessQuality.flacCd;
    LosslessService.instance.noteMirrorServed(tag.id, tier);
  }

  // ----------------------------------------------------------- identity

  _ArbIdentity? _identityFrom(Map<String, dynamic> song) {
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
    return _ArbIdentity(title, artist, durationMs);
  }

  // ------------------------------------------------------------ loopback

  HttpServer? _server;
  String? _baseUrl;

  Future<void> _ensureServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _baseUrl = 'http://${server.address.host}:${server.port}';
    server.listen(_handle, onError: (Object e) {
      print('[arbiter] loopback error: $e');
    });
    print('[arbiter] loopback listening on $_baseUrl');
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case '/kt':
          await _servePlain(request);
          break;
        case '/kz':
          await _serveDeezer(request);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (e) {
      print('[arbiter] loopback handler error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// GET /kt?u=<base64 upstream>
  ///
  /// Plain Range-forwarding passthrough for the Kotlin engine's upstream
  /// URL (signed CDN for qobuz/tidal, or the endpoint's /api/stream relay
  /// which ignores Range — the window emulation below covers that case).
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
        final to = end < chunkEnd - 1 ? (end - pos + 1) : chunk.length;
        if (to > from) {
          response.add(Uint8List.fromList(chunk.sublist(from, to)));
          written += to - from;
        }
        pos = chunkEnd;
      }
      await response.close();
    } catch (e) {
      print('[arbiter] plain passthrough error: $e');
      try {
        await response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  /// GET /kz?u=<base64 upstream>&k=<base64 key>
  ///
  /// Deezer CDN payload served by the Kotlin engine: every third 2048-byte
  /// block (3rd, 6th, …) is Blowfish-CBC encrypted with the fixed IV, the
  /// rest is plain. Reads are aligned to the 2048-byte grid so decryption
  /// stays deterministic no matter where the player seeks.
  Future<void> _serveDeezer(HttpRequest request) async {
    final u = request.uri.queryParameters['u'] ?? '';
    final k = request.uri.queryParameters['k'] ?? '';
    final response = request.response;
    if (u.isEmpty || k.isEmpty) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }
    String upstreamUrl;
    Uint8List keyBytes;
    try {
      upstreamUrl = utf8.decode(base64Url.decode(u));
      keyBytes = Uint8List.fromList(base64Url.decode(k));
    } catch (_) {
      response.statusCode = HttpStatus.badRequest;
      await response.close();
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = MirrorConfig.streamConnectTimeout;
    HttpClient? upstreamClient;
    try {
      final head = await client.getUrl(Uri.parse(upstreamUrl));
      head.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      HttpClientResponse headRes;
      try {
        headRes = await head.close().timeout(MirrorConfig.probeTimeout);
      } catch (_) {
        response.statusCode = HttpStatus.gatewayTimeout;
        await response.close();
        return;
      }
      int? total;
      final now0 = DateTime.now();
      final cachedTotal = _kzTotalCache[upstreamUrl];
      if (cachedTotal != null && now0.isBefore(cachedTotal.$2)) {
        total = cachedTotal.$1;
      }
      if (total == null) {
        final cr = headRes.headers.value(HttpHeaders.contentRangeHeader);
        if (cr != null) {
          final m = RegExp(r'/(\d+)$').firstMatch(cr);
          if (m != null) total = int.parse(m.group(1)!);
        }
      }
      if (total == null && headRes.statusCode == HttpStatus.ok &&
          headRes.contentLength > 0) {
        total = headRes.contentLength;
      }
      if (total != null) {
        _kzTotalCache[upstreamUrl] =
            (total, now0.add(const Duration(minutes: 4)));
      }
      try {
        await headRes.drain<void>().timeout(const Duration(seconds: 5),
            onTimeout: () {});
      } catch (_) {}
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

      upstreamClient = HttpClient()
        ..connectionTimeout = MirrorConfig.streamConnectTimeout;
      final req = await upstreamClient.getUrl(Uri.parse(upstreamUrl));
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

      final dec = BlowfishCbcDecryptor(keyBytes, _kDzIv);
      final buf = <int>[];
      var blockNo = startBlock;
      var served = 0;
      var skipped = 0;
      final want = end - start + 1;
      StreamIterator<List<int>>? it;

      Future<Uint8List?> nextBlock() async {
        it ??= StreamIterator(upstream);
        while (buf.length < _kDzBlockSize) {
          final has = await it!.moveNext();
          if (!has) break;
          buf.addAll(it!.current);
        }
        if (buf.isEmpty) return null;
        final take =
            buf.length < _kDzBlockSize ? buf.length : _kDzBlockSize;
        final out = Uint8List.fromList(buf.sublist(0, take));
        buf.removeRange(0, take);
        return out;
      }

      while (served < want) {
        final block = await nextBlock();
        if (block == null || block.isEmpty) break;
        var out = block;
        if (block.length == _kDzBlockSize && blockNo % 3 == 0) {
          out = Uint8List(block.length);
          for (var off = 0; off + 8 <= block.length; off += 8) {
            out.setRange(off, off + 8,
                dec.decryptBlock(Uint8List.sublistView(block, off)));
          }
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
        final take = avail < (want - served) ? avail : (want - served);
        response.add(Uint8List.sublistView(out, from, from + take));
        served += take;
      }
      await response.close();
    } catch (e) {
      print('[arbiter] deezer passthrough error: $e');
      try {
        await response.close();
      } catch (_) {}
    } finally {
      client.close(force: true);
      upstreamClient?.close(force: true);
    }
  }
}

// ------------------------------------------------------------------ types

class _ArbIdentity {
  _ArbIdentity(this.title, this.artist, this.durationMs);
  final String title;
  final String artist;
  final int? durationMs;
}
