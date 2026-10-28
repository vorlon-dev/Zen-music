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
//
// SP-72 (the fresh-login 401 loop — field log 2026-10, Android: sp_dc
// captured fine, Bearer minting fine and NOT anonymous, yet EVERY
// pathfinder call answered "Missing/invalid/expired access token" while
// the Web API 429'd, and the re-mint loop could never escape):
//  * ROOT CAUSE: one transient client-token mint failure ("Connection
//    closed before full header was received") used to assign the
//    captured constant to the in-memory cache FOREVER. The partner API
//    rejects an unbound client-token with exactly the 401 body above, so
//    every pathfinder call died regardless of how fresh the Bearer was.
//  * getClientToken() now returns the captured constant WITHOUT caching
//    it when the network mint fails, under a 20 s failure backoff — the
//    next call retries the real mint instead of serving the poisoned
//    downgrade for the whole process lifetime.
//  * invalidateClientToken() + notePathfinderAuthRejected(): the 401
//    recovery path can drop the client-token alongside the Bearer, and
//    repeated rejections within a minute also purge the STORED
//    client-token so a fully fresh credential is minted.
//
// SP-70 (the zombie token-only session — field log 2026-10: every authed
// call HTTP 401 while the app believed it was logged in):
//  * Token-only restores now honor the REAL persisted expiration instead
//    of re-arming the cached token for another ~58 minutes on every boot.
//    A dead cache is purged on sight (legacy caches without a stored
//    expiry count as dead; the next sign-in writes one).
//  * invalidateAccessToken(): a caller that saw HTTP 401 drops the token
//    so the next getAccessToken() mints instead of serving the dead one.
//  * Mints are single-flight: a page load firing a dozen authed calls at
//    a dead token shares one re-mint instead of stampeding the endpoint.
//  * getAccessToken(force:) no longer self-destructs a token-only session:
//    a forced re-mint can never succeed without sp_dc, so if the held
//    token is still unexpired it keeps serving; when nothing is usable
//    the token-only session is purged and loggedIn flips false — the home
//    section then swaps to its logged-out state (public shelves + connect
//    banner) instead of 401-ing into empty shelves.

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
  // SP-70: the token-only session's REAL expiration timestamp (ms epoch).
  // Without a stored clock a restore could not tell a live token from a
  // dead one — the zombie behind the field report.
  static const _kTokenExpiry = 'SPOTIFY_TOKEN_EXPIRY';
  static const _kTotpSecret = 'SPOTIFY_TOTP_SECRET';
  static const _kTotpVer = 'SPOTIFY_TOTP_VER';

  final ValueNotifier<bool> loggedIn = ValueNotifier<bool>(false);

  Box get _box => Hive.box(_boxName);

  String? _accessToken;
  int _tokenExpiryMs = 0;
  String? _clientToken;
  // SP-72: last client-token mint failure (epoch ms) — a bounded backoff
  // so an unreachable clienttoken endpoint is not hammered on every
  // call, while the captured-constant fallback stays OUT of the cache.
  int _clientTokenFailAtMs = 0;
  // SP-72: last pathfinder auth rejection (epoch ms) — two 401s inside a
  // minute mark the STORED client-token dead too (see
  // [notePathfinderAuthRejected]).
  int _pfRejectAtMs = 0;
  // Token-only session (embedded login): no sp_dc, but a live Bearer token.
  bool _tokenOnly = false;

  /// Why the last auth step failed (null after a success).
  String? lastError;

  String? get cookieHeader => _box.get(_kCookies);
  bool get hasSession => SpotifyConfig.hasValidSpDc(cookieHeader);

  /// SP-72: the in-memory client token (null right after an
  /// invalidation) — lets 401-recovery paths detect that the
  /// client-token moved and is worth one retry even when the Bearer was
  /// re-served unchanged.
  String? get currentClientToken => _clientToken;

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
    _box.delete(_kTokenExpiry);
    _accessToken = null;
    _clientToken = null;
    _tokenExpiryMs = 0;
    _tokenOnly = false;
    lastError = null;
    loggedIn.value = false;
  }

  /// Called by the embedded login when a Bearer token is intercepted live.
  /// Token-only session: no sp_dc, but ~1h of playable tokens. Re-login via
  /// the embedded window when it expires — with SP-70 the stored expiry is
  /// persisted, so later boots either restore it HONESTLY or forget it.
  Future<void> ingestAccessToken(String token) async {
    if (!token.startsWith('BQ')) return;
    final expiresAt = DateTime.now().millisecondsSinceEpoch + 3500000;
    _accessToken = token;
    _tokenExpiryMs = expiresAt;
    _tokenOnly = true;
    lastError = null;
    await _box.put(_kTokenCache, token);
    await _box.put(_kTokenExpiry, expiresAt);
    await _box.put(_kTokenOnly, true);
    loggedIn.value = true;
  }

  /// SP-70: a token-only session is only ever as good as its one token —
  /// with no sp_dc there is nothing to re-mint from. When that token is
  /// dead the session must be FORGOTTEN, not restored: flipping [loggedIn]
  /// here is what lets the home section swap to its logged-out state
  /// (public shelves + connect banner) instead of 401-ing into empty
  /// shelves for the rest of the run.
  Future<void> _purgeTokenOnly() async {
    await _box.delete(_kTokenCache);
    await _box.delete(_kTokenOnly);
    await _box.delete(_kTokenExpiry);
    _tokenOnly = false;
    _accessToken = null;
    _tokenExpiryMs = 0;
    loggedIn.value = hasSession;
  }

  /// Restores a stored token-only session — but HONESTLY (SP-70): the
  /// persisted expiry must still be in the future. The old restore re-armed
  /// the cached token for another ~58 minutes on every boot, so a token
  /// dead for days looked valid in memory while every server call answered
  /// HTTP 401. A legacy cache with no stored expiry counts as dead; the
  /// next sign-in writes one.
  bool _restoreTokenOnly() {
    final cached = _box.get(_kTokenCache);
    final tokenOnly = _box.get(_kTokenOnly) == true;
    final expiry = _box.get(_kTokenExpiry);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final usable = tokenOnly &&
        cached is String &&
        cached.startsWith('BQ') &&
        expiry is int &&
        nowMs < expiry;
    if (!usable) {
      if (tokenOnly) {
        // Dead (or legacy expiry-less) cache — forget it. Fire-and-forget
        // deletes: worst case a killed app re-checks once more at boot.
        _box.delete(_kTokenCache);
        _box.delete(_kTokenOnly);
        _box.delete(_kTokenExpiry);
      }
      return false;
    }
    _accessToken = cached;
    _tokenOnly = true;
    _tokenExpiryMs = expiry; // the REAL clock, never a fresh lease
    return true;
  }

  Future<void> load() async {
    if (hasSession) {
      final err = await _mintAccessToken();
      loggedIn.value = err == null;
      return;
    }
    loggedIn.value = _restoreTokenOnly();
  }

  /// SP-70: caller saw HTTP 401 with the token it got from
  /// [getAccessToken] — the credential is dead server-side even if our
  /// local expiry clock still trusts it. Drop it so the next
  /// [getAccessToken] mints (or, with nothing to mint from, fails honestly
  /// and the token-only session is purged).
  void invalidateAccessToken() {
    _accessToken = null;
    _tokenExpiryMs = 0;
  }

  /// SP-72: the client-token participates in pathfinder auth — when a 401
  /// recovery drops the Bearer it can drop this too, so the next
  /// [getClientToken] re-mints (or re-reads the Hive store) instead of
  /// serving a credential that just failed.
  void invalidateClientToken() {
    _clientToken = null;
    _clientTokenFailAtMs = 0;
  }

  /// SP-72: pathfinder answered 401. Clears the in-memory client-token
  /// (and the mint backoff, so the retry can re-mint immediately). Two
  /// rejections inside one minute mean the STORED client-token is dead
  /// as well — purge it so the next [getClientToken] mints a fully fresh
  /// credential. The partner API answers a bad client-token with the
  /// same body as a dead Bearer ("Missing/invalid/expired access
  /// token"), which is why the Bearer-only re-mint loop could never
  /// escape the fresh-login 401 flood in the field log.
  void notePathfinderAuthRejected() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_pfRejectAtMs > 0 &&
        nowMs - _pfRejectAtMs < 60000 &&
        _box.get(_kClientToken) != null) {
      _box.delete(_kClientToken);
      _log('client-token purged (repeated pathfinder 401) — full '
          're-mint next call');
    }
    _pfRejectAtMs = nowMs;
    invalidateClientToken();
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
    // SP-70: single-flight the mint — a page load fires a dozen authed
    // calls in parallel; when the token turns out dead they share one
    // re-mint instead of stampeding the TOTP/token endpoint.
    final inFlight = _mintInFlight;
    if (inFlight != null) {
      final err = await inFlight;
      if (err == null) return _accessToken;
      return _heldTokenOrPurge();
    }
    final mint = _mintAccessToken();
    _mintInFlight = mint;
    String? err;
    try {
      err = await mint;
    } finally {
      _mintInFlight = null;
    }
    if (err == null) return _accessToken;
    return _heldTokenOrPurge();
  }

  Future<String?>? _mintInFlight;

  /// SP-70: after a FAILED mint — serve an unexpired token we still hold
  /// (a forced re-mint on a token-only session can never succeed — mint
  /// needs sp_dc — and must not destroy a possibly-still-good token);
  /// otherwise a token-only session is unrecoverable: purge it so the UI
  /// flips to logged out with an honest lastError instead of zombie 401s.
  Future<String?> _heldTokenOrPurge() async {
    if (_accessToken != null &&
        DateTime.now().millisecondsSinceEpoch < _tokenExpiryMs) {
      return _accessToken;
    }
    if (!hasSession && _tokenOnly) {
      _fail('token-only session expired (re-mint needs sp_dc) — '
          'sign in again');
      await _purgeTokenOnly();
    }
    return null;
  }

  /// Client-token for pathfinder calls. SP-72: a failed network mint is
  /// NO LONGER cached — the old code assigned the captured constant to
  /// [_clientToken] and served it for the whole process lifetime, so one
  /// transient "Connection closed before full header was received" on a
  /// fresh install downgraded every pathfinder call permanently (the
  /// partner API 401s an unbound client-token with the same
  /// "Missing/invalid/expired access token" body as a dead Bearer).
  /// Now: memory cache -> Hive store -> network mint; on failure the
  /// constant is returned WITHOUT caching under a 20 s backoff, and the
  /// next call retries the real mint.
  Future<String> getClientToken() async {
    if (_clientToken != null) return _clientToken!;
    final stored = _box.get(_kClientToken);
    if (stored is String && stored.isNotEmpty) {
      _clientToken = stored;
      return stored;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_clientTokenFailAtMs > 0 && nowMs - _clientTokenFailAtMs < 20000) {
      return SpotifyConfig.clientToken;
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
          _clientTokenFailAtMs = 0;
          await _box.put(_kClientToken, token);
          return token;
        }
      } else {
        _clientTokenFailAtMs = nowMs;
        _log('client-token HTTP ${resp.statusCode} — captured constant '
            'returned but NOT cached (re-mint retries in 20 s)');
      }
    } catch (e) {
      _clientTokenFailAtMs = nowMs;
      _log('client-token error: $e (captured constant NOT cached — '
          'the next call re-mints)');
    }
    return SpotifyConfig.clientToken;
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