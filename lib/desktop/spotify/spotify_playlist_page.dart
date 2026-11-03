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

  Widget _roundButton(BuildContext context,
      {required IconData icon, VoidCallback? onTap}) {
    return Material(
      color: Colors.grey.withAlpha(60),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, size: 24),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final detail = _detail!;
    final songs = detail.songs;
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
    final hint = Theme.of(context).hintColor;
    final cover = _coverUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: cover.isEmpty
                    ? Container(
                  color: Colors.grey.withAlpha(40),
                  child: const Icon(Icons.queue_music, size: 64),
                )
                    : CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey.withAlpha(40),
                    child: const Icon(Icons.queue_music, size: 64),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text(meta,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16)),
          if (detail.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(detail.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: hint)),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _roundButton(
                context,
                icon: Icons.playlist_add,
                onTap: songs.isEmpty
                    ? null
                    : () async {
                  final mp = GetIt.I<MediaPlayer>();
                  for (final song in songs) {
                    await mp.addToQueue(song);
                  }
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Added to queue'),
                          duration: Duration(seconds: 2)));
                },
              ),
              const SizedBox(width: 12),
              AdaptiveFilledButton(
                onPressed: songs.isEmpty
                    ? null
                    : () => GetIt.I<MediaPlayer>().playFromSection(songs, 0),
                padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(35)),
                color: Theme.of(context).colorScheme.primary,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow,
                        size: 24,
                        color: Theme.of(context).colorScheme.onPrimary),
                    const SizedBox(width: 8),
                    Text('Play All',
                        style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onPrimary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _roundButton(
                context,
                icon: Icons.shuffle,
                onTap: songs.isEmpty
                    ? null
                    : () {
                  final shuffled = List<Map<String, dynamic>>.from(songs)
                    ..shuffle();
                  GetIt.I<MediaPlayer>().playFromSection(shuffled, 0);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _detail?.songs ?? const <Map<String, dynamic>>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        centerTitle: true,
      ),
      body: !_loaded
          ? const Center(child: AdaptiveProgressRing())
          : songs.isEmpty
          ? const Center(child: Text('Playlist is empty'))
          : Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildHeader(context),
              for (int i = 0; i < songs.length; i++)
                _Tile(song: songs[i], section: songs, index: i),
            ],
          ),
        ),
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