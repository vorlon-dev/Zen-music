// ZenMusic — spotify auth: sp_dc session cookie -> TOTP -> Bearer access
// token, plus client-token minting. Ported from Stopify's
// SpotifyAuthService/TokenManager (MIT). ZenMusic remains GPL-3.0.
// DEVIATION: Stopify's expired hardcoded FALLBACK_BEARER_TOKEN is dropped —
// failures surface as errors instead of falling back to a dead credential.
//
// FIXES / ADDITIONS (getAccessToken() == null with no explanation):
//  * lastError: every failure now records WHY (printed as "spotify-auth: ...")
//    and is readable via SpotifyAuth.instance.lastError.
//  * getAccessToken() no longer needs load() to have run: a stored
//    token-only session is restored lazily.
//  * TOTP secret is cached in Hive; if the GitHub gist fetch fails (rate
//    limit, offline) the cached secret is used instead of failing.
//  * Token endpoint errors include a short response body.
//  * Removed the circular self-import.

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyAuth {
  SpotifyAuth._();
  static final SpotifyAuth instance = SpotifyAuth._();

  static const _boxName = 'SETTINGS';
  static const _kCookies = 'SPOTIFY_COOKIES';
  static const _kClientToken = 'SPOTIFY_CLIENT_TOKEN';
  static const _kTokenCache = 'SPOTIFY_TOKEN_CACHE';
  static const _kTokenOnly = 'SPOTIFY_TOKEN_ONLY';
  static const _kTotpSecret = 'SPOTIFY_TOTP_SECRET';
  static const _kTotpVer = 'SPOTIFY_TOTP_VER';

  final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(false);

  Box get _box => Hive.box(_boxName);

  String? _accessToken;
  int _tokenExpiryMs = 0;
  String? _clientToken;
  // Token-only session (embedded login): no sp_dc, but a live Bearer token.
  bool _tokenOnly = false;

  /// Why the last auth step failed (null after a success).
  String? lastError;

  String? get cookieHeader => _box.get(_kCookies);
  bool get hasSession => SpotifyConfig.hasValidSpDc(cookieHeader);

  void _log(String m) => debugPrint('spotify-auth: $m');

  String? _fail(String message) {
    lastError = message;
    _log('FAILED: $message');
    return message;
  }

  String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  /// Current Bearer token (token-only or minted sessions), null when stale.
  String? get currentAccessToken {
    if (_accessToken != null &&
        DateTime.now().millisecondsSinceEpoch < _tokenExpiryMs) {
      return _accessToken;
    }
    return null;
  }

  /// Login: parse the pasted cookie blob, persist it, then mint a token.
  /// Returns an error string on failure, null on success.
  Future<String?> login(String cookieInput) async {
    final parsed = SpotifyConfig.parseCookieInput(cookieInput);
    if (!SpotifyConfig.hasValidSpDc(parsed)) {
      return _fail('No valid sp_dc found in the pasted text.');
    }
    _log('login: sp_dc stored, minting token');
    await _box.put(_kCookies, parsed);
    _accessToken = null;
    _tokenExpiryMs = 0;
    final err = await _mintAccessToken();
    if (err != null) return err;
    loggedIn.value = hasSession && _accessToken != null;
    return null;
  }

  void logout() {
    _box.delete(_kCookies);
    _box.delete(_kClientToken);
    _box.delete(_kTokenCache);
    _box.delete(_kTokenOnly);
    _accessToken = null;
    _clientToken = null;
    _tokenExpiryMs = 0;
    _tokenOnly = false;
    lastError = null;
    loggedIn.value = false;
  }

  /// Called by the embedded login when a Bearer token is intercepted live.
  /// Token-only session: no sp_dc, but ~1h of playable tokens. Re-login via
  /// the embedded window when it expires (v1; silent refresh is a later arc).
  Future<void> ingestAccessToken(String token) async {
    if (!token.startsWith('BQ')) return;
    _accessToken = token;
    _tokenExpiryMs = DateTime.now().millisecondsSinceEpoch + 3500000;
    _tokenOnly = true;
    lastError = null;
    await _box.put(_kTokenCache, token);
    await _box.put(_kTokenOnly, true);
    loggedIn.value = true;
  }

  /// Restores a stored token-only session into memory (valid ~1h).
  bool _restoreTokenOnly() {
    final cached = _box.get(_kTokenCache);
    final tokenOnly = _box.get(_kTokenOnly) == true;
    if (tokenOnly && cached is String && cached.startsWith('BQ')) {
      _accessToken = cached;
      _tokenOnly = true;
      _tokenExpiryMs = DateTime.now().millisecondsSinceEpoch + 3500000;
      return true;
    }
    return false;
  }

  Future<void> load() async {
    if (hasSession) {
      final err = await _mintAccessToken();
      loggedIn.value = err == null;
      return;
    }
    loggedIn.value = _restoreTokenOnly();
  }

  /// Valid access token for API calls, or null (callers gate on this).
  /// When null, [lastError] says why.
  Future<String?> getAccessToken({bool force = false}) async {
    if (!hasSession && !_tokenOnly && !_restoreTokenOnly()) {
      _fail('not logged in: no sp_dc stored (open the Spotify login first)');
      return null;
    }
    if (!force &&
        _accessToken != null &&
        DateTime.now().millisecondsSinceEpoch < _tokenExpiryMs) {
      return _accessToken;
    }
    final err = await _mintAccessToken();
    return err == null ? _accessToken : null;
  }

  Future<String> getClientToken() async {
    if (_clientToken != null) return _clientToken!;
    final stored = _box.get(_kClientToken);
    if (stored is String && stored.isNotEmpty) {
      _clientToken = stored;
      return stored;
    }
    try {
      final resp = await http
          .post(Uri.parse(SpotifyConfig.clientTokenUrl),
          headers: {
            'accept': 'application/json',
            'content-type': 'application/json',
            'User-Agent': SpotifyConfig.userAgent,
            'origin': 'https://open.spotify.com',
            'referer': 'https://open.spotify.com/',
          },
          body: jsonEncode({
            'client_data': {
              'client_version': SpotifyConfig.spotifyAppVersion,
              'client_id': SpotifyConfig.clientId,
              'js_sdk_data': {
                'device_brand': 'Apple',
                'device_model': 'unknown',
                'os': 'macos',
                'os_version': '10.15.7',
                'device_id': SpotifyConfig.defaultDeviceId,
                'device_type': 'computer',
              },
            },
          }))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final granted =
        (jsonDecode(resp.body) as Map)['granted_token'] as Map?;
        final token = granted?['token']?.toString();
        if (token != null && token.isNotEmpty) {
          _clientToken = token;
          await _box.put(_kClientToken, token);
          return token;
        }
      } else {
        _log('client-token HTTP ${resp.statusCode}: ${_short(resp.body)} '
            '(using the captured constant)');
      }
    } catch (e) {
      _log('client-token error: $e (using the captured constant)');
    }
    _clientToken = SpotifyConfig.clientToken;
    return _clientToken!;
  }

  /// TOTP secret + version: gist first, Hive cache as fallback.
  Future<(String, int)?> _totpSecret() async {
    String? secret;
    int? ver;
    try {
      final resp = await http.get(
        Uri.parse(SpotifyConfig.totpGistUrl),
        headers: {'User-Agent': SpotifyConfig.userAgent},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final gist = jsonDecode(resp.body) as Map;
        final files = gist['files'] as Map?;
        if (files != null && files.isNotEmpty) {
          final content = (files.values.first as Map)['content'] as String;
          final arr = jsonDecode(content) as List;
          for (final n in arr) {
            final v = ((n as Map)['v'] as num?)?.toInt() ?? 0;
            if (ver == null || v >= ver) {
              ver = v;
              secret = n['s']?.toString();
            }
          }
        }
        if (secret != null && ver != null) {
          await _box.put(_kTotpSecret, secret);
          await _box.put(_kTotpVer, ver);
          _log('TOTP secret from gist (v$ver)');
          return (secret, ver);
        }
        _log('gist parsed but contained no secret');
      } else {
        _log('gist HTTP ${resp.statusCode}: ${_short(resp.body)}');
      }
    } catch (e) {
      _log('gist fetch error: $e');
    }

    final cs = _box.get(_kTotpSecret);
    final cv = _box.get(_kTotpVer);
    if (cs is String && cs.isNotEmpty && cv is int) {
      _log('using cached TOTP secret (v$cv)');
      return (cs, cv);
    }
    return null;
  }

  /// TOTP -> token endpoint. Returns an error string, or null on success
  /// (token stored in _accessToken).
  Future<String?> _mintAccessToken() async {
    final spDc = SpotifyConfig.extractSpDc(cookieHeader) ?? '';
    if (spDc.isEmpty) return _fail('No sp_dc session cookie.');

    // 1. TOTP secret.
    final sec = await _totpSecret();
    if (sec == null) {
      return _fail('TOTP secret unavailable (gist fetch failed, no cache).');
    }
    final (secret, ver) = sec;

    // 2. Server time (fallback: local clock).
    int serverSec;
    try {
      final resp = await http.get(
        Uri.parse(SpotifyConfig.serverTimeUrl),
        headers: {'User-Agent': SpotifyConfig.userAgent},
      ).timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        serverSec =
            ((jsonDecode(resp.body) as Map)['serverTime'] as num).toInt();
      } else {
        _log('server-time HTTP ${resp.statusCode}, using local clock');
        serverSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      }
    } catch (e) {
      _log('server-time error: $e, using local clock');
      serverSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }

    // 3. Token endpoint.
    final totp = _totp6(secret, serverSec);
    final spKey = _cookieValue('sp_key');
    final cookie = spKey.isEmpty ? 'sp_dc=$spDc' : 'sp_dc=$spDc; sp_key=$spKey';
    final url = Uri.parse(
        '${SpotifyConfig.tokenUrlBase}&totp=$totp&totpServer=$totp&totpVer=$ver');

    try {
      final resp = await http.get(url, headers: {
        'User-Agent': SpotifyConfig.userAgent,
        'Cookie': cookie,
      }).timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return _fail(
            'Token endpoint HTTP ${resp.statusCode}: ${_short(resp.body)}');
      }
      final body = jsonDecode(resp.body) as Map;
      final token = body['accessToken']?.toString() ?? '';
      final anonymous = body['isAnonymous'] == true;
      if (token.isEmpty || anonymous) {
        return _fail('Session rejected (anonymous). Check that sp_dc is '
            'fresh, and that the TOTP secret/version is current.');
      }
      _accessToken = token;
      _tokenExpiryMs =
          (body['accessTokenExpirationTimestampMs'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch + 3600000;
      lastError = null;
      _log('access token minted');
      return null;
    } catch (e) {
      return _fail('Token fetch failed: $e');
    }
  }

  String _cookieValue(String name) {
    final cookies = cookieHeader ?? '';
    for (final part in cookies.split(';')) {
      final p = part.trim();
      if (p.startsWith('$name=')) return p.substring(name.length + 1).trim();
    }
    return '';
  }

  /// 6-digit TOTP from the base32 secret + server time (Stopify's
  /// generateTotpString, ported).
  String _totp6(String secret, int serverTimeSec) {
    final key = _base32Decode(secret);
    final timeStep = serverTimeSec ~/ 30;
    final timeBytes = ByteData(8)..setUint64(0, timeStep);
    final hmac = Hmac(sha1, key);
    final hash = hmac.convert(timeBytes.buffer.asUint8List()).bytes;
    final offset = hash[hash.length - 1] & 0x0F;
    final code = ((hash[offset] & 0x7F) << 24) |
    ((hash[offset + 1] & 0xFF) << 16) |
    ((hash[offset + 2] & 0xFF) << 8) |
    (hash[offset + 3] & 0xFF);
    final otp = code % 1000000;
    return otp.toString().padLeft(6, '0');
  }

  Uint8List _base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = input.toUpperCase().replaceAll('=', '');
    final out = BytesBuilder();
    var buffer = 0;
    var bitsLeft = 0;
    for (final c in cleaned.runes) {
      final value = alphabet.indexOf(String.fromCharCode(c));
      if (value < 0) continue;
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.addByte((buffer >> bitsLeft) & 0xFF);
      }
    }
    return out.takeBytes();
  }
}