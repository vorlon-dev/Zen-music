// ZenMusic · vorlon-dev

// ZenMusic — Spotify playlist details page.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/spotify/spotify_library.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';

class SpotifyPlaylistPage extends StatefulWidget {
  const SpotifyPlaylistPage({
    super.key,
    required this.playlistId,
    this.title,
  });

  final String playlistId;
  final String? title;

  @override
  State<SpotifyPlaylistPage> createState() => _SpotifyPlaylistPageState();
}

class _SpotifyPlaylistPageState extends State<SpotifyPlaylistPage> {
  SpotifyPlaylistDetail? _detail;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await SpotifyLibrary.instance
        .fetchPlaylistDetail(widget.playlistId, limit: 100);
    if (!mounted) return;
    setState(() {
      _detail = res;
      _loaded = true;
    });
  }

  String get _title {
    final n = _detail?.name ?? '';
    return n.isNotEmpty ? n : (widget.title ?? 'Playlist');
  }

  String get _coverUrl {
    final c = _detail?.coverUrl ?? '';
    if (c.isNotEmpty) return c;
    // Fallback: first track's artwork.
    final songs = _detail?.songs ?? const [];
    for (final s in songs) {
      final t = (s['thumbnails'] as List?)?.isNotEmpty == true
          ? (s['thumbnails'].first as Map)['url']?.toString() ?? ''
          : '';
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  String get _durationLabel {
    final songs = _detail?.songs ?? const [];
    var total = Duration.zero;
    for (final s in songs) {
      final d = s['duration'];
      if (d is Duration) total += d;
    }
    if (total == Duration.zero) return '';
    final h = total.inHours;
    final m = total.inMinutes % 60;
    if (h == 0) return '$m minutes';
    return '$h hour${h == 1 ? '' : 's'}, $m minutes';
  }

  Widget _glassButton({required IconData icon, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.black.withAlpha(90),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 22, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _roundButton(BuildContext context,
      {required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.white.withAlpha(40),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, size: 24, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _addAllToQueue(List<Map<String, dynamic>> songs) async {
    final mp = GetIt.I<MediaPlayer>();
    for (final song in songs) {
      await mp.addToQueue(song);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Added to queue'), duration: Duration(seconds: 2)));
  }

  void _shuffle(List<Map<String, dynamic>> songs) {
    final shuffled = List<Map<String, dynamic>>.from(songs)..shuffle();
    GetIt.I<MediaPlayer>().playFromSection(shuffled, 0);
  }

  /// LastWave-style header: full-bleed cover that fades into the page
  /// background, title + meta overlaid on the art, shuffle + Play pill.
  Widget _buildHeader(BuildContext context) {
    final detail = _detail!;
    final songs = detail.songs;
    final scheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final top = MediaQuery.of(context).padding.top;
    final width = MediaQuery.of(context).size.width;
    final height = (width * 1.0).clamp(380.0, 520.0) + top;
    final count = detail.totalCount > songs.length
        ? detail.totalCount
        : songs.length;
    final meta = [
      '$count songs',
      if (_durationLabel.isNotEmpty) _durationLabel,
    ].join(' • ');
    final sub = [
      detail.kind,
      if (detail.owner.isNotEmpty) detail.owner,
      if (detail.year.isNotEmpty) detail.year,
    ].join(' • ');
    final cover = _coverUrl;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover.isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary.withAlpha(120), bg],
                ),
              ),
            )
          else
            CachedNetworkImage(
              imageUrl: cover,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => ColoredBox(color: bg),
            ),
          // Soft top scrim so the back / more buttons stay readable.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.25, 0.45, 1.0],
                colors: [
                  Colors.black.withAlpha(110),
                  Colors.transparent,
                  bg.withAlpha(90),
                  bg,
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 8),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withAlpha(190))),
                const SizedBox(height: 2),
                Text(meta,
                    style: TextStyle(
                        fontSize: 14, color: Colors.white.withAlpha(190))),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _roundButton(context,
                        icon: Icons.shuffle,
                        onTap: songs.isEmpty ? null : () => _shuffle(songs)),
                    const SizedBox(width: 12),
                    AdaptiveFilledButton(
                      onPressed: songs.isEmpty
                          ? null
                          : () => GetIt.I<MediaPlayer>()
                              .playFromSection(songs, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(35)),
                      color: scheme.primary,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow,
                              size: 24, color: scheme.onPrimary),
                          const SizedBox(width: 8),
                          Text('Play',
                              style: TextStyle(
                                  fontSize: 18, color: scheme.onPrimary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _detail?.songs ?? const <Map<String, dynamic>>[];
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: canPop
            ? _glassButton(
                icon: Icons.arrow_back,
                onTap: () => Navigator.of(context).maybePop())
            : null,
        actions: [
          if (songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'queue') _addAllToQueue(songs);
                  if (v == 'shuffle') _shuffle(songs);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'queue', child: Text('Add to queue')),
                  PopupMenuItem(value: 'shuffle', child: Text('Shuffle play')),
                ],
                child: _glassButton(icon: Icons.more_vert),
              ),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: AdaptiveProgressRing())
          : songs.isEmpty
              ? const Center(child: Text('Playlist is empty'))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildHeader(context),
                    if ((_detail?.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text(_detail!.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).hintColor)),
                      ),
                    for (int i = 0; i < songs.length; i++)
                      _Tile(song: songs[i], section: songs, index: i),
                    const SizedBox(height: 120),
                  ],
                ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.song,
    required this.section,
    required this.index,
  });
  final Map<String, dynamic> song;
  final List<Map<String, dynamic>> section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final thumb = (song['thumbnails'] as List?)?.isNotEmpty == true
        ? (song['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveListTile(
      onTap: () {
        GetIt.I<MediaPlayer>().playFromSection(section, index);
      },
      leading: thumb.isEmpty
          ? const Icon(Icons.music_note)
          : ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CachedNetworkImage(
            imageUrl: thumb, width: 50, height: 50, fit: BoxFit.cover),
      ),
      title: Text(song['title'] ?? '', maxLines: 1),
      subtitle: Text(song['artist'] ?? '',
          maxLines: 1,
          style: TextStyle(color: Colors.grey.withAlpha(250))),
    );
  }
}
