// ZenMusic · vorlon-dev
//
// Echo-style mobile HOME page. Used ONLY when the mobile shell is active
// (Android / iOS) — the desktop keeps lib/desktop/screens/home/home_page.dart
// untouched, exactly as before.
//
// The visual language is ported 1:1 from Echo Music's Compose HomeScreen
// (github.com/EchoMusicApp/Echo-Music):
//   * header row: bold app title + circular action button
//   * filter-chip pills (surfaceContainer, radius 12)
//   * hero carousel: 360 dp tall, extra-large (28) corners, 1 dp
//     outlineVariant border, transparent→black(70%) bottom gradient,
//     bold white title + artists, auto-advances every 5 s
//   * NavigationTitle: UPPERCASE bold onSurfaceVariant + outlined
//     "Play all" pill (24 dp high, radius 12)
//   * song shelves render as rounded card rows (surfaceContainer, 48 dp
//     art with the Echo thumbnail corner)
//   * every other shelf renders as a 128 dp square-art horizontal grid
//   * the exact loading skeleton Echo uses: one shared 800 ms linear
//     shimmer band (surfaceVariant @ 25% base / 50% band, 250 ms pause)
//     over chips → hero blocks → grid rows → generic row
//
// Data, click routing, cache-first loading and pagination all come from the
// existing HomeCubit / YTMusic pipeline, so nothing about playback changes:
// the page paints instantly from the disk cache, shows the skeleton only
// when there is truly nothing yet, and NEVER blocks on the network.
//
// MOBILE differences vs the desktop home (desktop is byte-untouched):
//   * no SpotifyHomeSection — its feed fetches lagged the phone;
//   * no Billboard/Spotify chart row (HomeCubit fetchCharts: false);
//   * MusicMetrics chart shelves instead (see EchoChartsGroup below),
//     playing from YouTube Music only via the established isChart path.

import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:expressive_refresh/expressive_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart' show MediaItem;

import 'package:zenmusic/desktop/screens/home/cubit/home_cubit.dart';
import 'package:zenmusic/desktop/screens/home/smart_mix_card.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/media_player.dart'
    show MediaPlayer, ButtonState;
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/enhanced_image.dart';
import 'package:zenmusic/desktop/utils/internet_guard.dart';
import 'package:zenmusic/desktop/ytmusic/ytm_account_section.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/mobile/home/charts/chart_config.dart';
import 'package:zenmusic/mobile/home/charts/musicmetrics_service.dart';

// ── Echo dimensions ported from core/…/constants/Dimensions.kt ──────────────

const double _kThumbnailCorner = 6; // ThumbnailCornerRadius = 6.dp
const double _kGridItemSize = 128; // GridThumbnailHeight (BIG) = 128.dp
const double _kHeroHeight = 360; // hero carousel height = 360.dp
const double _kHeroCorner = 28; // MaterialTheme.shapes.extraLarge
const double _kListThumb = 48; // ListThumbnailSize = 48.dp

// Shimmer: 800 ms sweep + 250 ms pause, linear, restart (Echo ShimmerHost).
const int _kShimmerSweepMs = 800;
const int _kShimmerPauseMs = 250;

class EchoHomePage extends StatelessWidget {
  const EchoHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(GetIt.I<YTMusic>(), fetchCharts: false)..fetch(),
      child: const _EchoHomeBody(),
    );
  }
}

class _EchoHomeBody extends StatefulWidget {
  const _EchoHomeBody();

  @override
  State<_EchoHomeBody> createState() => _EchoHomeBodyState();
}

class _EchoHomeBodyState extends State<_EchoHomeBody> {
  late ScrollController _scrollController;

  final GlobalKey<EchoChartsGroupState> _chartsGroupKey =
      GlobalKey<EchoChartsGroupState>();

