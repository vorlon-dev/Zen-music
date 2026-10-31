// ZenMusic — spotify login (SP-1b; Windows path rebuilt in SP-66).
// HISTORY:
//   SP-1b — embedded InAppWebView + native CookieManager harvest (sp_dc is
//     an HttpOnly cookie, so document.cookie can NEVER see it — the native
//     CookieManager can). Bearer fetch-hook stays as a degraded fallback.
//   SP-63 — the Windows build ships an EMPTY in_app_webview platform impl
//     (pubspec override flutter_inappwebview_windows_fx ->
//     windows_webview_stub), so the embedded path crashed there and this
//     page degraded to the "Embedded sign-in is not available on Windows"
//     card. GUI sign-in died on Windows.
//   SP-66 — Windows gets a REAL sign-in window again, via
//     desktop_webview_window — the same plugin the playback engine
//     (webview2-zen-engine) and the SP-65 YTM login already run. sp_dc is
//     captured with Webview.getAllCookies(), implemented in the plugin's
//     Windows code through ICoreWebView2CookieManager::GetCookies — the
//     only API in this stack that reads HttpOnly cookies. Flow mirrors the
//     YTM login: sign in inside the window; the page detects the session,
//     validates it by minting a token (SpotifyAuth.login), and closes the
//     window by itself.
//
// Capture tiers on Windows (first hit wins):
//   1. Webview.getAllCookies() — HttpOnly-safe, the real path.
//   2. document.cookie         — belt-and-suspenders for exotic runtimes.
//   3. Bearer fetch hook       — short-lived token only (no refresh).
// Non-Windows keeps the proven embedded flow untouched.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';

class SpotifyLoginPage extends StatefulWidget {
  const SpotifyLoginPage({super.key});

  @override
  State<SpotifyLoginPage> createState() => _SpotifyLoginPageState();
}

class _SpotifyLoginPageState extends State<SpotifyLoginPage> {
  static final WebUri _spotifyUrl = WebUri('https://open.spotify.com');
  static const _spotifyLaunchUrl = 'https://open.spotify.com';

  // Same hook the embedded branch injects in onLoadStop — but on the
  // standalone window it must be registered BEFORE launch so the very
  // first document is hooked (sign-in pages fire authed fetches early).
  static const String _kFetchHook = '''
(function(){
  if (window.__zenHooked) return;
  window.__zenHooked = true;
  window.__zenTokens = window.__zenTokens || {};
  var oriFetch = window.fetch.bind(window);
  window.fetch = function(){
    try {
      var url = arguments[0], opts = arguments[1] || {};
      var us = (typeof url === 'string') ? url : (url && url.url) || '';
      var hs = opts.headers || {};
      function hv(n){ try { return hs.get ? hs.get(n) : (hs[n] || hs[n.toLowerCase()]); } catch(e){ return null; } }
      var au = hv('Authorization') || hv('authorization');
      var ct = hv('Client-Token') || hv('client-token');
      if (au && au.indexOf('Bearer BQ') === 0) {
        window.__zenTokens.token = au.replace('Bearer ', '').trim();
      }
      if (ct) {
        window.__zenTokens.clientToken = ct;
      }
    } catch(e){}
    return oriFetch.apply(this, arguments);
  };
})();
''';

