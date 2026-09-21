import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/collection.dart';
import '../models/song.dart';
import '../services/home_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/collection_card.dart';
import '../widgets/marquee.dart';
import '../widgets/section_header.dart';
import '../widgets/start_listening_list.dart';
import '../widgets/youtube_thumbnail.dart';
import 'collection_screen.dart';
import 'equalizer_screen.dart';
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
                  icon: Icon(FluentIcons.home_24_regular, size: 22),
                  activeIcon: Icon(FluentIcons.home_24_filled, size: 22),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(FluentIcons.search_24_regular, size: 22),
                  activeIcon: Icon(FluentIcons.search_24_filled, size: 22),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(FluentIcons.library_24_regular, size: 22),
                  activeIcon: Icon(FluentIcons.library_24_filled, size: 22),
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
  List<Song> _ytTrending = [];
  List<Song> _ytmHot = [];
  List<Song> _personalVideos = [];
  List<Song> _topCharts = [];
  List<Song> _startListening = [];
  List<Song> _recentlyPlayed = [];
  List<Collection> _collections = [];
  List<Collection> _newAlbums = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadAll();
  }

  void _loadRecent() {
    if (!mounted) return;
    setState(() {
      _recentlyPlayed = storage.getPlayedHistory().take(10).toList();
    });
  }

  Future<void> _loadAll() async {
    if (mounted) setState(() => _loading = true);
    _loadRecent();
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
      if (!mounted) return;
      setState(() => _loading = false);
    }
    _loadRecent();
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CollectionScreen(collection: c)),
    ).then((_) => _loadRecent());
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _videoShelfTitle {
    if (_recentlyPlayed.isEmpty) return 'Videos for you';
    final artist = _recentlyPlayed.first.artist.split(',').first.trim();
    if (artist.isEmpty) return 'Videos for you';
    return 'Because you listened to $artist';
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
            _greetingHeader(),

            // ── Cards first ──
            if (_collections.isNotEmpty)
              _collectionRow(
                'Playlists for you',
                _collections,
                FluentIcons.list_24_filled,
              ),
            if (_newAlbums.isNotEmpty)
              _collectionRow(
                'New releases',
                _newAlbums,
                FluentIcons.album_24_filled,
              ),

            // ── Recently played grid ──
            if (_recentlyPlayed.length >= 4) _recentlyPlayedGrid(),

            // ── Personalized videos from listening history ──
            if (_personalVideos.isNotEmpty)
              _songShelf(
                _videoShelfTitle,
                _personalVideos,
                FluentIcons.video_24_regular,
              ),

            // ── Start listening ──
            if (_startListening.isNotEmpty) _startListeningSection(),

            // ── Song shelves ──
            _songShelf(
              'Trending now',
              _trendingNow,
              FluentIcons.data_trending_24_filled,
            ),
            _songShelf(
              "Today's biggest hits",
              _biggestHits,
              FluentIcons.music_note_1_24_filled,
            ),
            _songShelf(
              'Trending on YouTube Music',
              _ytTrending,
              FluentIcons.person_24_filled,
            ),
            _songShelf(
              'Hot on YouTube Music',
              _ytmHot,
              FluentIcons.music_note_1_24_filled,
            ),
            _songShelf(
              'Top charts',
              _topCharts,
              FluentIcons.data_trending_24_filled,
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──

  Widget _greetingHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _greeting,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              color: SpotifyColors.textSecondary,
            ),
            tooltip: 'Equalizer',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EqualizerScreen()),
            ),
          ),
        ],
      ),
    );
  }

  // ── Collection carousel ──

  Widget _collectionRow(String title, List<Collection> items, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
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

  // ── Recently played: 2-column compact tiles ──

  Widget _recentlyPlayedGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recently played'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i + 1 < _recentlyPlayed.length; i += 2)
                Row(
                  children: [
                    Expanded(child: _recentTile(_recentlyPlayed[i])),
                    const SizedBox(width: 10),
                    Expanded(child: _recentTile(_recentlyPlayed[i + 1])),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recentTile(Song song) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _playSong(song),
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: SpotifyColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(8)),
              child: YoutubeThumbnail(
                videoId: song.id,
                imageUrl: song.thumbnail,
                width: 56,
                height: 56,
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
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: SpotifyColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  // ── Start listening ──

  Widget _startListeningSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Start listening',
          icon: FluentIcons.sparkle_24_filled,
        ),
        StartListeningList(
          songs: _startListening,
          onTap: _playSong,
        ),
      ],
    );
  }

  // ── Song shelf: horizontal mini-cards ──

  Widget _songShelf(String title, List<Song> songs, IconData icon) {
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title, icon: icon),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: songs.length.clamp(0, 15),
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final song = songs[i];
              return GestureDetector(
                onTap: () => _playSong(song),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: YoutubeThumbnail(
                          videoId: song.id,
                          imageUrl: song.thumbnail,
                          width: 140,
                          height: 140,
                          borderRadius: 10,
                        ),
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
// MINI PLAYER
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
                        hasNext: widget.hasNext,
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

class _CircularPlayButton extends StatelessWidget {
  const _CircularPlayButton({
    required this.playbackState,
    required this.totalDuration,
  });

  final PlaybackState playbackState;
  final Duration totalDuration;

  @override
  Widget build(BuildContext context) {
    final processingState = playbackState.processingState;
    final isPlaying = playbackState.playing;
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
          final progress = totalDuration.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds / totalDuration.inMilliseconds)
              .clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(48, 48),
                painter: _CircularProgressPainter(
                  progress: progress,
                  backgroundColor:
                  SpotifyColors.textTertiary.withOpacity(0.25),
                  progressColor: SpotifyColors.green,
                  strokeWidth: 3,
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

class _CircularProgressPainter extends CustomPainter {
  _CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;

  final waveAmplitude = 1.5;
  final waveFrequency = 12.0;
  final animationValue = 0.0;

  Path _buildWavyArcPath(Size size, double startAngle, double sweepAngle) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = (size.width - strokeWidth) / 2;
    final steps = (sweepAngle.abs() * 180 / math.pi).round().clamp(4, 720);
    final path = Path();

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final angle = startAngle + sweepAngle * t;
      final wave =
          waveAmplitude * math.sin(waveFrequency * angle + animationValue);
      final r = baseRadius + wave;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      _buildWavyArcPath(size, -math.pi / 2, 2 * math.pi),
      trackPaint,
    );

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(
        _buildWavyArcPath(size, -math.pi / 2, 2 * math.pi * progress),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularProgressPainter old) =>
      old.progress != progress ||
          old.backgroundColor != backgroundColor ||
          old.progressColor != progressColor;
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
                    Icons.tune_rounded,
                    color: SpotifyColors.textSecondary,
                  ),
                  tooltip: 'Equalizer',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EqualizerScreen()),
                  ),
                ),
              ],
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