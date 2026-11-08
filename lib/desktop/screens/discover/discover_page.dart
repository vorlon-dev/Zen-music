// ZenMusic · vorlon-dev
//
// Discover — full-screen, reels-style vertical feed of music videos.
//  • Plays INSIDE this page (own player, real audio) — never the mini player.
//  • Songs autoplay as you swipe (like reels). Tap = pause / play.
//  • Double-tap = like. Thin seek bar at the bottom (tap / drag to seek).
//  • Shell (dock + mini player) is hidden while Discover is open.
//  • Back arrow (top-left) or horizontal swipe leaves to another tab.
//  • Video: YouTube / YT Music. Spotify canvas is used only when logged in.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/shell_overlays_bus.dart';
import 'package:zenmusic/desktop/services/yt_video_engine.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart';
import 'package:zenmusic/desktop/utils/enhanced_image.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

/// Branch indexes of the shell (Home, Search, Discover, Saved, Settings).
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
  static const _seedQueries = [
    'trending music videos',
    'new songs official video',
    'top hits music video',
    'viral songs',
    'chill songs music video',
  ];

  final PageController _pages = PageController();
  final List<Map<String, dynamic>> _songs = [];
  final Set<String> _seen = {};
  final Map<String, String?> _canvas = {};
  final Set<String> _canvasLoading = {};
  final Map<String, YtVideoStreams?> _streams = {};

  late final Player _player;
  late final VideoController _video;
  StreamSubscription? _playingSub;
  StreamSubscription? _errSub;

  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  int _index = 0;

  bool _playing = false;
  bool _mediaLoading = false;
  bool _mediaError = false;
  int _openToken = 0;
  bool? _active; // is the Discover tab the visible one?
  bool _userPaused = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _player = Player(
        configuration: PlayerConfiguration(bufferSize: 12 * 1024 * 1024));
    _video = VideoController(_player);
    _player.setPlaylistMode(PlaylistMode.single); // loop the song
    _playingSub = _player.stream.playing.listen((p) {
      if (mounted && p != _playing) setState(() => _playing = p);
    });
    _errSub = _player.stream.error.listen((_) {
      if (mounted && !_mediaLoading) setState(() => _mediaError = true);
    });
    _loadInitial();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Branch pages are kept alive but get TickerMode disabled when hidden.
    final active = TickerMode.of(context);
    if (active != _active) {
      _active = active;
      if (!active) {
        _player.pause();
      } else if (!_userPaused &&
          _songs.isNotEmpty &&
          !_mediaLoading &&
          !_mediaError) {
        _pauseMainPlayer();
        _player.play();
      }
      // Hide / show the shell (dock + mini player) after this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_active == active) {
          ShellOverlaysBus.fullPageAbove.value = active;
        }
      });
    }
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _errSub?.cancel();
    _player.dispose();
    _pages.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShellOverlaysBus.fullPageAbove.value = false;
    });
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  bool _add(Map raw) {
    final id = raw['videoId']?.toString();
    if (id == null || id.isEmpty || !_seen.add(id)) return false;
    _songs.add(Map<String, dynamic>.from(raw));
    return true;
  }

  Future<List<Map>> _search(String q, String filter) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await GetIt.I<YTMusic>().search(q, filter: filter);
        final sections = res['sections'] as List?;
        if (sections == null || sections.isEmpty) continue;
        final list = ((sections[0]['contents'] as List?) ?? const [])
            .whereType<Map>()
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {
        // retry once (the YT Music API sometimes drops the connection)
      }
    }
    return <Map>[];
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final queries = [..._seedQueries]..shuffle();
    // Music videos first (real video), songs mixed in for variety.
    final results = await Future.wait([
      _search(queries[0], 'videos'),
      _search(queries[1], 'videos'),
      _search(queries[2], 'songs'),
    ]);
    final longest = results.fold<int>(0, (m, l) => math.max(m, l.length));
    for (var i = 0; i < longest; i++) {
      for (final l in results) {
        if (i < l.length) _add(l[i]);
      }
    }
    if (!mounted) return;
    if (_songs.isEmpty) {
      setState(() {
        _failed = true;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = false);
    _onShown(0);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _songs.isEmpty) return;
    _loadingMore = true;
    try {
      final seed = _songs[_songs.length - 1]['videoId'];
      final more = await GetIt.I<YTMusic>()
          .getNextSongList(videoId: seed, radio: true, limit: 25);
      var added = false;
      for (final s in more) {
        if (s is Map && _add(s)) added = true;
      }
      if (added && mounted) setState(() {});
    } catch (_) {
      // feed simply ends
    } finally {
      _loadingMore = false;
    }
  }

  // ───────────────────────── playback ─────────────────────────

  Future<YtVideoStreams?> _resolveStreams(String id) async {
    if (_streams.containsKey(id)) return _streams[id];
    YtVideoStreams? s;
    try {
      s = await YtVideoEngine.extractVideo(id, maxHeight: 480);
    } catch (_) {
      s = null;
    }
    _streams[id] = s;
    return s;
  }

  void _pauseMainPlayer() {
    try {
      GetIt.I<MediaPlayer>().player.pause();
    } catch (_) {}
  }

  /// Loads the song and starts it right away (reels style).
  Future<void> _openMedia(int i) async {
    if (i < 0 || i >= _songs.length) return;
    final id = _songs[i]['videoId'] as String;
    final token = ++_openToken;
    setState(() {
      _mediaLoading = true;
      _mediaError = false;
      _playing = false;
      _userPaused = false;
    });
    final s = await _resolveStreams(id);
    if (!mounted || token != _openToken) return;
    final url = s?.videoUrl;
    if (url == null) {
      setState(() {
        _mediaLoading = false;
        _mediaError = true;
      });
      return;
    }
    try {
      final autoplay = _active == true;
      if (autoplay) _pauseMainPlayer();
      await _player.open(Media(url), play: autoplay);
      final audio = s?.audioUrl;
      if (audio != null) {
        await _player.setAudioTrack(AudioTrack.uri(audio));
      }
      await _player.setVolume(100);
    } catch (_) {
      if (mounted && token == _openToken) {
        setState(() {
          _mediaLoading = false;
          _mediaError = true;
        });
      }
      return;
    }
    if (!mounted || token != _openToken) return;
    setState(() => _mediaLoading = false);
  }

  void _togglePlay() {
    if (_mediaLoading || _mediaError) return;
    if (_playing) {
      _userPaused = true;
    } else {
      _userPaused = false;
      _pauseMainPlayer();
    }
    _player.playOrPause();
  }

  // ───────────────────────── paging ─────────────────────────

  void _onShown(int i) {
    if (i < 0 || i >= _songs.length) return;
    _index = i;
    _openMedia(i);
    _resolveCanvas(i);
    // Prefetch the next two so swiping starts instantly.
    for (var k = 1; k <= 2; k++) {
      if (i + k < _songs.length) {
        _resolveStreams(_songs[i + k]['videoId'] as String);
      }
    }
    if (i >= _songs.length - 4) _loadMore();
  }

  Future<void> _resolveCanvas(int i) async {
    if (i < 0 || i >= _songs.length) return;
    final id = _songs[i]['videoId'] as String;
    if (_canvas.containsKey(id) || !_canvasLoading.add(id)) return;
    String? url;
    try {
      // Returns null unless the user is logged in to Spotify.
      url = await SpotifyCanvas.instance.resolveCanvasUrl(
        title: _title(_songs[i]),
        artist: _artist(_songs[i]),
        album: (_songs[i]['album'] as Map?)?['name']?.toString(),
      );
    } catch (_) {
      url = null;
    }
    _canvasLoading.remove(id);
    _canvas[id] = url;
    if (mounted) setState(() {});
  }

  // ───────────────────────── helpers ─────────────────────────

  static String _title(Map s) => (s['title'] ?? '').toString();

  static String _artist(Map s) {
    final a = s['artists'];
    if (a is List && a.isNotEmpty) {
      return a
          .map((e) => e is Map ? (e['name'] ?? '').toString() : e.toString())
          .where((e) => e.isNotEmpty)
          .join(', ');
    }
    return (s['artist'] ?? '').toString();
  }

  static String? _cover(Map s) {
    final t = s['thumbnails'];
    if (t is List && t.isNotEmpty && t.last is Map) {
      final url = (t.last as Map)['url']?.toString();
      if (url != null && url.isNotEmpty) {
        return getEnhancedImage(url, width: 360);
      }
    }
    return null;
  }

  // ───────────────────────── actions ─────────────────────────

  Future<void> _like(Map<String, dynamic> song, {bool toggle = false}) async {
    HapticFeedback.lightImpact();
    final box = Hive.box('FAVOURITES');
    final id = song['videoId'];
    if (box.get(id) == null) {
      await box.put(id, {
        ...song,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else if (toggle) {
      await box.delete(id);
    }
  }

  void _download(Map<String, dynamic> song) {
    HapticFeedback.lightImpact();
    GetIt.I<DownloadManager>().downloadSong(song);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Downloading…'),
        duration: Duration(seconds: 1),
      ));
  }

  void _goBranch(int b) {
    _player.pause();
    StatefulNavigationShell.of(context).goBranch(b);
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: Colors.white54, size: 36),
                  const SizedBox(height: 12),
                  const Text('Discover could not load.',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _loadInitial,
                    child: const Text('Retry',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
            _BackButton(onTap: () => _goBranch(_kHomeBranch)),
          ],
        ),
      );
    }

    final top = MediaQuery.viewPaddingOf(context).top;
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
              PageView.builder(
                controller: _pages,
                scrollDirection: Axis.vertical,
                itemCount: _songs.length,
                onPageChanged: _onShown,
                itemBuilder: (context, i) {
                  final song = _songs[i];
                  final current = i == _index;
                  return _DiscoverCard(
                    key: ValueKey(song['videoId']),
                    song: song,
                    current: current,
                    player: _player,
                    video: _video,
                    playing: current && _playing,
                    loading: current && _mediaLoading,
                    error: current && _mediaError,
                    title: _title(song),
                    artist: _artist(song),
                    cover: _cover(song),
                    canvasUrl: _canvas[song['videoId']],
                    onTap: _togglePlay,
                    onRetry: () => _openMedia(i),
                    onLike: () => _like(song),
                    onLikeToggle: () => _like(song, toggle: true),
                    onDownload: () => _download(song),
                  );
                },
              ),
              // Exit arrow (top-left).
              Positioned(
                left: 6,
                top: top + 4,
                child: _BackButton(onTap: () => _goBranch(_kHomeBranch)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: IconButton(
          tooltip: 'Back',
          onPressed: onTap,
          style: IconButton.styleFrom(backgroundColor: const Color(0x55000000)),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatefulWidget {
  final Map<String, dynamic> song;
  final bool current;
  final Player player;
  final VideoController video;
  final bool playing;
  final bool loading;
  final bool error;
  final String title;
  final String artist;
  final String? cover;
  final String? canvasUrl;
  final VoidCallback onTap;
  final VoidCallback onRetry;
  final VoidCallback onLike;
  final VoidCallback onLikeToggle;
  final VoidCallback onDownload;

  const _DiscoverCard({
    super.key,
    required this.song,
    required this.current,
    required this.player,
    required this.video,
    required this.playing,
    required this.loading,
    required this.error,
    required this.title,
    required this.artist,
    required this.cover,
    required this.canvasUrl,
    required this.onTap,
    required this.onRetry,
    required this.onLike,
    required this.onLikeToggle,
    required this.onDownload,
  });

  @override
  State<_DiscoverCard> createState() => _DiscoverCardState();
}

class _DiscoverCardState extends State<_DiscoverCard>
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
    widget.onLike(); // double tap only likes (never un-likes)
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.song['videoId'];
    final vp = MediaQuery.viewPaddingOf(context);
    final useCanvas = widget.canvasUrl != null && widget.current;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Backdrop: dimmed cover art, visible until the first video frame.
        _CoverStage(cover: widget.cover),

        // Video / Spotify canvas (current page only).
        if (widget.current)
          if (useCanvas)
            VideoBackdrop(
              streamUrl: widget.canvasUrl!,
              shortLoop: true,
              posterUrl: widget.cover,
              playing: widget.playing,
            )
          else if (!widget.error)
            Positioned.fill(
              child: Video(
                controller: widget.video,
                controls: NoVideoControls,
                fit: BoxFit.cover, // fill the 9:16 screen
                fill: Colors.transparent,
              ),
            ),

        // Readability gradients (cheap, no blur).
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0xCC000000)
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),

        // Tap = play/pause, double tap = like.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _lastDown = d.localPosition,
            onDoubleTapDown: (d) => _lastDown = d.localPosition,
            onTap: widget.current ? widget.onTap : null,
            onDoubleTap: widget.current ? _doubleTap : null,
          ),
        ),

        // Centre status: spinner / error / big play icon.
        if (widget.current)
          IgnorePointer(
            ignoring: !widget.error,
            child: Center(child: _centerStatus()),
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

        // Title / artist.
        Positioned(
          left: 20,
          right: 90,
          bottom: vp.bottom + 40,
          child: IgnorePointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.15)),
                const SizedBox(height: 6),
                Text(widget.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14.5)),
              ],
            ),
          ),
        ),

        // The two buttons: Like + Download.
        Positioned(
          right: 14,
          bottom: vp.bottom + 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: Hive.box('FAVOURITES').listenable(keys: [id]),
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
              const SizedBox(height: 22),
              ValueListenableBuilder(
                valueListenable: Hive.box('DOWNLOADS').listenable(keys: [id]),
                builder: (context, box, _) {
                  final status = (box.get(id) as Map?)?['status'];
                  final done = status == 'DOWNLOADED';
                  final busy = status == 'DOWNLOADING' || status == 'QUEUED';
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
            ],
          ),
        ),

        // Instagram-style thin seek bar.
        if (widget.current)
          Positioned(
            left: 0,
            right: 0,
            bottom: vp.bottom,
            child: _SeekBar(player: widget.player),
          ),
      ],
    );
  }

  Widget _centerStatus() {
    if (widget.error) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 34),
          const SizedBox(height: 10),
          const Text('This song could not be played.',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onRetry,
            child: const Text('Retry', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }
    if (widget.loading) {
      return const SizedBox(
        width: 30,
        height: 30,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
    }
    return AnimatedOpacity(
      opacity: widget.playing ? 0 : 1,
      duration: const Duration(milliseconds: 180),
      child: Container(
        width: 78,
        height: 78,
        decoration: const BoxDecoration(
            color: Color(0x66000000), shape: BoxShape.circle),
        child:
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 52),
      ),
    );
  }
}

