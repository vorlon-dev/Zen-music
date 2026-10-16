// ZenMusic — SP-4 SPIKE v2.5 (temporary). Full EME pipeline verification on
// desktop_webview_window 0.3.2, all-bridge-via-evaluateJavaScript.
// PROVEN: cdm ok; /media proxy defeats CORS; MSE parses the file (appended
// 213.6 s); 83 B CENC init extracted; CDM emitted challenge #1 = 2 bytes
// hex 0804 = SignedMessage{type:4} = SERVICE_CERTIFICATE_REQUEST (the
// standard Widevine privacy flow: cert first, then the real license
// request — same license URL, generic loop handles it).
// v2.5 fixes: (a) challenge transport without JSON.stringify (v2.4.1
// crashed on double-encoded quotes — FormatException on "CAQ="), values
// sanitized to the base64 alphabet; (b) 'appended' counts as healthy (the
// +2 s safety kick used to restart a healthy pipeline and caused the
// sourceclose/genreq-failed noise); kick only fires in phase 'boot'.
// Markers: [SP4S].

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

const String _kSpLicenseUrl =
    'https://gae2-spclient.spotify.com/widevine-license/v1/audio/license';

const String _spikeHtml = r'''
<!DOCTYPE html>
<html><body><audio id="a"></audio><script>
window.__sp4 = { phase: 'boot', lines: [], done: false, challenge: null,
                challengeCount: 0, licenseResponse: null, stalled: false };
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
    window.__sp4.done = true;
  }
})();

document.addEventListener('visibilitychange', () => {
  rep({ type: 'vischange', vis: document.visibilityState });
});

A.addEventListener('encrypted', (e) => {
  rep({ type: 'encrypted', initDataLen: e.initData.byteLength });
  if (session) {
    session.generateRequest(e.initDataType, e.initData)
      .catch(err => rep({ type: 'genreq-failed', error: String(err) }));
  } else {
    rep({ type: 'encrypted-no-session' });
  }
});
A.addEventListener('playing', () => {
  rep({ type: 'PLAYING', duration: A.duration, time: A.currentTime });
  window.__sp4.phase = 'playing';
  window.__sp4.done = true;
});
A.addEventListener('error', () => rep({ type: 'audio-error',
  error: A.error ? (A.error.code + ':' + A.error.message) : '?' }));

window.__zenStart = async function() {
  try {
    await cdmReady;
    // Healthy run keeps running: 'running' OR 'appended' with an open
    // MediaSource (v2.4.1's kick restarted healthy pipelines).
    if ((window.__sp4.phase === 'running' || window.__sp4.phase === 'appended') &&
        ms && ms.readyState === 'open') {
      rep({ type: 'already-running' });
      return;
    }
    if (session) { try { session.close(); } catch (e) {} session = null; }
    if (ms) { try { A.removeAttribute('src'); A.load(); } catch (e) {} ms = null; }
    if (!mediaKeys) { rep({ type: 'no-mediakeys' }); return; }
    window.__sp4.phase = 'running';
    window.__sp4.stalled = false;

    session = mediaKeys.createSession();
    session.addEventListener('message', (ev2) => {
      const u8 = new Uint8Array(ev2.message);
      let hex = '';
      for (let i = 0; i < Math.min(u8.length, 24); i++) {
        hex += u8[i].toString(16).padStart(2, '0');
      }
      window.__sp4.challengeCount++;
      window.__sp4.challenge = btoa(String.fromCharCode.apply(null, u8));
      rep({ type: 'challenge-ready', count: window.__sp4.challengeCount,
            mtype: String(ev2.messageType), len: u8.length, hex: hex });
    });
    session.addEventListener('keystatuseschange', () => {
      const st = [];
      session.keyStatuses.forEach((v, k) => st.push(String(k).slice(0,8) + '=' + v));
      rep({ type: 'keystatus', statuses: st });
      let usable = false;
      session.keyStatuses.forEach((v) => { if (v === 'usable') usable = true; });
      if (usable) {
        A.play().catch(err => rep({ type: 'play-blocked', error: String(err) }));
      }
    });

    const res = await fetch('/media');
    rep({ type: 'fetch-status', status: res.status });
    if (!res.ok) { window.__sp4.done = true; return; }
    const buf = await res.arrayBuffer();
    rep({ type: 'fetched', bytes: buf.byteLength });

    ms = new MediaSource();
    ms.addEventListener('sourceopen', () => {
      rep({ type: 'sourceopen', msReady: ms.readyState });
      try {
        const sb = ms.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
        rep({ type: 'sb-created' });
        sb.mode = 'sequence';
        sb.addEventListener('error', (e) => rep({ type: 'append-error', error: String(e) }));
        sb.addEventListener('updateend', () => {
          rep({ type: 'appended', duration: ms.duration });
          window.__sp4.phase = 'appended';
        }, { once: true });
        sb.appendBuffer(buf);
        rep({ type: 'append-issued' });
      } catch (e) { rep({ type: 'pipeline-error', error: String(e) }); }
    });
    ms.addEventListener('sourceclose', () => rep({ type: 'sourceclose' }));
    A.src = URL.createObjectURL(ms);
    rep({ type: 'src-set' });

    setTimeout(() => {
      const stalled = (window.__sp4.phase === 'running') &&
                      (!ms || ms.readyState === 'closed');
      window.__sp4.stalled = stalled;
      rep({ type: 'diag', phase: window.__sp4.phase,
            msReady: ms ? ms.readyState : 'null', aReady: A.readyState,
            net: A.networkState, vis: document.visibilityState,
            paused: A.paused, t: A.currentTime, stalled: stalled });
    }, 2500);
  } catch (e) {
    rep({ type: 'start-error', error: String(e) });
    window.__sp4.done = true;
  }
};

window.addEventListener('load', () => {
  try { window.__zenStart(); } catch (e) {}
});

setInterval(async () => {
  const b64 = window.__sp4.licenseResponse;
  if (b64 && session) {
    window.__sp4.licenseResponse = null;
    try {
      const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
      await session.update(raw);
      rep({ type: 'license-updated' });
    } catch (e) { rep({ type: 'license-update-failed', error: String(e) }); }
  }
}, 50);
</script></body></html>
''';

