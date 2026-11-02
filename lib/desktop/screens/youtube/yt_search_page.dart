// ZenMusic — YouTube search (SP-79).
//
// One query, four result scopes (All / Videos / Channels / Playlists)
// through the vendored youtube_explode SearchClient. Results paginate with
// the list's own nextPage(); videos open in the shared watch page, channels
// and playlists open their SP-79 pages.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart' show ytExplode;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yexp;

import 'package:zenmusic/desktop/screens/youtube/yt_ui.dart';

class YtSearchPage extends StatefulWidget {
  const YtSearchPage({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<YtSearchPage> createState() => _YtSearchPageState();
}

class _YtSearchPageState extends State<YtSearchPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  static const _scopes = ['All', 'Videos', 'Channels', 'Playlists'];
  int _scope = 0;

  yexp.SearchList? _list;
  final List<yexp.SearchResult> _results = [];
  String _query = '';
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _runSearch(widget.initialQuery!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd = _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset > _scroll.position.maxScrollExtent - 600;
    if (nearEnd) _loadMore();
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) return;
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
      _results.clear();
      _list = null;
    });
    try {
      final filter = switch (_scope) {
        1 => yexp.TypeFilters.video,
        2 => yexp.TypeFilters.channel,
        3 => yexp.TypeFilters.playlist,
        _ => const yexp.SearchFilter(''),
      };
      final list = await ytExplode.search.searchContent(query, filter: filter);
      if (!mounted) return;
      setState(() {
        _list = list;
        _results.addAll(list);
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
    final list = _list;
    if (_loadingMore || _loading || list == null || _query.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await list.nextPage();
      if (!mounted) return;
      setState(() {
        if (next == null) {
          _list = null; // exhausted
        } else {
          _list = next;
          _results.addAll(next);
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: _runSearch,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search YouTube',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _controller.clear();
                        setState(() => _results.clear());
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => _runSearch(_controller.text),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              children: [
                for (var i = 0; i < _scopes.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_scopes[i]),
                      selected: _scope == i,
                      showCheckmark: false,
                      selectedColor: cs.primary,
                      labelStyle: TextStyle(
                        color:
                            _scope == i ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight:
                            _scope == i ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) {
                        setState(() => _scope = i);
                        if (_query.isNotEmpty) _runSearch(_query);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(
          child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_error != null && _results.isEmpty) {
      return const YtErrorCard(message: 'Search is not reachable right now.');
    }
    if (_query.isEmpty) {
      return const YtErrorCard(message: 'Type something to search YouTube.');
    }
    if (_results.isEmpty) {
      return const YtErrorCard(message: 'No results found.');
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 96),
      itemCount: _results.length + (_list != null ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final r = _results[i];
        if (r is yexp.SearchVideo) {
          return YtVideoTile(vm: YtItemVm.fromSearchVideo(r), onOpenChannel: _openChannel);
        }
        if (r is yexp.SearchChannel) {
          return _channelRow(context, r);
        }
        if (r is yexp.SearchPlaylist) {
          return _playlistRow(context, r);
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _openChannel(String id) {
    context.push('/yt_channel', extra: {'id': id});
  }

  Widget _channelRow(BuildContext context, yexp.SearchChannel c) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/yt_channel',
          extra: {'id': c.id.value, 'title': c.name}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: cs.surfaceContainerHighest,
              backgroundImage: c.thumbnails.isEmpty
                  ? null
                  : CachedNetworkImageProvider(
                      c.thumbnails.last.url.toString()),
              child: c.thumbnails.isEmpty
                  ? Text(c.name.isEmpty
                      ? '?'
                      : c.name.characters.first.toUpperCase())
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                      if (c.isVerifiedArtist) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            size: 14, color: kYtRed),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      'Channel',
                      if (c.videoCount > 0) '${c.videoCount} videos',
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistRow(BuildContext context, yexp.SearchPlaylist p) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/yt_playlist',
          extra: {'id': p.id.value, 'title': p.title}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 148,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: cs.surfaceContainerHighest),
                      if (p.thumbnails.isNotEmpty)
                        Image(
                          image: CachedNetworkImageProvider(
                              p.thumbnails.last.url.toString()),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              ColoredBox(color: cs.surfaceContainerHighest),
                        ),
                      const Center(
                        child: Icon(Icons.playlist_play_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(p.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'Playlist',
                      if (p.videoCount > 0) '${p.videoCount} videos',
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11.5, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
