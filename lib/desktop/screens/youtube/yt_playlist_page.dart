// ZenMusic · vorlon-dev

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

import 'package:zenmusic/desktop/screens/youtube/yt_ui.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart' show ytExplode;

class YtPlaylistPage extends StatefulWidget {
  const YtPlaylistPage({super.key, required this.playlistId, this.title});
  final String playlistId;
  final String? title;

  @override
  State<YtPlaylistPage> createState() => _YtPlaylistPageState();
}

class _YtPlaylistPageState extends State<YtPlaylistPage> {
  yexp.Playlist? _playlist;
  final List<yexp.Video> _videos = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _playlist = null;
      _videos.clear();
      _exhausted = false;
    });
    try {
      final playlist = await ytExplode.playlists.get(widget.playlistId);
      final first = await ytExplode.playlists.getVideos(widget.playlistId)
          .take(30)
          .toList();
      if (!mounted) return;
      setState(() {
        _playlist = playlist;
        _videos.addAll(first);
        if (first.length < 30) _exhausted = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _exhausted) return;
    setState(() => _loadingMore = true);
    try {
      final more =
          await ytExplode.playlists.getVideos(widget.playlistId).skip(_videos.length).take(30).toList();
      if (!mounted) return;
      setState(() {
        if (more.isEmpty) {
          _exhausted = true;
        } else {
          final known = _videos.map((v) => v.id.value).toSet();
          _videos.addAll(more.where((v) => !known.contains(v.id.value)));
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = _playlist?.title ?? widget.title ?? 'Playlist';
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : _error != null
              ? YtErrorCard(
                  message: 'This playlist is not reachable right now.',
                  onRetry: _load,
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >
                        n.metrics.maxScrollExtent - 700) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 96),
                    itemCount: _videos.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 168,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 9,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        ColoredBox(
                                            color: cs
                                                .surfaceContainerHighest),
                                        if (_playlist != null)
                                          Image(
                                            image: CachedNetworkImageProvider(
                                                _playlist!.thumbnails
                                                    .highResUrl),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                ColoredBox(
                                                    color: cs
                                                        .surfaceContainerHighest),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25)),
                                    const SizedBox(height: 6),
                                    Text(
                                      [
                                        'Playlist',
                                        if (_playlist != null &&
                                            _playlist!.author.isNotEmpty)
                                          _playlist!.author,
                                        if (_playlist?.videoCount != null)
                                          '${_playlist!.videoCount} videos',
                                      ].join(' · '),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (i > _videos.length) return const SizedBox.shrink();
                      if (i == _videos.length) {
                        return _exhausted
                            ? const SizedBox.shrink()
                            : const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))),
                              );
                      }
                      return YtVideoTile(
                          vm: YtItemVm.fromVideo(_videos[i - 1]));
                    },
                  ),
                ),
    );
  }
}
