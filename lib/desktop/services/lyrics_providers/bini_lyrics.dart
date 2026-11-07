// ZenMusic · vorlon-dev
// Ported from BitChord (GPL-3.0) https://github.com/kushagrasinghx/BitChord — BiniLyrics.kt

import 'dart:convert';
import 'dart:io';

import 'lyric_doc.dart';

/// BiniLyrics: Apple Music TTML found through `lyrics-api.binimum.org`.
/// The search is answered by ISRC when one is known (it names one recording
/// and only that), otherwise by track / artist / album / duration. The hit
/// carries a `lyricsUrl`; the TTML itself is a second fetch.
class BiniLyrics {
  BiniLyrics._();

  static const String _base = 'https://lyrics-api.binimum.org/';
  static const String _ua =
      'ZenMusic/16.10 (desktop; +https://github.com/vorlon-dev/Zen-music)';

  static final RegExp _spanBegin = RegExp(
    r'<(?:[a-zA-Z0-9_-]+:)?span\b[^>]*\bbegin\s*=',
    caseSensitive: false,
  );
  static final RegExp _pBegin = RegExp(
    r'<(?:[a-zA-Z0-9_-]+:)?p\b[^>]*\bbegin\s*=',
    caseSensitive: false,
  );

  static HttpClient? _http;
  static HttpClient get _client => _http ??= HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 10);

  static void _log(String m) => print('[bini_lyrics] $m');

  /// Never throws. Null on a miss.
  static Future<LyricDoc?> lookup(LyricQuery q) async {
    try {
      final isrc = q.isrc?.trim() ?? '';
      final params = <String, String>{};
      if (isrc.isNotEmpty) {
        // Nothing else is worth sending: the recording is named, and a title
        // alongside it could only ever disagree with it.
        params['isrc'] = isrc;
      } else {
        if (q.title.trim().isEmpty) return null;
        params['track'] = q.title;
        params['artist'] = q.artist;
        final album = q.album;
        if (album != null && album.trim().isNotEmpty) params['album'] = album;
        final seconds = q.durationSec;
        if (seconds != null && seconds > 0) {
          params['duration'] = seconds.toString();
        }
      }

      final uri = Uri.parse(_base).replace(queryParameters: params);
      // A miss is a 404 here rather than an empty result set.
      final body = await _get(uri.toString());
      if (body == null) return null;

      dynamic json;
      try {
        json = jsonDecode(body);
      } catch (_) {
        return null;
      }
      if (json is! Map) return null;
      final results = json['results'];
      if (results is! List || results.isEmpty) return null;
      final hit = results.first;
      if (hit is! Map) return null;

      final url = hit['lyricsUrl'];
      if (url is! String || url.trim().isEmpty) return null;
      final ttml = await _get(url.trim());
      if (ttml == null) return null;

      final text = ttml.replaceAll('﻿', '').trim();
      final lower = text.toLowerCase();
      if (!lower.contains('<tt') && !lower.contains('<p')) return null;
      if (!_pBegin.hasMatch(text)) return null;
      final word = _spanBegin.hasMatch(text);
      return LyricDoc(payload: text, wordSynced: word, lineSynced: !word);
    } catch (e) {
      _log('lookup failed: $e');
      return null;
    }
  }

  static Future<String?> _get(String url) async {
    try {
      final req = await _client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      req.headers.set(HttpHeaders.acceptHeader,
          'application/json, application/xml, text/plain, */*');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Drain the error body so the socket is not pinned.
        await res.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      _log('GET failed ($url): $e');
      return null;
    }
  }
}
