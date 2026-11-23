// ZenMusic · vorlon-dev
//
// Community lossless mirrors (the Antra endpoint pool).
//
// These relays wrap Tidal / Qobuz / Deezer streaming APIs and hand out
// plain lossless audio (FLAC 16/44.1 up to 24/192) with no account of any
// kind on this side. The endpoint hosts and the shared API key are
// published by the Antra project (github.com/anandprtp/Antra) in a public
// endpoint manifest (a GitHub gist); the constants below are the bundled
// fallback and are refreshed from that manifest at runtime, so if the
// pool ever moves hosts this app follows without a rebuild.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier;

class MirrorConfig {
  MirrorConfig._();

  // ------------------------------------------------------------- hosts
  //
  // Mutable (not const) because the Antra manifest refresh updates them
  // in place. The bundled values mirror the published manifest and keep
  // the pool working even if the gist is unreachable on first launch.

  static String tidalHost = 'https://tidal.anandserver.cfd';
  static String qobuzHost = 'https://qobuz.anandserver.cfd';
  static String deezerHost = 'https://deezer.anandserver.cfd';

  /// Shared API key for the mirror pool (public Antra endpoint manifest).
  ///
  /// FIX (Nov 2026): the previous bundled key (ak_8e3f...0e6f) was RETIRED by
  /// the pool — every search returned HTTP 403 "This key has been retired",
  /// which silently killed the whole Dart mirror engine. This value is the
  /// key the live manifest gist publishes today; refreshFromManifest() keeps
  /// it current from runtime onwards (wired into main.dart and the mirror
  /// engine itself), so the next rotation can never strand the app again.
  static String apiKey = 'ak_4430c4405da2e71d0f5180380dbd497295a0360e';

  // Legacy aliases (older code paths referenced `tidal` / `deezer`).
  static String get tidal => tidalHost;
  static String get deezer => deezerHost;
  static String get qobuz => qobuzHost;

  static Map<String, String> get jsonHeaders => {
    'X-API-Key': apiKey,
    'Accept': 'application/json',
    'User-Agent': 'ZenMusic/1.0 (lossless mirror)',
  };

  /// True for loopback-passthrough targets that must carry the shared key
  /// (the mirrors' own /api/stream relays live under these hosts; the raw
  /// CDN URLs they hand out are self-signed and need no key).
  static bool hostNeedsApiKey(String url) {
    try {
      return Uri.parse(url).host.endsWith('anandserver.cfd');
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------- timeouts
  //
  // The mirror pool is an upgrade, never a blocker: every number here is
  // chosen so the play chain (JioSaavn -> cache -> YouTube) takes over
  // within seconds when the pool is slow or dead.
  //
  // Measured from a datacenter connection (2026-11-15): tidal search ~1 s,
  // deezer search ~1 s, qobuz search 1.3-5.5 s, manifests 0.7-4 s, CDN
  // head probes < 1 s. Qobuz is the slowest endpoint by far but also the
  // only one that serves 24-bit masters, so it gets its own generous
  // window and runs in parallel from the very start.

  static const Duration searchTimeoutTidal = Duration(seconds: 5);
  static const Duration searchTimeoutDeezer = Duration(seconds: 5);
  static const Duration searchTimeoutQobuz = Duration(seconds: 10);
  static const Duration manifestTimeout = Duration(seconds: 6);
  static const Duration streamConnectTimeout = Duration(seconds: 8);
  static const Duration probeTimeout = Duration(seconds: 6);

  /// Budget for the whole background resolution (search + manifest + probe
  /// across all three mirrors). Background work has no UI waiting on it.
  static const Duration backgroundBudget = Duration(seconds: 25);

  /// Budget for the AWAITED play path. The player wraps this layer with an
  /// 8 s hard timeout, so 7.5 s guarantees the layer answers (source or
  /// null) before that external cap — anything slower would just be cut
  /// off without our caches having been filled.
  static const Duration awaitedBudget = Duration(milliseconds: 7500);

  // ------------------------------------------------- manifest refresh

  /// The public Antra endpoint manifest (hosts + shared API key).
  static const String manifestUrl =
      'https://gist.githubusercontent.com/anandprtp/fdc2c16b7bfdc2d337fbc86161b79371/raw';

  /// Bumps whenever the runtime endpoints change so listeners can react.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static const Duration _refreshInterval = Duration(minutes: 15);
  static DateTime? _lastRefreshAttempt;

  /// Refresh the endpoint hosts + API key from the Antra manifest gist.
  /// Cadence-guarded (at most one real fetch per [_refreshInterval]),
  /// never throws, never blocks long (6 s worst case) — callers fire and
  /// forget it. Bundled constants stay untouched on any failure.
  ///
  /// [force] bypasses the cadence guard: the mirror engine passes true when
  /// a host answers 401/403 (retired key) so the very next resolve attempt
  /// already carries the fresh key instead of failing for up to 15 minutes.
  static Future<void> refreshFromManifest({bool force = false}) async {
    final now = DateTime.now();
    final last = _lastRefreshAttempt;
    if (!force && last != null && now.isBefore(last.add(_refreshInterval))) {
      return;
    }
    _lastRefreshAttempt = now;

    // A concurrent forced refresh must not double-fetch: serialize on the
    // same future so overlapping callers await one network round-trip.
    _refreshing ??= _refreshNow();
    try {
      await _refreshing;
    } finally {
      // Allow later refreshes once the in-flight one settles. A forced call
      // always leaves the cadence stamp updated above, so cadence still
      // applies to non-forced callers that arrive after it completes.
      _refreshing = null;
    }
  }

  static Future<void>? _refreshing;

  static Future<void> _refreshNow() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client
          .getUrl(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 6));
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != HttpStatus.ok) return;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4), onTimeout: () => '');
      if (body.isEmpty) return;
      final data = jsonDecode(body);
      if (data is! Map) return;
      final mirrors = data['mirrors'];
      var changed = false;
      String? cleanUrl(dynamic raw) {
        final s = '${raw ?? ''}'.trim();
        if (s.isEmpty) return null;
        final withScheme =
        s.startsWith('http://') || s.startsWith('https://') ? s : 'https://$s';
        try {
          final uri = Uri.parse(withScheme);
          if (!uri.host.contains('.')) return null;
          return withScheme.endsWith('/')
              ? withScheme.substring(0, withScheme.length - 1)
              : withScheme;
        } catch (_) {
          return null;
        }
      }

      if (mirrors is Map) {
        final t = cleanUrl(mirrors['tidal']);
        final q = cleanUrl(mirrors['qobuz']);
        final d = cleanUrl(mirrors['deezer']);
        if (t != null && t != tidalHost) {
          tidalHost = t;
          changed = true;
        }
        if (q != null && q != qobuzHost) {
          qobuzHost = q;
          changed = true;
        }
        if (d != null && d != deezerHost) {
          deezerHost = d;
          changed = true;
        }
      }
      final key = '${data['api_key'] ?? ''}'.trim();
      if (key.isNotEmpty && key != apiKey) {
        apiKey = key;
        changed = true;
      }
      if (changed) {
        print('[mirror] endpoints refreshed from Antra manifest');
        revision.value++;
      }
    } catch (e) {
      print('[mirror] manifest refresh failed (keeping bundled endpoints): $e');
    } finally {
      client?.close(force: true);
    }
  }
}
