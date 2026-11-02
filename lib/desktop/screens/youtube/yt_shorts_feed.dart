// ZenMusic — YouTube Shorts feed (SP-79).
//
// One shared media_kit player drives the vertical snap feed: swiping loads
// the next short through the SAME YtVideoEngine the watch page uses (local
// byte proxy, client priority chain), the next URL is resolved in the
// background while the current short plays, and every short loops until the
// user swipes on. Full watch page stays one tap away via the expand button.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:zenmusic/desktop/screens/youtube/yt_comments_sheet.dart';
import 'package:zenmusic/desktop/screens/youtube/yt_ui.dart';
import 'package:zenmusic/desktop/services/yt_video_engine.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart' show ytExplode;
import 'package:zenmusic/desktop/youtube/yt_browse.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

class YtShortsFeed extends StatefulWidget {
  const YtShortsFeed({super.key});

  @override
  State<YtShortsFeed> createState() => _YtShortsFeedState();
}

class _YtShortsFeedState extends State<YtShortsFeed>
    with AutomaticKeepAliveClientMixin {
  final List<String> _ids = [];
  String? _continuation;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  late final Player _player;
  late final VideoController _controller;
  StreamSubscription? _errSub;

  final Map<String, YtVideoStreams?> _urlCache = {};
  final Map<String, yexp.Video> _meta = {};
  String? _currentId;
  bool _pageLoading = false;
  Object? _pageError;
  bool _muted = false;
  bool _paused = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _player = Player(
        configuration:
            const PlayerConfiguration(bufferSize: 16 * 1024 * 1024));
    _controller = VideoController(_player);
    // Shorts loop until the user swipes on (media_kit's playlist loop).
    _player.setPlaylistMode(PlaylistMode.single);
    _errSub = _player.stream.error.listen((e) {
      if (mounted && _currentId != null) {
        setState(() => _pageError = e);
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _errSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────── feed data

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _ids.clear();
      _continuation = null;
    });
    try {
      final ids = await YtBrowse.shortsIds();
      if (!mounted) return;
      if (ids.isEmpty) {
        setState(() {
          _error = YtBrowseException('no shorts returned');
          _loading = false;
        });
        return;
      }
      setState(() {
        _ids.addAll(ids);
        // SP-80: the shorts engine now reports its own follow-up token
        // ("#shorts" search pages); remember it for the next page.
        _continuation = YtBrowse.lastShortsContinuation;
        _loading = false;
      });
      _resolveAndPlay(0);
      if (ids.length > 1) _prefetch(1);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _continuation == null) return;
    setState(() => _loadingMore = true);
    try {
      final ids = await YtBrowse.shortsIds(continuation: _continuation);
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          if (!_ids.contains(id)) _ids.add(id);
        }
        _continuation = YtBrowse.lastShortsContinuation;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  // ───────────────────────────────────────────────── playback

  Future<String?> _resolveUrl(String id) async {
    if (_urlCache.containsKey(id)) return _urlCache[id]?.videoUrl;
    YtVideoStreams? streams;
    try {
      streams = await YtVideoEngine.extractVideo(id, maxHeight: 720);
    } catch (_) {
      streams = null;
    }
    _urlCache[id] = streams;
    return streams?.videoUrl;
  }

  Future<void> _resolveAndPlay(int index) async {
    if (index < 0 || index >= _ids.length) return;
    final id = _ids[index];
    setState(() {
      _pageLoading = true;
      _pageError = null;
      _currentId = id;
      _paused = false;
    });
    _hydrateMeta(id);
    final url = await _resolveUrl(id);
    if (!mounted || _currentId != id) return;
    if (url == null) {
      setState(() {
        _pageLoading = false;
        _pageError = 'Could not resolve this short.';
      });
      return;
    }
    await _player.open(Media(url));
    if (!mounted) return;
    setState(() => _pageLoading = false);
    _player.setVolume(_muted ? 0.0 : 100.0);
  }

  void _prefetch(int index) {
    if (index >= _ids.length) return;
    final id = _ids[index];
    if (_urlCache.containsKey(id)) return;
    _resolveUrl(id).then((url) {
      if (url != null) _hydrateMeta(id);
    });
  }

  Future<void> _hydrateMeta(String id) async {
    if (_meta.containsKey(id)) return;
    try {
      final v = await ytExplode.videos.get(id);
      if (!mounted) return;
      setState(() => _meta[id] = v);
    } catch (_) {
      // Metadata is cosmetic here — the short still plays.
    }
  }

  void _onPageChanged(int index) {
    if (index >= _ids.length) {
      _loadMore();
      return;
    }
    _resolveAndPlay(index);
    _prefetch(index + 1);
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _player.setVolume(_muted ? 0.0 : 100.0);
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  // ─────────────────────────────────────────────────────── UI

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null && _ids.isEmpty) {
      return YtErrorCard(
        message: 'Shorts are not reachable right now.',
        onRetry: _reload,
      );
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _ids.length + (_continuation != null ? 1 : 0),
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        if (i >= _ids.length) {
          return const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return _shortPage(_ids[i]);
      },
    );
  }

  Widget _shortPage(String id) {
    final meta = _meta[id];
    final isCurrent = id == _currentId;
    final title = meta?.title ?? '';
    final author = meta?.author ?? '';
    final authorId = meta?.channelId.value ?? '';

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video stage — kept dark behind the vertical video.
        Container(color: Colors.black),
        if (isCurrent && _pageError == null)
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fit: BoxFit.contain,
          ),
        if (!isCurrent || _pageLoading)
          const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: Colors.white))),
        if (isCurrent && _pageError != null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white70, size: 34),
                const SizedBox(height: 10),
                const Text('This short could not be played.',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _resolveAndPlay(_ids.indexOf(id)),
                  child: const Text('Retry',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        // Tap → play/pause.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isCurrent && _pageError == null ? _togglePause : null,
        ),
        // Top-right: mute.
        Positioned(
          right: 12,
          top: 12,
          child: IconButton(
            tooltip: _muted ? 'Unmute' : 'Mute',
            onPressed: _toggleMute,
            style: IconButton.styleFrom(backgroundColor: Colors.black38),
            icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: Colors.white),
          ),
        ),
        // Bottom: meta + actions.
        Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title.isNotEmpty)
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: authorId.isEmpty
                          ? null
                          : () => context
                              .push('/yt_channel', extra: {'id': authorId, 'title': author}),
                      child: Text(
                        author.isEmpty ? 'YouTube Shorts' : author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  ),
                  if (meta != null && (meta.engagement.likeCount ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.thumb_up_alt_rounded,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text('${meta.engagement.likeCount}',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () {
                      YtItemVm(
                        id: id,
                        title: title,
                        author: author,
                        authorId: authorId,
                        thumb: 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
                      ).open(context);
                    },
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    icon: const Icon(Icons.open_in_full_rounded, size: 15),
                    label: const Text('Watch'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => YtCommentsSheet.show(context, id),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12)),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text('Comments'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Subtle shorts tag.
        Positioned(
          left: 16,
          top: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kYtRed.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
                SizedBox(width: 2),
                Text('Shorts',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