Future<void> runSp4Spike() async {
  await Future.delayed(const Duration(seconds: 3));
  print('[SP4S] begin (spike v2.5 — clean challenge transport + cert flow)');
  HttpServer? server;
  try {
    await SpotifyAuth.instance.load();
    final token = await SpotifyAuth.instance.getAccessToken();
    if (token == null) {
      print('[SP4S] no Spotify session (${SpotifyAuth.instance.lastError})');
      return;
    }
    final cdn = await SpotifyPlayer.instance
        .resolveTrack('4PTG3Z6ehGkBFwjybzWkR8')
        .timeout(const Duration(seconds: 45));
    if (cdn == null) {
      print('[SP4S] VERDICT: resolve failed.');
      return;
    }
    print('[SP4S] cdn resolved');

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    server.listen((req) async {
      try {
        if (req.uri.path == '/media') {
          final mresp = await http
              .get(Uri.parse(cdn))
              .timeout(const Duration(seconds: 30));
          final res = req.response
            ..headers.contentType = ContentType('video', 'mp4', charset: null)
            ..contentLength = mresp.bodyBytes.length;
          res.add(mresp.bodyBytes);
          await res.close();
          print('[SP4S] media proxy -> ${mresp.statusCode} '
              '(${mresp.bodyBytes.length} bytes)');
          return;
        }
        final res = req.response..headers.contentType = ContentType.html;
        res.add(_spikeHtml.codeUnits);
        await res.close();
      } catch (e) {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
    final url = 'http://127.0.0.1:$port/_sp4spike';
    print('[SP4S] serving spike at $url');

    if (!await WebviewWindow.isWebviewAvailable()) {
      print('[SP4S] VERDICT: WebView2 Runtime unavailable.');
      return;
    }
    final docs = await getApplicationSupportDirectory();
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        userDataFolderWindows: '${docs.path}/webview2-zen-spike',
      ),
    );
    webview.launch(url);
    await webview.bringToForeground();
    await Future.delayed(const Duration(seconds: 2));

    // Safety kick ONLY if auto-start never ran (phase still 'boot').
    await webview.evaluateJavaScript(
        'if (window.__sp4 && window.__sp4.phase === "boot") { window.__zenStart && window.__zenStart(); }');

    var licenseBusy = false;
    for (var i = 0; i < 120; i++) {
      await Future.delayed(const Duration(milliseconds: 200));

      // Self-heal: re-raise every 1 s if buried.
      if (i % 5 == 4) {
        try {
          final vis = await webview.evaluateJavaScript('document.visibilityState');
          if (vis.toString().contains('hidden')) {
            await webview.bringToForeground();
          }
        } catch (_) {}
      }

      // Restart-on-stall: suspended before sourceopen -> redo the pipeline.
      if (i % 15 == 14) {
        try {
          final st = await webview.evaluateJavaScript(
              'JSON.stringify({s: window.__sp4.stalled, d: window.__sp4.done,'
                  ' p: window.__sp4.phase})');
          if (st.toString().contains('"s":true')) {
            print('[SP4S] stall detected — restarting pipeline');
            await webview.bringToForeground();
            await webview.evaluateJavaScript(
                'window.__sp4.stalled = false; window.__zenStart();');
          }
        } catch (_) {}
      }

      if (!licenseBusy) {
        // Direct value read — NO JSON.stringify (double-encoding lesson).
        final ch = await webview.evaluateJavaScript(
            'window.__sp4.challenge || ""');
        // Sanitize to the base64 alphabet; kills every quote/escape issue.
        final b64 =
        (ch?.toString() ?? '').replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
        if (b64.isNotEmpty) {
          licenseBusy = true;
          print('[SP4S] challenge picked up (b64 len ${b64.length})');
          try {
            await webview.evaluateJavaScript('window.__sp4.challenge = null');
            final challenge = base64Decode(b64);
            print('[SP4S] challenge bytes: ${challenge.length}');
            if (challenge.length <= 4) {
              print('[SP4S] tiny challenge — likely SignedMessage type=4 '
                  'SERVICE_CERTIFICATE_REQUEST: posting to the license URL '
                  'for the cert roundtrip (real license request follows)');
            }
            final clientToken = await SpotifyAuth.instance.getClientToken();
            final resp = await http
                .post(Uri.parse(_kSpLicenseUrl),
                headers: {
                  'authorization': 'Bearer $token',
                  'client-token': clientToken,
                  'content-type': 'application/octet-stream',
                  'app-platform': SpotifyConfig.appPlatform,
                  'spotify-app-version': SpotifyConfig.spotifyAppVersion,
                  'origin': 'https://open.spotify.com',
                  'referer': 'https://open.spotify.com/',
                  'user-agent': SpotifyConfig.userAgent,
                },
                body: challenge)
                .timeout(const Duration(seconds: 15));
            print('[SP4S] license POST -> ${resp.statusCode} '
                '(${resp.bodyBytes.length} bytes)');
            final respB64 = base64Encode(resp.bodyBytes);
            await webview.evaluateJavaScript(
                'window.__sp4.licenseResponse = "$respB64"');
          } catch (e) {
            print('[SP4S] license bridge error: $e');
          }
          licenseBusy = false;
        }
      }

      final done = await webview.evaluateJavaScript(
          'JSON.stringify(window.__sp4 && window.__sp4.done)');
      if (done.toString().contains('true')) break;
    }

    final lines = await webview.evaluateJavaScript(
        'JSON.stringify(window.__sp4.lines)');
    print('[SP4S] VERDICT DATA: $lines');
    webview.close();
  } on PlatformException catch (e) {
    print('[SP4S] platform error: ${e.code} ${e.message}');
  } catch (e, st) {
    print('[SP4S] spike error: $e');
    print('[SP4S] $st');
  } finally {
    try {
      await server?.close(force: true);
    } catch (_) {}
    print('[SP4S] end — paste everything from "[SP4S] begin" onward');
  }
}