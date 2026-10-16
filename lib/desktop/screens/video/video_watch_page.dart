// ZenMusic Desktop — FRESH minimal video watch page (mobile): native
// extraction (InnertubexBridge — Android-only) + video_player. Landscape
// video area on top, quality picker, related songs below. Desktop shows
// the native-bridge-unavailable notice (video is a mobile feature).

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player/video_player.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

class VideoWatchPage extends StatefulWidget {
  const VideoWatchPage({super.key, required this.videoId});
  final String videoId;

  @override
  State<VideoWatchPage> createState() => _VideoWatchPageState();
}

class _VideoWatchPageState extends State<VideoWatchPage> {
  VideoPlayerController? _controller;
  List<ItxVideoQuality> _qualities = const [];
  int _selectedHeight = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _related = const [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Pause audio playback — the video takes over.
    try {
      await GetIt.I<MediaPlayer>().player.pause();
    } catch (_) {}

    final streams =
    await InnertubexBridge.extractVideo(widget.videoId, maxHeight: 0);
    if (!mounted) return;
    if (streams == null || streams.videoUrl == null) {
      setState(() {
        _loading = false;
        _error = streams == null
            ? 'Video needs the Android app (native extraction unavailable).'
            : 'No video stream available for this song.';
      });
      return;
    }
    _qualities = await InnertubexBridge.videoQualities(widget.videoId);
    await _open(streams.videoUrl!, streams.headers);
    if (!mounted) return;
    final related = await InnertubexBridge.relatedSongs(widget.videoId);
    if (mounted) setState(() => _related = related);
  }

  Future<void> _open(String url, Map<String, String> headers) async {
    final old = _controller;
    final c = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers,
    );
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    await c.play();
    setState(() {
      _controller = c;
      _loading = false;
      _error = null;
    });
    await old?.dispose();
  }

  Future<void> _switchQuality(int height) async {
    setState(() => _selectedHeight = height);
    final streams =
    await InnertubexBridge.extractVideo(widget.videoId, maxHeight: height);
    if (streams?.videoUrl != null) {
      await _open(streams!.videoUrl!, streams.headers);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Video')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      )
          : ListView(
        children: [
          AspectRatio(
            aspectRatio: c!.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          Row(
            children: [
              VideoProgressIndicator(c, allowScrubbing: true),
              IconButton(
                onPressed: () {
                  c.value.isPlaying
                      ? c.pause()
                      : c.play();
                },
                icon: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: c,
                  builder: (_, v, __) => Icon(
                    v.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                ),
              ),
              if (_qualities.isNotEmpty)
                PopupMenuButton<int>(
                  tooltip: 'Quality',
                  itemBuilder: (_) => [
                    for (final q in _qualities)
                      PopupMenuItem(
                        value: q.height,
                        child: Text(
                            '${q.height}p${q.height == _selectedHeight ? '  ✓' : ''}'),
                      ),
                  ],
                  onSelected: _switchQuality,
                ),
            ],
          ),
          if (_related.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final song in _related)
              SectionItem(section: {
                'title': 'Related',
                'contents': [song],
              }),
          ],
        ],
      ),
    );
  }
}