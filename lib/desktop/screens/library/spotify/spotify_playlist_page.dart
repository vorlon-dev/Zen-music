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

  /// Full Spotify URI (spotify:playlist:...) or the liked-songs collection
  /// URI (spotify:user:USER:collection). Passed to fetchPlaylistTracks.
  final String playlistId;
  final String? title;

  @override
  State<SpotifyPlaylistPage> createState() => _SpotifyPlaylistPageState();
}

class _SpotifyPlaylistPageState extends State<SpotifyPlaylistPage> {
  List<Map<String, dynamic>>? _songs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await SpotifyLibrary.instance
        .fetchPlaylistTracks(widget.playlistId, limit: 100);
    if (!mounted) return;
    setState(() => _songs = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Playlist'),
        centerTitle: true,
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _songs == null
          ? const Center(child: AdaptiveProgressRing())
          : _songs!.isEmpty
          ? const Center(child: Text('Playlist is empty'))
          : Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: AdaptiveFilledButton(
                  onPressed: () {
                    GetIt.I<MediaPlayer>()
                        .playFromSection(_songs!, 0);
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow),
                      SizedBox(width: 8),
                      Text('Play All'),
                    ],
                  ),
                ),
              ),
              for (int i = 0; i < _songs!.length; i++)
                _Tile(
                    song: _songs![i],
                    section: _songs!,
                    index: i),
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