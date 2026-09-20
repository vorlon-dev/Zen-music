import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import '../services/lyrics_service.dart';
import '../theme/spotify_theme.dart';

class LyricsView extends StatefulWidget {
  final String title;
  final String artist;
  final Duration? duration;
  final Stream<Duration> positionStream;
  final void Function(Duration)? onSeek;

  const LyricsView({
    super.key,
    required this.title,
    required this.artist,
    this.duration,
    required this.positionStream,
    this.onSeek,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _lyricController = LyricController();
  final _lyricsService = LyricsService();

  bool _loading = true;
  bool _found = false;

  @override
  void initState() {
    super.initState();
    _loadLyrics();

    widget.positionStream.listen((pos) {
      _lyricController.setProgress(pos);
    });

    _lyricController.setOnTapLineCallback((position) {
      widget.onSeek?.call(position);
    });
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _loading = true;
    });

    final result = await _lyricsService.fetchLyrics(
      title: widget.title,
      artist: widget.artist,
      duration: widget.duration,
    );

    if (!mounted) return;

    if (result.found) {
      final lyricText =
          result.syncedLyrics ?? _plainToLrc(result.plainLyrics ?? '');
      _lyricController.loadLyric(lyricText);
      setState(() {
        _loading = false;
        _found = true;
      });
    } else {
      setState(() {
        _loading = false;
        _found = false;
      });
    }
  }

  String _plainToLrc(String plain) {
    final lines = plain.split('\n');
    final buffer = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final minutes = (i * 5) ~/ 60;
      final seconds = (i * 5) % 60;
      buffer.writeln(
        '[${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}.00]$line',
      );
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _lyricController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: SpotifyColors.green),
      );
    }

    if (!_found) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lyrics_outlined,
                color: SpotifyColors.textSecondary, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Lyrics not available',
              style: TextStyle(color: SpotifyColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadLyrics,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return LyricView(
      controller: _lyricController,
      style: LyricStyles.default1.copyWith(
        textStyle: const TextStyle(
          fontSize: 18,
          color: SpotifyColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        activeStyle: const TextStyle(
          fontSize: 22,
          color: SpotifyColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
        lineGap: 20,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 80,
        ),
        activeHighlightColor: SpotifyColors.green.withOpacity(0.15),
      ),
      width: double.infinity,
      height: double.infinity,
    );
  }
}