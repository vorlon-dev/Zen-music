// ZenMusic · vorlon-dev
//
// Track sheet: song info, per-song stream quality picker, save to playlist
// and download. Opened from the player's (i) button.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality.dart';
import 'package:zenmusic/desktop/lossless/lossless_service.dart';
import 'package:zenmusic/desktop/lossless/song_quality.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

Future<void> showTrackSheet(BuildContext context, Map song) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) =>
          _TrackSheet(song: Map.from(song), controller: controller),
    ),
  );
}

class _TrackSheet extends StatefulWidget {
  const _TrackSheet({required this.song, required this.controller});
  final Map song;
  final ScrollController controller;

  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  late LosslessQuality? _override =
      SongQuality.forSong(_id);
  bool _applying = false;

  String get _id => (widget.song['videoId'] ?? '').toString();

  String get _artist {
    final a = widget.song['artists'];
    if (a is List && a.isNotEmpty) {
      return a.map((e) => e is Map ? (e['name'] ?? '') : '$e').join(', ');
    }
    return (widget.song['artist'] ?? widget.song['subtitle'] ?? '').toString();
  }

  String get _album {
    final a = widget.song['album'];
    if (a is Map) return (a['name'] ?? '').toString();
    return (a ?? '').toString();
  }

  String get _duration {
    final d = widget.song['duration'];
    if (d == null) return '';
    if (d is num) {
      final s = d > 100000 ? d ~/ 1000 : d.toInt();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    return d.toString();
  }

  String get _source {
    if (widget.song['status'] == 'DOWNLOADED') return 'Downloaded (offline)';
    if ((widget.song['spotifyUri'] as String?)?.isNotEmpty == true) {
      return 'Spotify';
    }
    if ((widget.song['jiosaavnStreamUrl'] as String?)?.isNotEmpty == true) {
      return 'JioSaavn';
    }
    return 'YouTube Music';
  }

  String get _streamQuality {
    final served = LosslessService.instance.servedTierFor(_id);
    if (served != null) return '${served.label} · ${served.detail}';
    return 'Standard stream';
  }

  Future<void> _pick(LosslessQuality? q) async {
    setState(() {
      _override = q;
      _applying = true;
    });
    await SongQuality.set(_id, q);
    // If this song is playing, reload it at the same spot with the new tier.
    final mp = GetIt.I<MediaPlayer>();
    if (mp.currentSongNotifier.value?.id == _id) {
      try {
        final pos = mp.player.position;
        await mp.playSong(Map<String, dynamic>.from(widget.song));
        await mp.player.seek(pos);
      } catch (_) {}
    }
    if (mounted) setState(() => _applying = false);
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settingsTier = LosslessPrefs.current;
    final thumbs = widget.song['thumbnails'];
    final thumb = (thumbs is List && thumbs.isNotEmpty)
        ? (thumbs.last['url'] ?? '').toString()
        : '';

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 64,
                height: 64,
                child: thumb.isEmpty
                    ? ColoredBox(color: cs.surfaceContainerHighest)
                    : Image.network(thumb, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((widget.song['title'] ?? '').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(_artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _row('Album', _album),
        _row('Duration', _duration),
        _row('Source', _source),
        _row('Stream', _streamQuality),
        const Divider(height: 28),
        Text('Stream quality for this song',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('Default (${settingsTier.label})'),
              selected: _override == null,
              onSelected: _applying ? null : (_) => _pick(null),
            ),
            for (final q in LosslessQuality.values)
              ChoiceChip(
                label: Text(q.label),
                selected: _override == q,
                onSelected: _applying ? null : (_) => _pick(q),
              ),
          ],
        ),
        if (_applying)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const Divider(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.playlist_add_rounded),
          title: const Text('Save to playlist'),
          onTap: () {
            Navigator.pop(context);
            Modals.addToPlaylist(context, widget.song);
          },
        ),
        _DownloadTile(song: widget.song),
      ],
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.song});
  final Map song;

  @override
  Widget build(BuildContext context) {
    final id = (song['videoId'] ?? '').toString();
    return ValueListenableBuilder<List<Map>>(
      valueListenable: GetIt.I<DownloadManager>().downloads,
      builder: (context, downloads, _) {
        String status = (song['status'] ?? '').toString();
        for (final d in downloads) {
          if ((d['videoId'] ?? '').toString() == id) {
            status = (d['status'] ?? status).toString();
            break;
          }
        }
        final downloaded = status == 'DOWNLOADED';
        final busy = status == 'DOWNLOADING' || status == 'QUEUED';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : Icon(downloaded
                  ? Icons.download_done_rounded
                  : Icons.download_rounded),
          title: Text(downloaded
              ? 'Downloaded'
              : busy
                  ? (status == 'QUEUED' ? 'Waiting to download…' : 'Downloading…')
                  : 'Download'),
          onTap: (downloaded || busy)
              ? null
              : () {
                  GetIt.I<DownloadManager>()
                      .downloadSong(Map<String, dynamic>.from(song));
                },
        );
      },
    );
  }
}
