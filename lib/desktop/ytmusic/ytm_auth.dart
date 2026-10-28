// ZenMusic — YouTube Music account session (SP-65).
// Cookie-based auth via the SAPISIDHASH scheme, the mechanism ytmusicapi
// (sigma67, GPL-3.0) uses for browser-cookie login — the same project the
// lib/desktop/ytmusic/ module is ported from. ZenMusic remains GPL-3.0
// (https://github.com/vorlon-dev/Zen-music).
//
// WHY COOKIES AND NOT OAUTH ANYMORE (SP-65): SP-62 shipped Google's
// device-code OAuth flow (ytmusicapi 1.3.0 TV-client constants). Login
// "succeeded" (tokens were minted and stored), but Google has since removed
// OAuth support from the YouTube Music innerTube API server-side: every
// authed request returns HTTP 400 "Request contains an invalid argument"
// while anonymous requests keep working. This is a global break, not a
// header-merging bug — sigma67/ytmusicapi issues #676/#682 document the
// exact same response body across all third-party clients, and ytmusicapi
// 1.4.0 dropped OAuth for this reason. The token endpoint still issues
// refresh tokens, so the old flow LOOKED connected while nothing it did
// could ever reach the feed. The only working account mechanism is browser
// cookies: a signed-in music.youtube.com session provides the SAPISID
// cookie, and Authorization: SAPISIDHASH <ts>_<sha1(sapisid ts origin)> is
// derived per request (exactly what ytmusicapi does).
//
// LOGIN FLOW (SP-65): ytm_login_page.dart captures the cookie string of a
// signed-in session — a real WebView2 window on Windows (the embedded
// InAppWebView is stubbed there, SP-63), an embedded InAppWebView with the
// native CookieManager elsewhere. [probeCookies] validates a candidate
// blob against the authed home endpoint BEFORE it is stored, so "connected"
// now means "Google accepted this session", not merely "a token exists".
// The cookie paste (loginWithCookies) stays as the manual fallback.
//
// With the merged headers, YTClient.sendRequest (browse FEmusic_home and
// friends) returns the signed-in user's personalized feed — Quick picks,
// Listen again, Mixed for you — and a logout truly returns the public feed.

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

class YtmAuth {
  YtmAuth._();
  static final YtmAuth instance = YtmAuth._();

  /// InnerTube origin used for SAPISIDHASH and X-Origin.
  static const origin = 'https://music.youtube.com';

  // The public WEB_REMIX key — same one YTClient sends anonymously.
  static const String _apiKey = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

  static const _boxName = 'SETTINGS';
  static const _kCookies = 'YTM_COOKIES';

  // SP-62 OAuth leftovers. Google killed YTM OAuth server-side (HTTP 400
  // on every authed request), so these keys are dead weight; load() wipes
  // them once so "logged in" can only ever mean "a working cookie session".
  static const _kLegacyRefresh = 'YTM_REFRESH_TOKEN';
  static const _kLegacyAccess = 'YTM_ACCESS_TOKEN';
  static const _kLegacyExpiresAt = 'YTM_EXPIRES_AT';

  /// True while an account (cookie session) is connected.
  final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(false);

  /// Login-flow error for the login page (null = no error).
  final ValueNotifier<String?> loginError = ValueNotifier<String?>(null);

  String? lastError;
  bool _migrated = false;

  Box get _box => Hive.box(_boxName);

  void _log(String m) => debugPrint('ytm-auth: $m');

  String? get cookieBlob {
    final c = _box.get(_kCookies);
    return c is String && c.isNotEmpty ? c : null;
  }

  bool get hasCookieSession {
    final c = cookieBlob;
    if (c == null) return false;
    return _cookieValue(c, 'SAPISID').isNotEmpty ||
        _cookieValue(c, '__Secure-3PAPISID').isNotEmpty ||
        _cookieValue(c, '__Secure-1PAPISID').isNotEmpty;
  }

  bool get hasSession => hasCookieSession;

  /// Boot restore (sync). The stored session is only trusted lazily: the
  /// first authed request either works, or YTClient reports a definitive
  /// rejection through [sessionRejected] and the app falls back to the
  /// public feed instead of failing on every call.
  void load() {
    if (!_migrated) {
      _migrated = true;
      // SP-65 one-time migration: drop the dead OAuth session parts so the
      // stored state matches what the app can actually use.
      _box.delete(_kLegacyRefresh);
      _box.delete(_kLegacyAccess);
      _box.delete(_kLegacyExpiresAt);
    }
    loggedIn.value = hasSession;
    _log('load: ${loggedIn.value ? "session present" : "anonymous"}');
  }

  // ── Cookie session (webview capture + paste fallback) ────────────────

  /// Cookie capture from the sign-in window (SP-65). Same rules and
  /// validation as [loginWithCookies] — named for the call site.
  Future<String?> ingestCookies(String input) => loginWithCookies(input);

