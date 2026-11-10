// ZenMusic · vorlon-dev
//
// Discover — "Music Flow" style (idea from Echo Music, GPL-3.0).
// A full-screen vertical feed of songs. Swiping plays the song through the
// app's MAIN player (queue), so background playback, notification and the
// mini player keep working after you leave. Mobile only.
//
//  • tap = play/pause · double-tap = like · long-press = more
//  • lyric line capsule on top, thin seek bar at the bottom
//  • 6 actions: like · playlist · lyrics · share · download · more
//  • top menu: refresh feed · less like this · restore previous queue
//  • back arrow (top-left) or horizontal swipe leaves to another tab
//  • shell (dock + mini player) is hidden while Discover is open

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:share_plus/share_plus.dart';
import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/services/discover_feed.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/lyrics_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/enhanced_image.dart';

/// Shell branch indexes (Home, Search, Discover, Saved, Settings).
const int _kHomeBranch = 0;
const int _kSearchBranch = 1;
const int _kSavedBranch = 3;

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with AutomaticKeepAliveClientMixin {
  final DiscoverFeed _feed = DiscoverFeed.instance;
  final MediaPlayer _mp = GetIt.I<MediaPlayer>();
  final PageController _pages = PageController();

  final Map<String, String?> _canvas = {};
  final Set<String> _canvasLoading = {};
  final Map<String, Future<LyricsData?>> _lyrics = {};

  int _page = 0;
  int _request = 0;
  Timer? _debounce;
  bool? _active;
  bool _owns = false; // Discover's queue is what the main player runs
  bool _syncing = false; // page moved because playback moved (not the user)

  // Snapshot of whatever was playing before Discover took over.
  List<Map<String, dynamic>> _prevQueue = const [];
  String? _prevId;
  Duration _prevPos = Duration.zero;

  StreamSubscription? _procSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_onFeed);
    _mp.currentSongNotifier.addListener(_onPlaybackSong);
    _procSub = _mp.player.processingStateStream.listen((s) {
      // Queue ended while Discover owns playback → move on to the next page.
      if (s == ProcessingState.completed && _owns && _active == true) {
        _goNext();
      }
    });
    _feed.warm().then((_) {
      if (mounted && _active == true) _select(_page, immediate: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Branch pages stay alive; TickerMode is switched off while another tab
    // is shown. TickerMode.of() does NOT notify on that change, so listen to
    // its notifier (this is what makes the dock come back after leaving).
    final notifier = TickerMode.getNotifier(context);
    if (!identical(notifier, _tickerNotifier)) {
      _tickerNotifier?.removeListener(_onTickerChanged);
      _tickerNotifier = notifier..addListener(_onTickerChanged);
    }
    _applyActive(notifier.value);
  }

  ValueListenable<bool>? _tickerNotifier;

  void _onTickerChanged() {
    final n = _tickerNotifier;
    if (n != null && mounted) _applyActive(n.value);
  }

  void _applyActive(bool active) {
    if (active == _active) return;
    _active = active;
    if (!active) _mp.flowActive = false; // normal auto-fetch resumes
    // Hide the shell only while Discover is the visible tab.
    // (post-frame: this can run during build, the shell listens to it)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_active == active) ShellOverlaysBus.fullPageAbove.value = active;
    });
    if (active && _feed.ready) _select(_page, immediate: true);
  }

  @override
  void dispose() {
    _tickerNotifier?.removeListener(_onTickerChanged);
    _debounce?.cancel();
    _procSub?.cancel();
    _feed.removeListener(_onFeed);
    _mp.currentSongNotifier.removeListener(_onPlaybackSong);
    _pages.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShellOverlaysBus.fullPageAbove.value = false;
    });
    super.dispose();
  }

  // ───────────────────────── feed / playback sync ─────────────────────────

  void _onFeed() {
    if (mounted) setState(() {});
  }

  String? get _currentId {
    final m = _mp.currentSongNotifier.value;
    if (m == null) return null;
    return (m.extras?['videoId'] ?? m.id).toString();
  }

  /// Playback moved by itself (auto-next) → follow it with the pager.
  void _onPlaybackSong() {
    if (!mounted || !_owns || _active != true) return;
    final idx = _feed.indexOf(_currentId);
    if (idx < 0 || idx == _page || !_pages.hasClients) return;
    _syncing = true;
    _page = idx;
    _pages
        .animateToPage(idx,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic)
        .whenComplete(() => _syncing = false);
    _prefetch(idx);
    _mp.flowTopUp(_feed.items.map((e) => e.song).toList(), idx);
    setState(() {});
  }

  void _goNext() {
    final next = _page + 1;
    if (next < _feed.items.length && _pages.hasClients) {
      _pages.animateToPage(next,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  void _onPageChanged(int i) {
    final wasSyncing = _syncing;
    setState(() => _page = i);
    _prefetch(i);
    if (!wasSyncing) _select(i);
  }

  void _prefetch(int i) {
    _resolveCanvas(i);
    _lyricsFor(i);
    if (i + 1 < _feed.items.length) _lyricsFor(i + 1);
    if (i >= _feed.items.length - 4) _feed.loadMore();
  }

  /// Settled-page selection → command on the single shared player. Rapid
  /// swipes only ever command the final destination (request id + debounce).
  void _select(int i, {bool immediate = false}) {
    if (i < 0 || i >= _feed.items.length) return;
    final req = ++_request;
    _debounce?.cancel();
    void run() {
      if (!mounted || req != _request || _active != true) return;
      final item = _feed.items[i];
      final songs = _feed.items.map((e) => e.song).toList();
      if (_currentId == item.id) {
        _owns = true;
        _mp.flowActive = true;
        _mp.flowTopUp(songs, i);
        return;
      }
      if (!_owns) {
        _prevQueue = List<Map<String, dynamic>>.from(_mp.queueSnapshot.value);
        _prevId = _currentId;
        _prevPos = _mp.progressBarState.value.current;
      }
      _owns = true;
      // One queue: already-loaded songs are a plain seek, the next few are
      // resolved in the background (see MediaPlayer.flowPlay).
      _mp.flowPlay(songs, i);
      _prefetch(i);
      if (mounted) setState(() {});
    }

    if (immediate) {
      run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 180), run);
    }
  }

  Future<void> _resolveCanvas(int i) async {
    if (i < 0 || i >= _feed.items.length) return;
    final item = _feed.items[i];
    if (_canvas.containsKey(item.id) || !_canvasLoading.add(item.id)) return;
    String? url;
    try {
      // null unless the user is logged in to Spotify.
      url = await SpotifyCanvas.instance.resolveCanvasUrl(
        title: item.title,
        artist: item.artist,
        album: (item.song['album'] as Map?)?['name']?.toString(),
      );
    } catch (_) {
      url = null;
    }
    _canvasLoading.remove(item.id);
    _canvas[item.id] = url;
    if (mounted) setState(() {});
  }

  Future<LyricsData?>? _lyricsFor(int i) {
    if (i < 0 || i >= _feed.items.length) return null;
    final item = _feed.items[i];
    return _lyrics.putIfAbsent(
        item.id,
        () => LyricsService.lookup(
              title: item.title,
              artist: item.artist,
              album: (item.song['album'] as Map?)?['name']?.toString(),
              videoId: item.id,
            ).catchError((_) => null));
  }

  // ───────────────────────── actions ─────────────────────────

  Future<void> _like(FlowItem item, {bool toggle = false}) async {
    HapticFeedback.lightImpact();
    final box = Hive.box('FAVOURITES');
    if (box.get(item.id) == null) {
      await box.put(item.id, {
        ...item.song,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else if (toggle) {
      await box.delete(item.id);
    }
  }

  void _download(FlowItem item) {
    HapticFeedback.lightImpact();
    GetIt.I<DownloadManager>().downloadSong(item.song);
    _snack('Downloading…');
  }

  void _share(FlowItem item) {
    Share.shareUri(Uri.parse('https://music.youtube.com/watch?v=${item.id}'));
  }

  void _openArtist(FlowItem item) {
    final a = item.artists;
    if (a.isEmpty) return;
    context.push('/artist', extra: {
      'name': (a.first['name'] ?? '').toString(),
      'browseId': a.first['id']?.toString(),
    });
  }

  Future<void> _showLyrics(FlowItem item, int i) async {
    final fut = _lyricsFor(i);
    if (fut == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, scroll) => FutureBuilder<LyricsData?>(
          future: fut,
          builder: (context, snap) {
            final d = snap.data;
            String text;
            if (snap.connectionState != ConnectionState.done) {
              text = 'Loading lyrics…';
            } else if (d == null) {
              text = 'No lyrics found for this song.';
            } else if (d.synced != null && d.synced!.isNotEmpty) {
              text = d.synced!.map((l) => l.text).join('\n');
            } else {
              text = (d.plain ?? '').isEmpty ? 'No lyrics found.' : d.plain!;
            }
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              children: [
                Text(item.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(item.artist,
                    style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 20),
                Text(text,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 17, height: 1.6)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _lessLikeThis() {
    if (_page >= _feed.items.length) return;
    final item = _feed.items[_page];
    _feed.lessLikeThis(item);
    _feed.hide(item.id);
    _snack('You will see less like this');
    _goNext();
  }

  Future<void> _restorePrevious() async {
    if (_prevQueue.isEmpty) {
      _snack('Nothing to restore');
      return;
    }
    final idx = _prevQueue.indexWhere((e) => e['videoId'] == _prevId);
    _owns = false;
    final queue = _prevQueue;
    final pos = _prevPos;
    _prevQueue = const [];
    await _mp.playAll(queue, index: idx < 0 ? 0 : idx);
    if (pos > Duration.zero) _mp.seekTo(pos);
    _snack('Previous queue restored');
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    _canvas.clear();
    _lyrics.clear();
    _page = 0;
    if (_pages.hasClients) _pages.jumpToPage(0);
    await _feed.warm(force: true);
    if (mounted && _active == true) _select(0, immediate: true);
  }

  void _snack(String s) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(s), duration: const Duration(milliseconds: 1400)));
  }

  void _goBranch(int b) => StatefulNavigationShell.of(context).goBranch(b);

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final top = MediaQuery.viewPaddingOf(context).top;
    final items = _feed.items;

    Widget body;
    if (items.isEmpty) {
      body = Center(
        child: _feed.isLoading
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white54, size: 36),
                  const SizedBox(height: 12),
                  const Text('Discover could not load.',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
      );
    } else {
      body = PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) {
          final item = items[i];
          return _FlowPage(
            key: ValueKey(item.id),
            item: item,
            current: i == _page,
            mp: _mp,
            canvasUrl: _canvas[item.id],
            lyrics: i == _page ? _lyricsFor(i) : null,
            onTap: _mp.togglePlayPause,
            onLike: () => _like(item),
            onLikeToggle: () => _like(item, toggle: true),
            onPlaylist: () => Modals.addToPlaylist(context, item.song),
            onLyrics: () => _showLyrics(item, i),
            onShare: () => _share(item),
            onDownload: () => _download(item),
            onMore: () => Modals.showSongBottomModal(context, item.song),
            onArtist: () => _openArtist(item),
          );
        },
      );
    }

    return NotificationListener<UserScrollNotification>(
      // Feed scrolling must not touch the shell's auto-hide logic.
      onNotification: (_) => true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Swipe right → previous tab, swipe left → next tab.
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v > 500) {
            _goBranch(_kSearchBranch);
          } else if (v < -500) {
            _goBranch(_kSavedBranch);
          }
        },
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              body,
              Positioned(
                left: 6,
                right: 6,
                top: top + 4,
                child: Row(
                  children: [
                    _RoundIcon(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        onTap: () => _goBranch(_kHomeBranch)),
                    const Spacer(),
                    if (_feed.isOffline)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Text('Offline',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600)),
                      ),
                    PopupMenuButton<String>(
                      tooltip: 'Menu',
                      color: const Color(0xFF1E1E1E),
                      icon: const _RoundIconBody(icon: Icons.more_vert_rounded),
                      onSelected: (v) {
                        switch (v) {
                          case 'refresh':
                            _refresh();
                          case 'less':
                            _lessLikeThis();
                          case 'restore':
                            _restorePrevious();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'refresh',
                            child: Text('Refresh feed',
                                style: TextStyle(color: Colors.white))),
                        const PopupMenuItem(
                            value: 'less',
                            child: Text('Less like this',
                                style: TextStyle(color: Colors.white))),
                        PopupMenuItem(
                            value: 'restore',
                            enabled: _prevQueue.isNotEmpty,
                            child: const Text('Restore previous queue',
                                style: TextStyle(color: Colors.white))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── one page ─────────────────────────

class _FlowPage extends StatefulWidget {
  final FlowItem item;
  final bool current;
  final MediaPlayer mp;
  final String? canvasUrl;
  final Future<LyricsData?>? lyrics;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onLikeToggle;
  final VoidCallback onPlaylist;
  final VoidCallback onLyrics;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onMore;
  final VoidCallback onArtist;

  const _FlowPage({
    super.key,
    required this.item,
    required this.current,
    required this.mp,
    required this.canvasUrl,
    required this.lyrics,
    required this.onTap,
    required this.onLike,
    required this.onLikeToggle,
    required this.onPlaylist,
    required this.onLyrics,
    required this.onShare,
    required this.onDownload,
    required this.onMore,
    required this.onArtist,
  });

  @override
  State<_FlowPage> createState() => _FlowPageState();
}

class _FlowPageState extends State<_FlowPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 750));
  Offset _burstAt = Offset.zero;
  Offset _lastDown = Offset.zero;

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  void _doubleTap() {
    setState(() => _burstAt = _lastDown);
    _burst.forward(from: 0);
    widget.onLike(); // double tap only likes
  }

  String? get _cover {
    final t = widget.item.song['thumbnails'];
    if (t is List && t.isNotEmpty && t.last is Map) {
      final url = (t.last as Map)['url']?.toString();
      if (url != null && url.isNotEmpty) return getEnhancedImage(url, width: 720);
    }
    return null;
  }

  bool get _isThisSongLoaded {
    final m = widget.mp.currentSongNotifier.value;
    if (m == null) return false;
    return (m.extras?['videoId'] ?? m.id).toString() == widget.item.id;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final id = item.id;
    final vp = MediaQuery.viewPaddingOf(context);
    final cover = _cover;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed art (no blur: stays smooth on low-end phones).
        if (cover != null)
          Image.network(cover,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF111111)))
        else
          const ColoredBox(color: Color(0xFF111111)),

        // Spotify canvas loop (only when logged in to Spotify).
        if (widget.current && widget.canvasUrl != null)
          ValueListenableBuilder<ButtonState>(
            valueListenable: widget.mp.buttonState,
            builder: (context, st, _) => VideoBackdrop(
              streamUrl: widget.canvasUrl!,
              shortLoop: true,
              posterUrl: cover,
              playing: st == ButtonState.playing && _isThisSongLoaded,
            ),
          ),

        // Bottom + top readability gradients.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x73000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0xCC000000),
                  Color(0xF5000000),
                ],
                stops: [0.0, 0.22, 0.45, 0.72, 1.0],
              ),
            ),
          ),
        ),

        // Tap = play/pause · double-tap = like · long-press = more.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _lastDown = d.localPosition,
            onDoubleTapDown: (d) => _lastDown = d.localPosition,
            onTap: widget.current ? widget.onTap : null,
            onDoubleTap: widget.current ? _doubleTap : null,
            onLongPress: widget.current ? widget.onMore : null,
          ),
        ),

        // Centre: loading spinner / big play icon when paused.
        if (widget.current)
          IgnorePointer(
            child: Center(
              child: ValueListenableBuilder<ButtonState>(
                valueListenable: widget.mp.buttonState,
                builder: (context, st, _) {
                  final loaded = _isThisSongLoaded;
                  if (!loaded || st == ButtonState.loading) {
                    return const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    );
                  }
                  return AnimatedOpacity(
                    opacity: st == ButtonState.playing ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(
                          color: Color(0x8C000000), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 50),
                    ),
                  );
                },
              ),
            ),
          ),

        // Lyric line capsule.
        if (widget.current && widget.lyrics != null)
          Positioned(
            top: vp.top + 64,
            left: 0,
            right: 0,
            child: _LyricCapsule(
                future: widget.lyrics!,
                mp: widget.mp,
                onTap: widget.onLyrics),
          ),

        // Double-tap heart burst.
        AnimatedBuilder(
          animation: _burst,
          builder: (context, _) {
            if (_burst.isDismissed) return const SizedBox.shrink();
            final t = _burst.value;
            final scale = Curves.elasticOut.transform(math.min(1, t * 1.6));
            final opacity = t < 0.65 ? 1.0 : (1 - (t - 0.65) / 0.35);
            return Positioned(
              left: _burstAt.dx - 48,
              top: _burstAt.dy - 48 - 30 * t,
              child: IgnorePointer(
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale,
                    child: const Icon(Icons.favorite_rounded,
                        size: 96, color: Color(0xFFFF3B5C)),
                  ),
                ),
              ),
            );
          },
        ),

        // Title / artist + 6 action buttons.
        Positioned(
          left: 0,
          right: 0,
          bottom: vp.bottom + 26,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.15)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: widget.onArtist,
                      child: Text(item.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 15)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ValueListenableBuilder(
                      valueListenable:
                          Hive.box('FAVOURITES').listenable(keys: [id]),
                      builder: (context, box, _) {
                        final liked = box.get(id) != null;
                        return _ActionButton(
                          icon: liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked ? const Color(0xFFFF3B5C) : Colors.white,
                          label: 'Like',
                          onTap: widget.onLikeToggle,
                        );
                      },
                    ),
                    _ActionButton(
                        icon: Icons.playlist_add_rounded,
                        label: 'Playlist',
                        onTap: widget.onPlaylist),
                    _ActionButton(
                        icon: Icons.lyrics_outlined,
                        label: 'Lyrics',
                        onTap: widget.onLyrics),
                    _ActionButton(
                        icon: Icons.ios_share_rounded,
                        label: 'Share',
                        onTap: widget.onShare),
                    ValueListenableBuilder(
                      valueListenable:
                          Hive.box('DOWNLOADS').listenable(keys: [id]),
                      builder: (context, box, _) {
                        final status = (box.get(id) as Map?)?['status'];
                        final done = status == 'DOWNLOADED';
                        final busy =
                            status == 'DOWNLOADING' || status == 'QUEUED';
                        return _ActionButton(
                          icon: done
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                          color: done ? const Color(0xFF4ADE80) : Colors.white,
                          label: done ? 'Saved' : (busy ? '…' : 'Download'),
                          onTap: (done || busy) ? null : widget.onDownload,
                        );
                      },
                    ),
                    _ActionButton(
                        icon: Icons.more_horiz_rounded,
                        label: 'More',
                        onTap: widget.onMore),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Thin seek bar (main player position).
        if (widget.current)
          Positioned(
            left: 0,
            right: 0,
            bottom: vp.bottom,
            child: _SeekBar(mp: widget.mp, enabled: _isThisSongLoaded),
          ),
      ],
    );
  }
}

