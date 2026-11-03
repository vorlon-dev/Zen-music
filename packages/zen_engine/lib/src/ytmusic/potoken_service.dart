import 'dart:convert';
import 'package:http/http.dart' as http;

/// Proof of Origin (poToken) solver & manager for YouTube / InnerTube.
///
/// Automatically handles visitorData and BotGuard/poToken generation,
/// allowing InnerTube/YouTube endpoints to stream without throttles or blocks.
class PoTokenService {
  PoTokenService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? _poToken;
  String? _visitorData;
  DateTime? _tokenExpiry;

  String? get currentPoToken => _poToken;
  String? get currentVisitorData => _visitorData;

  /// Check if the current poToken is valid and not expired
  bool get isTokenValid =>
      _poToken != null &&
      _tokenExpiry != null &&
      DateTime.now().isBefore(_tokenExpiry!);

  /// Manually set or update poToken credentials
  void setTokens({
    required String poToken,
    String? visitorData,
    Duration validDuration = const Duration(hours: 12),
  }) {
    _poToken = poToken;
    if (visitorData != null) _visitorData = visitorData;
    _tokenExpiry = DateTime.now().add(validDuration);
  }

  /// Solves or refreshes visitorData and mints poToken for InnerTube requests
  Future<String?> resolvePoToken({String? customVisitorData}) async {
    if (isTokenValid && customVisitorData == null) {
      return _poToken;
    }

    try {
      final vData = customVisitorData ?? _visitorData ?? await fetchVisitorData();
      _visitorData = vData;

      // Request token from remote or fallback endpoint if configured
      final uri = Uri.parse('https://jiosaavn-api.vorlon-revora.workers.dev/api/potoken')
          .replace(queryParameters: {
        if (vData != null) 'visitorData': vData,
      });

      final res = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['poToken'] != null) {
          _poToken = data['poToken'] as String;
          _tokenExpiry = DateTime.now().add(const Duration(hours: 6));
          return _poToken;
        }
      }
    } catch (_) {}

    return _poToken;
  }

  /// Fetches fresh YouTube visitorData identifier
  Future<String?> fetchVisitorData() async {
    try {
      final res = await _client.get(
        Uri.parse('https://www.youtube.com/sw.js_data'),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final match = RegExp(r'"visitorData"\s*:\s*"([^"]+)"').firstMatch(res.body);
        if (match != null) {
          _visitorData = match.group(1);
          return _visitorData;
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _client.close();
  }
}
