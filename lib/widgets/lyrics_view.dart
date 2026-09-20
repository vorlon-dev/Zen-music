import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_lyric/utils/lyric_lrc_to_qrc.dart'; // Added: Correct import for utility
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
  bool _isUserScrubbing = false;

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

    _lyricController.registerEvent(LyricEvent.stopSelection, (_) {
      if (mounted) setState(() => _isUserScrubbing = true);
    });
    _lyricController.registerEvent(LyricEvent.resumeActiveLine, (_) {
      if (mounted) setState(() => _isUserScrubbing = false);
    });
  }

  Future<void> _loadLyrics() async {
    setState(() => _loading = true);
    final result = await _lyricsService.fetchLyrics(
      title: widget.title,
      artist: widget.artist,
      duration: widget.duration,
    );

    if (!mounted) return;

    if (result.found) {
      final lyricText =
          result.syncedLyrics ?? _plainToLrc(result.plainLyrics ?? '');

      String finalLyric = lyricText;
      // Convert plain LRC to QRC for smoother word-by-word highlight
      if (result.syncedLyrics == null &&
          result.plainLyrics != null &&
          widget.duration != null) {
        try {
          finalLyric = LrcToQrcUtil.convert(
            lyricText,
            totalDuration: widget.duration!,
          );
        } catch (_) {}
      }

      _lyricController.loadLyric(finalLyric);
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
            const Icon(
              Icons.lyrics_outlined,
              color: SpotifyColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'Lyrics not available',
              style: TextStyle(color: SpotifyColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: _loadLyrics, child: const Text('Retry')),
          ],
        ),
      );
    }

    return Stack(
      children: [
        LyricView(
          controller: _lyricController,
          style: LyricStyles.default1.copyWith(
            // ── Idle line ──
            textStyle: const TextStyle(
              fontSize: 18,
              color: SpotifyColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            // ── Currently playing line ──
            activeStyle: const TextStyle(
              fontSize: 22,
              color: SpotifyColors.textPrimary,
              fontWeight: FontWeight.bold,
              height: 1.4,
            ),
            // ── Translation line (unused for now, but styled) ──
            translationStyle: const TextStyle(
              fontSize: 14,
              color: SpotifyColors.textTertiary,
              fontWeight: FontWeight.w400,
            ),
            lineGap: 20,
            translationLineGap: 6,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 100,
            ),
            // ── Progress highlight ──
            activeHighlightColor: SpotifyColors.green.withOpacity(0.15),
            // ── Alignment ──
            textAlign: TextAlign.left, // Corrected from lineTextAlign
            contentAlignment: CrossAxisAlignment.start,
            activeAnchorPosition: 0.4,
            // ── Smooth scroll & switch animation ──
            scrollCurve: Curves.easeOutCubic,
            enableSwitchAnimation: true,
            switchEnterDuration: const Duration(milliseconds: 400),
            switchExitDuration: const Duration(milliseconds: 300),
          ),
          width: double.infinity,
          height: double.infinity,
        ),

        // ── "Back to current line" hint when user is scrubbing ──
        if (_isUserScrubbing)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: SpotifyColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Back to current line',
                  style: TextStyle(
                    color: SpotifyColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}