import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
// WAKELOCK
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/song.dart';
import '../services/youtube_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';

/// Dedicated YouTube video watch page — like YouTube's watch screen.
/// The video (with its own audio) plays front-and-center; below are
/// title/channel and related videos. Fullscreen mode rotates to
/// landscape, hides system bars and expands the video edge-to-edge.
class VideoWatchScreen extends StatefulWidget {
  const VideoWatchScreen({
    super.key,
    required this.videoId,
    this.title,
    this.artist,
    this.thumbnail,
  });

  final String videoId;
  final String? title;
  final String? artist;
  final String? thumbnail;

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

class _VideoWatchScreenState extends State<VideoWatchScreen> {
  final _yt = YoutubeService();

  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;
  String? _loadedId;
  bool _fullscreen = false;

  Song? _current;
  List<Song> _related = [];
  bool _loadingRelated = true;
  String? _resolveError;

  @override
  void initState() {
    super.initState();
    _current = Song(
      id: widget.videoId,
      title: widget.title ?? 'Video',
      artist: widget.artist ?? 'YouTube',
      thumbnail: widget.thumbnail ??
          'https://i.ytimg.com/vi/${widget.videoId}/hqdefault.jpg',
      duration: Duration.zero,
    );
    _loadVideo(widget.videoId);
    _loadRelated(widget.videoId);
  }

  @override
  void dispose() {
    _exitFullscreen();
    _controller?.dispose();
    super.dispose();
  }

  // ── Fullscreen (YouTube-style): landscape + immersive + wakelock ──

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
  }

  void _exitFullscreen() {
    if (!_fullscreen) return;
    setState(() => _fullscreen = false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
  }

  void _toggleFullscreen() {
    _fullscreen ? _exitFullscreen() : _enterFullscreen();
  }

  // ── System back button exits fullscreen first ──

  Future<bool> _onWillPop() async {
    if (_fullscreen) {
      _exitFullscreen();
      return false;
    }
    return true;
  }

  // ── Video loading ──

  Future<void> _loadVideo(String videoId) async {
    setState(() {
      _failed = false;
      _resolveError = null;
      _initialized = false;
    });

    final result = await _yt.getMuxedStreamUrl(videoId, preferHd: true);

    if (!mounted) return;
    if (result == null || result.url.isEmpty) {
      setState(() {
        _failed = true;
        _resolveError = 'Could not load this video. Try another.';
      });
      return;
    }

    if (_loadedId == videoId && _controller != null) {
      setState(() => _initialized = true);
      await _controller!.play();
      return;
    }

    final old = _controller;
    _controller = null;
    setState(() => _initialized = false);
    await old?.dispose();

    final c = VideoPlayerController.networkUrl(
      Uri.parse(result.url),
      httpHeaders: result.headers,
    );
    _controller = c;

    try {
      await c.initialize();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _resolveError = 'Playback failed for this video.';
      });
      return;
    }
    if (!mounted || _controller != c) {
      await c.dispose();
      return;
    }

    await c.setVolume(1.0); // the video's OWN audio is the source
    await c.play();

    setState(() {
      _loadedId = videoId;
      _initialized = true;
      if (_current != null && _current!.duration == Duration.zero) {
        _current = Song(
          id: _current!.id,
          title: _current!.title,
          artist: _current!.artist,
          thumbnail: _current!.thumbnail,
          duration: c.value.duration,
        );
      }
    });

