// ZenMusic — SpotifyDesktopEngine (SP-5b). True Spotify playback on Windows
// via a hidden WebView2 EME pipeline. Formalized from the SP-4 spike v2.5
// (all-bridge-via-evaluateJavaScript) which proved the full chain on
// WebView2 155.0.4283.45 + desktop_webview_window 0.3.2:
//   CDM ok -> same-origin /media proxy defeats CDN CORS -> MSE parses the
//   fragmented CENC file -> Widevine cert roundtrip (challenge 0804,
//   SignedMessage type=4 SERVICE_CERTIFICATE_REQUEST) -> real license
//   request -> keystatus usable -> PLAYING.
//
// SP-5b FIXES over SP-5a:
//   * Bridge lifetime is purely generation-based. The old _bridgeRunning
//     flag never reset, so a second play() in the same session silently
//     skipped the license loop. Removed entirely.
//   * State poll no longer round-trips JSON. Pipe-delimited scalars,
//     sanitized to [0-9 . - |], parse-safe against double-escaped values.
//   * Track end is surfaced via ValueNotifier<bool> ended.
//   * _pageHtml is served via utf8.encode.
//   * _abort() bumps _gen so the bridge loop exits on its next iteration.
//
// DEPENDS: windows/runner/main.cpp sets
// WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--disable-features=CalculateNativeWinOcclusion
// (hidden-page media suspension is otherwise fatal — SP-4 lesson).
// Stopify (MIT) is the protocol reference; ZenMusic remains GPL-3.0.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

class SpotifyDesktopEngine {
  SpotifyDesktopEngine._();
  static final SpotifyDesktopEngine instance = SpotifyDesktopEngine._();

  /// Set false to silence "[sp-engine] ..." diagnostics.
  static bool debugLogs = true;

  void _log(String m) {
    if (debugLogs) debugPrint('[sp-engine] $m');
  }

  // ── Public state (consumed by MediaPlayer SP-5b wiring) ──
  final ValueNotifier<Duration> position =
  ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration =
  ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> ended = ValueNotifier<bool>(false);

  /// True while the engine owns playback (a Spotify track is loaded).
  Map<String, dynamic>? activeSong;
  bool get isActive => activeSong != null;

  HttpServer? _server;
  String? _pageUrl;
  Webview? _webview;
  int _gen = 0; // bridge generation; the sole loop lifetime control

