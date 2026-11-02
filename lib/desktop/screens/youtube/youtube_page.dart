// SP-78 — the in-app YouTube section (nav tab between Search and Saved).
//
// Cross-platform by construction: every platform browses and searches
// through the app's own InnerTube client (YTMusic — the same client the
// home feed and search run on), so no platform-specific fetcher lives in
// this file. Playback ALWAYS goes through the watch page (/video):
//   • Android resolves streams through the app's native InnerTube
//     resolver first (InnertubexBridge), falling back to pure Dart;
//   • Windows uses the pure-Dart pipeline (YtVideoEngine).
// The user's ask: mobile = the InnerTube the app already has, Windows =
// Dart. The split lives in video_watch_page.dart's stream cache; this page
// only ever hands over a videoId.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class YouTubePage extends StatefulWidget {
  const YouTubePage({super.key});

  @override
  State<YouTubePage> createState() => _YouTubePageState();
}

class _YouTubePageState extends State<YouTubePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Feed state (browse shelves) — a Future field the FutureBuilder can
  // re-arm by calling setState (new future each build).
  Future<List<_Shelf>>? _feed;
  Object? _feedError;

  // Search state (null = show the feed).
  List<_VideoCard>? _results;
  bool _searching = false;
  Object? _searchError;
  String _lastQuery = '';

  YTMusic get _yt => GetIt.I<YTMusic>();

  @override
  void initState() {
    super.initState();
    _feed = _loadFeed();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<List<_Shelf>> _loadFeed() async {
    try {
      final feed = await _yt.browse();
      final shelves = <_Shelf>[];
      for (final section in (feed['sections'] as List? ?? const [])) {
        if (section is! Map) continue;
        final title = section['title']?.toString() ?? '';
        final cards = _cardsOf(section['contents'] as List? ?? const []);
        if (cards.isEmpty) continue;
        shelves.add(_Shelf(title: title, items: cards));
      }
      if (shelves.isEmpty) {
        throw StateError('The YouTube feed came back empty.');
      }
      _feedError = null;
      return shelves;
    } catch (e) {
      _feedError = e;
      rethrow;
    }
  }

  void _reloadFeed() {
    setState(() => _feed = _loadFeed());
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = null;
        _searchError = null;
        _lastQuery = '';
      });
      _searchFocus.unfocus();
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _lastQuery = q;
    });
    _searchFocus.unfocus();
    try {
      final res = await _yt.search(q, filter: 'videos', limit: 40);
      final cards = <_VideoCard>[];
      for (final section in (res['sections'] as List? ?? const [])) {
        if (section is! Map) continue;
        cards.addAll(_cardsOf(section['contents'] as List? ?? const []));
      }
      if (!mounted) return;
      setState(() {
        _results = cards;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  /// Lenient item mapping: browse and search shelves agree on videoId /
  /// title / thumbnails, everything else is best-effort.
  List<_VideoCard> _cardsOf(List contents) {
    return [
      for (final m in ytVideoCardMaps(contents))
        _VideoCard(
          videoId: m['videoId']!,
          title: m['title']!,
          subtitle: m['subtitle']!,
          thumbnails: const [],
        ),
    ];
  }

  void _watch(_VideoCard card) {
    // The watch page owns streaming (native InnerTube on Android, pure
    // Dart on Windows) — this page never resolves URLs itself.
    context.push('/video', extra: card.videoId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: _runSearch,
              decoration: InputDecoration(
                hintText: 'Search YouTube',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: (_results != null || _searchCtrl.text.isNotEmpty)
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _runSearch('');
                        },
                      )
                    : null,
                filled: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchError != null && _results == null) {
      return _ErrorView(
        message: 'The search failed. Check your connection and try again.',
        actionLabel: 'Retry "$_lastQuery"',
        retry: true,
        onAction: () => _runSearch(_lastQuery),
      );
    }
    if (_results != null) {
      if (_results!.isEmpty) {
        return _ErrorView(
          message: 'No video results for "$_lastQuery".',
          actionLabel: 'Back to the feed',
          retry: false,
          onAction: () => _runSearch(''),
        );
      }
      return RefreshIndicator(
        onRefresh: () => _runSearch(_lastQuery),
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _results!.length,
          itemBuilder: (context, i) => _ResultTile(
            card: _results![i],
            onTap: () => _watch(_results![i]),
          ),
        ),
      );
    }
    return FutureBuilder<List<_Shelf>>(
      future: _feed,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError || _feedError != null) {
          return _ErrorView(
            message: 'Could not load the YouTube feed. '
                'Check your connection and try again.',
            actionLabel: 'Retry',
            retry: true,
            onAction: _reloadFeed,
          );
        }
        final shelves = snap.data ?? const <_Shelf>[];
        return RefreshIndicator(
          onRefresh: () async => _reloadFeed(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: shelves.length,
            itemBuilder: (context, i) => _ShelfRow(
              shelf: shelves[i],
              onTap: _watch,
            ),
          ),
        );
      },
    );
  }
}

