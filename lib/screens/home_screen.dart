import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/appearance_prefs.dart';
import '../services/downloads_service.dart';
import '../services/home_service.dart';
import '../services/update_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/collection_card.dart';
import '../widgets/marquee.dart';
import '../widgets/media_shelf.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/skeleton.dart';
import '../widgets/welcome_dialog.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/zen_nav_bar.dart';
import '../widgets/youtube_thumbnail.dart';
import 'collection_screen.dart';
import 'equalizer_screen.dart';
import 'history_screen.dart';
import 'import_spotify_screen.dart';
import 'liked_songs_screen.dart';
import 'listen_together_screen.dart';
import 'player_screen.dart';
import 'radio_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'user_playlist_screen.dart';
import 'video_watch_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  // Nav bar auto-hide: hides when the user scrolls a vertical list
  // down, returns on scroll-up or at any list's top. The
  // NotificationListener catches vertical scroll notifications
  // bubbling up from ALL tabs (horizontal shelf swipes are ignored
  // via the axis filter).
  bool _navVisible = true;

  @override
  void initState() {
    super.initState();
    // Default open tab from Appearance settings (applies on launch).
    AppearancePrefs.load().then((_) {
      if (!mounted) return;
      final tab = AppearancePrefs.defaultTab.value;
      setState(() => _currentTab = tab < 0 ? 0 : (tab > 2 ? 2 : tab));
    });

    // First-launch welcome + OTA update check, after the first frame
    // AND after the first build completes, so showDialog has a valid
    // Navigator and the dialog is never lost to a lifecycle race.
    // Welcome shows first; the update check runs after it is dismissed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await WelcomeDialog.maybeShow(context);
      if (!mounted) return;
      await UpdateService.instance.checkOnLaunch(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      // extendBody: the body scrolls BEHIND the floating mini player +
      // nav bar — no slot rectangle behind them.
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: (n) {
          // Vertical lists only — horizontal shelf swipes must not
          // flicker the bar.
          if (n.metrics.axis != Axis.vertical) return false;
          // At the top of any list the bar is always visible.
          if (n.metrics.pixels <= 0) {
            if (!_navVisible && mounted) setState(() => _navVisible = true);
            return false;
          }
          // Only EXPLICIT directions change state. IDLE (finger
          // release / fling settle) KEEPS the current state.
          if (n.direction == ScrollDirection.reverse) {
            if (_navVisible && mounted) setState(() => _navVisible = false);
          } else if (n.direction == ScrollDirection.forward) {
            if (!_navVisible && mounted) setState(() => _navVisible = true);
          }
          return false;
        },
        child: _TabStack(
          index: _currentTab,
          children: const [
            HomeTab(),
            SearchScreen(),
            LibraryTab(),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          ZenNavBar(
            visible: _navVisible,
            items: const [
              ZenNavItem(
                icon: FluentIcons.home_24_regular,
                activeIcon: FluentIcons.home_24_filled,
                label: 'Home',
              ),
              ZenNavItem(
                icon: FluentIcons.search_24_regular,
                activeIcon: FluentIcons.search_24_filled,
                label: 'Search',
              ),
              ZenNavItem(
                icon: FluentIcons.library_24_regular,
                activeIcon: FluentIcons.library_24_filled,
                label: 'Library',
              ),
            ],
            currentIndex: _currentTab,
            onTap: (i) {
              if (i == _currentTab) return;
              setState(() => _currentTab = i);
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SLIDING TAB STACK — state-preserving IndexedStack replacement.
// Every tab stays mounted (scroll positions / data kept); tabs slide
// horizontally with AnimatedSlide (320ms ease). Adjacent tabs stay
// painted during the slide; far tabs are offstage. Non-active tabs
// ignore pointers; their tickers are disabled to save battery.
// ═════════════════════════════════════════════

class _TabStack extends StatelessWidget {
  final int index;
  final List<Widget> children;

  const _TabStack({required this.index, required this.children});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          AnimatedSlide(
            offset: Offset((i - index).toDouble().clamp(-1.0, 1.0), 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            child: Offstage(
              offstage: (i - index).abs() > 1,
              child: TickerMode(
                enabled: i == index,
                child: IgnorePointer(
                  ignoring: i != index,
                  child: children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// HOME TAB — Spotify layout on the Black + Oxblood theme, with
// ZenMusic's own polish:
//   · subtle oxblood wash at the top (one DecoratedBox — delete for
//     a flat home)
//   · tick-rule section titles
//   · the breathing Liked-Songs heart
// Sections: greeting → shortcut tiles → Made for you → New releases
// → Playlists for you → Videos → trending shelves → charts.
// ═════════════════════════════════════════════

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with TickerProviderStateMixin {
  final _homeService = HomeService();
  final _scroll = ScrollController();

  List<Song> _trendingNow = [];
  List<Song> _biggestHits = [];
  List<Song> _ytTrending = [];
  List<Song> _ytmHot = [];
  List<Song> _personalVideos = [];
  List<Song> _topCharts = [];
  List<Song> _recentlyPlayed = [];
  List<Song> _ytmFresh = [];
  List<Song> _recommendedToday = [];
  List<Collection> _collections = [];
  List<Collection> _newAlbums = [];
  List<Song> _downloads = [];

  // Infinite append state — dynamic YTM chart shelves.
  final List<({String title, List<Song> songs})> _chartShelves = [];
  final Set<String> _shownSongIds = {};
  bool _loadingMore = false;
  bool _endReached = false;
  int _failedFetches = 0;

  bool _loading = true;
  bool _isRefreshing = false;

  // The breathing Liked-Songs heart: 1.0 → 1.06 over 2.8s, reversed,
  // paused while the tile is pressed.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
    value: 0,
  );
  late final Animation<double> _breathScale = Tween<double>(
    begin: 1.0,
    end: 1.06,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _breath.repeat(reverse: true);
    _loadAll();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _breath.dispose();
    _homeService.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || _endReached || _isRefreshing) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 800) _loadMore();
  }

  Future<void> _loadAll() async {
    _isRefreshing = true;
    if (mounted) setState(() {});
    try {
      final trendingF = _homeService.getTrendingNow();
      final hitsF = _homeService.getBiggestHits();
      final ytF = _homeService.getYtTrendingSongs();
      final ytmHotF = _homeService.getYtmShelf('top hits this week');
      final ytmFreshF = _homeService.getYtmShelf('new music this week', limit: 12);
      final recommendedF = _homeService.getRecommendedToday();
      final personalF =
      _homeService.getPersonalizedVideos(_recentlyPlayed.take(3).toList());
      final topChartsF = _homeService.getTopCharts();
      final collectionsF = _homeService.getHomeCollections();
      final albumsF = _homeService.getNewReleaseAlbums();

      final trendingNow = await trendingF;
      final biggestHits = await hitsF;
      final ytTrending = await ytF;
      final ytmHot = await ytmHotF;
      final ytmFresh = await ytmFreshF;
      final recommendedToday = await recommendedF;
      final personalVideos = await personalF;
      final topCharts = await topChartsF;
      final collections = await collectionsF;
      final newAlbums = await albumsF;

      if (!mounted) return;
      setState(() {
        _trendingNow = trendingNow;
        _biggestHits = biggestHits;
        _ytTrending = ytTrending;
        _ytmHot = ytmHot;
        _ytmFresh = ytmFresh;
        _recommendedToday = recommendedToday;
        _personalVideos = personalVideos;
        _topCharts = topCharts;
        _collections = collections;
        _newAlbums = newAlbums;
        _loading = false;
        _shownSongIds
          ..clear()
          ..addAll(_trendingNow.map((s) => s.id))
          ..addAll(_biggestHits.map((s) => s.id))
          ..addAll(_ytTrending.map((s) => s.id))
          ..addAll(_ytmHot.map((s) => s.id))
          ..addAll(_ytmFresh.map((s) => s.id))
          ..addAll(_recommendedToday.map((s) => s.id))
          ..addAll(_topCharts.map((s) => s.id));
        _chartShelves.clear();
        _endReached = false;
        _failedFetches = 0;
      });
    } catch (e) {
      debugPrint('Home load failed: $e');
      _loading = false;
    }
    _loadRecent();
    _isRefreshing = false;
    if (mounted) setState(() {});
  }

  /// Appends the next YTM chart shelf while scrolling. Stops after the
  /// rotation pool fails to add genuinely-new content twice in a row.
  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final songs = await _homeService.getNextChartShelf();
      if (!mounted) return;
      final fresh =
      songs.where((s) => _shownSongIds.add(s.id)).toList();
      if (fresh.length < 5) {
        _failedFetches++;
        if (_failedFetches >= 2) {
          setState(() {
            _endReached = true;
            _loadingMore = false;
          });
          return;
        }
        setState(() => _loadingMore = false);
        unawaited(_loadMore());
        return;
      }
      _failedFetches = 0;
      setState(() {
        _chartShelves.add((
        title: 'More for you · ${_chartTitle(_chartShelves.length)}',
        songs: fresh,
        ));
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      _failedFetches++;
      if (_failedFetches >= 3) {
        setState(() {
          _endReached = true;
          _loadingMore = false;
        });
      } else {
        setState(() => _loadingMore = false);
      }
    }
  }

  static const _chartTitles = [
    'Chart mix',
    'Throwback chart',
    'Mood chart',
    'Regional chart',
    'Fresh picks',
    'On repeat',
    'Discover',
  ];

  String _chartTitle(int index) => _chartTitles[index % _chartTitles.length];

  void _shufflePlay(List<Song> songs) {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs)..shuffle();
    audioHandler.setQueue(shuffled, startIndex: 0);
    _openPlayer();
  }

  void _loadRecent() {
    if (!mounted) return;
    final played = storage.getPlayedHistory();
    setState(() {
      _recentlyPlayed = played.take(10).toList();
    });
  }

  void _playSong(Song song) {
    audioHandler.startRadio(song);
    _openPlayer();
  }

  void _openPlayer() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _loadRecent());
  }

  /// Opens a video in the dedicated watch page (YouTube-style).
  void _openVideo(Song video) {
    pushSharedAxisY(
      context,
      VideoWatchScreen(
        videoId: video.id,
        title: video.title,
        artist: video.artist,
        thumbnail: video.thumbnail,
      ),
    );
  }

  void _openCollection(Collection c) {
    pushSharedAxisY(context, CollectionScreen(collection: c))
        .then((_) => _loadRecent());
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// The Spotify-style shortcut songs: most recent plays/downloads
  /// (deduped, max 5) — they pair with the Liked tile.
  List<Song> _shortcutSongs() {
    final out = <Song>[];
    final seen = <String>{};
    for (final s in [..._recentlyPlayed, ..._downloads]) {
      if (out.length >= 5) break;
      if (seen.add(s.id)) out.add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      onRefresh: _loadAll,
      child: _loading
          ? _buildSkeletons()
          : Stack(
        children: [
          // ── Subtle oxblood wash at the top (unique polish;
          // delete this Positioned block for a flat dark home).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      SpotifyColors.greenDark.withOpacity(0.30),
                      SpotifyColors.background,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom padding clears the floating mini player +
            // nav bar (extendBody: content scrolls behind them).
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 170),
            children: [
              if (_isRefreshing)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Center(child: WaveSpinner(size: 26)),
                ),

              _header(),

              // ── Shortcut grid ──
              _shortcutGrid(),

              // ── Made for you ──
              if (_recommendedToday.length >= 3) ...[
                const _SectionTitle(title: 'Made for you'),
                _DailyDiscoverPager(
                  songs: _recommendedToday.take(10).toList(),
                  seedArtist: _recentlyPlayed.isEmpty
                      ? ''
                      : _recentlyPlayed.first.artist
                      .split(',')
                      .first
                      .trim(),
                  onTap: _playSong,
                ),
                const SizedBox(height: 8),
              ],

              // ── New releases / playlists ──
              if (_newAlbums.isNotEmpty)
                _collectionRow('New releases', _newAlbums),
              if (_collections.isNotEmpty)
                _collectionRow('Playlists for you', _collections),

              // ── Videos ──
              if (_personalVideos.isNotEmpty)
                MediaShelfRow(
                  title: _videoShelfTitle,
                  items: [
                    for (final s in _personalVideos)
                      ShelfItem.fromSong(s)
                  ],
                  // Videos open the dedicated watch page.
                  onTapItem: (i) => _openVideo(_personalVideos[i]),
                  playingIdStream: audioHandler.currentSongStream,
                ),

              // ── Trending shelves ──
              if (_biggestHits.isNotEmpty)
                MediaShelfRow(
                  title: "Popular right now",
                  items: [
                    for (final s in _biggestHits)
                      ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_biggestHits[i]),
                  onShuffle: () => _shufflePlay(_biggestHits),
                  playingIdStream: audioHandler.currentSongStream,
                ),
              if (_ytTrending.isNotEmpty)
                MediaShelfRow(
                  title: 'Trending on YouTube Music',
                  items: [
                    for (final s in _ytTrending)
                      ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_ytTrending[i]),
                  onShuffle: () => _shufflePlay(_ytTrending),
                  playingIdStream: audioHandler.currentSongStream,
                ),
              if (_ytmHot.isNotEmpty)
                MediaShelfRow(
                  title: 'Hot on YouTube Music',
                  items: [
                    for (final s in _ytmHot) ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_ytmHot[i]),
                  onShuffle: () => _shufflePlay(_ytmHot),
                  playingIdStream: audioHandler.currentSongStream,
                ),
              if (_topCharts.isNotEmpty)
                MediaShelfRow(
                  title: 'Top charts',
                  items: [
                    for (final s in _topCharts) ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_topCharts[i]),
                  onShuffle: () => _shufflePlay(_topCharts),
                  playingIdStream: audioHandler.currentSongStream,
                ),
              if (_ytmFresh.isNotEmpty)
                MediaShelfRow(
                  title: 'Fresh music',
                  items: [
                    for (final s in _ytmFresh) ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_ytmFresh[i]),
                  onShuffle: () => _shufflePlay(_ytmFresh),
                  playingIdStream: audioHandler.currentSongStream,
                ),

              // ── Infinite chart shelves (appended on scroll) ──
              for (final shelf in _chartShelves)
                MediaShelfRow(
                  title: shelf.title,
                  items: [
                    for (final s in shelf.songs)
                      ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(shelf.songs[i]),
                  onShuffle: () => _shufflePlay(shelf.songs),
                  playingIdStream: audioHandler.currentSongStream,
                ),

              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: WaveSpinner(size: 22)),
                )
              else if (_endReached)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'You\'re all caught up — pull to refresh',
                      style: TextStyle(
                        color: SpotifyColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            ],        // ListView children
          ),          // ListView
        ],            // Stack children
      ),              // Stack
    );                // RefreshIndicator
  }

  /// Spotify-style skeleton: greeting line, 6 shortcut-tile
  /// placeholders, shelf placeholders.
  Widget _buildSkeletons() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 170),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Container(
            width: 180,
            height: 28,
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              for (var r = 0; r < 3; r++)
                Row(
                  children: [
                    for (var c = 0; c < 2; c++)
                      Expanded(
                        child: Container(
                          height: 60,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: SpotifyColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SkeletonShelf(itemCount: 5),
        const SkeletonTile(),
        const SkeletonTile(),
      ],
    );
  }

  /// Header: Playfair greeting on the left, Listen-Together and
  /// settings circles on the right.
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                fontFamily: 'PlayfairDisplay',
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                pushSharedAxisY(context, const ListenTogetherScreen()),
            child: Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                size: 24,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => pushSharedAxisY(context, const SettingsScreen())
                .then((_) => _loadAll()),
            child: Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.settings_outlined,
                  size: 24, color: SpotifyColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Spotify's 2-column shortcut grid: 60dp tiles, square art on the
  /// left, label on the right. First tile is Liked Songs.
  Widget _shortcutGrid() {
    final songs = _shortcutSongs();
    final rows = ((songs.length + 1) / 2).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          // Liked Songs tile always first (paired with the first song).
          Row(
            children: [
              Expanded(child: _likedTile()),
              if (songs.isNotEmpty)
                Expanded(child: _songTile(songs[0]))
              else
                const Expanded(child: SizedBox()),
            ],
          ),
          for (var r = 1; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 2; c++)
                  Expanded(
                    child: (r * 2 + c) < songs.length
                        ? _songTile(songs[r * 2 + c])
                        : const Expanded(child: SizedBox()),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _likedTile() {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Listener(
        // The heart holds its breath while the tile is pressed.
        onPointerDown: (_) => _breath.stop(),
        onPointerUp: (_) => _breath.repeat(reverse: true),
        onPointerCancel: (_) => _breath.repeat(reverse: true),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => pushSharedAxisY(context, const LikedSongsScreen()),
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        SpotifyColors.highlight,
                        SpotifyColors.green,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _breathScale,
                      builder: (context, _) => Transform.scale(
                        scale: _breathScale.value,
                        child: const Icon(
                          FluentIcons.heart_24_filled,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Liked Songs',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _songTile(Song song) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _playSong(song),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: YoutubeThumbnail(
                  videoId: song.id,
                  imageUrl: song.thumbnail,
                  borderRadius: 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collectionRow(String title, List<Collection> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: title),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            clipBehavior: Clip.none,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) => CollectionCard(
              collection: items[i],
              size: 160,
              onTap: () => _openCollection(items[i]),
            ),
          ),
        ),
      ],
    );
  }

  String get _videoShelfTitle {
    if (_recentlyPlayed.isEmpty) return 'Videos for you';
    final artist = _recentlyPlayed.first.artist.split(',').first.trim();
    if (artist.isEmpty) return 'Videos for you';
    return 'Because you listened to $artist';
  }
}

// ═════════════════════════════════════════════
// SECTION TITLE — ZenMusic's tick-rule: a small burgundy bar before
// the label. (Local to this screen — media_shelf.dart's internal
// headers are untouched.)
// ═════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 16,
            decoration: BoxDecoration(
              color: SpotifyColors.green,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DAILY DISCOVER PAGER — near-full-width hero cards (Made for you),
// dark gradient scrim over artwork, seed-based caption,
// deterministic per song, round play button.
// ═════════════════════════════════════════════

class _DailyDiscoverPager extends StatelessWidget {
  final List<Song> songs;
  final String seedArtist;
  final ValueChanged<Song> onTap;

  const _DailyDiscoverPager({
    required this.songs,
    required this.seedArtist,
    required this.onTap,
  });

  static const _captions = [
    'Sounds like {a}',
    'Because you listened to {a}',
    'Similar to {a}',
    'Based on {a}',
    'For fans of {a}',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.86),
        itemCount: songs.length,
        itemBuilder: (context, i) {
          final song = songs[i];
          final caption = _captions[
          math.Random(song.id.hashCode).nextInt(_captions.length)]
              .replaceAll('{a}', seedArtist.isEmpty ? song.artist : seedArtist);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => onTap(song),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: SpotifyColors.surface,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (song.thumbnail.isNotEmpty)
                        CachedNetworkImage(
                          imageUrl: song.thumbnail,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                          const ColoredBox(
                              color: SpotifyColors.surfaceLight),
                        )
                      else
                        const ColoredBox(
                            color: SpotifyColors.surfaceLight),
                      // Vertical gradient scrim (over artwork — the
                      // white text below depends on it staying dark).
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black45,
                              Colors.transparent,
                              Colors.black54,
                              Colors.black87,
                            ],
                            stops: [0.0, 0.35, 0.7, 1.0],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(song.title,
                                    maxLines: 2,
                                    overflow:
                                    TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight:
                                        FontWeight.w700,
                                        color: Colors.white)),
                                const SizedBox(height: 3),
                                Text(song.artist,
                                    maxLines: 1,
                                    overflow:
                                    TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.white
                                            .withOpacity(0.7))),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(caption,
                                      maxLines: 1,
                                      overflow:
                                      TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight:
                                          FontWeight.w600,
                                          color: Colors.white
                                              .withOpacity(
                                              0.6))),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: SpotifyColors.highlight,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 26,
                                    color: SpotifyColors.greenDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════
// MINI PLAYER — UNCHANGED (user instruction: the mini player stays
// exactly as it is; it is deliberately NOT part of the redesign).
// ═════════════════════════════════════════════

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  static const double _playerHeight = 72;
  static const double _borderRadius = 20;
  static const double _artworkSize = 52;
  static const double _artworkRadius = 14;

  PageRoute<void> _createSlideTransition() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, _) => const PlayerScreen(),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeInOut));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
    );
  }

  void _openNowPlaying(BuildContext context) {
    Navigator.of(context).push(_createSlideTransition());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final metadata = mediaSnapshot.data;
        if (metadata == null) return const SizedBox.shrink();

        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, stateSnapshot) {
            final state = stateSnapshot.data;
            if (state == null) return const SizedBox.shrink();

            return StreamBuilder<List<MediaItem>>(
              stream: audioHandler.queue,
              builder: (context, queueSnapshot) {
                final queue = queueSnapshot.data ?? const [];
                final hasNext = queue.length > 1 &&
                    (state.queueIndex ?? 0) < queue.length - 1;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: _MiniPlayerBody(
                    metadata: metadata,
                    playbackState: state,
                    hasNext: hasNext,
                    onOpen: () => _openNowPlaying(context),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerBody extends StatefulWidget {
  const _MiniPlayerBody({
    required this.metadata,
    required this.playbackState,
    required this.hasNext,
    required this.onOpen,
  });

  final MediaItem metadata;
  final PlaybackState playbackState;
  final bool hasNext;
  final VoidCallback onOpen;

  @override
  State<_MiniPlayerBody> createState() => _MiniPlayerBodyState();
}

class _MiniPlayerBodyState extends State<_MiniPlayerBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  static const double _dragThreshold = 10;

  // ── Track-change slide state (player-screen parity) ──
  bool _slideForward = true;
  bool? _pendingSlideForward;
  DateTime _slideIntentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSlideSongId;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _noteSlideIntent(bool forward) {
    _pendingSlideForward = forward;
    _slideIntentAt = DateTime.now();
  }

  void _consumeSlideIntentIfNeeded() {
    final id = widget.metadata.id;
    if (id == _lastSlideSongId) return;
    final pending = _pendingSlideForward;
    if (pending != null &&
        DateTime.now().difference(_slideIntentAt) <
            const Duration(milliseconds: 3000)) {
      _slideForward = pending;
    }
    _pendingSlideForward = null;
    _lastSlideSongId = id;
  }

  void _handleVerticalDrag(DragUpdateDetails details) {
    if ((details.primaryDelta ?? 0) < -_dragThreshold) {
      widget.onOpen();
    }
  }

  Widget _slideOnChange({
    required String slideKey,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.hardEdge,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(slideKey);
        final Offset slideFrom = incoming
            ? Offset(_slideForward ? 0.35 : -0.35, 0)
            : Offset(_slideForward ? -0.35 : 0.35, 0);
        return IgnorePointer(
          ignoring: !incoming,
          child: FadeTransition(
            opacity: incoming
                ? Tween<double>(begin: 0.35, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut))
                : Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeIn)),
            child: SlideTransition(
              position: Tween<Offset>(begin: slideFrom, end: Offset.zero)
                  .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(slideKey),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _consumeSlideIntentIfNeeded();
    final metadata = widget.metadata;
    final state = widget.playbackState;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: (_) => _animationController.forward(),
            onTapUp: (_) => _animationController.reverse(),
            onTapCancel: () => _animationController.reverse(),
            onVerticalDragUpdate: _handleVerticalDrag,
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -300) {
                _noteSlideIntent(true);
                audioHandler.skipToNext();
              } else if (v > 300) {
                _noteSlideIntent(false);
                audioHandler.skipToPrevious();
              }
            },
            onTap: widget.onOpen,
            child: ValueListenableBuilder<String>(
              valueListenable: AppearancePrefs.miniPlayerBackground,
              builder: (context, miniBg, _) => Container(
                height: MiniPlayer._playerHeight,
                decoration: BoxDecoration(
                  color: SpotifyColors.surface,
                  gradient: miniBg == 'gradient'
                      ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      SpotifyColors.green,
                      SpotifyColors.surface,
                    ],
                  )
                      : null,
                  borderRadius:
                  BorderRadius.circular(MiniPlayer._borderRadius),
                ),
                child: ClipRRect(
                  borderRadius:
                  BorderRadius.circular(MiniPlayer._borderRadius),
                  child: Stack(
                    children: [
                      if (miniBg == 'blur' &&
                          (metadata.artUri?.toString().isNotEmpty ?? false))
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: metadata.artUri.toString(),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                            const SizedBox.shrink(),
                          ),
                        ),
                      if (miniBg == 'blur')
                        Positioned.fill(
                          child: BackdropFilter(
                            filter:
                            ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: ColoredBox(
                                color: Colors.black.withOpacity(0.35)),
                          ),
                        ),
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            _slideOnChange(
                              slideKey: metadata.id,
                              child: _Artwork(metadata: metadata),
                            ),
                            Expanded(
                              child: _slideOnChange(
                                slideKey: 'meta-${metadata.id}',
                                child: _Metadata(
                                  title: metadata.title,
                                  artist: metadata.artist ?? '',
                                ),
                              ),
                            ),
                            _Controls(
                              playbackState: state,
                              hasNext: widget.hasNext &&
                                  !audioHandler.isRadioMode,
                              totalDuration:
                              metadata.duration ?? Duration.zero,
                              onNextIntent: () => _noteSlideIntent(true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.metadata});
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final url = metadata.artUri?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MiniPlayer._artworkRadius),
        child: url.isEmpty
            ? Container(
          width: MiniPlayer._artworkSize,
          height: MiniPlayer._artworkSize,
          color: SpotifyColors.surfaceLight,
          child: const Icon(
            Icons.music_note_rounded,
            size: 24,
            color: SpotifyColors.textTertiary,
          ),
        )
            : CachedNetworkImage(
          imageUrl: url,
          width: MiniPlayer._artworkSize,
          height: MiniPlayer._artworkSize,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: MiniPlayer._artworkSize,
            height: MiniPlayer._artworkSize,
            color: SpotifyColors.surfaceLight,
            child: const Center(
              child: WaveSpinner(size: 18, strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            width: MiniPlayer._artworkSize,
            height: MiniPlayer._artworkSize,
            color: SpotifyColors.surfaceLight,
            child: const Icon(
              Icons.music_note_rounded,
              size: 24,
              color: SpotifyColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.title, required this.artist});

  final String title;
  final String artist;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeWidget(
            manualScrollEnabled: false,
            animationDuration: const Duration(seconds: 8),
            backDuration: const Duration(seconds: 2),
            pauseDuration: const Duration(seconds: 2),
            child: Text(
              title,
              style: const TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (artist.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              artist,
              style: const TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.playbackState,
    required this.hasNext,
    required this.totalDuration,
    this.onNextIntent,
  });

  final PlaybackState playbackState;
  final bool hasNext;
  final Duration totalDuration;
  final VoidCallback? onNextIntent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircularPlayButton(
          playbackState: playbackState,
          totalDuration: totalDuration,
        ),
        if (hasNext) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              onNextIntent?.call();
              audioHandler.skipToNext();
            },
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            icon: const Icon(
              FluentIcons.next_24_filled,
              color: SpotifyColors.textSecondary,
              size: 24,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════
// CIRCULAR PLAY BUTTON — the ring is the WAVY ARC ONLY (no track
// circle behind it — deliberately removed): green wavy arc = elapsed
// (arc length = progress), wave travels while playing, flattens when
// paused (wavy-slider parity).
// ═════════════════════════════════════════════

class _CircularPlayButton extends StatefulWidget {
  const _CircularPlayButton({
    required this.playbackState,
    required this.totalDuration,
  });

  final PlaybackState playbackState;
  final Duration totalDuration;

  @override
  State<_CircularPlayButton> createState() => _CircularPlayButtonState();
}

class _CircularPlayButtonState extends State<_CircularPlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    duration: const Duration(milliseconds: 2000),
    vsync: this,
  );
  late final AnimationController _amp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 0,
  );

  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playing = widget.playbackState.playing;
    if (_playing) {
      _phase.repeat();
      _amp.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _CircularPlayButton old) {
    super.didUpdateWidget(old);
    final playing = widget.playbackState.playing;
    if (playing != _playing) {
      _playing = playing;
      if (playing) {
        _phase.repeat();
        _amp.forward();
      } else {
        _amp.reverse();
        _phase.stop();
      }
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final processingState = widget.playbackState.processingState;
    final isPlaying = widget.playbackState.playing;
    final isLoading = processingState == AudioProcessingState.loading ||
        processingState == AudioProcessingState.buffering;
    final isCompleted = processingState == AudioProcessingState.completed;

    return SizedBox(
      width: 48,
      height: 48,
      child: StreamBuilder<Duration>(
        stream: audioHandler.positionStream,
        builder: (context, posSnap) {
          final position = posSnap.data ?? Duration.zero;
          final progress = widget.totalDuration.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds /
              widget.totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: Listenable.merge([_phase, _amp]),
                builder: (context, _) => CustomPaint(
                  size: const Size(48, 48),
                  painter: WaveRingPainter(
                    phase: _phase.value * 2 * math.pi,
                    startAngle: -math.pi / 2,
                    sweepAngle: 2 * math.pi * progress.clamp(0.0, 1.0),
                    color: SpotifyColors.green,
                    strokeWidth: 3,
                    amplitude: 1.6 * _amp.value,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                    AlwaysStoppedAnimation<Color>(SpotifyColors.highlight),
                  ),
                )
              else
                IconButton(
                  onPressed: isCompleted
                      ? () async {
                    await audioHandler.seek(Duration.zero);
                    await audioHandler.play();
                  }
                      : (isPlaying ? audioHandler.pause : audioHandler.play),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  icon: Icon(
                    isCompleted
                        ? FluentIcons.arrow_counterclockwise_24_filled
                        : (isPlaying
                        ? FluentIcons.pause_16_filled
                        : FluentIcons.play_16_filled),
                    color: SpotifyColors.textPrimary,
                    size: 22,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════
// LIBRARY TAB
// ═════════════════════════════════════════════

class LibraryTab extends StatefulWidget {
  const LibraryTab({super.key});

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  List<Song> _played = [];
  List<({String id, String name, int count})> _userPlaylists = [];
  List<Song> _downloads = [];
  bool _loadingDownloads = true;
  int _likedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _played = storage.getPlayedHistory();
      _userPlaylists = storage.getUserPlaylists();
      _likedCount = storage.getLikedSongs().length;
    });
    DownloadsService().downloadedSongs().then((list) {
      if (!mounted) return;
      setState(() {
        _downloads = list;
        _loadingDownloads = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Your library',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: SpotifyColors.textPrimary,
                      fontFamily: 'PlayfairDisplay',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.history_rounded,
                    color: SpotifyColors.textSecondary,
                  ),
                  tooltip: 'History',
                  onPressed: () =>
                      pushSharedAxisY(context, const HistoryScreen()),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.radio_rounded,
                    color: SpotifyColors.textSecondary,
                  ),
                  tooltip: 'Radio',
                  onPressed: () =>
                      pushSharedAxisY(context, const RadioScreen()),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: SpotifyColors.textSecondary,
                  ),
                  tooltip: 'Equalizer',
                  onPressed: () =>
                      pushSharedAxisY(context, const EqualizerScreen()),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                const Text(
                  'Your playlists',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: SpotifyColors.surface,
                        title: const Text('Delete all downloads?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await DownloadsService().deleteAll();
                      _load();
                    }
                  },
                  icon: const Icon(
                    FluentIcons.delete_24_regular,
                    size: 16,
                    color: SpotifyColors.textTertiary,
                  ),
                  label: const Text(
                    'Clear downloads',
                    style: TextStyle(
                        fontSize: 12, color: SpotifyColors.textTertiary),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => pushSharedAxisY(
                    context,
                    const ImportSpotifyScreen(),
                  ).then((_) => _load()),
                  icon: const Icon(
                    FluentIcons.arrow_upload_24_regular,
                    size: 16,
                    color: SpotifyColors.highlight,
                  ),
                  label: const Text(
                    'Import',
                    style:
                    TextStyle(fontSize: 13, color: SpotifyColors.highlight),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => pushSharedAxisY(
                        context, const LikedSongsScreen()),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            SpotifyColors.highlight,
                            SpotifyColors.green,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(FluentIcons.heart_24_filled,
                              color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Liked songs',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final name = await showCreatePlaylistSheet(context);
                    if (name == null) return;
                    await storage.createUserPlaylist(name);
                    _load();
                  },
                  child: Container(
                    height: 56,
                    width: 56,
                    decoration: BoxDecoration(
                      color: SpotifyColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: SpotifyColors.textPrimary, size: 26),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_userPlaylists.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _userPlaylists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final p = _userPlaylists[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => pushSharedAxisY(
                      context,
                      UserPlaylistScreen(id: p.id, name: p.name),
                    ).then((_) => _load()),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: SpotifyColors.surface,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        '${p.name} · ${p.count}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SpotifyColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (!_loadingDownloads && _downloads.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.download_rounded,
                      size: 16, color: SpotifyColors.highlight),
                  const SizedBox(width: 6),
                  Text(
                    'Downloads · ${_downloads.length}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                clipBehavior: Clip.none,
                itemCount: _downloads.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final song = _downloads[i];
                  return GestureDetector(
                    onTap: () async {
                      await audioHandler.setQueue([song], startIndex: 0);
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PlayerScreen()),
                      );
                    },
                    child: SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          YoutubeThumbnail(
                            videoId: song.id,
                            imageUrl: song.thumbnail,
                            width: 140,
                            height: 140,
                            borderRadius: 10,
                          ),
                          const SizedBox(height: 8),
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: SpotifyColors.textPrimary)),
                          Text(song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: SpotifyColors.textSecondary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: _played.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.library_music_rounded,
                    size: 56,
                    color: SpotifyColors.textTertiary.withOpacity(0.6),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Nothing here yet',
                    style: TextStyle(
                      color: SpotifyColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Songs you play will appear here',
                    style: TextStyle(
                      color:
                      SpotifyColors.textTertiary.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
              itemCount: _played.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final song = _played[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    audioHandler.startRadio(song);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PlayerScreen(),
                      ),
                    ).then((_) => _load());
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        YoutubeThumbnail(
                          videoId: song.id,
                          imageUrl: song.thumbnail,
                          width: 52,
                          height: 52,
                          borderRadius: 6,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SpotifyColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SpotifyColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.play_circle_outline_rounded,
                          size: 22,
                          color: SpotifyColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}