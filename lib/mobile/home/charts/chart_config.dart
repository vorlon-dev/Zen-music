// ZenMusic · vorlon-dev
//
// MusicMetrics chart configuration — MOBILE home only.
//
// Every external endpoint used by the mobile MusicMetrics charts lives HERE
// and only here (no chart URL is ever hardcoded inside logic), following the
// app's config-constants rule. Change the values below and the whole chart
// stack follows.
//
// Charts shown on the mobile Echo home (in this exact order):
//   Global 200 / YouTube / Apple Music / iTunes / Deezer /
//   Spotify (user's region, detected from IP) / Top Albums.

/// The charts the mobile Echo home shows, in the order the user asked for.
enum MusicChartId {
  global,
  youtube,
  appleMusic,
  itunes,
  deezer,
  spotify,
  albums,
}

class ChartConfig {
  ChartConfig._();

  // ── MusicMetrics endpoints ────────────────────────────────────────────────
  static const String musicMetricsBase = 'https://musicmetrics.net';
  static const String globalChartPath = '/charts/global/';
  static const String youtubeChartPath = '/charts/youtube/';
  static const String appleMusicChartPath = '/charts/apple-music/';
  static const String itunesChartPath = '/charts/itunes/';
  static const String deezerChartPath = '/charts/deezer/';

  /// Regional Spotify charts live under /charts/spotify/{country}/
  /// e.g. /charts/spotify/in/ — the {country} part comes from the user's IP.
  static const String spotifyCountryBasePath = '/charts/spotify/';
  static const String albumsChartPath = '/charts/albums/';

  // ── IP → country lookup (keyless, in priority order) ──────────────────────
  // The Spotify chart follows the user's IP/location; the first endpoint that
  // answers within the timeout wins, then the device region, then the
  // fallback below.
  static const List<String> geoLookupUrls = [
    'https://ipwho.is/',
    'https://freeipapi.com/api/json',
    'https://ipapi.co/json/',
  ];
  static const String fallbackRegion = 'in';

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  // ── Behaviour ─────────────────────────────────────────────────────────────
  /// Per-chart HTTP timeout. A slow chart NEVER blocks the home — the shelf
  /// simply stays on its skeleton or keeps showing cached rows.
  static const Duration fetchTimeout = Duration(seconds: 12);
  static const Duration geoTimeout = Duration(seconds: 5);

  /// In-memory throttle so scrolling home does not re-fetch a chart that was
  /// just fetched. Pull-to-refresh bypasses this.
  static const Duration refetchThrottle = Duration(minutes: 10);

  /// How long the detected region (IP → country code) is remembered.
  static const Duration regionCacheTtl = Duration(hours: 24);

  /// Rows kept per chart shelf (MusicMetrics pages carry 20–50 rows; the
  /// mobile shelf stays light).
  static const int maxRowsPerChart = 30;

  /// Songs resolved when tapping "Play all" on a chart shelf.
  static const int playAllLimit = 15;

  // ── Disk cache (Hive SETTINGS box, same box the home feed cache uses) ─────
  static const String hiveBox = 'SETTINGS';
  static const String cacheKeyPrefix = 'MM_CHART_';
  static const String regionCacheKey = 'MM_CHART_REGION';

  /// Shelf order on the mobile home — exactly the list the user asked for.
  static const List<MusicChartId> homeChartOrder = [
    MusicChartId.global,
    MusicChartId.youtube,
    MusicChartId.appleMusic,
    MusicChartId.itunes,
    MusicChartId.deezer,
    MusicChartId.spotify,
    MusicChartId.albums,
  ];
}

/// Short shelf titles (Echo-style uppercase section titles are applied by the
/// UI). The Spotify shelf appends the detected country, e.g. "Spotify · India".
extension MusicChartIdTitle on MusicChartId {
  String get shortTitle => switch (this) {
        MusicChartId.global => 'Global 200',
        MusicChartId.youtube => 'YouTube Music',
        MusicChartId.appleMusic => 'Apple Music',
        MusicChartId.itunes => 'iTunes',
        MusicChartId.deezer => 'Deezer',
        MusicChartId.spotify => 'Spotify',
        MusicChartId.albums => 'Top Albums',
      };
}
