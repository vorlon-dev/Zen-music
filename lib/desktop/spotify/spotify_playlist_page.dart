import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;

import 'package:zenmusic/desktop/spotify/spotify_config.dart';
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
  /// SP-39: spotify:album:… URIs branch to fetchAlbumTracks (getAlbum
  /// persisted query) so the Spotify home shelves' album cards open here
  /// too.
  final String playlistId;
  final String? title;

  @override
  State<SpotifyPlaylistPage> createState() => _SpotifyPlaylistPageState();
}

class _SpotifyPlaylistPageState extends State<SpotifyPlaylistPage> {
  List<Map<String, dynamic>>? _songs;
  String? _error;
  String _cover = '';
  String _oembedTitle = '';

  bool get _isAlbum => widget.playlistId.contains(':album:');
  bool get _isLikedCollection =>
      widget.playlistId.contains(':collection') ||
          widget.playlistId.startsWith('spotify:user:');

  @override
  void initState() {
    super.initState();
    _load();
    _loadCover();
  }

  Future<void> _load() async {
    final List<Map<String, dynamic>> res;
    if (_isAlbum) {
      // SP-39: album shelf cards from the Spotify home feed land here.
      res = await SpotifyLibrary.instance
          .fetchAlbumTracks(widget.playlistId, limit: 100);
    } else {
      res = await SpotifyLibrary.instance
          .fetchPlaylistTracks(widget.playlistId, limit: 100);
    }
    if (!mounted) return;
    setState(() => _songs = res);
  }