// ───────────────────────── small widgets ─────────────────────────

class _LyricCapsule extends StatelessWidget {
  final Future<LyricsData?> future;
  final MediaPlayer mp;
  final VoidCallback onTap;
  const _LyricCapsule(
      {required this.future, required this.mp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsData?>(
      future: future,
      builder: (context, snap) {
        final lines = snap.data?.synced;
        if (lines == null || lines.isEmpty) return const SizedBox.shrink();
        return ValueListenableBuilder<ProgressBarState>(
          valueListenable: mp.progressBarState,
          builder: (context, p, _) {
            final ms = p.current.inMilliseconds;
            var idx = -1;
            for (var i = 0; i < lines.length; i++) {
              if (lines[i].timeMs <= ms) {
                idx = i;
              } else {
                break;
              }
            }
            final text = lines[idx < 0 ? 0 : idx].text.trim();
            if (text.isEmpty) return const SizedBox.shrink();
            return Center(
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0x80000000),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0x33FFFFFF)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lyrics_outlined,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 8),
                      Flexible(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(text,
                              key: ValueKey(text),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Thin progress line (Instagram style); grows while touched. Tap or drag to
/// seek the main player.
class _SeekBar extends StatefulWidget {
  final MediaPlayer mp;
  final bool enabled;
  const _SeekBar({required this.mp, required this.enabled});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  bool _down = false;

  void _seekTo(double f) {
    final total = widget.mp.progressBarState.value.total;
    if (total == Duration.zero) return;
    widget.mp.seekTo(Duration(
        milliseconds: (total.inMilliseconds * f.clamp(0.0, 1.0)).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _seekTo(d.localPosition.dx / w),
        onHorizontalDragStart: (_) => setState(() => _down = true),
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag = (d.localPosition.dx / w).clamp(0.0, 1.0)),
        onHorizontalDragEnd: (_) {
          if (_drag != null) _seekTo(_drag!);
          setState(() {
            _drag = null;
            _down = false;
          });
        },
        child: SizedBox(
          height: 26,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<ProgressBarState>(
              valueListenable: widget.mp.progressBarState,
              builder: (context, p, _) {
                final total = p.total.inMilliseconds;
                final f = _drag ??
                    (!widget.enabled || total <= 0
                        ? 0.0
                        : (p.current.inMilliseconds / total).clamp(0.0, 1.0));
                return Container(
                  height: _down ? 6 : 2.5,
                  width: w,
                  color: const Color(0x44FFFFFF),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: f,
                    child: Container(color: Colors.white),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                  color: Color(0x40FFFFFF), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 25),
            ),
            const SizedBox(height: 5),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(backgroundColor: const Color(0x55000000)),
      icon: Icon(icon, color: Colors.white),
    );
  }
}

class _RoundIconBody extends StatelessWidget {
  final IconData icon;
  const _RoundIconBody({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
          color: Color(0x55000000), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white),
    );
  }
}
