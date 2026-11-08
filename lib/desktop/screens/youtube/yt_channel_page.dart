// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

import 'package:zenmusic/desktop/screens/youtube/yt_ui.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart' show ytExplode;

class YtChannelPage extends StatefulWidget {
  const YtChannelPage({super.key, required this.channelId, this.title});
  final String channelId;
  final String? title;

  @override
  State<YtChannelPage> createState() => _YtChannelPageState();
}

class _YtChannelPageState extends State<YtChannelPage> {
  yexp.Channel? _channel;
  final List<yexp.Video> _videos = [];
  yexp.ChannelUploadsList? _uploads;
  bool _loading = true;
  bool _loadingMore = false;
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
      _channel = null;
      _videos.clear();
      _uploads = null;
    });
    try {
      final channel = await ytExplode.channels.get(widget.channelId);
      final uploads =
          await ytExplode.channels.getUploadsFromPage(widget.channelId);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _uploads = uploads;
        _videos.addAll(uploads);
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
    final uploads = _uploads;
    if (_loadingMore || uploads == null) return;
    setState(() => _loadingMore = true);
    try {
      final next = await uploads.nextPage();
      if (!mounted) return;
      setState(() {
        if (next == null) {
          _uploads = null;
        } else {
          _uploads = next;
          _videos.addAll(next);
        }
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  int _columns(double width) {
    if (width < 500) return 2;
    if (width < 800) return 3;
    if (width < 1100) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _channel?.title ?? widget.title ?? 'Channel';
    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(
              child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : _error != null
              ? YtErrorCard(
                  message: 'This channel is not reachable right now.',
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
                  child: CustomScrollView(
                    slivers: [
                      // Banner.
                      SliverToBoxAdapter(
                        child: (_channel?.bannerUrl ?? '').isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _channel!.bannerUrl,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    const SizedBox(height: 0))
                            : const SizedBox(height: 0),
                      ),
                      // Identity row.
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: cs.surfaceContainerHighest,
                                backgroundImage:
                                    (_channel?.logoUrl ?? '').isNotEmpty
                                        ? CachedNetworkImageProvider(
                                            _channel!.logoUrl)
                                        : null,
                                child: (_channel?.logoUrl ?? '').isEmpty
                                    ? Text(name.isEmpty
                                        ? '?'
                                        : name.characters.first
                                            .toUpperCase())
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                        ),
                                        const SizedBox(width: 5),
                                        const Icon(Icons.verified_rounded,
                                            size: 15,
                                            color: kYtRed),
                                      ],
                                    ),
                                    if (_channel != null)
                                      Text(
                                        [
                                          if (_channel!.url.isNotEmpty)
                                            _handleHint(_channel!.url),
                                          if (_channel!.subscribersCount !=
                                              null)
                                            '${_channel!.subscribersCount} subscribers',
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
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Videos'.tr,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount:
                                _columns(MediaQuery.of(context).size.width),
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 14,
                            childAspectRatio: 0.98,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              if (i >= _videos.length) {
                                return _uploads == null
                                    ? const SizedBox.shrink()
                                    : const Center(
                                        child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)));
                              }
                              return YtVideoCard(
                                  vm: YtItemVm.fromVideo(_videos[i]));
                            },
                            childCount: _videos.length +
                                (_uploads != null ? 1 : 0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  /// youtube.com/@handle → @handle (best-effort subtitle).
  String _handleHint(String url) {
    final m = RegExp(r'youtube\.com/(@[^/?]+)').firstMatch(url);
    return m?.group(1) ?? '';
  }
}
