// ZenMusic — Spotify Canvas (SP-9). Ported from Stopify's SpotifyCanvas.kt.
// Fetches the short looping videos that play behind a track using Spotify's
// internal `canvaz-cache` service (Protobuf, hand-encoded/decoded to avoid
// a protobuf runtime dependency). Reuses the web-player access token.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyCanvas {
  SpotifyCanvas._();
  static final SpotifyCanvas instance = SpotifyCanvas._();

  static const _endpoint =
      'https://spclient.wg.spotify.com/canvaz-cache/v0/canvases';
  final Map<String, String> _cache = {};

  Future<String?> fetchCanvasUrl(String trackIdOrUri) async {
    final cleanId = trackIdOrUri.split(':').last;
    if (cleanId.isEmpty) return null;

    if (_cache.containsKey(cleanId)) {
      final cached = _cache[cleanId];
      return (cached == null || cached.isEmpty) ? null : cached;
    }

    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) return null;
    final clientToken = await SpotifyAuth.instance.getClientToken();

    final uri = 'spotify:track:$cleanId';
    final body = _encodeRequest(uri);

    try {
      final r = await http
          .post(
        Uri.parse(_endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/protobuf',
          'Content-Type': 'application/protobuf',
          'User-Agent': SpotifyConfig.userAgent,
          'app-platform': SpotifyConfig.appPlatform,
          if (clientToken.isNotEmpty) 'client-token': clientToken,
        },
        body: body,
      )
          .timeout(const Duration(seconds: 8));

      if (r.statusCode < 200 || r.statusCode >= 300) {
        debugPrint('[spotify-canvas] HTTP ${r.statusCode} for $cleanId');
        _cache[cleanId] = '';
        return null;
      }

      final canvasUrl = _decodeFirstUrl(r.bodyBytes);
      debugPrint('[spotify-canvas] $cleanId -> ${canvasUrl ?? "none"}');
      _cache[cleanId] = canvasUrl ?? '';
      return canvasUrl;
    } catch (e) {
      debugPrint('[spotify-canvas] error for $cleanId: $e');
      _cache[cleanId] = '';
      return null;
    }
  }

  // ── Minimal protobuf wire encode/decode ──

  Uint8List _encodeRequest(String uri) {
    final uriBytes = utf8.encode(uri);
    // Entity: field 1 (entity_uri), wire type 2 (length-delimited)
    final entityBuilder = BytesBuilder();
    _writeTag(entityBuilder, 1, 2);
    _writeVarint(entityBuilder, uriBytes.length);
    entityBuilder.add(uriBytes);
    final entity = entityBuilder.toBytes();

    // EntityCanvazRequest: field 1 (entities), wire type 2
    final reqBuilder = BytesBuilder();
    _writeTag(reqBuilder, 1, 2);
    _writeVarint(reqBuilder, entity.length);
    reqBuilder.add(entity);
    return reqBuilder.toBytes();
  }

  String? _decodeFirstUrl(Uint8List data) {
    final r = _Reader(data);
    while (r.hasMore()) {
      final tag = r.readTag();
      final field = tag.$1;
      final wire = tag.$2;
      if (field == 1 && wire == 2) {
        final canvaz = r.readBytes();
        final url = _readCanvazUrl(canvaz);
        if (url != null) return url;
      } else {
        r.skip(wire);
      }
    }
    return null;
  }

  String? _readCanvazUrl(Uint8List canvaz) {
    final r = _Reader(canvaz);
    while (r.hasMore()) {
      final tag = r.readTag();
      final field = tag.$1;
      final wire = tag.$2;
      if (field == 2 && wire == 2) {
        return utf8.decode(r.readBytes());
      }
      r.skip(wire);
    }
    return null;
  }

  void _writeTag(BytesBuilder b, int field, int wire) {
    _writeVarint(b, (field << 3) | wire);
  }

  void _writeVarint(BytesBuilder b, int value) {
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    b.addByte(v & 0x7F);
  }
}

class _Reader {
  final Uint8List data;
  int pos = 0;
  _Reader(this.data);
  bool hasMore() => pos < data.length;

  (int, int) readTag() {
    final v = readVarint();
    return (v >> 3, v & 0x7);
  }

  int readVarint() {
    var result = 0;
    var shift = 0;
    while (pos < data.length) {
      final b = data[pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return result;
      shift += 7;
      if (shift >= 64) break;
    }
    return result;
  }

  Uint8List readBytes() {
    final len = readVarint();
    if (len <= 0) return Uint8List(0);
    final end = (pos + len).clamp(0, data.length);
    final out = data.sublist(pos, end);
    pos = end;
    return out;
  }

  void skip(int wire) {
    if (wire == 0) {
      readVarint();
    } else if (wire == 1) {
      pos = (pos + 8).clamp(0, data.length);
    } else if (wire == 2) {
      final len = readVarint();
      pos = (pos + len).clamp(0, data.length);
    } else if (wire == 5) {
      pos = (pos + 4).clamp(0, data.length);
    } else {
      pos = data.length;
    }
  }
}