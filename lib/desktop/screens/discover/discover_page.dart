// ZenMusic · vorlon-dev
//
// Discover — a full-screen, reels-style vertical feed of songs.
// Swipe up for the next song. Each page has a looping canvas (Spotify
// canvas when logged in, otherwise animated cover art) and exactly two
// actions: Like and Download.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart';
import 'package:zenmusic/desktop/utils/enhanced_image.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with AutomaticKeepAliveClientMixin {
  static const _seedQueries = [
    'trending songs',
    'new music this week',
    'top hits',
    'viral songs',
    'chill songs',
  ];

  final PageController _pages = PageController();
  final List<Map<String, dynamic>> _songs = [];
  final Set<String> _seen = {};
  final Map<String, String?> _canvas = {};
  final Set<String> _canvasLoading = {};

  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  int _index = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // ───────────────────────── data ─────────────────────────

  bool _add(Map raw) {
    final id = raw['videoId']?.toString();
    if (id == null || id.isEmpty || !_seen.add(id)) return false;
    _songs.add(Map<String, dynamic>.from(raw));
    return true;
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final yt = GetIt.I<YTMusic>();
      final queries = [..._seedQueries]..shuffle();
      final results = await Future.wait(queries.take(3).map((q) async {
        try {
          final res = await yt.search(q, filter: 'songs');
          final sections = res['sections'] as List?;
          if (sections == null || sections.isEmpty) return <Map>[];
          return ((sections[0]['contents'] as List?) ?? const [])
              .whereType<Map>()
              .toList();
        } catch (_) {
          return <Map>[];
        }
      }));
      // Interleave the lists so the feed mixes moods.
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
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
      // Feed just ends; user can pull the retry from an empty state.
    } finally {
      _loadingMore = false;
    }
  }

  // ───────────────────────── paging ─────────────────────────

  void _onShown(int i) {
    if (i < 0 || i >= _songs.length) return;
    _index = i;
    GetIt.I<MediaPlayer>().playSong(_songs[i]);
    _resolveCanvas(i);
    _resolveCanvas(i + 1);
    if (i >= _songs.length - 4) _loadMore();
  }

  Future<void> _resolveCanvas(int i) async {
    if (i < 0 || i >= _songs.length) return;
    final id = _songs[i]['videoId'] as String;
    if (_canvas.containsKey(id) || !_canvasLoading.add(id)) return;
    String? url;
    try {
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

  Future<void> _toggleLike(Map<String, dynamic> song) async {
    HapticFeedback.lightImpact();
    final box = Hive.box('FAVOURITES');
    final id = song['videoId'];
    if (box.get(id) == null) {
      await box.put(id, {
        ...song,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
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
        child: Center(
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
                child:
                    const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }
    // Keep the shell's dock visible while swiping (it hides on scroll
    // otherwise): swallow scroll notifications from the feed.
    return NotificationListener<UserScrollNotification>(
      onNotification: (_) => true,
      child: ColoredBox(
        color: Colors.black,
        child: PageView.builder(
          controller: _pages,
          scrollDirection: Axis.vertical,
          physics: const PageScrollPhysics(),
          itemCount: _songs.length,
          onPageChanged: _onShown,
          itemBuilder: (context, i) => _DiscoverCard(
            key: ValueKey(_songs[i]['videoId']),
            song: _songs[i],
            active: i == _index,
            title: _title(_songs[i]),
            artist: _artist(_songs[i]),
            cover: _cover(_songs[i]),
            canvasUrl: _canvas[_songs[i]['videoId']],
            onLike: () => _toggleLike(_songs[i]),
            onDownload: () => _download(_songs[i]),
          ),
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  final Map<String, dynamic> song;
  final bool active;
  final String title;
  final String artist;
  final String? cover;
  final String? canvasUrl;
  final VoidCallback onLike;
  final VoidCallback onDownload;

  const _DiscoverCard({
    super.key,
    required this.song,
    required this.active,
    required this.title,
    required this.artist,
    required this.cover,
    required this.canvasUrl,
    required this.onLike,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final id = song['videoId'];
    // Space for the shell's dock + mini player.
    final bottomInset = MediaQuery.paddingOf(context).bottom + 150;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Canvas ──
        if (canvasUrl != null && active)
          VideoBackdrop(
            streamUrl: canvasUrl!,
            shortLoop: true,
            posterUrl: cover,
          )
        else
          _CoverStage(cover: cover),

        // Readability gradients (cheap, no blur).
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000), Color(0xCC000000)],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),

        // ── Title / artist ──
        Positioned(
          left: 20,
          right: 90,
          bottom: bottomInset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.15)),
              const SizedBox(height: 6),
              Text(artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
            ],
          ),
        ),

        // ── The two buttons: Like + Download ──
        Positioned(
          right: 14,
          bottom: bottomInset,
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
                    onTap: onLike,
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
                    onTap: (done || busy) ? null : onDownload,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
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

/// Fallback canvas: cover art, slowly drifting/zooming with a dark tint.
/// Uses only a transform animation (no blur) so low-end phones stay smooth.
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
          const ColoredBox(color: Color(0x55000000)),
        ],
      ),
    );
  }
}
