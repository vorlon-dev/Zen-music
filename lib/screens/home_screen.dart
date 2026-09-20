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
          BottomNavigationBar(
            currentIndex: _currentTab,
            onTap: (i) => setState(() => _currentTab = i),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search),
                label: 'Search',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music_outlined),
                activeIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
            ],
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
      print('Home load failed: $e');
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
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // ── Greeting ──
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Text(
                'Good evening',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: SpotifyColors.textPrimary,
                ),
              ),
            ),

            // ── Filter chips ──
            _filterChips(),

            // ── Recent Searches (chips) ──
            if (_recentQueries.isNotEmpty && _showMusic())
              _recentSearchesSection(),

            // ── Recently Played ──
            if (_recentlyPlayed.isNotEmpty && _showMusic())
              HomeSection(
                title: 'Recently Played',
                songs: _recentlyPlayed,
                onTap: _playSong,
              ),

            // ── Music sections ──
            if (_showMusic()) ...[
              HomeSection(
                title: 'Trending Now',
                songs: _trendingNow,
                onTap: _playSong,
              ),
              HomeSection(
                title: 'New Releases for You',
                songs: _newReleases,
                onTap: _playSong,
              ),
              HomeSection(
                title: "Today's Biggest Hits",
                songs: _biggestHits,
                onTap: _playSong,
              ),
              StartListeningList(
                songs: _startListening,
                onTap: _playSong,
              ),
              HomeSection(
                title: 'Top Charts',
                songs: _topCharts,
                onTap: _playSong,
              ),
            ],

            // ── Video sections ──
            if (_showVideo())
              HomeSection(
                title: 'Recommended for Today',
                songs: _recommended,
                onTap: _playSong,
              ),

            // ── Empty state ──
            if (!_showMusic() && !_showVideo())
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: Text(
                    'Nothing to show',
                    style:
                    TextStyle(color: SpotifyColors.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _showMusic() => _filter == 'All' || _filter == 'Music';
  bool _showVideo() => _filter == 'All' || _filter == 'Videos';

  Widget _filterChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: ['All', 'Music', 'Videos'].map((f) {
          final selected = _filter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f),
              selected: selected,
              onSelected: (_) => setState(() => _filter = f),
              backgroundColor: SpotifyColors.surfaceLight,
              selectedColor: SpotifyColors.green,
              labelStyle: TextStyle(
                color: selected ? Colors.black : SpotifyColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
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
          padding: EdgeInsets.fromLTRB(20, 28, 20, 12),
          child: Text(
            'Recent Searches',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _recentQueries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              return ActionChip(
                label: Text(_recentQueries[i]),
                onPressed: () {
                  // Copy to search field is not directly supported here,
                  // but tapping does nothing harmful.
                },
                backgroundColor: SpotifyColors.surfaceLight,
                labelStyle: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(
                    color: SpotifyColors.textTertiary,
                    width: 0.5,
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
        SizedBox(height: 80),
        Center(
          child: CircularProgressIndicator(color: SpotifyColors.green),
        ),
        SizedBox(height: 24),
        Center(
          child: Text(
            'Loading your music…',
            style: TextStyle(color: SpotifyColors.textSecondary),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Your Library',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: SpotifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _played.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.library_music_outlined,
                      size: 72,
                      color: SpotifyColors.textTertiary,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Nothing here yet',
                      style: TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Songs you play will appear here',
                      style: TextStyle(
                        color: SpotifyColors.textTertiary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                itemCount: _played.length,
                itemBuilder: (context, i) {
                  final song = _played[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: YoutubeThumbnail(
                      videoId: song.id,
                      imageUrl: song.thumbnail,
                      width: 52,
                      height: 52,
                      borderRadius: 6,
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      audioHandler.startRadio(song);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PlayerScreen(),
                        ),
                      ).then((_) => _load());
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: SpotifyColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            YoutubeThumbnail(
              videoId: song.id,
              imageUrl: song.thumbnail,
              width: 42,
              height: 42,
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textPrimary,
                    ),
                  ),
                  Text(
                    song.artist,
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
            IconButton(
              icon: Icon(
                controller.isPlaying ? Icons.pause : Icons.play_arrow,
                color: SpotifyColors.textPrimary,
              ),
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