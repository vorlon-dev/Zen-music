// ZenMusic — YouTube Music login (SP-65, harvest reworked in SP-68).
// Cookie capture from a signed-in music.youtube.com session — the flow
// PixelMusic-class clients use: the user signs in inside an app-hosted
// webview, the session cookies are harvested automatically, validated
// against the authed home endpoint (YtmAuth.probeCookies), stored, and the
// window closes by itself. No code typing, no paste.
//
//   Windows — a REAL WebView2 window via desktop_webview_window (the same
//     plugin the Spotify engine already runs; the embedded InAppWebView is
//     an empty stub on this platform — SP-63). The 2 s harvest loop has
//     two capture tiers:
//       1. Webview.getAllCookies() — the NATIVE WebView2 cookie jar,
//         HttpOnly included. The SAPISID family is HttpOnly, so
//         document.cookie can NEVER see it; this native read is the only
//         path that can actually capture the session (the original
//         document.cookie-only loop waited forever and never auto-closed).
//       2. document.cookie — non-HttpOnly cookies, kept as a fallback.
//     A dedicated user-data folder (webview2-zen-login) keeps this
//     window's profile independent of the Spotify engine's (WebView2
//     locks the folder per-instance).
//   Other platforms — embedded InAppWebView + native CookieManager poll
//     (the proven Spotify-login pattern), document.cookie as fallback.
//
// Guard doctrine: the poll tick holds _busy; validation holds _validating
// exclusively (a validator must never test _busy — it is called from
// inside a tick that already holds it, and re-testing deadlocks the loop:
// exactly the SP-65 bug where "Sign-in detected" appeared but the window
// never closed). Tier errors never kill the loop — only a tick where BOTH
// tiers failed (a dead window handle) ends it, and "I signed in" restarts
// the poll.
//
// A cookie paste stays available in Settings -> YouTube Music for exotic
// cases. Google removed OAuth support from the YTM API (see ytm_auth.dart)
// — cookies are the only working path, so the SP-62 device-code UI is gone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/ytmusic/ytm_auth.dart';

class YtmLoginPage extends StatefulWidget {
  const YtmLoginPage({super.key});

  @override
  State<YtmLoginPage> createState() => _YtmLoginPageState();
}

class _YtmLoginPageState extends State<YtmLoginPage> {
  static const _musicUrl = 'https://music.youtube.com';

  Webview? _webview; // Windows: the real sign-in window.
  InAppWebViewController? _controller; // Other platforms: embedded webview.
  Timer? _poll;
  bool _busy = false; // held by one poll tick
  bool _validating = false; // held exclusively by session validation
  bool _done = false;
  bool _windowOpen = false;
  String? _status;

  /// The SAPISID family — any one of these proves a signed-in Google
  /// session (different Google surfaces set different variants).
  static final RegExp _sapisidFamily =
      RegExp(r'(?:^|;)[ ]*(?:SAPISID|__Secure-1PAPISID|__Secure-3PAPISID)=');

