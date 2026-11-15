// ZenMusic · vorlon-dev
//
// Community lossless mirrors (the Antra endpoint pool).
//
// These relays wrap Tidal / Deezer streaming APIs and hand out plain
// lossless audio (FLAC 16/44.1 up to 24/192) with no account of any kind
// on this side — that is exactly how Antra serves "Spotify without
// premium". The endpoints and the shared API key are published by the
// Antra project (github.com/anandprtp/Antra) in a public endpoint
// manifest; if they ever move, update the constants here.

class MirrorConfig {
  MirrorConfig._();

  static const String tidal = 'https://tidal.anandserver.cfd';
  static const String deezer = 'https://deezer.anandserver.cfd';

  /// Shared API key for the mirror pool (public Antra endpoint manifest).
  static const String apiKey = 'ak_8e3f1a7c2b5d9e4f0a6c3b8d1e5f2a9c7b4d0e6f';

  static const Map<String, String> jsonHeaders = {
    'X-API-Key': apiKey,
    'Accept': 'application/json',
    'User-Agent': 'ZenMusic/1.0 (lossless mirror)',
  };

  // Timeouts are deliberately tight: the mirror pool is an upgrade, never
  // a blocker. When the pool is unreachable the playback chain must fall
  // through (JioSaavn -> cache -> YouTube) within seconds, not minutes —
  // "song loads and loads but never plays" is exactly what these numbers
  // prevent. Tidal and Deezer searches also run in parallel, so a dead
  // pool costs ONE search window per track, not two.
  static const Duration searchTimeout = Duration(seconds: 4);
  static const Duration manifestTimeout = Duration(seconds: 6);
  static const Duration streamConnectTimeout = Duration(seconds: 8);

  /// CDN head probe (FLAC STREAMINFO duration check) per attempt.
  static const Duration probeTimeout = Duration(seconds: 6);

  /// Whole-resolution budget for one tryBuildSource call (search + manifest
  /// + probe across Tidal and Deezer). Once spent the chain falls through.
  static const Duration resolveBudget = Duration(seconds: 10);
}