  /// Accepts a raw cookie header ("a=b; c=d") or Netscape cookies.txt
  /// content. The blob is PROBED against the authed home endpoint before it
  /// is stored, so a connected state means Google accepted it. Returns an
  /// error string, or null on success.
  Future<String?> loginWithCookies(String input) async {
    final parsed = _parseCookieBlob(input);
    if (parsed.isEmpty ||
        (parsed['SAPISID'] == null &&
            parsed['__Secure-3PAPISID'] == null &&
            parsed['__Secure-1PAPISID'] == null)) {
      return lastError =
          'No SAPISID cookie found — sign in inside the login window, or '
          'paste cookies from a signed-in music.youtube.com session.';
    }
    final blob =
        parsed.entries.map((e) => '${e.key}=${e.value}').join('; ');
    final probe = await probeCookies(blob);
    if (probe == _ProbeResult.rejected) {
      return lastError =
          'Google rejected this session — the cookies are stale or '
          'incomplete. Sign in again in the login window.';
    }
    await _box.put(_kCookies, blob);
    lastError = null;
    loginError.value = null;
    loggedIn.value = true;
    _log(probe == _ProbeResult.verified
        ? 'cookie session stored and verified (${parsed.length} cookies)'
        : 'cookie session stored (${parsed.length} cookies, network '
            'unavailable — saved without verification)');
    return null;
  }

  /// SP-65: probe a candidate cookie blob against the authed home endpoint
  /// (browse FEmusic_home with SAPISIDHASH headers) WITHOUT storing it.
  /// The login page waits for this to pass before declaring success.
  Future<_ProbeResult> probeCookies(String cookieString) async {
    final parsed = _parseCookieBlob(cookieString);
    final auth = _sapisidHashValue(parsed);
    if (auth == null) return _ProbeResult.rejected;
    try {
      final resp = await http
          .post(
            Uri.parse('$origin/youtubei/v1/browse?alt=json&key=$_apiKey'),
            headers: {
              'User-Agent': initializeHeaders()['User-Agent']!,
              'accept': '*/*',
              'content-type': 'application/json',
              'Origin': origin,
              'Accept-Language': 'en-IN',
              'cookie': cookieString,
              'Authorization': auth,
              'X-Origin': origin,
            },
            body: jsonEncode({
              'browseId': 'FEmusic_home',
              ...initializeContext(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      _log('probe: HTTP ${resp.statusCode} '
          '${resp.statusCode == 200 ? "(session ok)" : "(rejected)"}');
      return resp.statusCode == 200
          ? _ProbeResult.verified
          : _ProbeResult.rejected;
    } catch (e) {
      // Network trouble is not proof of a bad session — fail open.
      _log('probe network error (saving unverified): $e');
      return _ProbeResult.unverified;
    }
  }

  /// SAPISIDHASH Authorization value for a parsed cookie map, or null when
  /// no SAPISID-family cookie is present. hash = sha1("$sapisid $ts $origin")
  /// — ytmusicapi's browser-cookie scheme.
  String? _sapisidHashValue(Map<String, String> parsed) {
    var sapisid = parsed['SAPISID'] ??
        parsed['__Secure-3PAPISID'] ??
        parsed['__Secure-1PAPISID'];
    if (sapisid == null || sapisid.isEmpty) return null;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final hash =
        crypto.sha1.convert(utf8.encode('$sapisid $ts $origin')).toString();
    return 'SAPISIDHASH ${ts}_$hash';
  }

  /// Parses both formats; keeps the LAST occurrence of a name (Google
  /// sends identical values across domains).
  static Map<String, String> _parseCookieBlob(String input) {
    final out = <String, String>{};
    for (final rawLine in input.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#HttpOnly_')) {
        // Netscape files mark HttpOnly rows this way — still valid cookies.
        final fields = line.substring(10).split('\t');
        if (fields.length >= 7) {
          out[fields[5].trim()] = fields[6].trim();
        }
        continue;
      }
      if (line.startsWith('#') || line.toLowerCase() == '#netscape http cookie file') {
        continue;
      }
      if (line.contains('\t')) {
        final fields = line.split('\t');
        if (fields.length >= 7) {
          out[fields[5].trim()] = fields[6].trim();
        }
        continue;
      }
      // Header-style blob.
      for (final part in line.split(';')) {
        final p = part.trim();
        final i = p.indexOf('=');
        if (i <= 0) continue;
        out[p.substring(0, i).trim()] = p.substring(i + 1).trim();
      }
    }
    return out;
  }

  static String _cookieValue(String cookies, String name) {
    for (final part in cookies.split(';')) {
      final p = part.trim();
      if (p.startsWith('$name=')) return p.substring(name.length + 1).trim();
    }
    return '';
  }

  // ── Headers for YTClient ─────────────────────────────────────────────

  /// Authorization headers for InnerTube requests, or null when anonymous.
  /// The returned map overwrites the anonymous CONSENT cookie with the real
  /// session cookie string when merged by YTClient.sendRequest().
  Future<Map<String, String>?> authHeaders() async {
    final cookies = cookieBlob;
    if (cookies == null || !hasCookieSession) return null;
    final auth = _sapisidHashValue(_parseCookieBlob(cookies));
    if (auth == null) return null;
    return {
      'Authorization': auth,
      'X-Origin': origin,
      'cookie': cookies,
    };
  }

  /// SP-65: called by YTClient when an authed request is DEFINITIVELY
  /// rejected (HTTP 401). Drops the dead session so the home feed falls
  /// back to the public one instead of failing on every call. A 400/403 is
  /// request-specific and must NOT kill the session — YTClient only logs
  /// those.
  Future<void> sessionRejected(String reason) async {
    if (!hasSession) return;
    lastError = 'youtube music session rejected ($reason) — log in again';
    _log('session invalidated ($reason) — falling back to the public feed');
    logout();
  }

  void logout() {
    _box.delete(_kCookies);
    loggedIn.value = false;
    loginError.value = null;
    lastError = null;
    _log('logged out');
  }
}

enum _ProbeResult { verified, rejected, unverified }
