// ZenMusic — SpotifyDesktopEngine (SP-5b-stealth). True Spotify playback on
// Windows via a WebView2 EME pipeline. Formalized from the SP-4 spike v2.5
// which proved the full chain on WebView2 155.0.4283.45 +
// desktop_webview_window 0.3.2.
//
// SP-5b-stealth: THE WINDOW FIX, v3.
//   openHidden: true makes Chromium enter "hidden playback state" and
//   MediaSource never fires sourceopen — no initData, no challenge, no
//   license, no PLAYING. Browser args don't change this (visibility gate,
//   not scheduling gate).
//   v1/v2 tried SetWindowPos(GetForegroundWindow()/window-walk, -32000).
//   On some systems the WebView2 host is re-shown by the plugin or refuses
//   to leave the desktop, so a visible white rectangle remained.
//   v3 keeps the window technically visible (Chromium happy) and adds
//   WS_EX_LAYERED + LWA_ALPHA=0 so it renders nothing. Also adds
//   WS_EX_TOOLWINDOW (no taskbar) and WS_EX_NOACTIVATE (no focus steal).
//   Belt-and-suspenders: the window is still moved to (-32000,-32000).
//
// SP-5b-stealth v4 (this build): kills the visible gap.
//   create() shows the window natively at default position and the v3 mask
//   only landed ~1.1 s later (bringToForeground even fronted it — the flash
//   the user saw on warm() / first Spotify play). The window is now BORN
//   off-screen via the plugin's own config (useWindowPositionAndSize,
//   windowPos -32000): IsWindowVisible() stays true from frame zero, so the
//   hidden-playback gate never triggers and nothing can flash. The
//   LAYERED/TOOLWINDOW/NOACTIVATE mask remains for taskbar + focus hygiene
//   and now runs twice (right after create(), and after the 800 ms settle).
//
// SP-5b-fix: the missing setInterval that fed window.__sp4.licenseResponse
//   back into session.update(raw).
// SP-5b (base): bridge lifetime is generation-based; state poll uses
//   pipe-delimited scalars; ended surfaced via ValueNotifier; _pageHtml
//   served via utf8.encode; JS-line drain via cursor closure.
//
// SP-48 — NATIVE MEDIA-SESSION METADATA. The WebView's own Chromium engine
//   registers an OS media session (Windows SMTC / MPRIS / Android media card)
//   for the <audio> element it plays. With no document title and no
//   MediaSession metadata, every OS surface showed the raw page URL
//   ("127.0.0.1:<port>/_spengine") instead of the song. The page now:
//   • carries <title>ZenMusic</title> (pre-play fallback), and
//   • exposes window.__zenTrackMeta({title,artist,album,artwork}) which sets
//     document.title AND navigator.mediaSession.metadata so ANY session the
//     webview registers shows the real track.
//   play() pushes the song map's fields into the page right before
//   __zenStart. (windows/runner/main.cpp additionally disables the Chromium
//   MediaSessionService feature on Windows, so the app's own smtc_bridge
//   session stays the only SMTC card; the in-page metadata remains as
//   belt-and-suspenders for WebView builds where that flag does not apply.)
//
// DEPENDS: windows/runner/main.cpp sets WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS.
// Stopify (MIT) is the protocol reference; ZenMusic remains GPL-3.0.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:ffi/ffi.dart';
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

  // ── Public state ──
  final ValueNotifier<Duration> position =
  ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> duration =
  ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  final ValueNotifier<bool> ended = ValueNotifier<bool>(false);

  Map<String, dynamic>? activeSong;
  bool get isActive => activeSong != null;

  HttpServer? _server;
  String? _pageUrl;
  Webview? _webview;
  int _gen = 0;

  // ── Embedded page ──
  static const String _pageHtml = r'''
<!DOCTYPE html>
<html><head><title>ZenMusic</title></head><body><audio id="a"></audio><script>
window.__sp4 = { phase: 'boot', lines: [], challenge: null,
                licenseResponse: null, startResult: null,
                state: {pos: 0, dur: 0, playing: false, ended: false} };
function rep(o) { window.__sp4.lines.push(JSON.stringify(o)); }
const A = document.getElementById('a');

// SP-48 — real track metadata for the webview's own OS media session.
// document.title is the fallback Chromium uses; MediaSession.metadata is
// the proper channel (title/artist/album/artwork on SMTC, MPRIS, Android).
window.__zenTrackMeta = function(m) {
  try {
    var t  = (m && m.title)   ? String(m.title)   : 'ZenMusic';
    var ar = (m && m.artist)  ? String(m.artist)  : '';
    var al = (m && m.album)   ? String(m.album)   : '';
    var aw = (m && m.artwork) ? String(m.artwork) : '';
    try { document.title = ar ? (t + ' \u2014 ' + ar) : t; } catch (e2) {}
    try {
      if ('mediaSession' in navigator && window.MediaMetadata) {
        navigator.mediaSession.metadata = new window.MediaMetadata({
          title: t, artist: ar, album: al,
          artwork: aw ? [{ src: aw, sizes: '640x640', type: 'image/jpeg' }] : []
        });
      }
    } catch (e3) {}
    rep({ type: 'meta', title: t });
    return 'ok';
  } catch (e) { rep({ type: 'meta-failed', error: String(e) }); return 'err'; }
};

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
  rep({ type: 'encrypted', len: e.initData.byteLength, dt: e.initDataType });
  if (session) {
    session.generateRequest(e.initDataType, e.initData)
      .catch(err => rep({ type: 'genreq-failed', error: String(err) }));
  } else {
    rep({ type: 'encrypted-no-session' });
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
    rep({ type: 'start-called', path: mediaPath });
    await cdmReady;
    if (!mediaKeys) {
      rep({ type: 'no-mediakeys' });
      window.__sp4.startResult = 'no-mediakeys';
      return 'no-mediakeys';
    }
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
      rep({ type: 'challenge-set', len: u8.length, mtype: String(ev2.messageType) });
    });
    session.addEventListener('keystatuseschange', () => {
      let usable = false;
      session.keyStatuses.forEach((v) => { if (v === 'usable') usable = true; });
      rep({ type: 'keystatus', usable: usable });
      if (usable) {
        A.play().then(
          () => rep({ type: 'play-ok' }),
          (err) => rep({ type: 'play-blocked', error: String(err) })
        );
      }
    });

    rep({ type: 'fetch-issuing' });
    const res = await fetch(mediaPath);
    rep({ type: 'fetch-status', status: res.status });
    if (!res.ok) {
      window.__sp4.startResult = 'fetch-' + res.status;
      return 'fetch-' + res.status;
    }
    const buf = await res.arrayBuffer();
    rep({ type: 'fetched', bytes: buf.byteLength });
    ms = new MediaSource();
    ms.addEventListener('sourceopen', () => {
      rep({ type: 'sourceopen', msReady: ms.readyState });
      try {
        const sb = ms.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
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
    rep({ type: 'src-set', readyState: A.readyState });
    window.__sp4.startResult = 'started';
    return 'started';
  } catch (e) {
    rep({ type: 'start-error', error: String(e) });
    window.__sp4.startResult = 'error:' + String(e);
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

// ★ SP-5b-fix: THE MISSING PIECE. Dart writes base64 responses into
// window.__sp4.licenseResponse (cert, then real license). This feeds each
// into the CDM session. Without it the session never advances past the
// first challenge.
setInterval(async () => {
  const b64 = window.__sp4.licenseResponse;
  if (b64 && session) {
    window.__sp4.licenseResponse = null;
    try {
      const raw = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
      await session.update(raw);
      rep({ type: 'license-updated' });
    } catch (e) {
      rep({ type: 'license-update-failed', error: String(e) });
    }
  }
}, 50);
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

      // openHidden MUST stay false (Chromium hidden-playback gate kills
      // sourceopen). SP-5b-stealth v4: the window is BORN off-screen via
      // the plugin's own config — IsWindowVisible() stays true from frame
      // zero, so the EME chain is unaffected, but nothing can flash on the
      // desktop. The LAYERED/TOOLWINDOW/NOACTIVATE mask below remains for
      // taskbar-button + focus-steal hygiene.
      _webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          userDataFolderWindows: '${docs.path}/webview2-zen-engine',
          openHidden: false,
          useWindowPositionAndSize: true,
          windowPosX: -32000,
          windowPosY: -32000,
        ),
      );
      _webview!.launch(_pageUrl!);

      // Pass 1 immediately: the HWND exists once create() resolves, so
      // TOOLWINDOW (no taskbar button) applies within milliseconds.
      _maskWebViewWindows();

      await Future.delayed(const Duration(milliseconds: 800));

      // Pass 2: catches the WebView2 host window if the plugin realized it
      // late. The walk is idempotent (styles OR-ed, position re-applied).
      _maskWebViewWindows();

      await Future.delayed(const Duration(milliseconds: 300));

      try {
        final vis =
        await _webview!.evaluateJavaScript('document.visibilityState');
        _log('page visibility: $vis');
      } catch (e) {
        _log('visibility probe failed: $e');
      }
      await Future.delayed(const Duration(seconds: 2));
      _log('engine webview running (masked)');
      return true;
    } on PlatformException catch (e) {
      _log('webview init failed: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      _log('webview init failed: $e');
      return false;
    }
  }

  /// Walks every top-level window owned by this process. For each window
  /// that is not the main Flutter runner:
  ///   1. moves it to (-32000, -32000)   → off-screen
  ///   2. adds WS_EX_LAYERED              → allow per-window alpha
  ///   3. adds WS_EX_TOOLWINDOW           → no taskbar button
  ///   4. adds WS_EX_NOACTIVATE           → cannot steal focus
  ///   5. SetLayeredWindowAttributes α=0  → fully transparent
  ///
  /// Result: IsWindowVisible() stays TRUE (Chromium happy, media pipeline
  /// runs), but the user sees nothing on screen and has no window to close.
  void _maskWebViewWindows() {
    if (!Platform.isWindows) return;
    Pointer<Uint32>? pidPtr;
    Pointer<Utf16>? classBuf;
    Pointer<Utf16>? titleBuf;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final getTopWindow = user32.lookupFunction<
          IntPtr Function(IntPtr),
          int Function(int)>('GetTopWindow');
      final getWindow = user32.lookupFunction<
          IntPtr Function(IntPtr, Uint32),
          int Function(int, int)>('GetWindow');
      final getWindowThreadProcessId = user32.lookupFunction<
          Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
      final isWindowVisible = user32.lookupFunction<
          Int32 Function(IntPtr),
          int Function(int)>('IsWindowVisible');
      final getClassNameW = user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetClassNameW');
      final getWindowTextW = user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32),
          int Function(int, Pointer<Utf16>, int)>('GetWindowTextW');
      final setWindowPos = user32.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');
      // GetWindowLongW / SetWindowLongW are 32-bit-style; styles fit in
      // 32 bits so they're correct on 64-bit Windows too.
      final getWindowLongW = user32.lookupFunction<
          Int32 Function(IntPtr, Int32),
          int Function(int, int)>('GetWindowLongW');
      final setWindowLongW = user32.lookupFunction<
          Int32 Function(IntPtr, Int32, Int32),
          int Function(int, int, int)>('SetWindowLongW');
      final setLayeredWindowAttributes = user32.lookupFunction<
          Int32 Function(IntPtr, Uint32, Uint8, Uint32),
          int Function(int, int, int, int)>('SetLayeredWindowAttributes');

      final myPid = pid;
      pidPtr = calloc<Uint32>();
      classBuf = calloc<Uint16>(256).cast<Utf16>();
      titleBuf = calloc<Uint16>(256).cast<Utf16>();

      const swpNoZorder = 0x0004;
      const swpNoActivate = 0x0010;
      const swpNoSize = 0x0001;
      const offscreen = -32000;

      const gwlExstyle = -20;
      const wsExLayered = 0x00080000;
      const wsExToolwindow = 0x00000080;
      const wsExNoactivate = 0x08000000;
      const lwaAlpha = 0x00000002;

      var h = getTopWindow(0);
      var masked = 0;
      var skipped = 0;
      var examined = 0;
      while (h != 0) {
        examined++;
        getWindowThreadProcessId(h, pidPtr);
        if (pidPtr.value == myPid) {
          final visible = isWindowVisible(h) != 0;
          final cLen = getClassNameW(h, classBuf, 256);
          final tLen = getWindowTextW(h, titleBuf, 256);
          final cls = cLen > 0 ? classBuf.toDartString() : '';
          final title = tLen > 0 ? titleBuf.toDartString() : '';
          if (!visible) {
            _log('mask skip (hidden): class="$cls" title="$title" hwnd=$h');
          } else if (cls.contains('FLUTTER_RUNNER')) {
            _log('mask skip (main): class="$cls" title="$title"');
            skipped++;
          } else {
            // 1. Move off-screen (belt-and-suspenders — layered alpha does
            // the real hiding).
            setWindowPos(h, 0, offscreen, offscreen, 0, 0,
                swpNoZorder | swpNoActivate | swpNoSize);

            // 2-4. Add the layered + toolwindow + noactivate EX styles.
            final ex = getWindowLongW(h, gwlExstyle);
            final newEx = ex |
            wsExLayered |
            wsExToolwindow |
            wsExNoactivate;
            setWindowLongW(h, gwlExstyle, newEx);

            // 5. α = 0 → fully transparent.
            final ok = setLayeredWindowAttributes(h, 0, 0, lwaAlpha);

            _log('mask apply: class="$cls" title="$title" hwnd=$h '
                'ex=0x${ex.toRadixString(16)} -> '
                '0x${newEx.toRadixString(16)} layeredOk=$ok');
            if (ok != 0) masked++;
          }
        }
        h = getWindow(h, 2); // GW_HWNDNEXT
      }
      _log('mask done: examined=$examined masked=$masked skipped=$skipped');
    } catch (e) {
      _log('mask failed: $e');
    } finally {
      try {
        if (pidPtr != null) calloc.free(pidPtr);
        if (classBuf != null) calloc.free(classBuf);
        if (titleBuf != null) calloc.free(titleBuf);
      } catch (_) {}
    }
  }

  Future<bool> _ensureReady() async =>
      await _ensureServer() && await _ensureWebview();

  Future<void> warm() async {
    if (!Platform.isWindows) return;
    await _ensureReady();
  }

  // ── Playback API ──

  /// SP-48 — push the real track metadata into the engine page so the OS
  /// media session the WebView's Chromium registers on its own shows the
  /// song — never the 127.0.0.1:<port>/_spengine page URL. Reads the same
  /// song-map fields the player's MediaItem tag uses (title / artists[] /
  /// album.name / thumbnails[].url), JSON-encodes them and lets the page
  /// set document.title + navigator.mediaSession.metadata.
  Future<void> _pushMediaSessionMeta(
      Webview wv, Map<String, dynamic> song) async {
    try {
      final String title = (song['title'] ?? 'ZenMusic').toString();
      String artist = '';
      final artists = song['artists'];
      if (artists is List && artists.isNotEmpty) {
        artist = artists
            .map((a) => a is Map ? (a['name'] ?? '').toString() : '')
            .where((s) => s.isNotEmpty)
            .join(', ');
      }
      if (artist.isEmpty && song['artist'] != null) {
        artist = song['artist'].toString();
      }
      String album = '';
      if (song['album'] is Map) {
        album = ((song['album'] as Map)['name'] ?? '').toString();
      }
      String? artwork;
      final thumbs = song['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        final last = thumbs.last;
        if (last is Map && last['url'] != null) {
          artwork = last['url'].toString();
        }
      }
      final payload = json.encode(<String, String?>{
        'title': title,
        'artist': artist,
        'album': album,
        'artwork': artwork,
      });
      final res = await wv.evaluateJavaScript(
          'window.__zenTrackMeta ? window.__zenTrackMeta($payload) : "no-fn"');
      _log('media session meta -> $res');
    } catch (e) {
      _log('media session meta push failed: $e');
    }
  }

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

    // SP-48 — the webview's Chromium registers its own OS media session;
    // feed it the real track BEFORE playback starts so no OS surface ever
    // falls back to the page URL.
    unawaited(_pushMediaSessionMeta(wv, song));

    final mediaPath = '/media?u=${Uri.encodeQueryComponent(cdn)}';
    final start = await wv
        .evaluateJavaScript(
        'window.__zenStart ? window.__zenStart("$mediaPath") : "no-fn"')
        .timeout(const Duration(seconds: 60), onTimeout: () => 'timeout');
    _log('start -> $start');
    try {
      final res =
      await wv.evaluateJavaScript('window.__sp4.startResult || ""');
      _log('start result slot -> $res');
    } catch (_) {}

    if (start.toString() == 'no-fn' || start.toString() == 'timeout') {
      activeSong = null;
      return false;
    }

    unawaited(_bridgeLoop(myGen, token));

    for (var i = 0; i < 125; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (myGen != _gen) return false;
      if (playing.value) return true;
      if (activeSong == null) return false;
    }
    _log('no PLAYING within 25 s');
    _gen++;
    activeSong = null;
    return false;
  }

  Future<void> _bridgeLoop(int myGen, String initialToken) async {
    var token = initialToken;
    String? lastChallenge;
    var refreshUsed = false;
    var jsLineIdx = 0;
    while (myGen == _gen) {
      await Future.delayed(const Duration(milliseconds: 150));
      final wv = _webview;
      if (wv == null) break;

      try {
        final raw = await wv.evaluateJavaScript(
            '(function(){'
                ' var s = $jsLineIdx;'
                ' var L = window.__sp4.lines;'
                ' if (s >= L.length) return "";'
                ' var out = L.slice(s).join("\\u0001");'
                ' window.__sp4._readIdx = L.length;'
                ' return out;'
                '})()');
        final txt = raw?.toString() ?? '';
        if (txt.isNotEmpty && txt != '""' && txt != 'null') {
          try {
            final n = await wv.evaluateJavaScript(
                'window.__sp4._readIdx || window.__sp4.lines.length');
            jsLineIdx = int.tryParse(
                n.toString().replaceAll(RegExp(r'[^0-9]'), '')) ??
                jsLineIdx;
          } catch (_) {}
          _log('js: $txt');
        }
      } catch (_) {}

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
          if ((resp.statusCode == 401 || resp.statusCode == 403) &&
              !refreshUsed) {
            refreshUsed = true;
            _log('license ${resp.statusCode} — refreshing token, retrying');
            token = await SpotifyAuth.instance.getAccessToken(force: true) ??
                token;
            final ct2 = await SpotifyAuth.instance.getClientToken();
            resp = await http
                .post(Uri.parse(_kLicenseUrl),
                headers: _licenseHeaders(token, ct2), body: challenge)
                .timeout(const Duration(seconds: 15));
          }
          _log('license POST -> ${resp.statusCode} '
              '(${resp.bodyBytes.length} B)');
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

  // ── Transport ──

  Future<void> pause() async {
    if (!isActive) return;
    try {
      await _webview
          ?.evaluateJavaScript('window.__zenPause && window.__zenPause()');
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

  Future<void> stop() async {
    if (!isActive) return;
    _gen++;
    activeSong = null;
    playing.value = false;
    ended.value = false;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    try {
      await _webview
          ?.evaluateJavaScript('window.__zenStop && window.__zenStop()');
    } catch (_) {}
  }

  void dispose() {
    _gen++;
    activeSong = null;
    try {
      _webview?.close();
    } catch (_) {}
    _webview = null;
    try {
      _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _pageUrl = null;
  }
}