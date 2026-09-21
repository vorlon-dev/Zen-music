import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/home_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/home_section.dart';
import '../widgets/start_listening_list.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: IndexedStack(
        index: _currentTab,
        children: const [
          HomeTab(),
          SearchScreen(),
          LibraryTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          Container(
            decoration: BoxDecoration(
              color: SpotifyColors.background,
              border: Border(
                top: BorderSide(
                  color: SpotifyColors.textTertiary.withOpacity(0.12),
                  width: 0.6,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentTab,
              onTap: (i) => setState(() => _currentTab = i),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: SpotifyColors.textPrimary,
              unselectedItemColor: SpotifyColors.textTertiary,
              selectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded, size: 24),
                  activeIcon: Icon(Icons.home_rounded, size: 24),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded, size: 24),
                  activeIcon: Icon(Icons.search_rounded, size: 24),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music_rounded, size: 24),
                  activeIcon: Icon(Icons.library_music_rounded, size: 24),
                  label: 'Library',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// HOME TAB
// ═════════════════════════════════════════════

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _homeService = HomeService();

  List<Song> _trendingNow = [];
  List<Song> _biggestHits = [];
  List<Song> _newReleases = [];
  List<Song> _recommended = [];
  List<Song> _topCharts = [];
  List<Song> _startListening = [];
  List<Song> _recentlyPlayed = [];
  List<String> _recentQueries = [];

  bool _loading = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadAll();
  }

  void _loadRecent() {
    if (!mounted) return;
    setState(() {
      _recentQueries = storage.getRecentQueries();
      _recentlyPlayed = storage.getPlayedHistory().take(10).toList();
    });
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _homeService.getTrendingNow(),
        _homeService.getBiggestHits(),
        _homeService.getNewReleases(),
        _homeService.getRecommendedToday(),
        _homeService.getTopCharts(),
        _homeService.getStartListening(),
      ]);
      if (!mounted) return;
      setState(() {
        _trendingNow = results[0];
        _biggestHits = results[1];
        _newReleases = results[2];
        _recommended = results[3];
        _topCharts = results[4];
        _startListening = results[5];
        _loading = false;
      });
    } catch (e) {
      debugPrint('Home load failed: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
    _loadRecent();
  }

  void _playSong(Song song) {
    audioHandler.startRadio(song);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _loadRecent());
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: SpotifyColors.green,
        backgroundColor: SpotifyColors.surface,
        onRefresh: _loadAll,
        child: _loading
            ? const _LoadingView()
            : ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // ── Greeting ──
            _greetingHeader(),

            const SizedBox(height: 4),

            // ── Filter tabs ──
            _filterTabs(),

            const SizedBox(height: 8),

            // ── Recent Searches (chips) ──
            if (_recentQueries.isNotEmpty && _showMusic())
              _recentSearchesSection(),

            // ── Recently Played ──
            if (_recentlyPlayed.isNotEmpty && _showMusic())
              HomeSection(
                title: 'Recently played',
                songs: _recentlyPlayed,
                onTap: _playSong,
              ),

            // ── Music sections ──
            if (_showMusic()) ...[
              HomeSection(
                title: 'Trending now',
                songs: _trendingNow,
                onTap: _playSong,
              ),
              HomeSection(
                title: 'New releases for you',
                songs: _newReleases,
                onTap: _playSong,
              ),
              HomeSection(
                title: "Today's biggest hits",
                songs: _biggestHits,
                onTap: _playSong,
              ),
              StartListeningList(
                songs: _startListening,
                onTap: _playSong,
              ),
              HomeSection(
                title: 'Top charts',
                songs: _topCharts,
                onTap: _playSong,
              ),
            ],

            // ── Video sections ──
            if (_showVideo())
              HomeSection(
                title: 'Recommended for today',
                songs: _recommended,
                onTap: _playSong,
              ),

            // ── Empty state ──
            if (!_showMusic() && !_showVideo()) _emptyState(),
          ],
        ),
      ),
    );
  }

  bool _showMusic() => _filter == 'All' || _filter == 'Music';
  bool _showVideo() => _filter == 'All' || _filter == 'Videos';

  Widget _greetingHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SpotifyColors.surfaceLight,
              border: Border.all(
                color: SpotifyColors.textTertiary.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.person_rounded,
              size: 18,
              color: SpotifyColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _greeting,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // Understated segmented tabs instead of solid, saturated pill chips —
  // keeps the accent colour reserved for the one thing that's actually
  // selected, rather than painting every chip.
  Widget _filterTabs() {
    const options = ['All', 'Music', 'Videos'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: options.map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 20),
            child: InkWell(
              onTap: () => setState(() => _filter = f),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? SpotifyColors.textPrimary
                            : SpotifyColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 2,
                      width: 16,
                      color: selected ? SpotifyColors.green : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _recentSearchesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
          child: Text(
            'Recent searches',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _recentQueries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  // TODO: if SearchScreen supports an initial query param,
                  // pass _recentQueries[i] through here to prefill search.
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: SpotifyColors.textTertiary.withOpacity(0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 14,
                        color: SpotifyColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _recentQueries[i],
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 40,
              color: SpotifyColors.textTertiary.withOpacity(0.6),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nothing to show',
              style: TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different filter above',
              style: TextStyle(
                color: SpotifyColors.textTertiary.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _homeService.dispose();
    super.dispose();
  }
}

// ═════════════════════════════════════════════
// LOADING VIEW
// ═════════════════════════════════════════════

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: SpotifyColors.green,
              strokeWidth: 2.5,
            ),
          ),
        ),
      ],
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _played = storage.getPlayedHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Text(
              'Your library',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
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
                      color: SpotifyColors.textTertiary.withOpacity(0.85),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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

// ═════════════════════════════════════════════
// MINI PLAYER
// ═════════════════════════════════════════════

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlayerController>();
    final song = controller.currentSong;
    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SpotifyColors.surface,
          border: Border(
            top: BorderSide(
              color: SpotifyColors.textTertiary.withOpacity(0.15),
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: YoutubeThumbnail(
                videoId: song.id,
                imageUrl: song.thumbnail,
                width: 40,
                height: 40,
                borderRadius: 4,
              ),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
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
            IconButton(
              icon: Icon(
                controller.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: SpotifyColors.textPrimary,
                size: 28,
              ),
              splashRadius: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => controller.isPlaying
                  ? audioHandler.pause()
                  : audioHandler.play(),
            ),
          ],
        ),
      ),
    );
  }
}