/// Thin progress line (Instagram style). Grows while touched; tap or drag
/// to seek.
class _SeekBar extends StatefulWidget {
  final Player player;
  const _SeekBar({required this.player});

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag; // 0..1 while dragging
  bool _down = false;

  void _seekTo(double f) {
    final d = widget.player.state.duration;
    if (d == Duration.zero) return;
    widget.player.seek(Duration(
        milliseconds: (d.inMilliseconds * f.clamp(0.0, 1.0)).round()));
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
            child: StreamBuilder<Duration>(
              stream: widget.player.stream.duration,
              initialData: widget.player.state.duration,
              builder: (context, durSnap) {
                final total = (durSnap.data ?? Duration.zero).inMilliseconds;
                return StreamBuilder<Duration>(
                  stream: widget.player.stream.position,
                  initialData: widget.player.state.position,
                  builder: (context, posSnap) {
                    final pos = (posSnap.data ?? Duration.zero).inMilliseconds;
                    final f = _drag ??
                        (total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0));
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
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Color(0x55000000),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 29),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Backdrop: cover art, slowly drifting/zooming under a dark tint.
/// Transform-only animation (no blur) so low-end phones stay smooth.
class _CoverStage extends StatefulWidget {
  final String? cover;
  const _CoverStage({required this.cover});

  @override
  State<_CoverStage> createState() => _CoverStageState();
}

class _CoverStageState extends State<_CoverStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 14))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cover = widget.cover;
    if (cover == null) return const ColoredBox(color: Color(0xFF111111));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.translate(
          offset: Offset((t - 0.5) * 24, (0.5 - t) * 18),
          child: Transform.scale(scale: 1.35 + 0.12 * t, child: child),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(cover,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xFF111111))),
          const ColoredBox(color: Color(0xAA000000)),
        ],
      ),
    );
  }
}
