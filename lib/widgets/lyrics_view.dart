import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_lyric/utils/lyric_lrc_to_qrc.dart'; // Added: Correct import for utility
import '../services/lyrics_service.dart';
import '../theme/spotify_theme.dart';

class LyricsView extends StatefulWidget {
  final String songId;
  final String title;
  final String artist;
  final String imageUrl;
  final Duration? duration;
  final Stream<Duration> positionStream;
  final void Function(Duration)? onSeek;

  const LyricsView({
    super.key,
    required this.songId,
    required this.title,
    required this.artist,
    required this.imageUrl,
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
  bool _synced = false;
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
      final hasTimedLyrics = result.syncedLyrics != null;
      final lyricText = result.syncedLyrics ?? _plainToLrc(result.plainLyrics ?? '');

      String finalLyric = lyricText;
      // Convert plain LRC to QRC for smoother word-by-word highlight
      if (!hasTimedLyrics &&
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
        // "Synced" here means the source actually gave us real timestamps,
        // not our own 5-second-per-line estimate — that distinction is
        // what the badge in the footer communicates.
        _synced = hasTimedLyrics;
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
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            color: SpotifyColors.green,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (!_found) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_rounded,
                color: SpotifyColors.textTertiary.withOpacity(0.7),
                size: 44,
              ),
              const SizedBox(height: 16),
              const Text(
                'Lyrics not available',
                style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "We couldn't find lyrics for this track",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: SpotifyColors.textTertiary.withOpacity(0.9),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _loadLyrics,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SpotifyColors.textPrimary,
                  side: BorderSide(
                    color: SpotifyColors.textTertiary.withOpacity(0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        LyricView(
          controller: _lyricController,
          style: LyricStyles.default1.copyWith(
            // ── Idle line ──
            textStyle: TextStyle(
              fontSize: 19,
              color: SpotifyColors.textPrimary.withOpacity(0.55),
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
            // ── Currently playing line ──
            activeStyle: const TextStyle(
              fontSize: 24,
              color: SpotifyColors.textPrimary,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            // ── Translation line (unused for now, but styled) ──
            translationStyle: const TextStyle(
              fontSize: 14,
              color: SpotifyColors.textTertiary,
              fontWeight: FontWeight.w400,
            ),
            lineGap: 22,
            translationLineGap: 6,
            contentPadding: const EdgeInsets.fromLTRB(24, 110, 24, 110),
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
            bottom: 84,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: SpotifyColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 14,
                      color: SpotifyColors.textPrimary.withOpacity(0.85),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Back to current line',
                      style: TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ── Pinned song identity strip ──
        // Stays fixed at the bottom while lyrics scroll underneath it,
        // same as Spotify's lyrics screen. The checkmark only appears
        // when the lyrics we loaded are genuinely time-synced — it's a
        // real signal, not decoration.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 32, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.55),
                  ],
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: SpotifyColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: SpotifyColors.textPrimary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_synced) ...[
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Synced lyrics',
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: SpotifyColors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}