// ─── data holders ───────────────────────────────────────────────────────

/// SP-78: public so the smoke test can pin the mapping contract. Maps
/// InnerTube shelf items (browse + search) to plain
/// {videoId, title, subtitle, art} maps — lenient by design: non-video
/// items, missing ids and malformed rows are dropped, duplicates
/// collapsed, art falls back to i.ytimg.com.
List<Map<String, String>> ytVideoCardMaps(List contents) {
  final out = <Map<String, String>>[];
  final seen = <String>{};
  for (final raw in contents) {
    if (raw is! Map) continue;
    final id = raw['videoId']?.toString() ?? '';
    final title = raw['title']?.toString() ?? '';
    // Title first: a malformed row must not poison the dedupe set for a
    // later, valid copy of the same video.
    if (title.isEmpty || id.length != 11 || !seen.add(id)) continue;
    final thumbs = (raw['thumbnails'] as List? ?? const [])
        .whereType<Map>()
        .map((t) => _Thumb(
              url: t['url']?.toString() ?? '',
              width: (t['width'] as num?)?.toInt() ?? 0,
            ))
        .toList();
    final card = _VideoCard(
      videoId: id,
      title: title,
      subtitle: raw['subtitle']?.toString() ??
          raw['artist']?.toString() ??
          '',
      thumbnails: thumbs,
    );
    out.add({
      'videoId': card.videoId,
      'title': card.title,
      'subtitle': card.subtitle,
      'art': card.art,
    });
  }
  return out;
}

class _Thumb {
  const _Thumb({required this.url, required this.width});
  final String url;
  final int width;
}

class _VideoCard {
  const _VideoCard({
    required this.videoId,
    required this.title,
    required this.subtitle,
    required this.thumbnails,
  });

  final String videoId;
  final String title;
  final String subtitle;
  final List<_Thumb> thumbnails;

  /// Best usable art: the widest URL that is still a sane card size.
  String get art {
    if (thumbnails.isEmpty) {
      return 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg';
    }
    _Thumb best = thumbnails.first;
    for (final t in thumbnails) {
      if (t.width >= best.width && t.width <= 640) best = t;
    }
    if (best.width > 640) best = thumbnails.last;
    return best.url;
  }
}

class _Shelf {
  const _Shelf({required this.title, required this.items});
  final String title;
  final List<_VideoCard> items;
}

// ─── widgets ────────────────────────────────────────────────────────────

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.shelf, required this.onTap});

  final _Shelf shelf;
  final void Function(_VideoCard) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shelf.title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(shelf.title,
                style: Theme.of(context).textTheme.titleMedium),
          ),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: shelf.items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final card = shelf.items[i];
              return SizedBox(
                width: 224,
                child: _VideoTile(card: card, onTap: () => onTap(card)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.card, required this.onTap});

  final _VideoCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 148,
                height: 84,
                child: _Art(url: card.art),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    card.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65)),
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

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.card, required this.onTap});

  final _VideoCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _Art(url: card.art),
            ),
          ),
          const SizedBox(height: 6),
          Text(card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, height: 1.2)),
          if (card.subtitle.isNotEmpty)
            Text(card.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65))),
        ],
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.white.withValues(alpha: 0.06),
        alignment: Alignment.center,
        child: const Icon(Icons.play_circle_outline_rounded, size: 30),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.white.withValues(alpha: 0.04),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.retry,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: Icon(retry ? Icons.refresh_rounded : Icons.arrow_back),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
