import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/extension_bridge.dart';
import '../services/extension_feed_service.dart';
import '../services/home_service.dart';
import '../services/listening_stats_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/listening_stats_utils.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/collection_card.dart';
import '../widgets/extension_feed_view.dart';
import '../widgets/listening_recap_card.dart';
import '../widgets/marquee.dart';
import '../widgets/media_shelf.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';
import '../widgets/source_picker_sheet.dart';
import '../widgets/start_listening_list.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/zen_nav_bar.dart';
import '../widgets/youtube_thumbnail.dart';
import 'collection_screen.dart';
import 'equalizer_screen.dart';
import 'extension_detail_screen.dart';
import 'extensions_screen.dart';
import 'import_spotify_screen.dart';
import 'player_screen.dart';
import 'radio_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'user_playlist_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  final _homeTabKey = GlobalKey<HomeTabState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: IndexedStack(
        index: _currentTab,
        children: [
          HomeTab(key: _homeTabKey),
          const SearchScreen(),
          const LibraryTab(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          ZenNavBar(
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
              // Echo: re-selecting Home opens the extension sheet.
              if (i == _currentTab) {
                if (i == 0) _homeTabKey.currentState?.openSourcePicker();
                return;
              }
              setState(() => _currentTab = i);
            },
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
  HomeTabState createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  final _homeService = HomeService();

  List<Song> _trendingNow = [];
  List<Song> _biggestHits = [];
  List<Song> _ytTrending = [];
  List<Song> _ytmHot = [];
  List<Song> _personalVideos = [];
  List<Song> _topCharts = [];
  List<Song> _startListening = [];
  List<Song> _recentlyPlayed = [];
  List<Collection> _collections = [];
  List<Collection> _newAlbums = [];

  // Source switcher state — id == null means the built-in sources.
  List<Map<String, dynamic>> _extensions = [];
  String? _activeExtensionId;
  int _feedRefreshTick = 0;

  bool _loading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _isRefreshing = true;
    _loadExtensions();
    if (mounted) setState(() {});
    try {
      // All futures created up front — they run in parallel.
      final trendingF = _homeService.getTrendingNow();
      final hitsF = _homeService.getBiggestHits();
      final ytF = _homeService.getYtTrendingSongs();
      final ytmHotF = _homeService.getYtmShelf('top hits this week');
      final personalF =
      _homeService.getPersonalizedVideos(_recentlyPlayed.take(3).toList());
      final topChartsF = _homeService.getTopCharts();
      final startF = _homeService.getStartListening();
      final collectionsF = _homeService.getHomeCollections();
      final albumsF = _homeService.getNewReleaseAlbums();

      final trendingNow = await trendingF;
      final biggestHits = await hitsF;
      final ytTrending = await ytF;
      final ytmHot = await ytmHotF;
      final personalVideos = await personalF;
      final topCharts = await topChartsF;
      final startListening = await startF;
      final collections = await collectionsF;
      final newAlbums = await albumsF;

      if (!mounted) return;
      setState(() {
        _trendingNow = trendingNow;
        _biggestHits = biggestHits;
        _ytTrending = ytTrending;
        _ytmHot = ytmHot;
        _personalVideos = personalVideos;
        _topCharts = topCharts;
        _startListening = startListening;
        _collections = collections;
        _newAlbums = newAlbums;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Home load failed: $e');
      _loading = false;
    }
    _loadRecent();
    _isRefreshing = false;
    if (mounted) setState(() {});
  }

  Future<void> _loadExtensions() async {
    final list = await ExtensionBridge.list();
    if (!mounted) return;
    String? activeId;
    for (final e in list) {
      if (e['isActive'] == true) activeId = e['id']?.toString();
    }
    setState(() {
      _extensions = list;
      _activeExtensionId = activeId;
    });
  }

  String _extensionName(String? id) {
    if (id == null) return 'Default';
    for (final e in _extensions) {
      if (e['id']?.toString() == id) {
        return e['name']?.toString() ?? 'Extension';
      }
    }
    return 'Extension';
  }

  void _showSourceSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SpotifyColors.surfaceLight,
        content: Text(
          message,
          style: const TextStyle(color: SpotifyColors.textPrimary),
        ),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  Future<void> _selectExtension(String? id) async {
    if (id == _activeExtensionId) return;
    final ok = id == null
        ? await ExtensionBridge.deselect()
        : await ExtensionBridge.select(id);
    if (!mounted) return;
    if (!ok) {
      _showSourceSnack('Could not switch to ${_extensionName(id)}');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _activeExtensionId = id);
    _showSourceSnack('Source: ${_extensionName(id)}');
  }

  Future<void> _openSourcePicker() async {
    await showSourcePickerSheet(
      context: context,
      extensions: _extensions,
      activeId: _activeExtensionId,
      onSelect: _selectExtension,
      onOpenManager: _openExtensionsManager,
    );
  }

  /// Public hook for the shell: re-tapping Home opens the picker.
  void openSourcePicker() => _openSourcePicker();

  void _openExtensionsManager() {
    pushSharedAxisY(context, const ExtensionsScreen())
        .then((_) => _loadExtensions());
  }

  Future<void> _refreshExtensionFeed() async {
    setState(() => _feedRefreshTick++);
  }

  /// Queues the tapped shelf's playable tracks and starts at [index] —
  /// next/prev work inside the queue; each track resolves via the
  /// extension bridge at play time.
  Future<void> _playExtensionTracks(List<ExtMedia> tracks, int index) async {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
    _showSourceSnack('Loading ${tracks[index].title}…');
    final songs = [
      for (final t in tracks)
        Song(
          id: t.id,
          title: t.title,
          artist: (t.subtitle ?? '').isNotEmpty ? t.subtitle! : 'Unknown',
          thumbnail: t.coverUrl ?? '',
          duration: Duration(milliseconds: t.durationMs ?? 0),
          extRaw: jsonEncode(t.raw),
        ),
    ];
    await audioHandler.setQueue(songs, startIndex: index);
    if (!mounted) return;
    _openPlayer();
  }

  /// Opens the detail page for a non-track card (album / playlist /
  /// artist) loaded through the extension's detail clients.
  void _openExtensionDetail(ExtMedia media) {
    pushSharedAxisY(
      context,
      ExtensionDetailScreen(
        media: media,
        onTrackTap: _playExtensionTracks,
        onMediaTap: _openExtensionDetail,
      ),
    );
  }

  void _shufflePlay(List<Song> songs) {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs)..shuffle();
    audioHandler.setQueue(shuffled, startIndex: 0);
    _openPlayer();
  }

  void _loadRecent() {
    if (!mounted) return;
    setState(() {
      _recentlyPlayed = storage.getPlayedHistory().take(10).toList();
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

  void _openCollection(Collection c) {
    pushSharedAxisY(context, CollectionScreen(collection: c))
        .then((_) => _loadRecent());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: Colors.transparent,
        backgroundColor: Colors.transparent,
        onRefresh: () => _activeExtensionId == null
            ? _loadAll()
            : _refreshExtensionFeed(),
        child: _loading
            ? _buildSkeletons()
            : ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_isRefreshing)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Center(child: WaveSpinner(size: 26)),
              ),

            _echoHeader(),

            if (_activeExtensionId != null)
              ExtensionHomeFeed(
                key: ValueKey(
                    'ext-feed-${_activeExtensionId ?? 'default'}-$_feedRefreshTick'),
                onTrackTap: _playExtensionTracks,
                onMediaTap: _openExtensionDetail,
              )
            else ...[
              if (wrappedEnabled.value &&
                  listeningStatsService.hasStats &&
                  listeningStatsService.availableMonthKeys.isNotEmpty)
                _recapSection(
                    listeningStatsService.availableMonthKeys.first),

              if (_recentlyPlayed.isNotEmpty)
                MediaShelfRow(
                  title: 'Recently played',
                  items: [
                    for (final s in _recentlyPlayed) ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_recentlyPlayed[i]),
                  playingIdStream: audioHandler.currentSongStream,
                ),

              if (_collections.isNotEmpty)
                _collectionRow('Playlists for you', _collections),
              if (_newAlbums.isNotEmpty)
                _collectionRow('New releases', _newAlbums),

              if (_personalVideos.isNotEmpty)
                MediaShelfRow(
                  title: _videoShelfTitle,
                  items: [
                    for (final s in _personalVideos) ShelfItem.fromSong(s)
                  ],
                  onTapItem: (i) => _playSong(_personalVideos[i]),
                  playingIdStream: audioHandler.currentSongStream,
                ),

              if (_startListening.isNotEmpty) _startListeningSection(),

              MediaShelfRow(
                title: 'Trending now',
                items: [for (final s in _trendingNow) ShelfItem.fromSong(s)],
                onTapItem: (i) => _playSong(_trendingNow[i]),
                onShuffle: () => _shufflePlay(_trendingNow),
                playingIdStream: audioHandler.currentSongStream,
              ),
              MediaShelfRow(
                title: "Today's biggest hits",
                items: [for (final s in _biggestHits) ShelfItem.fromSong(s)],
                onTapItem: (i) => _playSong(_biggestHits[i]),
                onShuffle: () => _shufflePlay(_biggestHits),
                playingIdStream: audioHandler.currentSongStream,
              ),
              MediaShelfRow(
                title: 'Trending on YouTube Music',
                items: [for (final s in _ytTrending) ShelfItem.fromSong(s)],
                onTapItem: (i) => _playSong(_ytTrending[i]),
                onShuffle: () => _shufflePlay(_ytTrending),
                playingIdStream: audioHandler.currentSongStream,
              ),
              MediaShelfRow(
                title: 'Hot on YouTube Music',
                items: [for (final s in _ytmHot) ShelfItem.fromSong(s)],
                onTapItem: (i) => _playSong(_ytmHot[i]),
                onShuffle: () => _shufflePlay(_ytmHot),
                playingIdStream: audioHandler.currentSongStream,
              ),
              MediaShelfRow(
                title: 'Top charts',
                items: [for (final s in _topCharts) ShelfItem.fromSong(s)],
                onTapItem: (i) => _playSong(_topCharts[i]),
                onShuffle: () => _shufflePlay(_topCharts),
                playingIdStream: audioHandler.currentSongStream,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletons() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: const [
        SizedBox(height: 8),
        SkeletonShelf(),
        SkeletonShelf(),
        SkeletonTile(),
        SkeletonTile(),
        SkeletonTile(),
        SkeletonShelf(itemCount: 5),
      ],
    );
  }

  /// Echo-style bar: source circle · centered title · settings circle.
  Widget _echoHeader() {
    Widget circle(IconData icon, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SpotifyColors.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 24, color: SpotifyColors.textPrimary),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              child: circle(
                _activeExtensionId == null
                    ? Icons.music_note_rounded
                    : Icons.extension_rounded,
                _openSourcePicker,
              ),
            ),
            const Text(
              'ZenMusic',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'PaytoneOne',
                color: SpotifyColors.textPrimary,
                fontSize: 20,
                letterSpacing: 0.2,
              ),
            ),
            Positioned(
              right: 0,
              child: circle(
                Icons.settings_outlined,
                    () => pushSharedAxisY(context, const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collectionRow(String title, List<Collection> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(title: title),
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

  Widget _recapSection(String monthKey) {
    final monthStats = listeningStatsService.monthStats(monthKey);
    final songs = listeningStatsService.monthTopSongs(monthKey, limit: 3);
    final minutes = monthDisplayMinutes(monthStats);
    if (minutes <= 0 && songs.isEmpty) return const SizedBox.shrink();

    final parts = monthKey.split('-');
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'
    ];
    final monthName = months[int.tryParse(parts[1]) ?? 1];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Your month',
          icon: FluentIcons.data_trending_24_filled,
        ),
        ListeningRecapCard(
          periodLabel: monthName,
          minutes: minutes,
          songs: songs,
          onSongTap: (i) {
            if (i >= songs.length) return;
            final map = songs[i];
            final id = map['ytid']?.toString();
            if (id == null || id.isEmpty) return;
            _playSong(Song(
              id: id,
              title: map['title']?.toString() ?? '',
              artist: map['artist']?.toString() ?? '',
              thumbnail: map['image']?.toString() ?? '',
              duration: Duration.zero,
            ));
          },
        ),
      ],
    );
  }

  Widget _startListeningSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(title: 'Start listening'),
        StartListeningList(
          songs: _startListening,
          onTap: _playSong,
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
// MINI PLAYER  (redesign-excluded by confirmation)
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

  void _handleVerticalDrag(DragUpdateDetails details) {
    if ((details.primaryDelta ?? 0) < -_dragThreshold) {
      widget.onOpen();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onTap: widget.onOpen,
            child: Container(
              height: MiniPlayer._playerHeight,
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      _Artwork(metadata: metadata),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeIn,
                          switchOutCurve: Curves.easeOut,
                          layoutBuilder:
                              (currentChild, previousChildren) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: KeyedSubtree(
                            key: ValueKey(metadata.id),
                            child: _Metadata(
                              title: metadata.title,
                              artist: metadata.artist ?? '',
                            ),
                          ),
                        ),
                      ),
                      _Controls(
                        playbackState: state,
                        hasNext: widget.hasNext && !audioHandler.isRadioMode,
                        totalDuration: metadata.duration ?? Duration.zero,
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
  });

  final PlaybackState playbackState;
  final bool hasNext;
  final Duration totalDuration;

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
            onPressed: audioHandler.skipToNext,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController = AnimationController(
    duration: const Duration(milliseconds: 4000),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _waveController.dispose();
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
                animation: _waveController,
                builder: (context, _) => CustomPaint(
                  size: const Size(48, 48),
                  painter: WaveRingPainter(
                    phase: _waveController.value * 2 * math.pi,
                    startAngle: -math.pi / 2,
                    sweepAngle: 2 * math.pi * progress.clamp(0.0, 1.0),
                    color: SpotifyColors.green,
                    backgroundColor:
                    SpotifyColors.textTertiary.withOpacity(0.25),
                    strokeWidth: 3,
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
                    AlwaysStoppedAnimation<Color>(SpotifyColors.green),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _played = storage.getPlayedHistory();
      _userPlaylists = storage.getUserPlaylists();
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
                    ),
                  ),
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
                  onPressed: () => pushSharedAxisY(
                    context,
                    const ImportSpotifyScreen(),
                  ).then((_) => _load()),
                  icon: const Icon(
                    FluentIcons.arrow_upload_24_regular,
                    size: 16,
                    color: SpotifyColors.green,
                  ),
                  label: const Text(
                    'Import',
                    style: TextStyle(fontSize: 13, color: SpotifyColors.green),
                  ),
                ),
              ],
            ),
          ),
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