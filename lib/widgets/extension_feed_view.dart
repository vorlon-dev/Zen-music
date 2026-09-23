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

/// Loads and renders the home feed of the active extension.
/// Remount it (change its key) to reload.
class ExtensionHomeFeed extends StatefulWidget {
  const ExtensionHomeFeed({
    super.key,
    required this.onTrackTap,
    required this.onMediaTap,
  });

  final void Function(List<ExtMedia> tracks, int index) onTrackTap;
  final void Function(ExtMedia media) onMediaTap;

  @override
  State<ExtensionHomeFeed> createState() => _ExtensionHomeFeedState();
}

class _ExtensionHomeFeedState extends State<ExtensionHomeFeed> {
  final _service = ExtensionFeedService();
  List<ExtShelf> _shelves = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shelves = await _service.homeFeed();
      if (!mounted) return;
      setState(() {
        _shelves = shelves;
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
    return ExtensionShelfList(
      shelves: _shelves,
      onTrackTap: widget.onTrackTap,
      onMediaTap: widget.onMediaTap,
    );
  }
}

class ExtensionShelfList extends StatelessWidget {
  const ExtensionShelfList({
    super.key,
    required this.shelves,
    required this.onTrackTap,
    required this.onMediaTap,
  });

  final List<ExtShelf> shelves;
  final void Function(List<ExtMedia> tracks, int index) onTrackTap;
  final void Function(ExtMedia media) onMediaTap;

  static final _playingStream = audioHandler.currentSongStream;

  void _tap(List<ExtMedia> items, int index) {
    final playable = <ExtMedia>[];
    var playIndex = -1;
    for (var i = 0; i < items.length; i++) {
      if (items[i].kind == 'Track') {
        if (i == index) playIndex = playable.length;
        playable.add(items[i]);
      }
    }
    if (playable.isEmpty || playIndex < 0) return;
    onTrackTap(playable, playIndex);
  }

  void _onItemTap(List<ExtMedia> items, int index) {
    final media = items[index];
    if (media.kind == 'Track') {
      _tap(items, index);
    } else {
      onMediaTap(media);
    }
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
        return ThreeTracksRow(
          title: shelf.title,
          subtitle: shelf.subtitle,
          items: [for (final m in shelf.items) ShelfItem.fromExt(m)],
          onTapItem: (i) => _tap(shelf.items, i),
          playingIdStream: _playingStream,
        );
      case 'items':
        if (shelf.grid) return _grid(shelf);
        return MediaShelfRow(
          title: shelf.title,
          subtitle: shelf.subtitle,
          items: [for (final m in shelf.items) ShelfItem.fromExt(m)],
          onTapItem: (i) => _onItemTap(shelf.items, i),
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
    final items = shelf.items.take(8).toList();
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
              for (var i = 0; i < items.length; i++)
                GestureDetector(
                  onTap: () => _onItemTap(items, i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ShelfCover(
                          item: ShelfItem.fromExt(items[i]),
                          isPlaying: false,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        items[i].title,
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