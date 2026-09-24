import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'blowfish.dart';
import 'zarz_service.dart';

/// Deezer lossless via the zarz resolver: match → signed descriptor →
/// download → Blowfish-CBC decrypt → cached FLAC file. Gated behind
/// the Settings toggle — off by default.
///
/// Matching falls back through: Deezer search → MusicBrainz ISRC route
/// (search indexes can be geo-restricted; direct track lookups are not).
class DeezerLosslessService {
  static const _blowfishSecret = 'g4el58wc0zvf9na1';
  static const _chunkSize = 2048;
  static const List<int> _cbcIv = [0, 1, 2, 3, 4, 5, 6, 7];
  static const _negativeTtl = Duration(minutes: 10);
  static const _searchInterval = Duration(milliseconds: 400);
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';
  static const _mbUa = 'ZenMusic/1.0 (lossless matcher)';

  final http.Client _client = http.Client();
  final ZarzService _zarz = ZarzService();
  final Map<String, DateTime> _negativeCache = {};
  final Set<String> _inFlight = {};
  bool _cryptoChecked = false;
  bool _cryptoOk = false;
  DateTime? _lastSearchAt;

  void dispose() {
    _client.close();
    _zarz.dispose();
  }

  /// Settings toggle — the tier runs only when explicitly enabled.
  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('deezer_lossless_enabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Search (public api.deezer.com — verified from deezer.sflx) ──

  Future<void> _searchThrottle() async {
    final now = DateTime.now();
    if (_lastSearchAt != null) {
      final elapsed = now.difference(_lastSearchAt!);
      if (elapsed < _searchInterval) {
        await Future.delayed(_searchInterval - elapsed);
      }
    }
    _lastSearchAt = DateTime.now();
  }

  /// One Deezer search. Returns:
  ///  · List (possibly empty) on a clean 200 response
  ///  · null on transport / HTTP / API-error / bad-JSON failure
  Future<List<dynamic>?> _searchTracks(String query) async {
    await _searchThrottle();
    final url =
        'https://api.deezer.com/2.0/search?q=${Uri.encodeComponent(query)}&limit=25';
    http.Response resp;
    try {
      resp = await _client
          .get(Uri.parse(url), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      print('🔎 Deezer search: transport error for "$query": $e');
      return null;
    }
    if (resp.statusCode != 200) {
      print('🔎 Deezer search: HTTP ${resp.statusCode} for "$query"');
      return null;
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      print('🔎 Deezer search: non-JSON body for "$query"');
      return null;
    }
    if (decoded is! Map) {
      print('🔎 Deezer search: unexpected shape for "$query"');
      return null;
    }
    final err = decoded['error'];
    if (err != null) {
      print('🔎 Deezer search: API error for "$query" → $err');
      return null;
    }
    final items = decoded['data'];
    if (items is! List) {
      print('🔎 Deezer search: no data field for "$query"');
      return const [];
    }
    print('🔎 Deezer search: ${items.length} results for "$query"');
    return items;
  }

  /// Match: Deezer search → (geo-restricted / empty) → MusicBrainz
  /// ISRC route → Deezer /track/isrc: lookup. All endpoints verified.
  Future<String?> _matchTrackId(Song song) async {
    final artist = song.artist.split(',').first.trim();
    final title = song.title.trim();
    if (title.isEmpty) return null;

    var items = await _searchTracks('$artist $title'.trim());
    if (items == null) return null; // hard failure — negative-cache upstream
    if (items.isEmpty &&
        artist.isNotEmpty &&
        artist.toLowerCase() != title.toLowerCase()) {
      print('🔎 Deezer match: combined query empty — retrying title-only');
      items = await _searchTracks(title);
      if (items == null) return null;
    }
    if (items.isNotEmpty) {
      final bySearch = _bestFromItems(items, artist, title);
      if (bySearch != null) return bySearch;
    } else {
      print('🔎 Deezer match: search empty — trying MusicBrainz ISRC route');
    }

    final isrc = await _isrcFromMusicBrainz(artist, title);
    if (isrc == null) {
      print('🔎 Deezer match: MusicBrainz produced no ISRC for "$title"');
      return null;
    }
    print('🔎 Deezer match: MusicBrainz ISRC $isrc — looking up Deezer');
    final byIsrc = await _trackIdFromIsrc(isrc);
    if (byIsrc == null) {
      print('🔎 Deezer match: Deezer has no track for ISRC $isrc');
      return null;
    }
    return byIsrc;
  }

  String? _bestFromItems(
      List<dynamic> items, String artist, String title) {
    String norm(String v) => v
        .replaceAll(RegExp(r'[^\w\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    int compare(String a, String b) {
      if (a.isEmpty || b.isEmpty) return 0;
      if (a == b) return 100;
      if (a.contains(b) || b.contains(a)) return 60;
      return 0;
    }

    final nTitle = norm(title);
    final nArtist = norm(artist);
    String? bestId;
    var bestScore = 0;
    String bestLabel = '';
    for (final entry in items) {
      if (entry is! Map) continue;
      final track = Map<String, dynamic>.from(entry);
      final t = '${track['title'] ?? ''}';
      final trackArtist = '${(track['artist'] as Map?)?['name'] ?? ''}';
      if (track['id'] == null) continue;
      var score = 0;
      if (nTitle.isNotEmpty) score += compare(nTitle, norm(t)) * 70;
      if (nArtist.isNotEmpty) score += compare(nArtist, norm(trackArtist)) * 30;
      if (score > bestScore) {
        bestScore = score;
        bestId = '${track['id']}';
        bestLabel = '$t — $trackArtist';
      }
    }
    if (bestScore >= 55 && bestId != null) {
      print('🔎 Deezer match: score $bestScore → "$bestLabel" (id $bestId)');
      return bestId;
    }
    print('🔎 Deezer match: no confident match for "$title" '
        '(best $bestScore < 55)');
    return null;
  }

  /// MusicBrainz: recording search (score ≥ 90 + title/artist match,
  /// verified from SpotiFLAC's resolver service) → recording ISRC.
  /// 1 request/second per MusicBrainz policy.
  Future<String?> _isrcFromMusicBrainz(String artist, String title) async {
    String esc(String v) => v.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final query = 'recording:"${esc(title)}" AND artist:"${esc(artist)}"';
    await _searchThrottle();
    try {
      final searchUrl =
          'https://musicbrainz.org/ws/2/recording?fmt=json&limit=5&query=${Uri.encodeComponent(query)}';
      final resp = await _client.get(
        Uri.parse(searchUrl),
        headers: {'User-Agent': _mbUa},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        print('🔎 MusicBrainz: HTTP ${resp.statusCode}');
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final recordings = data['recordings'];
      if (recordings is! List) return null;

      String norm(String v) => v
          .replaceAll(RegExp(r'[^\w\s]+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      final nTitle = norm(title);
      final nArtist = norm(artist);
      String? recordingId;
      for (final entry in recordings) {
        if (entry is! Map) continue;
        final rec = Map<String, dynamic>.from(entry);
        final score = (rec['score'] as num?)?.toInt() ?? 0;
        if (score < 90) continue;
        final rTitle = '${rec['title'] ?? ''}';
        if (norm(rTitle) != nTitle) continue;
        final artists = rec['artist-credit'];
        var artistOk = false;
        if (artists is List && artists.isNotEmpty && artists.first is Map) {
          final candidate = norm('${(artists.first as Map)['name'] ?? ''}');
          artistOk = candidate == nArtist ||
              candidate.contains(nArtist) ||
              nArtist.contains(candidate);
        }
        if (!artistOk) continue;
        recordingId = '${rec['id']}';
        break;
      }
      if (recordingId == null) {
        print('🔎 MusicBrainz: no verified recording match');
        return null;
      }
      print('🔎 MusicBrainz: recording matched ($recordingId)');

      await Future.delayed(const Duration(milliseconds: 1100));
      final detailUrl =
          'https://musicbrainz.org/ws/2/recording/$recordingId?fmt=json&inc=isrcs';
      final resp2 = await _client.get(
        Uri.parse(detailUrl),
        headers: {'User-Agent': _mbUa},
      ).timeout(const Duration(seconds: 10));
      if (resp2.statusCode != 200) {
        print('🔎 MusicBrainz detail: HTTP ${resp2.statusCode}');
        return null;
      }
      final detail = jsonDecode(resp2.body) as Map<String, dynamic>;
      final isrcs = detail['isrcs'];
      if (isrcs is List && isrcs.isNotEmpty) {
        final first = isrcs.first;
        if (first is Map && first['isrc'] != null) {
          return '${first['isrc']}';
        }
      }
      print('🔎 MusicBrainz: recording has no ISRC');
      return null;
    } catch (e) {
      print('🔎 MusicBrainz failed: $e');
      return null;
    }
  }

  /// Deezer lookup by ISRC — verified from deezer.sflx
  /// resolveTrackIDFromISRC (/track/isrc:{isrc}).
  Future<String?> _trackIdFromIsrc(String isrc) async {
    try {
      final url =
          'https://api.deezer.com/2.0/track/isrc:${Uri.encodeComponent(isrc)}';
      final resp = await _client
          .get(Uri.parse(url), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        print('🔎 Deezer ISRC lookup: HTTP ${resp.statusCode}');
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['error'] != null) {
        print('🔎 Deezer ISRC lookup: API error ${data['error']}');
        return null;
      }
      final id = data['id'];
      if (id == null) {
        print('🔎 Deezer ISRC lookup: no id in response');
        return null;
      }
      final tTitle = '${data['title'] ?? ''}';
      print('🔎 Deezer ISRC lookup: id $id → "$tTitle"');
      return '$id';
    } catch (e) {
      print('🔎 Deezer ISRC lookup failed: $e');
      return null;
    }
  }

  /// Full flow: match → ticket → descriptor → download → decrypt.
  /// Returns a playable file:// URL, or null (caller falls through).
  Future<({String url, Map<String, String> headers, int? kbps})?>
  tryLossless(Song song) async {
    if (!_cryptoChecked) {
      _cryptoChecked = true;
      _cryptoOk = BlowfishCipher.selfTest();
      if (!_cryptoOk) {
        print('↳ Deezer lossless disabled: Blowfish self-test failed');
      } else {
        print('✅ Blowfish self-test passed — Deezer lossless armed');
      }
    }
    if (!_cryptoOk) return null;

    final neg = _negativeCache[song.id];
    if (neg != null && DateTime.now().difference(neg) < _negativeTtl) {
      return null;
    }
    if (_inFlight.contains(song.id)) return null;
    _inFlight.add(song.id);
    try {
      final trackId = await _matchTrackId(song);
      if (trackId == null) {
        _negativeCache[song.id] = DateTime.now();
        return null;
      }

      final trackUrl = 'https://www.deezer.com/track/$trackId';
      final resourceHash = crypto.sha256
          .convert(utf8.encode('dzr:track:${trackUrl.toLowerCase()}'))
          .toString();
      final ticketResp = await _zarz.signedCall(
        'POST',
        '/tickets',
        jsonEncode({
          'capability': 'download_ticket',
          'provider': 'dzr',
          'resource_hash': resourceHash,
        }),
      );
      if (ticketResp == null) {
        print('🎫 zarz ticket: failed for track $trackId');
        _negativeCache[song.id] = DateTime.now();
        return null;
      }
      final ticketMap = jsonDecode(ticketResp.body) as Map<String, dynamic>;
      final ticketId =
      '${ticketMap['ticket_id'] ?? ticketMap['ticket'] ?? ''}'.trim();
      if (ticketId.isEmpty) {
        print('🎫 zarz ticket: response missing ticket_id');
        return null;
      }
      print('🎫 zarz ticket: issued');

      final descriptorResp = await _zarz.signedCall(
        'POST',
        '/dl/dzr',
        jsonEncode({
          'id': trackId,
          'type': 'track',
          'platform': 'deezer',
          'url': trackUrl,
        }),
        extraHeaders: {'X-Zarz-Ticket': ticketId},
      );
      if (descriptorResp == null) {
        print('📦 zarz descriptor: failed for track $trackId');
        return null;
      }
      final descriptor =
      jsonDecode(descriptorResp.body) as Map<String, dynamic>;
      if (descriptor['success'] == false) {
        print('📦 zarz descriptor: success=false '
            '(${descriptor['message'] ?? descriptor['error'] ?? 'no message'})');
        return null;
      }
      final downloadUrl =
          '${descriptor['direct_download_url'] ?? descriptor['download_url'] ?? ''}';
      if (downloadUrl.isEmpty) {
        print('📦 zarz descriptor: no download URL in response');
        return null;
      }
      final needsDecrypt = descriptor['requires_client_decryption'] == true ||
          descriptor['deezer_encrypted'] == true;
      print('📦 zarz descriptor: ok (decrypt=$needsDecrypt)');

      final cacheFile = await _cacheFile(trackId);
      if (!cacheFile.existsSync()) {
        final sw = Stopwatch()..start();
        final raw = await _download(downloadUrl);
        if (raw == null) {
          print('⬇️ Deezer download: failed');
          return null;
        }
        print('⬇️ Deezer download: ${(raw.length / 1048576).toStringAsFixed(1)} MB '
            'in ${sw.elapsedMilliseconds}ms');
        if (needsDecrypt) {
          final decrypted = _decryptDeezer(raw, trackId);
          if (decrypted == null) return null;
          await cacheFile.writeAsBytes(decrypted, flush: true);
        } else {
          await cacheFile.writeAsBytes(raw, flush: true);
        }
        print('🔓 Deezer: FLAC cached (${cacheFile.path})');
      }
      return (
      url: 'file://${cacheFile.path}',
      headers: const <String, String>{},
      kbps: 900,
      );
    } catch (e) {
      print('↳ Deezer lossless failed: $e');
      return null;
    } finally {
      _inFlight.remove(song.id);
    }
  }

  Future<File> _cacheFile(String trackId) async {
    final dir = Directory.systemTemp;
    final safe = trackId.replaceAll(RegExp(r'[^0-9]'), '');
    return File('${dir.path}/deezer_$safe.flac');
  }

  Future<List<int>?> _download(String url) async {
    try {
      final resp = await _client
          .get(Uri.parse(url), headers: {'User-Agent': _ua})
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) {
        print('⬇️ Deezer download: HTTP ${resp.statusCode}');
        return null;
      }
      return resp.bodyBytes;
    } catch (e) {
      print('⬇️ Deezer download error: $e');
      return null;
    }
  }

  // ── Blowfish decryption (scheme verified from deezer.sflx download()
  //    + Rust crypto.rs: per-track key md5^secret, CBC on ciphertext
  //    with fresh IV per chunk, every 3rd 2048-byte chunk encrypted) ──

  /// Per-track Blowfish key: md5(trackId)[i] ^ md5[i+16] ^ secret[i].
  Uint8List _trackKey(String trackId) {
    final md5hex = crypto.md5.convert(utf8.encode(trackId)).toString();
    final key = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      key[i] = md5hex.codeUnitAt(i) ^
      md5hex.codeUnitAt(i + 16) ^
      _blowfishSecret.codeUnitAt(i);
    }
    return key;
  }

  /// Decrypts every 3rd 2048-byte chunk with a fresh CBC chain per chunk.
  List<int>? _decryptDeezer(List<int> bytes, String trackId) {
    try {
      final sw = Stopwatch()..start();
      final key = _trackKey(trackId);
      final cipher = BlowfishCipher(Uint8List.fromList(key));
      final out = Uint8List.fromList(bytes);
      final block = Uint8List(8);
      var encryptedChunks = 0;
      for (var chunkStart = 0;
      chunkStart + _chunkSize <= out.length;
      chunkStart += _chunkSize) {
        final chunkIndex = chunkStart ~/ _chunkSize;
        if (chunkIndex % 3 != 0) continue; // every 3rd chunk is encrypted
        encryptedChunks++;
        var prev = Uint8List.fromList(_cbcIv);
        for (var off = chunkStart; off < chunkStart + _chunkSize; off += 8) {
          block.setRange(0, 8, out, off);
          cipher.decryptBlock(block, 0);
          for (var i = 0; i < 8; i++) {
            block[i] ^= prev[i];
          }
          out.setRange(off, off + 8, block);
          prev = Uint8List.fromList(block); // CBC chains on ciphertext
        }
      }
      print('🔓 Decrypt: $encryptedChunks chunks in ${sw.elapsedMilliseconds}ms');
      return out;
    } catch (e) {
      print('↳ Deezer decrypt failed: $e');
      return null;
    }
  }
}