    // Auto-fullscreen for landscape content (YouTube parity) — portrait
    // videos stay inline.
    if (c.value.size.width > c.value.size.height && mounted) {
      _enterFullscreen();
    }
  }

  Future<void> _loadRelated(String videoId) async {
    setState(() => _loadingRelated = true);
    try {
      final related = await _yt.getYtmRadio(videoId);
      if (!mounted) return;
      setState(() {
        _related = related.where((s) => s.id != videoId).take(20).toList();
        _loadingRelated = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRelated = false);
    }
  }

  void _openRelated(Song song) {
    _exitFullscreen();
    setState(() => _current = song);
    _loadVideo(song.id);
    _loadRelated(song.id);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !_initialized) return;
    c.value.isPlaying ? c.pause() : c.play();
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Fullscreen: video edge-to-edge, no scaffold chrome at all.
    if (_fullscreen) {
      return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onDoubleTap: _toggleFullscreen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _videoSurface(),
                // Exit-fullscreen button top corner.
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: _fullscreenButton(
                        icon: Icons.fullscreen_exit_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Normal (portrait) watch page.
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: SpotifyColors.background,
        appBar: AppBar(
          backgroundColor: SpotifyColors.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
          title: const Text('Video',
              style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _videoArea(),
            if (_failed)
              _errorBlock()
            else ...[
              _infoBlock(),
              const SizedBox(height: 8),
              _relatedShelf(),
              const SizedBox(height: 16),
              _relatedList(),
            ],
          ],
        ),
      ),
    );
  }

  // ── Inline video area (portrait): 16:9 wrapper around the surface ──

  Widget _videoArea() {
    return Container(
      color: Colors.black,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _videoSurface(),
      ),
    );
  }

  // ── Video surface (shared between inline and fullscreen) ──

  Widget _videoSurface() {
    final c = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initialized && c != null)
          GestureDetector(
            onTap: _togglePlay,
            // Double-tap anywhere toggles fullscreen (YouTube parity).
            onDoubleTap: _toggleFullscreen,
            child: FittedBox(
              fit: _fullscreen ? BoxFit.cover : BoxFit.contain,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          )
        else if (!_failed)
          Center(
            child: _current != null && _current!.thumbnail.isNotEmpty
                ? Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  _current!.thumbnail,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                      color: SpotifyColors.surfaceLight),
                ),
                const Center(
                  child: CircularProgressIndicator(
                      color: SpotifyColors.green),
                ),
              ],
            )
                : const Center(
              child: CircularProgressIndicator(
                  color: SpotifyColors.green),
            ),
          )
        else
          const SizedBox.shrink(),

        // Thin progress bar along the bottom edge (YouTube style).
        if (_initialized && c != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: SpotifyColors.green,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
            ),
          ),

        // Center play overlay when paused.
        if (_initialized && c != null && !c.value.isPlaying && !_failed)
          Center(
            child: GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 40, color: Colors.white),
              ),
            ),
          ),

        // Fullscreen button overlay (portrait mode).
        if (_initialized && !_fullscreen)
          Positioned(
            right: 8,
            top: 8,
            child: _fullscreenButton(icon: Icons.fullscreen_rounded),
          ),
      ],
    );
  }

  Widget _fullscreenButton({required IconData icon}) {
    return GestureDetector(
      onTap: _toggleFullscreen,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }

  Widget _errorBlock() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: SpotifyColors.textTertiary),
          const SizedBox(height: 12),
          Text(_resolveError ?? 'Playback failed',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: SpotifyColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 16),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: SpotifyColors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23)),
            ),
            onPressed: () =>
            _current != null ? _loadVideo(_current!.id) : null,
            child: const Text('Retry',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _infoBlock() {
    final v = _current;
    if (v == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(v.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: SpotifyColors.textPrimary)),
          const SizedBox(height: 4),
          Text(v.artist,
              style: const TextStyle(
                  fontSize: 13, color: SpotifyColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _relatedShelf() {
    if (_loadingRelated || _related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('Up next',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
        ),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _related.length.clamp(0, 10),
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final s = _related[i];
              return GestureDetector(
                onTap: () => _openRelated(s),
                child: SizedBox(
                  width: 180,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          YoutubeThumbnail(
                            videoId: s.id,
                            imageUrl: s.thumbnail,
                            width: 180,
                            height: 101,
                            borderRadius: 10,
                          ),
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _fmt(s.duration),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: SpotifyColors.textPrimary)),
                      Text(s.artist,
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
    );
  }

  Widget _relatedList() {
    if (_loadingRelated) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: CircularProgressIndicator(color: SpotifyColors.green)),
      );
    }
    if (_related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('More videos',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
        ),
        for (final s in _related)
          InkWell(
            onTap: () => _openRelated(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  YoutubeThumbnail(
                    videoId: s.id,
                    imageUrl: s.thumbnail,
                    width: 110,
                    height: 62,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: SpotifyColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(s.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: SpotifyColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}