  /// Playlist / album cover via public oEmbed (SP-38-proven endpoint).
  /// SP-39e: albums resolve through the same endpoint — a real album
  /// cover beats the first-track approximation. The liked-songs
  /// collection paints its gradient in _buildCover; any failure here
  /// just leaves the fallback chain in charge.
  Future<void> _loadCover() async {
    if (_isLikedCollection) return;
    final String kind;
    if (widget.playlistId.contains(':playlist:')) {
      kind = 'playlist';
    } else if (_isAlbum) {
      kind = 'album';
    } else {
      return;
    }
    final id = widget.playlistId.split(':').last;
    try {
      final url = Uri.parse('https://open.spotify.com/oembed?url='
          '${Uri.encodeComponent('spotify:$kind:$id')}');
      final r = await http.get(url, headers: {
        'accept': 'application/json',
        'user-agent': SpotifyConfig.userAgent,
      }).timeout(const Duration(seconds: 10));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final thumb = body['thumbnail_url']?.toString() ?? '';
        final title = body['title']?.toString() ?? '';
        if (!mounted) return;
        setState(() {
          if (thumb.isNotEmpty) _cover = thumb;
          if (title.isNotEmpty) _oembedTitle = title;
        });
      } else {
        print('[spotify-playlist] oembed HTTP ${r.statusCode} (cover)');
      }
    } catch (e) {
      print('[spotify-playlist] oembed cover error: $e');
    }
  }

  String get _headerTitle {
    if (widget.title?.isNotEmpty == true) return widget.title!;
    if (_oembedTitle.isNotEmpty) return _oembedTitle;
    return _isAlbum ? 'Album' : 'Playlist';
  }

  /// First ≤4 distinct track artworks — the YTM-style collage source.
  List<String> get _trackArts {
    final arts = <String>[];
    for (final s in _songs ?? const <Map<String, dynamic>>[]) {
      final t = s['thumbnails'] as List?;
      if (t?.isNotEmpty != true) continue;
      final u = (t!.first as Map)['url']?.toString() ?? '';
      if (u.isNotEmpty && !arts.contains(u)) arts.add(u);
      if (arts.length == 4) break;
    }
    return arts;
  }

  /// "5 hr 6 min" summed from the tracks' own durations; '' when the
  /// feed carried none (SP-39e meta line, like YTM's header).
  String get _durationLabel {
    var total = Duration.zero;
    for (final s in _songs ?? const <Map<String, dynamic>>[]) {
      final d = s['duration'];
      if (d is Duration) total += d;
    }
    if (total.inMinutes <= 0) return '';
    final h = total.inHours;
    final m = total.inMinutes % 60;
    return h > 0 ? '$h hr $m min' : '$m min';
  }

  Widget _buildCover(BuildContext context) {
    // Liked Songs: Spotify's signature purple gradient tile, always.
    if (_isLikedCollection) {
      return Container(
        width: 225,
        height: 225,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF43278C), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.favorite, size: 64, color: Colors.white),
      );
    }
    // The real playlist / album cover from oEmbed.
    if (_cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
            imageUrl: _cover, width: 225, height: 225, fit: BoxFit.cover),
      );
    }
    // YTM signature: collage of the first ≤4 track artworks — also
    // serves the single-art case the old first-track fallback did.
    final arts = _trackArts;
    if (arts.isNotEmpty) return _buildCollage(arts);
    return Container(
      width: 225,
      height: 225,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(_isAlbum ? Icons.album : Icons.queue_music,
          size: 64, color: Theme.of(context).hintColor),
    );
  }

  Widget _collageCell(String url) {
    return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover);
  }

  /// 1 / 2 / 3 / 4-image mosaic in a fixed 225×225 box — plain
  /// Row/Column, no extra dependencies. Same 2-column collage idea as
  /// the app's YTM playlist header (MyPlayistHeader).
  Widget _buildCollage(List<String> arts) {
    Widget grid;
    if (arts.length == 1) {
      grid = _collageCell(arts[0]);
    } else if (arts.length == 2) {
      grid = Row(
        children: [
          Expanded(child: _collageCell(arts[0])),
          Expanded(child: _collageCell(arts[1])),
        ],
      );
    } else if (arts.length == 3) {
      grid = Column(
        children: [
          Expanded(child: _collageCell(arts[0])),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _collageCell(arts[1])),
                Expanded(child: _collageCell(arts[2])),
              ],
            ),
          ),
        ],
      );
    } else {
      grid = Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _collageCell(arts[0])),
                Expanded(child: _collageCell(arts[1])),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _collageCell(arts[2])),
                Expanded(child: _collageCell(arts[3])),
              ],
            ),
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 225, height: 225, child: grid),
    );
  }

  /// SP-39e: the YTM playlist header (MyPlayistHeader) look — Card →
  /// 225px cover + bold title + "N songs · total time · Spotify" meta
  /// + big Play All pill; Row on wide windows, Column on narrow. The
  /// pill uses the app theme's primary/onPrimary (SP-39c doctrine),
  /// not the YTM header's hard-coded white/black.
  Widget _buildHeader(BuildContext context) {
    final songs = _songs!;
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      '${songs.length} songs',
      if (_durationLabel.isNotEmpty) _durationLabel,
      'Spotify',
    ].join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 600;
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Text(_headerTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: wide ? TextAlign.start : TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).hintColor)),
              const SizedBox(height: 14),
              AdaptiveFilledButton(
                onPressed: () {
                  GetIt.I<MediaPlayer>().playFromSection(songs, 0);
                },
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(Platform.isWindows ? 8 : 35),
                ),
                color: scheme.primary,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow, size: 24, color: scheme.onPrimary),
                    const SizedBox(width: 8),
                    Text('Play All',
                        style:
                        TextStyle(fontSize: 18, color: scheme.onPrimary)),
                  ],
                ),
              ),
            ],
          );
          final cover = _buildCover(context);
          return wide
              ? Row(
            children: [
              cover,
              const SizedBox(width: 16),
              Expanded(child: content),
            ],
          )
              : Column(
            children: [
              cover,
              const SizedBox(height: 12),
              content,
            ],
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_headerTitle),
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
              // SP-39e: YTM-style playlist header card.
              _buildHeader(context),
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