  // ── Embedded page ──
  static const String _pageHtml = r'''
<!DOCTYPE html>
<html><body><audio id="a"></audio><script>
window.__sp4 = { phase: 'boot', lines: [], challenge: null,
                licenseResponse: null,
                state: {pos: 0, dur: 0, playing: false, ended: false} };
function rep(o) { window.__sp4.lines.push(JSON.stringify(o)); }
const A = document.getElementById('a');
let mediaKeys = null, session = null, ms = null;

const cdmReady = (async () => {
  try {
    const cfg = [{ initDataTypes: ['cenc','keyids'],
      audioCapabilities: [{ contentType: 'audio/mp4; codecs="mp4a.40.2"' }] }];
    const acc = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', cfg);
    mediaKeys = await acc.createMediaKeys();
    await A.setMediaKeys(mediaKeys);
    rep({ type: 'cdm', ok: true });
  } catch (e) {
    rep({ type: 'cdm', ok: false, error: String(e) });
  }
})();

function tick() {
  window.__sp4.state.pos = A.currentTime || 0;
  window.__sp4.state.dur = A.duration || 0;
  window.__sp4.state.playing = !A.paused && !A.ended;
  window.__sp4.state.ended = !!A.ended;
}
setInterval(tick, 200);
A.addEventListener('timeupdate', tick);
A.addEventListener('durationchange', tick);

A.addEventListener('encrypted', (e) => {
  rep({ type: 'encrypted', len: e.initData.byteLength });
  if (session) {
    session.generateRequest(e.initDataType, e.initData)
      .catch(err => rep({ type: 'genreq-failed', error: String(err) }));
  }
});
A.addEventListener('playing', () => {
  tick();
  rep({ type: 'PLAYING', duration: A.duration });
});
A.addEventListener('ended', () => { tick(); rep({ type: 'ENDED' }); });
A.addEventListener('error', () => rep({ type: 'audio-error',
  error: A.error ? (A.error.code + ':' + A.error.message) : '?' }));

window.__zenStart = async function(mediaPath) {
  try {
    await cdmReady;
    if (!mediaKeys) { rep({ type: 'no-mediakeys' }); return 'no-mediakeys'; }
    if (session) { try { session.close(); } catch (e) {} session = null; }
    if (ms) { try { A.removeAttribute('src'); A.load(); } catch (e) {} ms = null; }
    window.__sp4.phase = 'running';
    window.__sp4.state.ended = false;

    session = mediaKeys.createSession();
    session.addEventListener('message', (ev2) => {
      const u8 = new Uint8Array(ev2.message);
      let b = '';
      for (let i = 0; i < u8.length; i++) b += String.fromCharCode(u8[i]);
      window.__sp4.challenge = btoa(b);
    });
    session.addEventListener('keystatuseschange', () => {
      let usable = false;
      session.keyStatuses.forEach((v) => { if (v === 'usable') usable = true; });
      rep({ type: 'keystatus', usable: usable });
      if (usable) {
        A.play().catch(err => rep({ type: 'play-blocked', error: String(err) }));
      }
    });

    const res = await fetch(mediaPath);
    if (!res.ok) { rep({ type: 'fetch-failed', status: res.status });
      return 'fetch-' + res.status; }
    const buf = await res.arrayBuffer();
    ms = new MediaSource();
    ms.addEventListener('sourceopen', () => {
      try {
        const sb = ms.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
        sb.mode = 'sequence';
        sb.addEventListener('error', (e) => rep({ type: 'append-error', error: String(e) }));
        sb.appendBuffer(buf);
      } catch (e) { rep({ type: 'pipeline-error', error: String(e) }); }
    });
    A.src = URL.createObjectURL(ms);
    return 'started';
  } catch (e) {
    rep({ type: 'start-error', error: String(e) });
    return 'error';
  }
};

window.__zenPause  = () => { try { A.pause(); } catch (e) {} };
window.__zenResume = () => { try { A.play();  } catch (e) {} };
window.__zenSeek   = (msPos) => { try { A.currentTime = msPos / 1000.0; } catch (e) {} };
window.__zenStop   = () => {
  try { A.pause(); } catch (e) {}
  try { A.removeAttribute('src'); A.load(); } catch (e) {}
  try { if (session) { session.close(); } } catch (e) {}
  session = null; ms = null;
  window.__sp4.state.pos = 0;
  window.__sp4.state.dur = 0;
  window.__sp4.state.playing = false;
  window.__sp4.state.ended = false;
};
</script></body></html>
''';

  // ── Infrastructure ──

