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
import 'youtube_tab_screen.dart';

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
      setState(() => _currentTab = tab < 0 ? 0 : (tab > 3 ? 3 : tab));
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
            YoutubeTab(),
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
              ZenNavItem(
                icon: Icons.play_circle_outline_rounded,
                activeIcon: Icons.play_circle_outline_rounded,
                label: 'Videos',
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
// HOME TAB — "Brass" layout (from the reference design):
//   app-name header + gold-ringed action circles →
//   TRENDING hero card (gold border, real song cover, Play) →
//   Recently Played (horizontal cards, See all → History) →
//   Made For You (list rows: thumb · title/artist·duration · heart) →
//   New releases / Playlists / Videos / trending shelves / charts.
// ═════════════════════════════════════════════

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
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

  // Infinite append state — dynamic YTM chart shelves.
  final List<({String title, List<Song> songs})> _chartShelves = [];
  final Set<String> _shownSongIds = {};
  bool _loadingMore = false;
  bool _endReached = false;
  int _failedFetches = 0;

  bool _loading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
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

  /// The hero song: TRENDING first (YTM trending shelves — real songs
  /// with clean titles/artists), recommendation last. The previous
  /// order led with recommendedToday, whose first entry can be a long
  /// mix/radio title instead of a proper trending song.
  Song? _featuredSong() {
    if (_biggestHits.isNotEmpty) return _biggestHits.first;
    if (_trendingNow.isNotEmpty) return _trendingNow.first;
    if (_ytmHot.isNotEmpty) return _ytmHot.first;
    if (_recommendedToday.isNotEmpty) {
      final s = _recommendedToday.first;
      // Guard: recommended feeds sometimes lead with a long mix —
      // only accept it as the hero if it looks like a song.
      if (s.duration <= const Duration(minutes: 12)) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      onRefresh: _loadAll,
      child: _loading
          ? _buildSkeletons()
          : ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        // Bottom padding clears the floating mini player + nav
        // bar (extendBody: content scrolls behind them).
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 170),
        children: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: WaveSpinner(size: 26)),
            ),

          _header(),

          // ── TRENDING hero card ──
          if (_featuredSong() != null) ...[
            _HeroCard(
              song: _featuredSong()!,
              onPlay: () => _playSong(_featuredSong()!),
            ),
            const SizedBox(height: 24),
          ],

          // ── Recently Played ──
          if (_recentlyPlayed.isNotEmpty) ...[
            _SectionHead(
              title: 'Recently Played',
              onSeeAll: () => pushSharedAxisY(
                  context, const HistoryScreen()),
            ),
            _recentRow(),
            const SizedBox(height: 24),
          ],

          // ── Made For You ──
          if (_recommendedToday.isNotEmpty) ...[
            const _SectionHead(title: 'Made For You'),
            _madeForYouList(),
            const SizedBox(height: 24),
          ],

          // ── New releases / playlists ──
          if (_newAlbums.isNotEmpty)
            _collectionRow('New Releases', _newAlbums),
          if (_collections.isNotEmpty)
            _collectionRow('Playlists For You', _collections),

          // ── Videos ──
          if (_personalVideos.isNotEmpty)
            MediaShelfRow(
              title: _videoShelfTitle,
              items: [
                for (final s in _personalVideos) ShelfItem.fromSong(s)
              ],
              // Videos open the dedicated watch page.
              onTapItem: (i) => _openVideo(_personalVideos[i]),
              playingIdStream: audioHandler.currentSongStream,
            ),

          // ── Trending shelves ──
          if (_biggestHits.isNotEmpty)
            MediaShelfRow(
              title: 'Popular Right Now',
              items: [
                for (final s in _biggestHits) ShelfItem.fromSong(s)
              ],
              onTapItem: (i) => _playSong(_biggestHits[i]),
              onShuffle: () => _shufflePlay(_biggestHits),
              playingIdStream: audioHandler.currentSongStream,
            ),
          if (_ytTrending.isNotEmpty)
            MediaShelfRow(
              title: 'Trending on YouTube Music',
              items: [
                for (final s in _ytTrending) ShelfItem.fromSong(s)
              ],
              onTapItem: (i) => _playSong(_ytTrending[i]),
              onShuffle: () => _shufflePlay(_ytTrending),
              playingIdStream: audioHandler.currentSongStream,
            ),
          if (_ytmHot.isNotEmpty)
            MediaShelfRow(
              title: 'Hot on YouTube Music',
              items: [for (final s in _ytmHot) ShelfItem.fromSong(s)],
              onTapItem: (i) => _playSong(_ytmHot[i]),
              onShuffle: () => _shufflePlay(_ytmHot),
              playingIdStream: audioHandler.currentSongStream,
            ),
          if (_topCharts.isNotEmpty)
            MediaShelfRow(
              title: 'Top Charts',
              items: [for (final s in _topCharts) ShelfItem.fromSong(s)],
              onTapItem: (i) => _playSong(_topCharts[i]),
              onShuffle: () => _shufflePlay(_topCharts),
              playingIdStream: audioHandler.currentSongStream,
            ),
          if (_ytmFresh.isNotEmpty)
            MediaShelfRow(
              title: 'Fresh Music',
              items: [for (final s in _ytmFresh) ShelfItem.fromSong(s)],
              onTapItem: (i) => _playSong(_ytmFresh[i]),
              onShuffle: () => _shufflePlay(_ytmFresh),
              playingIdStream: audioHandler.currentSongStream,
            ),

          // ── Infinite chart shelves (appended on scroll) ──
          for (final shelf in _chartShelves)
            MediaShelfRow(
              title: shelf.title,
              items: [
                for (final s in shelf.songs) ShelfItem.fromSong(s)
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
    );            // RefreshIndicator
  }

  /// Header: app name in Playfair (the unique font) + gold-ringed
  /// action circles (Listen Together, Settings).
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'ZenMusic',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                fontFamily: 'Retro Blendy',
              ),
            ),
          ),
          GestureDetector(
            onTap: () =>
                pushSharedAxisY(context, const ListenTogetherScreen()),
            child: _ringedCircle(icon: Icons.people_outline),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => pushSharedAxisY(context, const SettingsScreen())
                .then((_) => _loadAll()),
            child: _ringedCircle(icon: Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  /// The reference's avatar treatment: card fill, 1px brass ring,
  /// honey icon. PURE VISUAL — deliberately no GestureDetector here:
  /// an inner detector with an empty onTap wins the gesture arena and
  /// swallows the outer header's tap (the dead-buttons bug).
  Widget _ringedCircle({required IconData icon}) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: SpotifyColors.surfaceLight,
        shape: BoxShape.circle,
        border: Border.all(color: SpotifyColors.green),
      ),
      child: Icon(icon, size: 20, color: SpotifyColors.highlight),
    );
  }

  /// Recently Played — horizontal 118dp cards (reference layout).
  Widget _recentRow() {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _recentlyPlayed.length.clamp(0, 12),
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final song = _recentlyPlayed[i];
          return GestureDetector(
            onTap: () => _playSong(song),
            child: SizedBox(
              width: 118,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YoutubeThumbnail(
                    videoId: song.id,
                    imageUrl: song.thumbnail,
                    width: 118,
                    height: 118,
                    borderRadius: 12,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: SpotifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Made For You — thumb · title/artist·duration · heart rows.
  Widget _madeForYouList() {
    final songs = _recommendedToday.take(6).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < songs.length; i++) ...[
            _MadeForRow(song: songs[i], onPlay: () => _playSong(songs[i])),
            if (i < songs.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 58,
                color: SpotifyColors.surfaceLighter,
              ),
          ],
        ],
      ),
    );
  }

  Widget _collectionRow(String title, List<Collection> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(title: title),
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

  /// Skeleton matching the layout: masthead, hero block, recent
  /// squares, list rows.
  Widget _buildSkeletons() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 170),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Container(
            width: 180,
            height: 30,
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            height: 170,
            decoration: BoxDecoration(
              color: SpotifyColors.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: SpotifyColors.green.withOpacity(0.35),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  margin: const EdgeInsets.only(right: 14),
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: SpotifyColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 4; i++)
          Container(
            height: 66,
            margin: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// SECTION HEAD — reference style: bold title left, gold "See all"
// right (optional).
// ═════════════════════════════════════════════

class _SectionHead extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHead({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SpotifyColors.highlight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// TRENDING HERO CARD — gold-bordered card, TRENDING tag, the song's
// REAL COVER in a brass-ringed 96dp block, dark-on-brass Play
// button. Vinyl ornament only as the no-image fallback.
// ═════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final Song song;
  final VoidCallback onPlay;

  const _HeroCard({required this.song, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final sub = song.duration.inSeconds > 0
        ? '${song.artist} · ${_fmt(song.duration)}'
        : song.artist;
    final hasArt = song.thumbnail.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: SpotifyColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: SpotifyColors.green.withOpacity(0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRENDING',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w800,
                color: SpotifyColors.highlight,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.3,
                          color: SpotifyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SpotifyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                _cover(hasArt: hasArt),
              ],
            ),
            const SizedBox(height: 16),
            // Play button — dark-on-brass, like the reference.
            Material(
              color: SpotifyColors.green,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onPlay,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 16,
                        color: SpotifyColors.background,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Play',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: SpotifyColors.background,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The song's real cover: rounded 96dp block with a brass ring.
  /// Falls back to the vinyl ornament only when no image exists.
  Widget _cover({required bool hasArt}) {
    final core = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: hasArt
          ? CachedNetworkImage(
        imageUrl: song.thumbnail,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 96,
          height: 96,
          color: SpotifyColors.surface,
        ),
        errorWidget: (_, __, ___) => _vinylFallback(),
      )
          : _vinylFallback(),
    );

    // Brass ring around the cover (keeps the gold signature).
    return Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: SpotifyColors.green.withOpacity(0.5),
        ),
      ),
      child: core,
    );
  }

  Widget _vinylFallback() {
    return Container(
      width: 96,
      height: 96,
      color: SpotifyColors.surface,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: SpotifyColors.surfaceLighter, width: 2),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: SpotifyColors.surfaceLighter, width: 2),
            ),
          ),
          Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: SpotifyColors.green,
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: SpotifyColors.background,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ═════════════════════════════════════════════
// MADE FOR YOU ROW — thumb · title / artist·duration · heart.
// Own like-state (reads storage once, toggles locally + persists).
// ═════════════════════════════════════════════

