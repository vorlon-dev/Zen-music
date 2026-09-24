import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Client for the zarz signed-session API (ZARZ-HMAC-V1), ported from
/// SpotiFLAC Mobile's signed_session crates. The protocol is fully
/// server-driven: bootstrap issues {session_id, session_secret,
/// expires_at} (or a verification challenge), and requests are signed
/// with a rolling HMAC derived from the server-issued secret. No keys
/// are embedded in this client.
class ZarzService {
  static const _base = 'https://api.zarz.moe/v2';
  static const _appVersion = 'deezer@1.3.5';
  static const _platform = 'extension';
  static const _scheme = 'ZARZ-HMAC-V1';
  static const _timeWindow = 300;

  static const _timeout = Duration(seconds: 15);

  final http.Client _client = http.Client();
  ZarzSession? _session;
  bool _verificationRequired = false;

  void dispose() => _client.close();

  /// Stored-session snapshot for Settings display (no network).
  static Future<String> storedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('zarz_session');
      if (raw == null) return 'Not started — activates on first play';
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final expires = DateTime.tryParse('${map['expires_at'] ?? ''}');
      if (expires == null) return 'Not started — activates on first play';
      return DateTime.now().isBefore(expires)
          ? 'Session active — FLAC ready'
          : 'Session expired — renews on next play';
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('zarz_install_id');
    if (id == null || id.isEmpty) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
          .join();
      await prefs.setString('zarz_install_id', id);
    }
    return id;
  }

  Future<ZarzSession?> _loadSession() async {
    if (_session != null) return _session;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('zarz_session');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final session = ZarzSession(
        sessionId: '${map['session_id'] ?? ''}',
        sessionSecret: '${map['session_secret'] ?? ''}',
        expiresAt: '${map['expires_at'] ?? ''}',
      );
      if (session.usable) _session = session;
      return _session;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSession(ZarzSession session) async {
    _session = session;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('zarz_session', jsonEncode({
        'session_id': session.sessionId,
        'session_secret': session.sessionSecret,
        'expires_at': session.expiresAt,
      }));
    } catch (_) {}
  }

  bool get verificationRequired => _verificationRequired;

  Future<ZarzSession?> _bootstrap() async {
    final installId = await _installId();
    final url =
        '$_base/bootstrap?app_version=${Uri.encodeComponent(_appVersion)}&install_id=${Uri.encodeComponent(installId)}';
    final resp = await _client
        .get(Uri.parse(url), headers: {'Accept': 'application/json'})
        .timeout(_timeout);
    print('🌐 zarz bootstrap: HTTP ${resp.statusCode}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _verificationRequired = false;
      throw Exception('zarz bootstrap HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    // Field names are read case-insensitively, mirroring the Rust decoder.
    String field(String name) {
      for (final entry in body.entries) {
        if (entry.key.toLowerCase() == name) {
          return entry.value?.toString() ?? '';
        }
      }
      return '';
    }

    final sessionId = field('session_id');
    final sessionSecret = field('session_secret');
    final expiresAt = field('expires_at');
    if (sessionId.isNotEmpty && sessionSecret.isNotEmpty && expiresAt.isNotEmpty) {
      _verificationRequired = false;
      final session = ZarzSession(
        sessionId: sessionId,
        sessionSecret: sessionSecret,
        expiresAt: expiresAt,
      );
      await _saveSession(session);
      print('🌐 zarz bootstrap: session issued (expires $expiresAt)');
      return session;
    }
    // Challenge flow requires the spotiflac:// deeplink callback — not
    // interceptable from ZenMusic. Reported, not silently retried.
    final authUrl = field('auth_url').isNotEmpty
        ? field('auth_url')
        : field('challenge_url');
    _verificationRequired = true;
    print('🌐 zarz bootstrap: VERIFY_REQUIRED'
        '${authUrl.isEmpty ? '' : ' — ${Uri.tryParse(authUrl)?.host ?? authUrl}'}');
    throw Exception(
        authUrl.isEmpty ? 'zarz bootstrap returned no session' : 'VERIFY_REQUIRED');
  }

  Future<ZarzSession?> ensureSession() async {
    final existing = await _loadSession();
    if (existing != null && existing.usable) {
      // Refresh when inside the last hour, best-effort.
      if (existing.expiresSoon) {
        try {
          await _refresh(existing);
        } catch (_) {}
      }
      return _session;
    }
    return _bootstrap();
  }

  Future<void> _refresh(ZarzSession session) async {
    final installId = await _installId();
    final body = jsonEncode({'install_id': installId});
    final resp = await _signedRequest(
        session, 'POST', '/session/refresh', body, const {});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final map = jsonDecode(resp.body) as Map<String, dynamic>;
      String field(String name) {
        for (final entry in map.entries) {
          if (entry.key.toLowerCase() == name) {
            return entry.value?.toString() ?? '';
          }
        }
        return '';
      }

      final refreshed = ZarzSession(
        sessionId: field('session_id').isNotEmpty ? field('session_id') : session.sessionId,
        sessionSecret: field('session_secret').isNotEmpty
            ? field('session_secret')
            : session.sessionSecret,
        expiresAt: field('expires_at').isNotEmpty ? field('expires_at') : session.expiresAt,
      );
      if (refreshed.usable) {
        await _saveSession(refreshed);
        print('🌐 zarz refresh: session renewed');
      }
    } else {
      print('🌐 zarz refresh: HTTP ${resp.statusCode}');
    }
  }

  // ── signing (verified against protocol.rs signed_headers) ──

  Map<String, String> _signedHeaders(
      ZarzSession session, String method, String url, String body) {
    final now = DateTime.now().toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-${two(now.day)}'
        'T${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
        '.${now.millisecond.toString().padLeft(3, '0')}Z';
    final hash = crypto.sha256.convert(utf8.encode(body)).toString();
    final window = now.millisecondsSinceEpoch ~/ 1000 ~/ _timeWindow;
    final rolling = _b64url(crypto.Hmac(crypto.sha256, utf8.encode(session.sessionSecret))
        .convert(utf8.encode('$window:${session.sessionId}'))
        .bytes);
    final nonce = _randomHex(12);
    final path = Uri.parse(url).path;
    final signing = [
      _scheme,
      method.toUpperCase(),
      path,
      '',
      hash,
      timestamp,
      nonce,
      session.sessionId,
      _appVersion,
      _platform,
    ].join('\n');
    final signature = _b64url(crypto.Hmac(crypto.sha256, utf8.encode(rolling))
        .convert(utf8.encode(signing))
        .bytes);
    return {
      'X-Zarz-Session': session.sessionId,
      'X-Zarz-Timestamp': timestamp,
      'X-Zarz-Nonce': nonce,
      'X-Zarz-Body-SHA256': hash,
      'X-Zarz-Signature': signature,
      'X-Zarz-App-Version': _appVersion,
      'X-Zarz-Platform': _platform,
      'Accept': 'application/json',
    };
  }

  Future<http.Response> _signedRequest(ZarzSession session, String method,
      String path, String body, Map<String, String> extraHeaders) async {
    final url = '$_base$path';
    final headers = _signedHeaders(session, method, url, body);
    headers.addAll(extraHeaders);
    final uri = Uri.parse(url);
    final resp = switch (method.toUpperCase()) {
      'POST' => await _client
          .post(uri, headers: headers, body: utf8.encode(body))
          .timeout(_timeout),
      _ => await _client.get(uri, headers: headers).timeout(_timeout),
    };
    return resp;
  }

  /// Signed GET/POST with a one-shot re-bootstrap on session invalidation.
  Future<http.Response?> signedCall(
      String method, String path, String body,
      {Map<String, String> extraHeaders = const {}}) async {
    var session = await ensureSession();
    if (session == null) return null;
    var resp =
    await _signedRequest(session, method, path, body, extraHeaders);
    if (resp.statusCode == 401) {
      // Session may have been invalidated server-side — one re-bootstrap.
      print('🌐 zarz $path: 401 — re-bootstrapping session');
      _session = null;
      session = await _bootstrap();
      if (session == null) return null;
      resp = await _signedRequest(session, method, path, body, extraHeaders);
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      print('🌐 zarz $path: HTTP ${resp.statusCode}');
      return null;
    }
    return resp;
  }

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static String _randomHex(int byteCount) {
    final rnd = Random.secure();
    return List.generate(byteCount, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class ZarzSession {
  ZarzSession({
    required this.sessionId,
    required this.sessionSecret,
    required this.expiresAt,
  });

  final String sessionId;
  final String sessionSecret;
  final String expiresAt;

  DateTime? get _expires => DateTime.tryParse(expiresAt);

  bool get usable =>
      sessionId.trim().isNotEmpty &&
          sessionSecret.trim().isNotEmpty &&
          (_expires == null || DateTime.now().isBefore(_expires!));

  bool get expiresSoon {
    final e = _expires;
    if (e == null) return false;
    return e.difference(DateTime.now()) <= const Duration(hours: 1);
  }
}