  Future<bool> _ensureServer() async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _server!.port;
      _server!.listen((req) async {
        try {
          if (req.uri!.path == '/media') {
            final target = req.uri!.queryParameters['u'] ?? '';
            if (!_isAllowedMediaHost(target)) {
              await req.response.close();
              return;
            }
            final mresp = await http
                .get(Uri.parse(target))
                .timeout(const Duration(seconds: 30));
            final res = req.response
              ..headers.contentType =
              ContentType('video', 'mp4', charset: null)
              ..contentLength = mresp.bodyBytes.length;
            res.add(mresp.bodyBytes);
            await res.close();
            _log('media proxy ${mresp.statusCode} '
                '(${mresp.bodyBytes.length} B)');
            return;
          }
          final res = req.response..headers.contentType = ContentType.html;
          res.add(utf8.encode(_pageHtml));
          await res.close();
        } catch (_) {
          try {
            await req.response.close();
          } catch (_) {}
        }
      });
      _pageUrl = 'http://127.0.0.1:$port/_spengine';
      _log('serving engine page at $_pageUrl');
      return true;
    } catch (e) {
      _log('server bind failed: $e');
      return false;
    }
  }

  bool _isAllowedMediaHost(String url) {
    if (!url.startsWith('https://')) return false;
    final host = Uri.tryParse(url)?.host ?? '';
    return host.endsWith('spotifycdn.com') ||
        host.endsWith('akamaized.net') ||
        host.endsWith('scdn.co');
  }

  Future<bool> _ensureWebview() async {
    if (_webview != null) return true;
    try {
      if (!await WebviewWindow.isWebviewAvailable()) {
        _log('WebView2 runtime unavailable');
        return false;
      }
      final docs = await getApplicationSupportDirectory();
      _webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          userDataFolderWindows: '${docs.path}/webview2-zen-engine',
          openHidden: true,
        ),
      );
      _webview!.launch(_pageUrl!);
      await Future.delayed(const Duration(seconds: 3));
      _log('hidden engine webview running');
      return true;
    } on PlatformException catch (e) {
      _log('webview init failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      _log('webview init failed: $e');
      return false;
    }
  }

  Future<bool> _ensureReady() async =>
      await _ensureServer() && await _ensureWebview();

  Future<void> warm() async {
    if (!Platform.isWindows) return;
    await _ensureReady();
  }

  // ── Playback API ──

  /// Plays a Spotify song map (needs 'spotifyUri'). Returns true when audio
  /// is actually playing. On any failure: activeSong stays null and the
  /// caller (MediaPlayer wiring) falls back to the YT path.
  Future<bool> play(Map<String, dynamic> song) async {
    if (!Platform.isWindows) return false;
    final uri = song['spotifyUri'] as String?;
    if (uri == null || uri.isEmpty) return false;

    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      _log('no session: ${SpotifyAuth.instance.lastError}');
      return false;
    }
    final cdn = await SpotifyPlayer.instance.resolveTrack(uri);
    if (cdn == null || cdn.isEmpty) {
      _log('resolve failed for $uri');
      return false;
    }
    if (!await _ensureReady()) return false;

    final wv = _webview!;
    _gen++;
    final myGen = _gen;
    activeSong = song;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    playing.value = false;
    ended.value = false;

    final mediaPath = '/media?u=${Uri.encodeQueryComponent(cdn)}';
    final start = await wv
        .evaluateJavaScript(
        'window.__zenStart ? window.__zenStart("$mediaPath") : "no-fn"')
        .timeout(const Duration(seconds: 60), onTimeout: () => 'timeout');
    _log('start -> $start');
    if (start.toString() == 'no-fn' || start.toString() == 'timeout') {
      activeSong = null;
      return false;
    }

    // Always start a fresh bridge loop. Any prior loop exits on its next
    // iteration because its myGen != _gen. No lifetime flag needed.
    unawaited(_bridgeLoop(myGen, token));

    // Wait for PLAYING (or give up after ~25 s).
    for (var i = 0; i < 125; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (myGen != _gen) return false; // superseded by another play()/stop()
      if (playing.value) return true;
      if (activeSong == null) return false; // bridge aborted
    }
    _log('no PLAYING within 25 s');
    activeSong = null;
    return false;
  }

  Future<void> _bridgeLoop(int myGen, String initialToken) async {
    var token = initialToken;
    String? lastChallenge;
    var refreshUsed = false;
    while (myGen == _gen) {
      await Future.delayed(const Duration(milliseconds: 150));
      final wv = _webview;
      if (wv == null) break;

      // 1. Challenge pickup (raw value, sanitized — no JSON round-trip).
      String? challengeB64;
      try {
        final raw =
        await wv.evaluateJavaScript('window.__sp4.challenge || ""');
        challengeB64 =
            (raw?.toString() ?? '').replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
        if (challengeB64.isEmpty) challengeB64 = null;
      } catch (_) {}

      if (challengeB64 != null && challengeB64 != lastChallenge) {
        lastChallenge = challengeB64;
        try {
          await wv.evaluateJavaScript('window.__sp4.challenge = null');
          final challenge = base64Decode(challengeB64);
          _log('challenge ${challenge.length} B -> license endpoint');
          final clientToken = await SpotifyAuth.instance.getClientToken();
          var resp = await http
              .post(Uri.parse(_kLicenseUrl),
              headers: _licenseHeaders(token, clientToken),
              body: challenge)
              .timeout(const Duration(seconds: 15));
          // 401/403: force one token refresh, retry once.
          if ((resp.statusCode == 401 || resp.statusCode == 403) &&
              !refreshUsed) {
            refreshUsed = true;
            _log('license ${resp.statusCode} — refreshing token, retrying');
            token = await SpotifyAuth.instance.getAccessToken(force: true) ?? token;
            final ct2 = await SpotifyAuth.instance.getClientToken();
            resp = await http
                .post(Uri.parse(_kLicenseUrl),
                headers: _licenseHeaders(token, ct2), body: challenge)
                .timeout(const Duration(seconds: 15));
          }
          _log('license POST -> ${resp.statusCode} (${resp.bodyBytes.length} B)');
          if (resp.statusCode >= 200 && resp.statusCode < 300) {
            final b64 = base64Encode(resp.bodyBytes);
            await wv.evaluateJavaScript(
                'window.__sp4.licenseResponse = "$b64"');
          } else if (resp.statusCode == 401 || resp.statusCode == 403) {
            _log('license rejected after refresh — aborting playback');
            _abort();
            break;
          }
        } catch (e) {
          _log('license bridge error: $e');
        }
      }

      // 2. State poll — pipe-delimited scalars, stripped to [0-9 . - |].
      try {
        final st = await wv.evaluateJavaScript(
            'window.__sp4.state.pos + "|" + window.__sp4.state.dur + "|" + '
                '(window.__sp4.state.playing ? "1" : "0") + "|" + '
                '(window.__sp4.state.ended ? "1" : "0")');
        if (st != null) {
          final cleaned =
          st.toString().replaceAll(RegExp(r'[^0-9|.\-]'), '');
          final parts = cleaned.split('|');
          if (parts.length == 4) {
            final pos = double.tryParse(parts[0]) ?? 0;
            final dur = double.tryParse(parts[1]) ?? 0;
            final play = parts[2] == '1';
            final end = parts[3] == '1';
            position.value =
                Duration(milliseconds: (pos * 1000).round());
            if (dur > 0) {
              duration.value =
                  Duration(milliseconds: (dur * 1000).round());
            }
            playing.value = play;
            ended.value = end;
          }
        }
      } catch (_) {}
    }
  }

  static const String _kLicenseUrl =
      'https://gae2-spclient.spotify.com/widevine-license/v1/audio/license';

  Map<String, String> _licenseHeaders(String token, String clientToken) => {
    'authorization': 'Bearer $token',
    'client-token': clientToken,
    'content-type': 'application/octet-stream',
    'app-platform': SpotifyConfig.appPlatform,
    'spotify-app-version': SpotifyConfig.spotifyAppVersion,
    'origin': 'https://open.spotify.com',
    'referer': 'https://open.spotify.com/',
    'user-agent': SpotifyConfig.userAgent,
  };

  void _abort() {
    _gen++;
    activeSong = null;
    playing.value = false;
    ended.value = false;
  }

  // ── Transport (no-ops when the engine is inactive) ──

  Future<void> pause() async {
    if (!isActive) return;
    try {
      await _webview?.evaluateJavaScript('window.__zenPause && window.__zenPause()');
    } catch (_) {}
  }

  Future<void> resume() async {
    if (!isActive) return;
    try {
      await _webview
          ?.evaluateJavaScript('window.__zenResume && window.__zenResume()');
    } catch (_) {}
  }

  Future<void> seek(Duration d) async {
    if (!isActive) return;
    try {
      await _webview?.evaluateJavaScript(
          'window.__zenSeek && window.__zenSeek(${d.inMilliseconds})');
    } catch (_) {}
  }

  /// Stops engine playback and releases the current track.
  Future<void> stop() async {
    if (!isActive) return;
    _gen++; // invalidate the bridge loop
    activeSong = null;
    playing.value = false;
    ended.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    try {
      await _webview?.evaluateJavaScript('window.__zenStop && window.__zenStop()');
    } catch (_) {}
  }

  void dispose() {
    _gen++;
    activeSong = null;
    try { _webview?.close(); } catch (_) {}
    _webview = null;
    try { _server?.close(force: true); } catch (_) {}
    _server = null;
    _pageUrl = null;
  }
}