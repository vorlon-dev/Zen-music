import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Proof of Origin (poToken) solver & manager for YouTube / InnerTube.
///
/// Implements the LibreTube/ZenMusic BotGuard JS protocol (`po_token.html` mechanics)
/// to mint valid session poTokens and prevent YouTube stream 403 Forbidden errors.
class PoTokenService {
  PoTokenService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? _poToken;
  String? _visitorData;
  DateTime? _tokenExpiry;

  String? get currentPoToken => _poToken;
  String? get currentVisitorData => _visitorData;

  /// Embedded BotGuard JavaScript template from po_token.html
  static const String botguardTemplate = r'''
    function loadBotGuard(challengeData) {
      this.vm = this[challengeData.globalName];
      this.program = challengeData.program;
      this.vmFunctions = {};
      this.syncSnapshotFunction = null;

      if (!this.vm)
        throw new Error('[BotGuardClient]: VM not found in the global object');

      if (!this.vm.a)
        throw new Error('[BotGuardClient]: Could not load program');

      const vmFunctionsCallback = function (
        asyncSnapshotFunction,
        shutdownFunction,
        passEventFunction,
        checkCameraFunction
      ) {
        this.vmFunctions = {
          asyncSnapshotFunction: asyncSnapshotFunction,
          shutdownFunction: shutdownFunction,
          passEventFunction: passEventFunction,
          checkCameraFunction: checkCameraFunction
        };
      };

      this.syncSnapshotFunction = this.vm.a(this.program, vmFunctionsCallback, true, this.userInteractionElement, function () {}, [ [], [] ])[0];

      return new Promise(function (resolve, reject) {
        let i = 0;
        let refreshIntervalId = setInterval(function () {
          if (!!this.vmFunctions.asyncSnapshotFunction) {
            resolve(this);
            clearInterval(refreshIntervalId);
          }
          if (i >= 10000) {
            reject("asyncSnapshotFunction is null even after 10 seconds");
            clearInterval(refreshIntervalId);
          }
          i += 1;
        }, 1);
      });
    }

    function obtainPoToken(webPoSignalOutput, integrityToken, identifier) {
      const getMinter = webPoSignalOutput[0];
      if (!getMinter) throw new Error('PMD:Undefined');
      const mintCallback = getMinter(integrityToken);
      if (!(mintCallback instanceof Function)) throw new Error('APF:Failed');
      const result = mintCallback(identifier);
      if (!result) throw new Error('YNJ:Undefined');
      return result;
    }
  ''';

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

      // 1. First try the ZenMusic cloud worker poToken minter
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
