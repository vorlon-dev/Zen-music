import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';

/// Qobuz lossless source. The request-signing scheme, app credentials,
/// getFileUrl contract and track-matching rules are ported from the
/// qobuz-web extension source. Without a user auth token the service
/// stays dormant and the app uses its default chain unchanged.
class QobuzService {
  static const _apiBase = 'https://www.qobuz.com/api.json/0.2';
  static const _streamAppId = '712109809';
  static const _streamAppSecret = '589be88e4538daea11f509d29e4a23b1';
  static const _publicAppId = '735532640';

  // Lossless ladder, hi-res first. Only format_id 5 appears in the
  // pasted source; the lossless ids are community Qobuz-API knowledge
  // — flagged per house rules. Unsupported ids simply fail and the
  // ladder falls through.
  static const List<String> _formatLadder = ['27', '7', '6'];

  static const _requestTimeout = Duration(seconds: 10);
  static const _negativeTtl = Duration(minutes: 10);

  final http.Client _client = http.Client();
  final Map<String, DateTime> _negativeCache = {};

  void dispose() => _client.close();

  static Future<String?> _token() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = (prefs.getString('qobuz_token') ?? '').trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> losslessOnlyEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('lossless_only') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── request signing (verified against qobuzSignedURL) ──

  String _signedUrl(String object, String method, Map<String, String> params) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final keys = params.keys.toList()..sort();
    final raw = StringBuffer(object + method);
    for (final k in keys) {
      raw
        ..write(k)
        ..write(params[k]!);
    }
    raw
      ..write(ts)
      ..write(_streamAppSecret);
    final sig = md5.convert(utf8.encode(raw.toString())).toString();
    final query = [
      for (final k in keys)
        '${Uri.encodeComponent(k)}=${Uri.encodeComponent(params[k]!)}',
      'request_ts=${Uri.encodeComponent(ts)}',
      'request_sig=${Uri.encodeComponent(sig)}',
    ].join('&');
    return '$_apiBase/$object/$method?$query';
  }

  Future<Map<String, dynamic>?> _getJson(
      String url, Map<String, String> headers) async {
    try {
      final resp = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(_requestTimeout);
      if (resp.statusCode != 200) return null;
      final body = resp.body;
      if (body.startsWith('<!DOCTYPE html') || body.startsWith('<html')) {
        return null;
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── search (public endpoint, widget app id — flagged) ──

  Future<List<dynamic>> _searchTracks(String query) async {
    final url = '$_apiBase/track/search?q=${Uri.encodeComponent(query)}&limit=25';
    final data = await _getJson(url, const {
      'X-App-Id': _publicAppId,
      'Accept': 'application/json',
    });
    final tracks = data?['tracks'];
    if (tracks is! Map) return const [];
    final items = tracks['items'];
    return items is List ? items : const [];
  }

  // ── matching engine (ported from the extension's matchers) ──

  static String _norm(String v) => v
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^\w\s]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static String _cleanTitle(String v) {
    var out = v;
    const patterns = [
      'remaster', 'remastered', 'deluxe', 'bonus', 'single',
      'album version', 'radio edit', 'original mix', 'extended',
      'club mix', 'remix', 'live', 'acoustic', 'demo',
    ];
    var changed = true;
    while (changed) {
      changed = false;
      out = out.replaceAllMapped(
        RegExp(r'\(([^)]*)\)|\[([^\]]*)\]'),
            (m) {
          final inner =
          ((m.group(1) ?? '') + (m.group(2) ?? '')).toLowerCase();
          for (final p in patterns) {
            if (inner.contains(p)) {
              changed = true;
              return ' ';
            }
          }
          return m.group(0)!;
        },
      );
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _titlesMatch(String expected, String found) {
    final a = _norm(expected);
    final b = _norm(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final ca = _cleanTitle(a);
    final cb = _cleanTitle(b);
    if (ca.isNotEmpty &&
        cb.isNotEmpty &&
        (ca == cb || ca.contains(cb) || cb.contains(ca))) {
      return true;
    }
    return false;
  }

  static List<String> _splitArtists(String v) => v
      .toLowerCase()
      .replaceAll(RegExp(r'\bfeat\b'), '|')
      .replaceAll(RegExp(r'\bfeaturing\b'), '|')
      .replaceAll(RegExp(r'\bft\b'), '|')
      .replaceAll(RegExp(r'\band\b'), '|')
      .replaceAll(RegExp(r'[,&;]'), '|')
      .replaceAll(RegExp(r'\bx\b'), '|')
      .split('|')
      .map(_norm)
      .where((s) => s.isNotEmpty)
      .toList();

  static bool _artistsMatch(String expected, String found) {
    final a = _norm(expected);
    final b = _norm(found);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    for (final ap in _splitArtists(expected)) {
      for (final bp in _splitArtists(found)) {
        if (ap == bp || ap.contains(bp) || bp.contains(ap)) return true;
      }
    }
    return false;
  }

  static bool _durationOk(int expectedMs, num? foundSeconds) {
    if (expectedMs <= 0) return true;
    final foundMs = ((foundSeconds ?? 0) * 1000).round();
    if (foundMs <= 0) return true;
    return (foundMs - expectedMs).abs() <= 10000;
  }

  Map<String, dynamic>? _bestMatch(List<dynamic> items, Song song) {
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final entry in items) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final title = '${item['title'] ?? ''}';
      final version = '${item['version'] ?? ''}';
      final display =
      version.isEmpty || title.toLowerCase().contains(version.toLowerCase())
          ? title
          : '$title ($version)';
      final artist = '${(item['performer'] as Map?)?['name'] ?? ''}';

      if (!_titlesMatch(song.title, display)) continue;
      if (!_artistsMatch(song.artist, artist)) continue;
      if (!_durationOk(song.duration.inMilliseconds,
          item['duration'] as num?)) {
        continue;
      }

      var score = 0;
      if (_norm(song.title) == _norm(display)) score += 100;
      if (_norm(song.artist) == _norm(artist)) score += 40;
      score += (item['maximum_bit_depth'] as num? ?? 0).toInt();
      score += ((item['maximum_sampling_rate'] as num? ?? 0) * 10).toInt();
      if (score > bestScore) {
        bestScore = score;
        best = item;
      }
    }
    return best;
  }

  // ── stream resolution (getFileUrl, signed + token) ──

  Future<({String url, bool sample, int? kbps})?> _getFileUrl(
      String trackId, String formatId, String token) async {
    final url = _signedUrl('track', 'getFileUrl', {
      'track_id': trackId,
      'format_id': formatId,
      'intent': 'stream',
    });
    final data = await _getJson(url, {
      'X-App-Id': _streamAppId,
      'X-User-Auth-Token': token,
      'Accept': 'application/json',
    });
    if (data == null) return null;
    final streamUrl = '${data['url'] ?? ''}';
    if (streamUrl.isEmpty) return null;
    final sample = data['sample'] == true;

    int? kbps;
    final format = data['format'];
    if (format is Map) {
      final depth = (format['bit_depth'] as num?)?.toInt() ?? 0;
      final rate = (format['sampling_rate'] as num?)?.toDouble() ?? 0;
      if (depth > 0 && rate > 0) {
        kbps = (depth * rate * 1000 * 2 / 1000).round(); // stereo estimate
      }
    }
    return (url: streamUrl, sample: sample, kbps: kbps);
  }

  /// Lossless attempt for a default-chain song. Returns null when the
  /// service is off, no confident match exists, or no full-quality
  /// stream is available — the caller then falls through its chain.
  Future<({String url, Map<String, String> headers, int? kbps})?>
  tryLossless(Song song) async {
    final token = await _token();
    if (token == null) return null;

    final neg = _negativeCache[song.id];
    if (neg != null && DateTime.now().difference(neg) < _negativeTtl) {
      return null;
    }

    try {
      final artist = song.artist.split(',').first.trim();
      final items = await _searchTracks('${song.title} $artist'.trim());
      if (items.isEmpty) {
        _negativeCache[song.id] = DateTime.now();
        return null;
      }
      final match = _bestMatch(items, song);
      if (match == null) {
        _negativeCache[song.id] = DateTime.now();
        return null;
      }
      final trackId = '${match['id']}';
      for (final formatId in _formatLadder) {
        final stream = await _getFileUrl(trackId, formatId, token);
        if (stream == null || stream.sample) continue;
        return (url: stream.url, headers: const <String, String>{}, kbps: stream.kbps);
      }
      _negativeCache[song.id] = DateTime.now();
      return null;
    } catch (_) {
      return null;
    }
  }
}