class _MadeForRow extends StatefulWidget {
  final Song song;
  final VoidCallback onPlay;

  const _MadeForRow({required this.song, required this.onPlay});

  @override
  State<_MadeForRow> createState() => _MadeForRowState();
}

class _MadeForRowState extends State<_MadeForRow> {
  late bool _liked;

  @override
  void initState() {
    super.initState();
    _liked = storage.isLiked(widget.song.id);
  }

  Future<void> _toggleLike() async {
    final newValue = !_liked;
    setState(() => _liked = newValue);
    try {
      await storage.setLiked(widget.song, newValue);
    } catch (_) {
      if (mounted) setState(() => _liked = !newValue);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final hasDuration = song.duration.inSeconds > 0;

    return InkWell(
      onTap: widget.onPlay,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            YoutubeThumbnail(
              videoId: song.id,
              imageUrl: song.thumbnail,
              width: 46,
              height: 46,
              borderRadius: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasDuration
                        ? '${song.artist} · ${_fmt(song.duration)}'
                        : song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SpotifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _toggleLike,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _liked
                      ? FluentIcons.heart_24_filled
                      : FluentIcons.heart_24_regular,
                  size: 20,
                  color: _liked
                      ? SpotifyColors.highlight
                      : SpotifyColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// MINI PLAYER — UNCHANGED in structure (standing user instruction);
// it recolors via the theme tokens. The reference's thin progress
// line on top is available as a follow-up on request.
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
    // An active video session reopens the WATCH page at its saved
    // position (YouTube parity) instead of the audio player.
    if (VideoSession.active) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoWatchScreen(
          videoId: VideoSession.videoId,
          title: VideoSession.title,
          artist: VideoSession.artist,
          thumbnail: VideoSession.thumbnail,
          startPosition: VideoSession.position,
        ),
      ));
      return;
    }
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
                      ? LinearGradient(
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
// circle behind it — deliberately removed): wavy arc = elapsed
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
                    color: SpotifyColors.highlight,
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
// LIBRARY TAB (recolors via tokens; structure unchanged)
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
                              color: SpotifyColors.background, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Liked songs',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: SpotifyColors.background,
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
                        const Icon(
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