  Webview? _webview; // Windows: the real sign-in window.
  InAppWebViewController? _controller; // Other platforms: embedded webview.
  Timer? _poll;
  bool _done = false;
  bool _busy = false;
  bool _windowOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      // Open the sign-in window as soon as the page is on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSignInWindow();
      });
    } else {
      // SPA navigation after login does not always fire onLoadStop, so poll.
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _harvest());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _poll = null;
    try {
      _webview?.close();
    } catch (_) {}
    _webview = null;
    super.dispose();
  }

  // ── Windows: WebView2 sign-in window ─────────────────────────────────

  Future<void> _openSignInWindow() async {
    if (_done || _windowOpen) return;
    setState(() => _error = null);
    try {
      if (!await WebviewWindow.isWebviewAvailable()) {
        setState(() => _error =
            'WebView2 runtime unavailable on this PC — use "Use cookies '
            'instead" under Settings -> Spotify.');
        return;
      }
      final docs = await getApplicationSupportDirectory();
      final wv = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'Sign in — Spotify',
          // Dedicated folder: WebView2 locks the user-data folder per
          // instance, so this must differ from the playback engine's
          // (webview2-zen-engine) and the YTM login's (webview2-zen-login).
          userDataFolderWindows: '${docs.path}/webview2-zen-spotify-login',
          openHidden: false,
        ),
      );
      _webview = wv;
      if (mounted) setState(() => _windowOpen = true);
      // Tier-3 net before launch: hook fetch so the first document is
      // covered (register-then-launch order matters).
      wv.addScriptToExecuteOnDocumentCreated(_kFetchHook);
      // launch() returns void on desktop_webview_window 0.3.x — a bare
      // call, exactly like the engine's. Awaiting it is a compile error
      // ("expression has type 'void'") — the SP-65.1 lesson.
      wv.launch(_spotifyLaunchUrl);
      _poll ??= Timer.periodic(
          const Duration(seconds: 2), (_) => _harvestWindows());
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open the sign-in window: $e');
      }
    }
  }

  void _closeWindow() {
    try {
      _webview?.close();
    } catch (_) {}
    _webview = null;
  }

  Future<void> _harvestWindows() async {
    if (_done || _busy || !mounted) return;
    final wv = _webview;
    if (wv == null) return;
    _busy = true;
    try {
      // Tier 1: the REAL cookie jar — HttpOnly included. sp_dc only exists
      // once sign-in completes, so its presence IS the signed-in signal.
      try {
        final cookies = await wv.getAllCookies();
        for (final c in cookies) {
          if (c.name == 'sp_dc' && c.value.length >= 20) {
            await _finishLogin('sp_dc=${c.value}');
            return;
          }
        }
      } catch (e) {
        debugPrint('[zen-login] getAllCookies error: $e');
      }

      // Tier 2: document.cookie (in case a runtime ever fails the manager).
      try {
        final raw =
            await wv.evaluateJavaScript('document.cookie') as String?;
        var cookie = raw?.toString() ?? '';
        if (cookie.startsWith('"')) {
          // The bridge returns the JS value JSON-encoded.
          try {
            cookie = jsonDecode(cookie) as String;
          } catch (_) {}
        }
        final m = RegExp(r'sp_dc=([^;\s]{20,})').firstMatch(cookie);
        if (m != null) {
          await _finishLogin('sp_dc=${m.group(1)}');
          return;
        }
      } catch (_) {}

      // Tier 3: Bearer token stashed by the fetch hook. No sp_dc -> no
      // refresh; ~1 h of playable tokens. Kept for parity with the
      // embedded flow's fallback.
      //
      // WebView2's ExecuteScript returns the JS value JSON-ENCODED, so
      // JSON.stringify's string arrives double-wrapped ('"{\"token\":…}"').
      // Unwrap once, then decode — and GUARD the whole tier: an unguarded
      // cast here crashed every poll tick ("String is not a subtype of
      // Map"), killed the loop, and the window could never auto-close
      // (SP-66.1). A tier failing must never take the poll down.
      try {
        var tokensJson = await wv.evaluateJavaScript(
            'JSON.stringify(window.__zenTokens || {})') as String?;
        if (tokensJson != null && tokensJson.startsWith('"')) {
          // Unwrap the bridge's outer JSON encoding.
          try {
            final unwrapped = jsonDecode(tokensJson);
            if (unwrapped is String) tokensJson = unwrapped;
          } catch (_) {}
        }
        if (tokensJson != null && tokensJson != 'null') {
          final decoded = jsonDecode(tokensJson);
          if (decoded is Map) {
            final token = decoded['token']?.toString() ?? '';
            if (token.startsWith('BQ')) {
              _done = true;
              _poll?.cancel();
              _closeWindow();
              await SpotifyAuth.instance.ingestAccessToken(token);
              if (mounted) {
                BottomMessage.showText(context, 'spotify connected');
                context.pop();
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[zen-login] token hook error: $e');
      }
    } catch (e) {
      // The window was closed (user or system) — the object handle is dead.
      debugPrint('[zen-login] webview window gone: $e');
      _poll?.cancel();
      _poll = null;
      _webview = null;
      if (mounted) {
        setState(() {
          _windowOpen = false;
          _error = 'Sign-in window closed. Press "Open sign-in window" to '
              'try again, or use the cookie paste under Settings -> '
              'Spotify.';
        });
      }
    } finally {
      _busy = false;
    }
  }

  // ── Other platforms: embedded webview harvest (unchanged since SP-1b) ─

  /// HttpOnly-safe: reads the cookie jar natively, not via JavaScript.
  Future<String?> _readSpDc() async {
    try {
      final cookies =
      await CookieManager.instance().getCookies(url: _spotifyUrl);
      for (final c in cookies) {
        final v = '${c.value ?? ''}';
        if (c.name == 'sp_dc' && v.length >= 20) return v;
      }
    } catch (e) {
      debugPrint('[zen-login] CookieManager error: $e');
    }
    // Fallback for platforms where the jar is not exposed.
    try {
      final cookie = await _controller
          ?.evaluateJavascript(source: 'document.cookie') as String?;
      final m = RegExp(r'sp_dc=([^;\s]{20,})').firstMatch(cookie ?? '');
      if (m != null) return m.group(1);
    } catch (_) {}
    return null;
  }

  Future<void> _harvest() async {
    if (_done || _busy || !mounted) return;
    _busy = true;
    try {
      // 1. sp_dc cookie -> full login (refreshable session).
      final spDc = await _readSpDc();
      debugPrint('[zen-login] sp_dc: ${spDc == null ? "not yet" : "FOUND"}');
      if (spDc != null) {
        await _finishLogin('sp_dc=$spDc');
        return;
      }

      // 2. Fallback: Bearer token stashed by the fetch hook.
      final tokensJson = await _controller?.evaluateJavascript(
          source: 'JSON.stringify(window.__zenTokens || {})') as String?;
      if (tokensJson != null && tokensJson != 'null') {
        final t = jsonDecode(tokensJson) as Map;
        final token = t['token']?.toString() ?? '';
        if (token.startsWith('BQ')) {
          _done = true;
          _poll?.cancel();
          await SpotifyAuth.instance.ingestAccessToken(token);
          if (mounted) {
            BottomMessage.showText(context, 'spotify connected');
            context.pop();
          }
        }
      }
    } catch (e) {
      debugPrint('[zen-login] harvest error: $e');
    } finally {
      _busy = false;
    }
  }

  // ── Shared: validate + store + finish ────────────────────────────────

  Future<void> _finishLogin(String spDcCookie) async {
    final err = await SpotifyAuth.instance.login(spDcCookie);
    if (!mounted) return;
    if (err == null) {
      _done = true;
      _poll?.cancel();
      _closeWindow();
      BottomMessage.showText(context, 'spotify connected');
      context.pop();
    } else {
      debugPrint('[zen-login] SpotifyAuth.login failed: $err');
      _poll?.cancel(); // do not hammer login with the same bad cookie
      setState(() => _error = err);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _poll?.cancel();
    _poll = null;
    if (Platform.isWindows) {
      if (_windowOpen) {
        // Window alive: RESTART the poll, not a one-shot check — a single
        // shot starves the loop after any early error (SP-66.1).
        _poll = Timer.periodic(
            const Duration(seconds: 2), (_) => _harvestWindows());
        _harvestWindows();
      } else {
        _openSignInWindow();
      }
    } else {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _harvest());
      _harvest();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to spotify'),
        actions: [
          TextButton(
            onPressed: _done ? null : _retry,
            child: const Text('I logged in'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.deepPurple.withValues(alpha: 0.15),
            child: Text(
              _error ??
                  (Platform.isWindows
                      ? 'A sign-in window is opening. Sign in with your '
                          'Spotify account on open.spotify.com — this page '
                          'closes by itself once your session lands.'
                      : 'Log in with your spotify account. This window closes '
                          'automatically once the session is captured.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (Platform.isWindows)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.graphic_eq_rounded,
                            size: 40, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(
                          _windowOpen
                              ? 'Finish the sign-in in the Spotify window…'
                              : 'Open the Spotify sign-in window',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in exactly like on the website. When '
                          'open.spotify.com shows you as signed in, ZenMusic '
                          'captures the session automatically (the sp_dc '
                          'cookie, HttpOnly included) and closes the window.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _done
                              ? null
                              : (_windowOpen ? null : _openSignInWindow),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(_windowOpen
                              ? 'Sign-in window is open'
                              : 'Open sign-in window'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No window? Press "I logged in" to re-check, or '
                          'reopen it. A manual cookie paste is still '
                          'available under Settings -> Spotify -> "Use '
                          'cookies instead".',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: _spotifyUrl),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36',
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                ),
                onWebViewCreated: (c) => _controller = c,
                onUpdateVisitedHistory: (controller, url, isReload) {
                  _controller = controller;
                  _harvest();
                },
                onLoadStop: (controller, url) async {
                  _controller = controller;
                  await controller.evaluateJavascript(
                      source: _kFetchHook);
                  await _harvest();
                },
              ),
            ),
        ],
      ),
    );
  }
}
