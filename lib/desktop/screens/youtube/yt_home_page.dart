// ZenMusic · vorlon-dev

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/youtube/yt_shorts_feed.dart';
import 'package:zenmusic/desktop/screens/youtube/yt_ui.dart';
import 'package:zenmusic/desktop/youtube/yt_browse.dart';

class YtHomePage extends StatefulWidget {
  const YtHomePage({super.key});

  @override
  State<YtHomePage> createState() => _YtHomePageState();
}

class _YtHomePageState extends State<YtHomePage> {
  int _tab = 0;
  final Map<int, Widget> _builtTabs = {};

  static const List<String> _tabNames = ['Home', 'Trending', 'Shorts'];

  Widget _tabBody(int i) {
    return _builtTabs.putIfAbsent(
      i,
      () => switch (i) {
        0 => const _YtFeedTab(browseId: YtBrowse.home),
        1 => const _YtTrendingTab(),
        _ => const YtShortsFeed(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 18,
              decoration: BoxDecoration(
                color: kYtRed,
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.play_arrow_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Text('YouTube'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Search YouTube',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/yt_search'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab chips.
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              children: [
                for (var i = 0; i < _tabNames.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_tabNames[i]),
                      selected: _tab == i,
                      showCheckmark: false,
                      selectedColor: cs.primary,
                      labelStyle: TextStyle(
                        color: _tab == i
                            ? cs.onPrimary
                            : cs.onSurfaceVariant,
                        fontWeight:
                            _tab == i ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [for (var i = 0; i < _tabNames.length; i++) _tabBody(i)],
            ),
          ),
        ],
      ),
    );
  }
}


class _FeedBox {
  final List<YtFeedVideo> items = [];
  String? continuation;
  bool loading = false;
  bool loadingMore = false;
  Object? error;
}

/// One paged browse feed rendered as a responsive video grid.
class _YtFeedTab extends StatefulWidget {
  const _YtFeedTab({required this.browseId});
  final String browseId;

  @override
  State<_YtFeedTab> createState() => _YtFeedTabState();
}

class _YtFeedTabState extends State<_YtFeedTab>
    with AutomaticKeepAliveClientMixin {
  final _box = _FeedBox();
  final _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd = _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset > _scroll.position.maxScrollExtent - 800;
    if (nearEnd) _loadMore();
  }

  Future<void> _reload() async {
    if (_box.loading) return;
    setState(() {
      _box
        ..loading = true
        ..error = null
        ..items.clear()
        ..continuation = null;
    });
    try {
      final page = await YtBrowse.fetch(browseId: widget.browseId);
      if (!mounted) return;
      setState(() {
        _box.items.addAll(page.items);
        _box.continuation = page.continuation;
        _box.loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _box.error = e;
        _box.loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_box.loadingMore || _box.loading || _box.continuation == null) return;
    setState(() => _box.loadingMore = true);
    try {
      final page =
          await YtBrowse.fetch(continuation: _box.continuation);
      if (!mounted) return;
      // A continuation may replay items on flaky responses — dedupe by id.
      final known = _box.items.map((e) => e.id).toSet();
      final fresh =
          page.items.where((e) => e.id.isNotEmpty && !known.contains(e.id));
      setState(() {
        _box.items.addAll(fresh);
        _box.continuation = page.continuation;
        _box.loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _box.loadingMore = false);
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
    super.build(context);
    if (_box.loading) {
      return LayoutBuilder(builder: (context, box) =>
          YtGridSkeleton(columns: _columns(box.maxWidth)));
    }
    if (_box.error != null && _box.items.isEmpty) {
      return YtErrorCard(
        message: 'YouTube is not reachable right now.',
        onRetry: _reload,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(builder: (context, box) {
        final cols = _columns(box.maxWidth);
        final rows = _box.items.length + (_box.continuation != null ? cols : 0);
        return GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.98,
          ),
          itemCount: rows,
          itemBuilder: (context, i) {
            if (i >= _box.items.length) {
              return const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final vm = YtItemVm.fromFeed(_box.items[i]);
            return YtVideoCard(
              vm: vm,
              onOpenChannel: (id) => context.push('/yt_channel',
                  extra: {'id': id, 'title': vm.author}),
            );
          },
        );
      }),
    );
  }
}


class _YtTrendingTab extends StatefulWidget {
  const _YtTrendingTab();

  @override
  State<_YtTrendingTab> createState() => _YtTrendingTabState();
}

class _YtTrendingTabState extends State<_YtTrendingTab>
    with AutomaticKeepAliveClientMixin {
  final _box = _FeedBox();
  final _scroll = ScrollController();
  List<YtChip> _chips = const [];
  int _selectedChip = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd = _scroll.position.maxScrollExtent > 0 &&
        _scroll.offset > _scroll.position.maxScrollExtent - 800;
    if (nearEnd) _loadMore();
  }

  Future<void> _reload() => _load(browseId: YtBrowse.trending);

  Future<void> _load({String? browseId, String? continuation}) async {
    if (_box.loading) return;
    setState(() {
      _box
        ..loading = true
        ..error = null
        ..items.clear()
        ..continuation = null;
    });
    try {
      final page = await YtBrowse.fetch(
          browseId: browseId, continuation: continuation);
      if (!mounted) return;
      setState(() {
        _box.items.addAll(page.items.where((e) => !e.isShort));
        _box.continuation = page.continuation;
        _box.loading = false;
        if (page.chips.isNotEmpty) {
          _chips = page.chips;
          _selectedChip = 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _box.error = e;
        _box.loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_box.loadingMore || _box.loading || _box.continuation == null) return;
    setState(() => _box.loadingMore = true);
    try {
      final page =
          await YtBrowse.fetch(continuation: _box.continuation);
      if (!mounted) return;
      final known = _box.items.map((e) => e.id).toSet();
      final fresh = page.items
          .where((e) => e.id.isNotEmpty && !e.isShort && !known.contains(e.id));
      setState(() {
        _box.items.addAll(fresh);
        _box.continuation = page.continuation;
        _box.loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _box.loadingMore = false);
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
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    if (_box.loading) {
      return LayoutBuilder(builder: (context, box) =>
          YtGridSkeleton(columns: _columns(box.maxWidth)));
    }
    if (_box.error != null && _box.items.isEmpty) {
      return YtErrorCard(
        message: 'Trending is not reachable right now.',
        onRetry: _reload,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: LayoutBuilder(builder: (context, box) {
        final cols = _columns(box.maxWidth);
        final rows = _box.items.length + (_box.continuation != null ? cols : 0);
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            if (_chips.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    children: [
                      for (var i = 0; i < _chips.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_chips[i].title),
                            selected: _selectedChip == i,
                            showCheckmark: false,
                            selectedColor: cs.primary,
                            labelStyle: TextStyle(
                              color: _selectedChip == i
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                              fontWeight: _selectedChip == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            onSelected: (_) {
                              setState(() => _selectedChip = i);
                              // Chip taps browse BY THEIR OWN continuation
                              // token — no hardcoded category params.
                              _load(continuation: _chips[i].continuation);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.98,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i >= _box.items.length) {
                      return const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)));
                    }
                    final vm = YtItemVm.fromFeed(_box.items[i]);
                    return YtVideoCard(
                      vm: vm,
                      onOpenChannel: (id) => context.push('/yt_channel',
                          extra: {'id': id, 'title': vm.author}),
                    );
                  },
                  childCount: rows,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
