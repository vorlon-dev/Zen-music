// ZenMusic · vorlon-dev
//
// Instagram reel canvas — configuration constants.
//
// SELF-CONTAINED: this folder is the whole feature. Endpoints live here
// only — nothing is hardcoded elsewhere. The canvas is ALWAYS found from
// the song itself (its title + artist): the search builds related-tag
// queries per song (song videos / edits / dance videos) — there is no
// fixed keyword list anywhere.
//
// Put at: lib/desktop/instagram_canvas/instagram_canvas_config.dart

class InstagramCanvasConfig {
  InstagramCanvasConfig._();

  // ── Master switch ──────────────────────────────────────────────────────
  /// Set false to disable the whole feature (every call returns null fast).
  static const bool enabled = true;

  // ── Self-hosted reel resolver service ─────────────────────────────────
  /// The user-deployed instagram-video-scraper instance (v2, keyless embed
  /// resolve, no browser needed). Endpoints:
  ///   GET /api/video?url={ig post url}  -> { videoUrl, source }
  ///   GET /api/stream?url={ig post url} -> raw video bytes (Range capable)
  ///   GET /api/diag                     -> environment report
  static const String serviceBaseUrl =
      'https://freeloveduck.antideploy.app/';

  /// Playback through the service's Range-capable stream proxy (recommended:
  /// the server resolves the reel and pipes the bytes, so IP-locked CDN
  /// signatures can never break playback). When false, the direct CDN mp4
  /// returned by /api/video is played instead (fewer server bytes, but the
  /// signature may refuse to play from the device's IP).
  static const bool preferProxyPlayback = true;

  /// Timeout for one /api/video validation call.
  static const Duration serviceTimeout = Duration(seconds: 10);

  // ── Service-side discovery (recommended) ──────────────────────────────
  /// The deployed service (v3) also exposes GET /api/search?q={query} which
  /// runs the SAME per-song engine search from the server's own IP (usually
  /// far cleaner than a phone's) and caches per query for 30 minutes. The
  /// app tries this first for every query and falls back to its on-device
  /// engines whenever the service is down / empty.
  static const bool serviceSearchEnabled = true;

  /// Timeout for one /api/search call.
  static const Duration serviceSearchTimeout = Duration(seconds: 12);

  // ── Reel discovery: per-song related-tag queries ──────────────────────
  /// For every song the finder builds several search queries from the song
  /// itself, one per reel category the song could have on Instagram:
  ///   "<song> <artist> edit"          (fan edits)
  ///   "<song> <artist> song video"    (song videos)
  ///   "<song> <artist> dance video"   (dance videos)
  ///   "<song> <artist>"               (plain — anything the song is tagged in)
  /// plus title-only variants when the artist name is noisy. Every query is
  /// derived from THIS song — no fixed keywords, no preset reel list.
  ///
  /// `site:instagram.com/reel` is always prepended so engines return only
  /// public Instagram reel pages. Two unquoted variants per song are also
  /// included — engines that drop the site: operator still see the domain
  /// words plus the song.
  static const int maxDiscoveryQueries = 8;

  /// Search engines tried per query, in order (Bing returns real HTML on
  /// clean networks; DDG html/lite are fallbacks). All queries run in
  /// parallel — each engine failure just yields fewer candidates.
  static const String bingSearchUrl = 'https://www.bing.com/search?q={query}&count=20';
  static const String ddgHtmlSearchUrl = 'https://html.duckduckgo.com/html/?q={query}';
  static const String ddgLiteSearchUrl = 'https://lite.duckduckgo.com/lite/?q={query}';

  /// Per-engine request timeout.
  static const Duration searchTimeout = Duration(seconds: 7);

  /// Whole discovery stage budget (all queries and engines together).
  static const Duration discoveryBudget = Duration(seconds: 20);

  /// Minimum fuzzy score (0-100) between the song and a candidate's result
  /// text. A wrong-song reel is worse than no reel.
  static const int minReelScore = 55;

  /// A query stops trying more engines once it has this many candidates.
  static const int candidatesPerQuery = 3;

  /// Maximum candidates kept from discovery (top-scored).
  static const int maxReelCandidates = 6;

  /// How many of the top candidates actually get resolved/validated.
  static const int maxReelResolutions = 3;

  /// Whole reel stage budget (discovery + validations together).
  static const Duration reelStageBudget = Duration(seconds: 30);

  // ── Cache ──────────────────────────────────────────────────────────────
  /// Successful resolutions live in memory for this long.
  static const Duration cacheTtl = Duration(hours: 4);

  /// After a total miss, the song is not retried for this long.
  static const Duration negativeCooldown = Duration(minutes: 3);

  /// Maximum songs remembered (LRU-ish trim).
  static const int maxCacheEntries = 96;
}