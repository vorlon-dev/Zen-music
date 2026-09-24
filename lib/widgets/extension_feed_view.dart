import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/extension_feed_service.dart';
import '../theme/spotify_theme.dart';
import 'media_shelf.dart';
import 'wave_spinner.dart';

export 'media_shelf.dart'
    show ExtCover, ExtTrackRow, CoverArt, parseHexColor, formatExtDuration;

/// Loads and renders the home feed of the active extension, appending
/// pages as the user scrolls. Remount it (change its key) to reload.
class ExtensionHomeFeed extends StatefulWidget {
  const ExtensionHomeFeed({
    super.key,
    required this.onTrackTap,
    required this.onMediaTap,
    this.onMediaLongPress,
  });

  final void Function(List<ExtMedia> tracks, int index) onTrackTap;
  final void Function(ExtMedia media) onMediaTap;
  final void Function(ExtMedia media)? onMediaLongPress;

  @override
  State<ExtensionHomeFeed> createState() => _ExtensionHomeFeedState();
}

class _ExtensionHomeFeedState extends State<ExtensionHomeFeed> {
  final _service = ExtensionFeedService();
  final _scroll = ScrollController();

  List<ExtShelf> _shelves = [];
  String? _continuation;
  bool _loading = true;
  bool _loadingMore = false;
  bool _endReached = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_endReached || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _shelves = [];
      _continuation = null;
      _endReached = false;
    });
    try {
      final page = await _service.homeFeedPage(null);
      if (!mounted) return;
      setState(() {
        _shelves = page.shelves;
        _continuation = page.continuation;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e is PlatformException && e.message != null
          ? e.message!
          : 'Could not load this extension\'s home feed';
      setState(() {
        _loading = false;
        _error = message;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_continuation == null || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.homeFeedPage(_continuation);
      if (!mounted) return;
      setState(() {
        _shelves.addAll(page.shelves);
        _continuation = page.continuation;
        _endReached = page.continuation == null;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: WaveSpinner(size: 26)),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: SpotifyColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_shelves.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
        child: Center(
          child: Text(
            'This extension returned no home content',
            style: TextStyle(color: SpotifyColors.textSecondary, fontSize: 14),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        children: [
          ExtensionShelfList(
            shelves: _shelves,
            onTrackTap: widget.onTrackTap,
            onMediaTap: widget.onMediaTap,
            onMediaLongPress: widget.onMediaLongPress,
          ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: WaveSpinner(size: 22)),
            )
          else if (_endReached)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'You\'re all caught up',
                  style: TextStyle(
                    color: SpotifyColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ExtensionShelfList extends StatelessWidget {
  const ExtensionShelfList({
    super.key,
    required this.shelves,
    required this.onTrackTap,
    required this.onMediaTap,
    this.onMediaLongPress,
  });

  final List<ExtShelf> shelves;
  final void Function(List<ExtMedia> tracks, int index) onTrackTap;
  final void Function(ExtMedia media) onMediaTap;
  final void Function(ExtMedia media)? onMediaLongPress;

  static final _playingStream = audioHandler.currentSongStream;

  // ── Songs-only policy ──
  // Home feeds render and queue ONLY songs (Track + Song type, no
  // podcasts, no videos). Albums / artists / playlists stay as
  // navigation cards. Videos belong to the search screen only.

  static List<ExtMedia> _songsOnly(List<ExtMedia> items) =>
      items.where((m) => m.isSong).toList();

  void _tap(List<ExtMedia> items, int index) {
    final playable = <ExtMedia>[];
    var playIndex = -1;
    for (var i = 0; i < items.length; i++) {
      if (items[i].isSong) {
        if (i == index) playIndex = playable.length;
        playable.add(items[i]);
      }
    }
    if (playable.isEmpty || playIndex < 0) return;
    onTrackTap(playable, playIndex);
  }

  void _onItemTap(List<ExtMedia> items, int index) {
    final media = items[index];
    if (media.isSong) {
      _tap(items, index);
    } else if (!media.isVideo) {
      // Navigation cards only — video items are search-only.
      onMediaTap(media);
    }
  }

  void _onItemLongPress(List<ExtMedia> items, int index) {
    final media = items[index];
    if (media.isSong) onMediaLongPress?.call(media);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections) ...[
          section,
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  List<Widget> get sections {
    final widgets = <Widget>[];
    for (final shelf in shelves) {
      final section = _section(shelf);
      if (section != null) widgets.add(section);
    }
    return widgets;
  }

  Widget? _section(ExtShelf shelf) {
    switch (shelf.kind) {
      case 'tracks':
        final songs = _songsOnly(shelf.items);
        if (songs.isEmpty) return null;
        return ThreeTracksRow(
          title: shelf.title,
          subtitle: shelf.subtitle,
          items: [for (final m in songs) ShelfItem.fromExt(m)],
          onTapItem: (i) => _tap(songs, i),
          onItemLongPress: onMediaLongPress == null
              ? null
              : (i) => _onItemLongPress(songs, i),
          playingIdStream: _playingStream,
        );
      case 'items':
        if (shelf.grid) return _grid(shelf);
        final visible = shelf.items
            .where((m) => m.isSong || (m.kind != 'Track' && !m.isVideo))
            .toList();
        if (visible.isEmpty) return null;
        return MediaShelfRow(
          title: shelf.title,
          subtitle: shelf.subtitle,
          items: [for (final m in visible) ShelfItem.fromExt(m)],
          onTapItem: (i) => _onItemTap(visible, i),
          onItemLongPress: onMediaLongPress == null
              ? null
              : (i) => _onItemLongPress(visible, i),
          playingIdStream: _playingStream,
        );
      case 'categories':
        return _categoryRow(shelf);
      case 'item':
        return _singleItem(shelf);
      case 'category':
        return _categoryHeader(shelf);
      default:
        return null;
    }
  }

  Widget _grid(ExtShelf shelf) {
    final visible = shelf.items
        .where((m) => m.isSong || (m.kind != 'Track' && !m.isVideo))
        .take(8)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(title: shelf.title, subtitle: shelf.subtitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 0.55,
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < visible.length; i++)
                GestureDetector(
                  onTap: () => _onItemTap(visible, i),
                  onLongPress: (visible[i].isSong && onMediaLongPress != null)
                      ? () => onMediaLongPress!(visible[i])
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ShelfCover(
                          item: ShelfItem.fromExt(visible[i]),
                          isPlaying: false,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        visible[i].title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _categoryRow(ExtShelf shelf) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShelfHeaderBar(title: shelf.title, subtitle: shelf.subtitle),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            clipBehavior: Clip.none,
            itemCount: shelf.categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) =>
                _CategoryTile(category: shelf.categories[i]),
          ),
        ),
      ],
    );
  }

  Widget _singleItem(ExtShelf shelf) {
    final media = shelf.items.first;
    if (media.isVideo) return const SizedBox.shrink();
    final item = ShelfItem.fromExt(media);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => ShelfCover(
            item: item,
            isPlaying: false,
            size: constraints.maxWidth,
            borderRadius: 12,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          media.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: SpotifyColors.textPrimary,
          ),
        ),
        if ((media.subtitle ?? '').isNotEmpty)
          Text(
            media.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: SpotifyColors.textSecondary.withOpacity(0.66),
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () => _onItemTap(shelf.items, 0),
        onLongPress: (media.isSong && onMediaLongPress != null)
            ? () => onMediaLongPress!(media)
            : null,
        child: body,
      ),
    );
  }

  Widget _categoryHeader(ExtShelf shelf) {
    final bg = parseHexColor(shelf.backgroundColor);
    final hasVisual = bg != null || shelf.imageUrl != null;
    if (!hasVisual) {
      if (shelf.title.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ShelfHeaderBar(title: shelf.title),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _CategoryTile(
        category: ExtCategory(
          title: shelf.title,
          backgroundColor: shelf.backgroundColor,
          imageUrl: shelf.imageUrl,
          imageHeaders: shelf.imageHeaders,
        ),
        expand: true,
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.expand = false});

  final ExtCategory category;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final bg = parseHexColor(category.backgroundColor);
    final hasImage = category.imageUrl != null && bg == null;
    final tile = Container(
      width: expand ? double.infinity : 160,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? SpotifyColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        image: hasImage
            ? DecorationImage(
          image: CoverArt.provider(
            category.imageUrl!,
            headers: category.imageHeaders.isEmpty
                ? null
                : category.imageHeaders,
          ),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black45,
            BlendMode.darken,
          ),
        )
            : null,
      ),
      child: Text(
        category.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: hasImage || bg != null
              ? Colors.white
              : SpotifyColors.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: expand ? SizedBox(height: 84, child: tile) : tile,
    );
  }
}