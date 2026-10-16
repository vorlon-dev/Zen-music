// ZenMusic — embedded spotify login (SP-1b). FRESH implementation.
// FIX: sp_dc is an HttpOnly cookie, so document.cookie can NEVER see it —
// the old harvest always fell through and no session was stored (-> "no
// access token (not logged in?)"). The cookie is now read with the
// native CookieManager, which can read HttpOnly cookies.
// Flow: CookieManager poll (every 2 s + after every page event) -> sp_dc ->
// SpotifyAuth.login(). The JS fetch hook stays as a fallback that only
// ingests a short-lived Bearer token (no refresh without sp_dc).
// Auto-closes when the session lands; SpotifyAuth TOTP stays as refresher.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';

class SpotifyLoginPage extends StatefulWidget {
  const SpotifyLoginPage({super.key});

  @override
  State<SpotifyLoginPage> createState() => _SpotifyLoginPageState();
}

class _SpotifyLoginPageState extends State<SpotifyLoginPage> {
  static final WebUri _spotifyUrl = WebUri('https://open.spotify.com');

  InAppWebViewController? _controller;
  Timer? _poll;
  bool _done = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // SPA navigation after login does not always fire onLoadStop, so poll.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _harvest());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

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
          debugPrint('[zen-login] bearer token captured via fetch hook');
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

  Future<void> _finishLogin(String spDcCookie) async {
    final err = await SpotifyAuth.instance.login(spDcCookie);
    if (!mounted) return;
    if (err == null) {
      _done = true;
      _poll?.cancel();
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
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _harvest());
    _harvest();
  }

  @override
  Widget build(BuildContext context) {
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
                  'Log in with your spotify account. This window closes '
                      'automatically once the session is captured.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
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

                // Fetch hook: stash fresh auth headers into window scope.
                await controller.evaluateJavascript(source: '''
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
''');

                await _harvest();
              },
            ),
          ),
        ],
      ),
    );
  }
}