  bool _hasSapisidFamily(String cookie) => _sapisidFamily.hasMatch(cookie);

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      // Open the sign-in window as soon as the page is on screen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSignInWindow();
      });
    } else {
      // SPA navigation after sign-in does not always fire onLoadStop, so
      // poll — mirrors the Spotify embedded login.
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
    setState(() => _status = null);
    try {
      if (!await WebviewWindow.isWebviewAvailable()) {
        setState(() => _status =
            'WebView2 runtime unavailable on this PC — use "Use cookies '
            'instead" on the Settings tile.');
        return;
      }
      final docs = await getApplicationSupportDirectory();
      final wv = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'Sign in — YouTube Music',
          userDataFolderWindows: '${docs.path}/webview2-zen-login',
          openHidden: false,
        ),
      );
      _webview = wv;
      if (mounted) setState(() => _windowOpen = true);
      // launch() returns void on desktop_webview_window 0.3.x — a bare call,
      // exactly like the Spotify engine's. Awaiting it is a compile error
      // ("expression has type 'void'") — SP-65.1.
      wv.launch(_musicUrl);
      _poll ??= Timer.periodic(
          const Duration(seconds: 2), (_) => _harvestWindows());
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Could not open the sign-in window: $e');
      }
    }
  }

  Future<void> _harvestWindows() async {
    if (_done || _busy || !mounted) return;
    final wv = _webview;
    if (wv == null) return;
    _busy = true;
    var windowGone = false;
    try {
      // Tier 1 — the NATIVE WebView2 cookie jar via getAllCookies().
      // HttpOnly included: the SAPISID family only exists as HttpOnly
      // cookies, so this is the tier that actually sees a sign-in. Only
      // youtube.com cookies are folded into the blob (the jar also holds
      // unrelated domains from other windows sharing the machine).
      try {
        final all = await wv.getAllCookies();
        final buf = StringBuffer();
        for (final c in all) {
          if (!c.domain.contains('youtube.com')) continue;
          final v = c.value;
          if (v.isEmpty) continue;
          if (buf.isNotEmpty) buf.write('; ');
          buf.write('${c.name}=$v');
        }
        await _tryCookieBlob(buf.toString());
      } catch (e) {
        debugPrint('[ytm-login] getAllCookies tier error: $e');
        windowGone = true; // dead handle — tier 2 would fail identically
      }
      if (_done) return;
      // Tier 2 — document.cookie (non-HttpOnly cookies; kept as a
      // fallback in case a runtime ever fails the native manager).
      try {
        final raw = await wv.evaluateJavaScript('document.cookie');
        var cookie = raw?.toString() ?? '';
        if (cookie.startsWith('"')) {
          // The bridge returns the JS value JSON-encoded.
          try {
            cookie = jsonDecode(cookie) as String;
          } catch (_) {}
        }
        await _tryCookieBlob(cookie);
      } catch (e) {
        if (!windowGone) {
          debugPrint('[ytm-login] document.cookie tier error: $e');
          windowGone = true;
        }
      }
    } finally {
      _busy = false;
    }
    if (windowGone && !_done && mounted) {
      // BOTH tiers failed on the same tick — the window object is gone
      // (user closed it, or the OS did). Stop polling; the page offers
      // the reopen button instead of erroring forever.
      _poll?.cancel();
      _poll = null;
      _webview = null;
      setState(() {
        _windowOpen = false;
        _status = 'Sign-in window closed. Press "Open sign-in window" to '
            'try again, or use the cookie paste on the Settings tile.';
      });
    }
  }

  // ── Other platforms: embedded webview harvest ────────────────────────

  Future<void> _harvest() async {
    if (_done || _busy || !mounted) return;
    // 1. Native cookie jar (HttpOnly-safe on these platforms).
    try {
      final cookies =
          await CookieManager.instance().getCookies(url: WebUri(_musicUrl));
      final blob = cookies
          .where((c) => (c.value ?? '').isNotEmpty)
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      await _tryCookieBlob(blob);
      if (_done) return;
    } catch (e) {
      debugPrint('[ytm-login] CookieManager error: $e');
    }
    // 2. document.cookie fallback.
    try {
      final cookie = await _controller
          ?.evaluateJavascript(source: 'document.cookie') as String?;
      if (cookie != null && cookie.isNotEmpty) {
        await _tryCookieBlob(cookie);
      }
    } catch (_) {}
  }

  // ── Shared: validate + store + finish ────────────────────────────────

  Future<void> _tryCookieBlob(String cookie) async {
    if (_done || _validating) return;
    if (!_hasSapisidFamily(cookie)) return;
    _validating = true;
    try {
      if (mounted) {
        setState(() => _status = 'Sign-in detected — validating session…');
      }
      final err = await YtmAuth.instance.ingestCookies(cookie);
      if (!mounted) return;
      if (err != null) {
        setState(() => _status =
            '$err Keep the window open a moment — browse one page on '
            'YouTube Music, then wait here.');
        return;
      }
      _finish();
    } finally {
      _validating = false;
    }
  }

  void _finish() {
    _done = true;
    _poll?.cancel();
    _poll = null;
    try {
      _webview?.close();
    } catch (_) {}
    _webview = null;
    BottomMessage.showText(context, 'youtube music connected');
    context.pop();
  }

  void _checkAgain() {
    if (Platform.isWindows) {
      if (_windowOpen) {
        // SP-68: a one-shot check can miss — the session may land right
        // after the current tick passed. Restart the 2 s poll (it may
        // have died with a transient error) and run one check now.
        _poll ??= Timer.periodic(
            const Duration(seconds: 2), (_) => _harvestWindows());
        _harvestWindows();
      } else {
        _openSignInWindow();
      }
    } else {
      _harvest();
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login to YouTube Music'),
        actions: [
          TextButton(
            onPressed: _done ? null : _checkAgain,
            child: const Text('I signed in'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.withValues(alpha: 0.12),
            child: Text(
              _status ??
                  (Platform.isWindows
                      ? 'A sign-in window is opening. Sign in with your '
                          'Google account on music.youtube.com — this page '
                          'closes by itself once your session lands and '
                          'your home feed starts following your taste.'
                      : 'Sign in with your Google account in this window. '
                          'It closes by itself once your session lands, '
                          'and your home feed starts following your taste.'),
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
                        Icon(Icons.music_note_rounded,
                            size: 40, color: cs.primary),
                        const SizedBox(height: 12),
                        Text(
                          _windowOpen
                              ? 'Finish the sign-in in the YouTube Music '
                                  'window…'
                              : 'Open the YouTube Music sign-in window',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in with your Google account exactly like on '
                          'the website. When music.youtube.com shows you as '
                          'signed in, ZenMusic captures the session '
                          'automatically and closes the window.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed:
                              _done ? null : (_windowOpen ? null : _openSignInWindow),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(_windowOpen
                              ? 'Sign-in window is open'
                              : 'Open sign-in window'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No window? Press "I signed in" to re-check, or '
                          'reopen it. A manual cookie paste is available '
                          'under Settings → YouTube Music → "Use cookies '
                          'instead".',
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
                initialUrlRequest: URLRequest(url: WebUri(_musicUrl)),
                initialSettings: InAppWebViewSettings(
                  userAgent:
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/155.0.0.0 Safari/537.36',
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
                  await _harvest();
                },
              ),
            ),
        ],
      ),
    );
  }
}