  final GlobalKey<YtmAccountSectionState> _ytmSectionKey =
      GlobalKey<YtmAccountSectionState>();

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    YtmAuth.instance.loggedIn.addListener(_onYtmAuthChanged);
  }

  void _onYtmAuthChanged() {
    if (!mounted) return;
    context.read<HomeCubit>().fetch();
  }

  @override
  void dispose() {
    YtmAuth.instance.loggedIn.removeListener(_onYtmAuthChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Trigger the next page slightly before the very end (Echo does it when
    // the last visible item is within ~3 items of the end).
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  Future<void> _loadMore() async {
    final cubit = context.read<HomeCubit>();
    final state = cubit.state;
    if (state is! HomeSuccess) return;
    if (state.loadingMore || state.continuation == null) return;
    await cubit.fetchNext();
  }

  Future<void> _refresh() async {
    _chartsGroupKey.currentState?.reload();
    _ytmSectionKey.currentState?.reload();
    await context.read<HomeCubit>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return InternetGuard(
      onInternetRestored: context.read<HomeCubit>().fetch,
      child: Scaffold(
        body: ExpressiveRefreshIndicator(
          onRefresh: _refresh,
          child: BlocBuilder<HomeCubit, HomeState>(
            builder: (context, state) {
              switch (state) {
                case HomeLoading():
                  return const _EchoSkeleton();
                case HomeError():
                  return Center(child: Text(state.message ?? ''));
                case HomeSuccess():
                  return _EchoFeed(
                    state: state,
                    scrollController: _scrollController,
                    chartsKey: _chartsGroupKey,
                    ytmKey: _ytmSectionKey,
                  );
              }
            },
          ),
        ),
      ),
    );
  }
}

// ── Feed ─────────────────────────────────────────────────────────────────────

class _EchoFeed extends StatelessWidget {
  const _EchoFeed({
    required this.state,
    required this.scrollController,
    required this.chartsKey,
    required this.ytmKey,
  });

  final HomeSuccess state;
  final ScrollController scrollController;
  final GlobalKey<EchoChartsGroupState> chartsKey;
  final GlobalKey<YtmAccountSectionState> ytmKey;

  /// The first song shelf becomes the big Echo hero carousel.
  Map? _heroSection() {
    for (final sec in state.sections) {
      if (sec is! Map) continue;
      final contents = sec['contents'];
      if (contents is! List || contents.length < 3) continue;
      int songs = 0;
      for (final item in contents) {
        if (item is Map && item['videoId'] != null) songs++;
      }
      if (songs >= contents.length * 0.6) return sec;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final hero = _heroSection();
    final shelves = <Map>[
      for (final sec in state.sections)
        if (sec is Map && !identical(sec, hero)) sec,
    ];

    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Header — Echo's top bar: bold title + circular action.
        SliverToBoxAdapter(child: _EchoHeader(topInset: topInset)),

        // Filter chips (Echo pills, Zen /chip behaviour preserved).
        if (state.chips.isNotEmpty)
          SliverToBoxAdapter(child: _EchoChipsRow(chips: state.chips)),

        // Zen feature cards keep working, placed like Echo's entry card.
        SliverToBoxAdapter(child: SmartMixCard()),

        // MusicMetrics charts — Global 200 / YouTube / Apple Music / iTunes /
        // Deezer / Spotify (user's IP region) / Top Albums. Replaces the old
        // Spotify home section, whose feed fetches made the phone lag. Song
        // charts use the same compact box strip as Top Albums (no endless
        // inline list); tapping a box opens the full ranked chart, billboard
        // style, and every row plays from YouTube Music via the established
        // isChart path. Every shelf uses the exact Echo skeleton while loading.
        EchoChartsGroup(key: chartsKey),

        SliverToBoxAdapter(child: YtmAccountSection(key: ytmKey)),

        // Hero carousel.
        if (hero != null && (hero['contents'] as List?)?.isNotEmpty == true)
          SliverToBoxAdapter(
            child: _EchoHeroCarousel(items: hero['contents'] as List),
          ),

        // Sections.
        ...shelves.map((sec) {
          final contents = (sec['contents'] as List?) ?? const [];
          if (contents.isEmpty) {
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          }
          int songs = 0;
          for (final item in contents) {
            if (item is Map && item['videoId'] != null) songs++;
          }
          if (songs >= contents.length * 0.6) {
            return _EchoSongSection(
              title: sec['title']?.toString() ?? '',
              items: contents,
            );
          }
          return _EchoGridSection(
            title: sec['title']?.toString() ?? '',
            items: contents,
          );
        }),

        // Echo's bottom loading shimmer: shown while a continuation exists,
        // so the next page always has a place to grow into.
        if (state.continuation != null)
          const SliverToBoxAdapter(child: _EchoLoadingMoreSkeleton()),

        SliverPadding(
          padding: EdgeInsets.only(top: 8, bottom: bottomInset + 30),
        ),
      ],
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _EchoHeader extends StatelessWidget {
  const _EchoHeader({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topInset + 10, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'ZenMusic',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: scheme.surfaceContainer,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: 'Listen Together'.tr,
              onPressed: () => context.push('/listen'),
              icon: const Icon(Icons.groups_rounded, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chips ────────────────────────────────────────────────────────────────────

class _EchoChipsRow extends StatelessWidget {
  const _EchoChipsRow({required this.chips});

  final List chips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          for (final chip in chips)
            if (chip is Map && chip['title'] != null) ...[
              Material(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.go('/chip', extra: chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(
                      chip['title'].toString(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
        ],
      ),
    );
  }
}

// ── Hero carousel ────────────────────────────────────────────────────────────

class _EchoHeroCarousel extends StatefulWidget {
  const _EchoHeroCarousel({required this.items});

  final List items;

  @override
  State<_EchoHeroCarousel> createState() => _EchoHeroCarouselState();
}

class _EchoHeroCarouselState extends State<_EchoHeroCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();
    // Hero width = screen − 32 dp (Echo), neighbours peek at the edges.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final dpr = view.devicePixelRatio;
    final width = dpr > 0 ? view.physicalSize.width / dpr : 0.0;
    final fraction = width > 0 ? (width - 32) / width : 0.9;
    _pageController = PageController(
      viewportFraction: fraction.clamp(0.55, 0.95),
    );
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _advance());
  }

  void _advance() {
    if (!mounted) return;
    if (_userScrolling) return;
    if (!_pageController.hasClients) return;
    final items = widget.items;
    if (items.length < 2) return;
    final page = _pageController.page;
    if (page == null) return;
    final next = (page.round() + 1) % items.length;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) _userScrolling = true;
        if (n is ScrollEndNotification) _userScrolling = false;
        return false;
      },
      child: SizedBox(
        height: _kHeroHeight,
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            if (item is! Map) return const SizedBox.shrink();
            return Padding(
              // 8 dp between cards, like Echo's itemSpacing.
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _EchoHeroCard(item: item, scheme: scheme),
            );
          },
        ),
      ),
    );
  }
}

class _EchoHeroCard extends StatelessWidget {
  const _EchoHeroCard({required this.item, required this.scheme});

  final Map item;
  final ColorScheme scheme;

  Future<void> _open(BuildContext context) async {
    if (item['videoId'] == null) {
      if (item['endpoint'] != null) {
        context.push('/browse', extra: {'endpoint': item['endpoint']});
      }
      return;
    }
    final mp = GetIt.I<MediaPlayer>();
    final current = mp.currentSongNotifier.value;
    if (current != null && current.id == item['videoId']) {
      await mp.togglePlayPause();
      return;
    }
    await mp.playSong(Map<String, dynamic>.from(item));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final thumbnails = (item['thumbnails'] as List?) ?? const [];
    final url = thumbnails.isNotEmpty
        ? getEnhancedImage(
            thumbnails.first['url']?.toString() ?? '',
            dp: mediaQuery.devicePixelRatio,
            width: mediaQuery.size.width - 40,
          )
        : '';

    return ValueListenableBuilder<MediaItem?>(
      valueListenable: GetIt.I<MediaPlayer>().currentSongNotifier,
      builder: (context, currentSong, _) {
        final isActive =
            currentSong != null && currentSong.id == item['videoId'];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_kHeroCorner),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_kHeroCorner),
              side: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
            child: InkWell(
              onTap: () => _open(context),
              onLongPress: item['videoId'] != null
                  ? () => Modals.showSongBottomModal(context, item)
                  : null,
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (url.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox.expand(),
                        errorWidget: (_, __, ___) => const SizedBox.expand(),
                      ),
                    // transparent → transparent → black(70%), Echo exact.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    if (isActive)
                      ValueListenableBuilder<ButtonState>(
                        valueListenable: GetIt.I<MediaPlayer>().buttonState,
                        builder: (context, button, _) {
                          if (button != ButtonState.playing) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: scheme.onSurface,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.volume_up,
                                  size: 18,
                                  color: scheme.onPrimary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                            Text(
                              _subtitleOf(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.8),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── NavigationTitle (Echo exact) ─────────────────────────────────────────────

class _EchoSectionTitle extends StatelessWidget {
  const _EchoSectionTitle({required this.title, this.onPlayAll});

  final String title;
  final VoidCallback? onPlayAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          if (onPlayAll != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 24,
              child: OutlinedButton(
                onPressed: onPlayAll,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  foregroundColor: scheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: Theme.of(context).textTheme.labelSmall,
                ),
                child: const Text('Play all'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sections ─────────────────────────────────────────────────────────────────

class _EchoSongSection extends StatelessWidget {
  const _EchoSongSection({required this.title, required this.items});

  final String title;
  final List items;

  @override
  Widget build(BuildContext context) {
    final playable = [
      for (final item in items)
        if (item is Map && item['videoId'] != null)
          Map<String, dynamic>.from(item),
    ];
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _EchoSectionTitle(
            title: title,
            onPlayAll: playable.isNotEmpty
                ? () => GetIt.I<MediaPlayer>().playAll(List.from(playable))
                : null,
          ),
        ),
        SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            if (item is! Map) return const SizedBox.shrink();
            return _EchoSongRow(song: item);
          },
        ),
      ],
    );
  }
}

class _EchoSongRow extends StatelessWidget {
  const _EchoSongRow({required this.song});

  final Map song;

  Future<void> _open(BuildContext context) async {
    // Same routing as the desktop SongTile.
    if (song['endpoint'] != null && song['videoId'] == null) {
      context.push('/browse', extra: {'endpoint': song['endpoint']});
      return;
    }
    if (song['isChart'] == true) {
      BottomMessage.showText(
          context, "Searching and playing ${song['title']}...");
      final query = "${song['title']} ${song['subtitle'] ?? ''}";
      try {
        final result = await GetIt.I<YTMusic>().search(query, filter: 'songs');
        if (!context.mounted) return;
        final sections = result['sections'] as List?;
        final section =
            (sections != null && sections.isNotEmpty) ? sections[0] : null;
        final contents = section is Map ? section['contents'] as List? : null;
        if (contents != null && contents.isNotEmpty) {
          await GetIt.I<MediaPlayer>()
              .playSong(Map<String, dynamic>.from(contents[0]));
        } else {
          BottomMessage.showText(context, "Song not found");
        }
      } catch (_) {
        if (context.mounted) {
          BottomMessage.showText(context, "Error playing song");
        }
      }
      return;
    }
    await GetIt.I<MediaPlayer>().playSong(Map<String, dynamic>.from(song));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnails = (song['thumbnails'] as List?) ?? const [];
    String url = '';
    if (thumbnails.isNotEmpty) {
      url = thumbnails.first['url']?.toString() ?? '';
      for (final el in thumbnails) {
        final w = el['width'];
        if (w != null && w >= 50) {
          url = el['url']?.toString() ?? url;
          break;
        }
      }
    }
    final isBrowse = song['endpoint'] != null && song['videoId'] == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _open(context),
          onLongPress: song['videoId'] != null
              ? () => Modals.showSongBottomModal(context, song)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(_kThumbnailCorner + 4),
                  child: url.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: getEnhancedImage(url, width: _kListThumb),
                          width: _kListThumb,
                          height: _kListThumb,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          placeholder: (_, __) => Container(
                              color: scheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => Container(
                              color: scheme.surfaceContainerHighest),
                        )
                      : Container(
                          width: _kListThumb,
                          height: _kListThumb,
                          color: scheme.surfaceContainerHighest,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (song['explicit'] == true)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.explicit,
                                size: 14,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              _subtitleOf(song),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                isBrowse
                    ? Icon(Icons.chevron_right,
                        color: scheme.onSurfaceVariant)
                    : song['videoId'] != null
                        ? SizedBox(
                            height: 40,
                            width: 40,
                            child: IconButton(
                              onPressed: () =>
                                  Modals.showSongBottomModal(context, song),
                              icon: Icon(Icons.more_vert,
                                  color: scheme.onSurfaceVariant, size: 20),
                            ),
                          )
                        : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EchoGridSection extends StatelessWidget {
  const _EchoGridSection({required this.title, required this.items});

  final String title;
  final List items;

  @override
  Widget build(BuildContext context) {
    final playable = [
      for (final item in items)
        if (item is Map && item['videoId'] != null) item,
    ];
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _EchoSectionTitle(
            title: title,
            onPlayAll: playable.isNotEmpty
                ? () => GetIt.I<MediaPlayer>().playAll(
                    [for (final s in playable) Map<String, dynamic>.from(s)])
                : null,
          ),
        ),
        SliverToBoxAdapter(
          child: _EchoAnimatedStrip(
            builder: (direction) => SizedBox(
              height: _kGridItemSize + 74,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  if (item is! Map) return const SizedBox.shrink();
                  return _EchoSlideRotateIn(
                    direction: direction,
                    child: _EchoGridCard(item: item),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EchoGridCard extends StatelessWidget {
  const _EchoGridCard({required this.item});

  final Map item;

  Future<void> _open(BuildContext context) async {
    // Same routing as the desktop grid card.
    if (item['chartUrl'] != null) {
      context.push('/chart_details', extra: item['chartUrl']);
      return;
    }
    if (item['endpoint'] != null && item['videoId'] == null) {
      context.push('/browse', extra: {'endpoint': item['endpoint']});
      return;
    }
    await GetIt.I<MediaPlayer>().playSong(Map<String, dynamic>.from(item));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final thumbnails = (item['thumbnails'] as List?) ?? const [];
    final url = thumbnails.isNotEmpty
        ? getEnhancedImage(
            thumbnails.first['url']?.toString() ?? '',
            dp: mediaQuery.devicePixelRatio,
            width: _kGridItemSize,
          )
        : '';
    final isArtist = item['type'] == 'ARTIST';
    final radius = isArtist
        ? BorderRadius.circular(_kGridItemSize / 2)
        : BorderRadius.circular(_kThumbnailCorner);

    return SizedBox(
      width: _kGridItemSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(context),
              onLongPress: () {
                if (item['videoId'] != null) {
                  Modals.showSongBottomModal(context, item);
                } else if (item['playlistId'] != null) {
                  Modals.showPlaylistBottomModal(context, item);
                }
              },
              child: SizedBox(
                width: _kGridItemSize,
                height: _kGridItemSize,
                child: url.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox.expand(),
                        errorWidget: (_, __, ___) => const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item['title']?.toString() ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(height: 1.25, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 1),
          Text(
            _subtitleOf(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Shared subtitle logic (identical to desktop SectionItem) ────────────────

String _subtitleOf(Map item) {
  final sub = <String>[];
  final artists = item['artists'];
  if (artists is List) {
    for (final artist in artists) {
      if (artist is Map && artist['name'] != null) {
        sub.add(artist['name'].toString());
      }
    }
  }
  if (sub.isEmpty && item['album'] is Map && item['album']['name'] != null) {
    sub.add(item['album']['name'].toString());
  }
  final joined = sub.join(' · ');
  return item['subtitle']?.toString() ?? joined;
}

// ── Loading skeleton (Echo exact) ────────────────────────────────────────────

/// One shared shimmer timeline for every placeholder on screen: a single
/// AnimationController drives all boxes, each box repaints only its own
/// small bounds inside a RepaintBoundary. No blur, no saveLayer — the band
/// is a plain LinearGradient sweep, so it stays smooth on low-end phones.
class _EchoShimmerScope extends StatefulWidget {
  const _EchoShimmerScope({required this.child});

  final Widget child;

  @override
  State<_EchoShimmerScope> createState() => _EchoShimmerScopeState();

  static _EchoShimmerScopeState? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_EchoShimmerInherited>()
        ?.state;
  }
}

class _EchoShimmerScopeState extends State<_EchoShimmerScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration:
        const Duration(milliseconds: _kShimmerSweepMs + _kShimmerPauseMs),
  )..repeat();

  /// 0→1 during the sweep, then holds at 1 for the pause.
  double get band =>
      (_controller.value * (_kShimmerSweepMs + _kShimmerPauseMs) /
          _kShimmerSweepMs)
          .clamp(0.0, 1.0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EchoShimmerInherited(state: this, child: widget.child);
  }
}

class _EchoShimmerInherited extends InheritedWidget {
  const _EchoShimmerInherited({required this.state, required super.child});

  final _EchoShimmerScopeState state;

  @override
  bool updateShouldNotify(_EchoShimmerInherited oldWidget) => false;
}

class _EchoShimmerBox extends StatelessWidget {
  const _EchoShimmerBox({
    this.width,
    this.height,
    this.borderRadius,
    this.expand = false,
  });

  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scope = _EchoShimmerScope.of(context);
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.25);
    final bandColor = scheme.surfaceContainerHighest.withValues(alpha: 0.50);

    // The gradient MUST be rebuilt inside the AnimatedBuilder so the box
    // actually repaints as the band sweeps across.
    Widget boxBuilder(BuildContext context, Widget? _) {
      final t = scope?.band ?? 0.0;
      Widget box = DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: borderRadius,
          gradient: scope == null
              ? null
              : LinearGradient(
                  begin: Alignment(-3 + 4 * t, 0),
                  end: Alignment(-1 + 4 * t, 0),
                  colors: [base, bandColor, base],
                ),
        ),
      );
      if (expand) {
        box = SizedBox.expand(child: box);
      } else {
        box = SizedBox(width: width, height: height, child: box);
      }
      return box;
    }

    if (scope == null) {
      return RepaintBoundary(child: boxBuilder(context, null));
    }
    return RepaintBoundary(
      child: AnimatedBuilder(animation: scope._controller, builder: boxBuilder),
    );
  }
}

/// Echo TextPlaceholder: 16 dp tall by default, a random 25–75% width,
/// pinned to the leading edge (a fixed widthFactor overrides the random one).
class _EchoTextPlaceholder extends StatefulWidget {
  const _EchoTextPlaceholder({
    this.height = 16,
    this.borderRadius,
    this.widthFactor,
  });

  final double height;
  final BorderRadius? borderRadius;
  final double? widthFactor;

  @override
  State<_EchoTextPlaceholder> createState() => _EchoTextPlaceholderState();
}

class _EchoTextPlaceholderState extends State<_EchoTextPlaceholder> {
  late final double _factor = 0.25 + Random().nextDouble() * 0.5;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widget.widthFactor ?? _factor,
          child: _EchoShimmerBox(
            height: widget.height,
            borderRadius: widget.borderRadius,
          ),
        ),
      ),
    );
  }
}

/// Echo GridItemPlaceHolder: square thumbnail (6 dp corners) + two text
/// placeholders below, wrapped in 12 dp padding.
class _EchoGridPlaceholder extends StatelessWidget {
  const _EchoGridPlaceholder({this.fillMaxWidth = false});

  final bool fillMaxWidth;

  @override
  Widget build(BuildContext context) {
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fillMaxWidth
            ? AspectRatio(
                aspectRatio: 1,
                child: _EchoShimmerBox(
                  borderRadius: BorderRadius.circular(_kThumbnailCorner),
                ),
              )
            : _EchoShimmerBox(
                width: _kGridItemSize,
                height: _kGridItemSize,
                borderRadius: BorderRadius.circular(_kThumbnailCorner),
              ),
        const SizedBox(height: 6),
        const _EchoTextPlaceholder(),
        const _EchoTextPlaceholder(),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(12),
      child: fillMaxWidth ? inner : SizedBox(width: _kGridItemSize, child: inner),
    );
  }
}

/// The full-screen skeleton, composed exactly like Echo's `loading_shimmer`
/// item: chips row → hero blocks → speed-dial grid → generic row.
class _EchoSkeleton extends StatelessWidget {
  const _EchoSkeleton();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return _EchoShimmerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: topInset + 10, bottom: bottomInset + 30),
        children: [
          // Header placeholder.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: 0.35,
                      child: _EchoShimmerBox(
                        height: 28,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                _EchoShimmerBox(
                  width: 40,
                  height: 40,
                  borderRadius: BorderRadius.circular(20),
                ),
              ],
            ),
          ),

          // Chips skeleton: 5 × 72×30 rounded-16 pills (Echo exact).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  _EchoShimmerBox(
                    width: 72,
                    height: 30,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),

          // Hero skeleton: big extra-large blocks peeking at the edges.
          SizedBox(
            height: _kHeroHeight + 12,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, __) => _EchoShimmerBox(
                width: MediaQuery.of(context).size.width - 48,
                borderRadius: BorderRadius.circular(_kHeroCorner),
              ),
            ),
          ),

          // Speed-dial skeleton: title + 2 rows × 3 grid placeholders.
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EchoTextPlaceholder(height: 36, widthFactor: 0.4),
          ),
          for (var r = 0; r < 2; r++)
            Row(
              children: [
                for (var c = 0; c < 3; c++)
                  Expanded(child: _EchoGridPlaceholder(fillMaxWidth: true)),
              ],
            ),

          // Generic row skeleton: title + 4 grid placeholders.
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EchoTextPlaceholder(height: 36, widthFactor: 0.5),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) _EchoGridPlaceholder(),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

/// Echo's bottom "loading more" shimmer (generic row skeleton only).
class _EchoLoadingMoreSkeleton extends StatelessWidget {
  const _EchoLoadingMoreSkeleton();

  @override
  Widget build(BuildContext context) {
    return _EchoShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EchoTextPlaceholder(height: 36, widthFactor: 0.5),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) _EchoGridPlaceholder(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── MusicMetrics charts (mobile home only) ───────────────────────────────────

/// The MusicMetrics chart shelves shown on the mobile Echo home, in the
/// user-defined order (see ChartConfig.homeChartOrder):
/// Global 200 → YouTube → Apple Music → iTunes → Deezer → Spotify (the
/// user's IP region) → Top Albums.
///
/// Lag rules this widget obeys:
///   * cached charts paint on the FIRST frame (cache is read in initState,
///     no skeleton flash for known data);
///   * uncached charts show the exact Echo skeleton and are replaced the
///     moment their fetch lands (12 s cap) — a slow or failing chart never
///     blocks the feed around it;
///   * parsing happens in a background isolate (see MusicMetricsService);
///   * a failing chart with no cache is hidden, nothing shows an error;
///   * playback is YouTube Music only, through the established isChart path
///     (YTMusic.search → MediaPlayer), so media_player.dart stays untouched.
///
/// The widget returns a SliverMainAxisGroup so each shelf keeps its own lazy
/// slivers — nothing on this page is built eagerly.
class EchoChartsGroup extends StatefulWidget {
  const EchoChartsGroup({super.key});

  @override
  State<EchoChartsGroup> createState() => EchoChartsGroupState();
}

class EchoChartsGroupState extends State<EchoChartsGroup> {
  final MusicMetricsService _service = MusicMetricsService();
  late final List<_ChartSlot> _slots;

  @override
  void initState() {
    super.initState();
    _slots = [for (final id in ChartConfig.homeChartOrder) _ChartSlot(id)];
    // Disk cache first: charts seen before paint on frame one.
    for (final slot in _slots) {
      slot.page = _service.cached(slot.id);
      slot.loading = slot.page == null;
    }
    // Network freshening after the first frame (setState-safe).
    Future.microtask(_loadAll);
  }

  Future<void> _loadAll({bool force = false}) async {
    await Future.wait([
      for (final slot in _slots) _loadSlot(slot, force: force),
    ]);
  }

  Future<void> _loadSlot(_ChartSlot slot, {bool force = false}) async {
    final page = await _service.fetch(slot.id, force: force);
    if (!mounted) return;
    setState(() {
      if (page != null && page.items.isNotEmpty) {
        slot.page = page;
        slot.loading = false;
        slot.failed = false;
      } else if (slot.page == null) {
        // No data ever arrived for this chart — hide it. Stale content
        // already on screen is kept as-is (never wiped by a failed refresh).
        slot.loading = false;
        slot.failed = true;
      }
    });
  }

  /// Pull-to-refresh: re-fetch everything, keep stale rows visible while
  /// the refresh runs (smoother than flashing skeletons again).
  Future<void> reload() => _loadAll(force: true);

  String _displayTitle(_ChartSlot slot) {
    if (slot.id == MusicChartId.spotify) {
      // MusicMetrics h1 looks like "Spotify Weekly Top Songs · India".
      final h1 = slot.page?.title ?? '';
      if (h1.contains('·')) {
        final country = h1.split('·').last.trim();
        if (country.isNotEmpty) return 'Spotify · $country';
      }
      return 'Spotify Charts';
    }
    return slot.id.shortTitle;
  }

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        for (final slot in _slots) _buildSlot(context, slot),
      ],
    );
  }

  Widget _buildSlot(BuildContext context, _ChartSlot slot) {
    final page = slot.page;
    if (page == null || page.items.isEmpty) {
      if (slot.loading) {
        return const SliverToBoxAdapter(child: _EchoChartsSkeleton());
      }
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    if (page.isAlbum) {
      return _EchoAlbumChartSection(title: _displayTitle(slot), items: page.items);
    }
    return _EchoChartStripSection(title: _displayTitle(slot), items: page.items);
  }
}

class _ChartSlot {
  final MusicChartId id;
  MusicChartPage? page;
  bool loading;
  bool failed;

  _ChartSlot(this.id) : loading = true, failed = false;
}

// ── Chart playback (YouTube Music only, zero media_player changes) ──────────

/// Resolves a chart entry to YouTube Music and plays it, with a title-only
/// retry. Mirrors the app's established isChart search-and-play path.
Future<void> _playChartEntry(BuildContext context, MusicChartEntry entry) async {
  BottomMessage.showText(context, 'Searching and playing ${entry.title}...');
  Map? song = await _searchFirstSong('${entry.title} ${entry.artist}'.trim(),
      const Duration(seconds: 10));
  song ??= await _searchFirstSong(entry.title, const Duration(seconds: 8));
  if (!context.mounted) return;
  if (song != null) {
    await GetIt.I<MediaPlayer>().playSong(Map<String, dynamic>.from(song));
  } else {
    BottomMessage.showText(context, "Couldn't find on YouTube Music");
  }
}

Future<Map?> _searchFirstSong(String query, Duration timeout) async {
  try {
    final result = await GetIt.I<YTMusic>().search(query, filter: 'songs')
        .timeout(timeout);
    final sections = result['sections'] as List?;
    if (sections != null && sections.isNotEmpty) {
      final contents = (sections[0] as Map)['contents'] as List?;
      if (contents != null && contents.isNotEmpty && contents[0] is Map) {
        return contents[0] as Map;
      }
    }
  } catch (_) {/* caller decides the fallback */}
  return null;
}

/// "Play all" hands the isChart maps straight to MediaPlayer.playAll, which
/// resolves each row through YouTube Music search (existing behaviour).
void _playChartQueue(BuildContext context, List<Map<String, dynamic>> songs) {
  if (songs.isEmpty) return;
  BottomMessage.showText(context, 'Loading chart...');
  GetIt.I<MediaPlayer>().playAll(List<Map<String, dynamic>>.from(songs));
}

// ── Chart shelves (Echo visual language) ─────────────────────────────────────

/// Song charts (Global 200 / YouTube / Apple Music / iTunes / Deezer /
/// Spotify) — the exact same compact box placement the Top Albums shelf
/// uses: one fixed-height 128 dp square-art strip, never a long inline list
/// on the home. Tapping a box (or its title) opens the full ranked chart
/// — billboard style, like the desktop ChartDetailsPage — with every song
/// of the chart inside; rows play from YouTube Music only.
class _EchoChartStripSection extends StatelessWidget {
  const _EchoChartStripSection({required this.title, required this.items});

  final String title;
  final List<MusicChartEntry> items;

  void _openChart(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _EchoChartDetailsPage(title: title, items: items),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final playable = [
      for (final e in items.take(ChartConfig.playAllLimit)) e.toSongMap(),
    ];
    return SliverMainAxisGroup(
      slivers: [
        // Title row: "Play all" pill keeps working, tapping the title opens
        // the chart (the pill wins its own taps — standard Flutter arena).
        SliverToBoxAdapter(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openChart(context),
            child: _EchoSectionTitle(
              title: title,
              onPlayAll: playable.isNotEmpty
                  ? () => _playChartQueue(context, playable)
                  : null,
            ),
          ),
        ),
        // The box strip — identical placement to the Top Albums shelf.
        // Gaps between the cards also open the chart; every card opens it.
        SliverToBoxAdapter(
          child: _EchoAnimatedStrip(
            builder: (direction) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openChart(context),
              child: SizedBox(
                height: _kGridItemSize + 74,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _EchoSlideRotateIn(
                    direction: direction,
                    child: _EchoAlbumCard(
                      entry: items[index],
                      onTap: () => _openChart(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Inside" a chart box — every song of the chart as ranked rows, the same
/// billboard-style list the desktop ChartDetailsPage shows, rebuilt in the
/// Echo mobile language. The rows are already parsed in memory, so the page
/// is instant (no fetch, no skeleton); every row plays from YouTube Music
/// only through the established isChart path.
class _EchoChartDetailsPage extends StatelessWidget {
  const _EchoChartDetailsPage({required this.title, required this.items});

  final String title;
  final List<MusicChartEntry> items;

  @override
  Widget build(BuildContext context) {
    final playable = [
      for (final e in items.take(ChartConfig.playAllLimit)) e.toSongMap(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        actions: [
          if (playable.isNotEmpty)
            IconButton(
              tooltip: 'Play all',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => _playChartQueue(context, playable),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemCount: items.length,
        itemBuilder: (context, index) => _EchoChartRow(entry: items[index]),
      ),
    );
  }
}

class _EchoChartRow extends StatelessWidget {
  const _EchoChartRow({required this.entry});

  final MusicChartEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playChartEntry(context, entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(_kThumbnailCorner + 4),
                  child: entry.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: entry.imageUrl,
                          width: _kListThumb,
                          height: _kListThumb,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          placeholder: (_, __) => Container(
                              color: scheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => Container(
                              color: scheme.surfaceContainerHighest),
                        )
                      : Container(
                          width: _kListThumb,
                          height: _kListThumb,
                          color: scheme.surfaceContainerHighest,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
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
  }
}

/// Top Albums — Echo's 128 dp square-art horizontal grid shelf.
class _EchoAlbumChartSection extends StatelessWidget {
  const _EchoAlbumChartSection({required this.title, required this.items});

  final String title;
  final List<MusicChartEntry> items;

  @override
  Widget build(BuildContext context) {
    final playable = [
      for (final e in items.take(ChartConfig.playAllLimit)) e.toSongMap(),
    ];
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _EchoSectionTitle(
            title: title,
            onPlayAll:
                playable.isNotEmpty ? () => _playChartQueue(context, playable) : null,
          ),
        ),
        SliverToBoxAdapter(
          child: _EchoAnimatedStrip(
            builder: (direction) => SizedBox(
              height: _kGridItemSize + 74,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => _EchoSlideRotateIn(
                  direction: direction,
                  child: _EchoAlbumCard(entry: items[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EchoAlbumCard extends StatelessWidget {
  const _EchoAlbumCard({required this.entry, this.onTap});

  final MusicChartEntry entry;

  /// Optional tap override: album cards on the Top Albums shelf keep playing
  /// the album (null), chart box cards pass [onTap] to open their chart.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    return SizedBox(
      width: _kGridItemSize,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(_kThumbnailCorner),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap ?? () => _playChartEntry(context, entry),
              child: SizedBox(
                width: _kGridItemSize,
                height: _kGridItemSize,
                child: entry.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: getEnhancedImage(
                          entry.imageUrl,
                          dp: mediaQuery.devicePixelRatio,
                          width: _kGridItemSize,
                        ),
                        fit: BoxFit.cover,
                        memCacheWidth: 256,
                        placeholder: (_, __) => const SizedBox.expand(),
                        errorWidget: (_, __, ___) => const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(height: 1.25, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 1),
          Text(
            entry.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Echo skeleton for a not-yet-loaded chart shelf: section-title placeholder
/// plus a horizontal grid placeholder row. Every chart shelf — song charts
/// included — renders as the albums-style box strip, so one skeleton shape
/// covers all of them, driven by the same shared Echo shimmer timeline.
class _EchoChartsSkeleton extends StatelessWidget {
  const _EchoChartsSkeleton();

  @override
  Widget build(BuildContext context) {
    return _EchoShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: _EchoTextPlaceholder(height: 36, widthFactor: 0.4),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 4; i++) _EchoGridPlaceholder(),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Echo Nightly slide-in scroll animation (ported 1:1, home page only) ──────
//
// Echo Nightly's home shelves play a signature entrance while the user slides
// them left or right (AnimationUtils.kt → applyTranslationAndScaleAnimation,
// driven by HorizontalListViewHolder's scrollAmountX on card bind):
//   * slide in from the side the card came from — 50% of its own width;
//   * un-rotate from a 5° tilt around its center (the "rotation type" feel);
//   * scale 0.5 → 1, pivot at the center;
//   * a quick ~100 ms fade inside the same run;
//   * the standard fast-out-slow-in easing over ~350 ms.
// Cards bound before any slide (multiplier 0) only fade in, exactly like
// Echo's first paint. MOBILE home page only — nothing else is touched.

/// The last horizontal scroll direction of a strip: +1 while swiping towards
/// the left (new cards enter from the right), -1 the other way, 0 before any
/// slide — Echo Nightly's `scrollAmountX` sign, re-created for Flutter.
typedef _EchoSlideDirection = ValueNotifier<int>;

/// Wraps a horizontal strip: tracks its scroll direction once (State, so it
/// survives rebuilds) and hands it to [builder] so every card can play the
/// Echo Nightly entrance the moment it appears.
class _EchoAnimatedStrip extends StatefulWidget {
  const _EchoAnimatedStrip({required this.builder});

  final Widget Function(_EchoSlideDirection direction) builder;

  @override
  State<_EchoAnimatedStrip> createState() => _EchoAnimatedStripState();
}

class _EchoAnimatedStripState extends State<_EchoAnimatedStrip> {
  final _EchoSlideDirection _direction = ValueNotifier(0);

  @override
  void dispose() {
    _direction.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // scrollDelta is the signed delta along the strip's own (horizontal)
          // axis: positive while swiping left (cards enter from the right),
          // negative the other way — exactly Echo Nightly's scrollAmountX.
          final dx = notification.scrollDelta ?? 0;
          if (dx != 0) _direction.value = dx.sign.toInt();
        }
        return false;
      },
      child: widget.builder(_direction),
    );
  }
}

/// The entrance itself — one timeline, the same transform set Echo applies
/// on bind: translate (relative to the card's own width), rotate around the
/// center, scale around the center, and the short fade.
class _EchoSlideRotateIn extends StatefulWidget {
  const _EchoSlideRotateIn({required this.direction, required this.child});

  final _EchoSlideDirection direction;
  final Widget child;

  @override
  State<_EchoSlideRotateIn> createState() => _EchoSlideRotateInState();
}

class _EchoSlideRotateInState extends State<_EchoSlideRotateIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _motion;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _tilt; // degrees, captured at bind time
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // The sign of the strip's last scroll delta at the moment this card is
    // built — Echo Nightly reads scrollAmountX on onBindViewHolder.
    final m = widget.direction.value.toDouble();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _motion =
        CurvedAnimation(parent: _controller, curve: Curves.fastOutSlowIn);
    // Echo's fade uses motionDurationShort1 (~100 ms) inside the same run.
    _fade = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.28, curve: Curves.easeOut),
    ));
    _slide =
        Tween(begin: Offset(0.5 * m, 0), end: Offset.zero).animate(_motion);
    _tilt = Tween(begin: 5.0 * m, end: 0.0).animate(_motion);
    _scale =
        Tween(begin: 1.0 - 0.5 * m.abs(), end: 1.0).animate(_motion);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        return Opacity(
          opacity: _fade.value,
          child: Transform.scale(
            scale: _scale.value,
            alignment: Alignment.center,
            child: Transform.rotate(
              angle: _tilt.value * pi / 180,
              alignment: Alignment.center,
              child: FractionalTranslation(
                translation: _slide.value,
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
