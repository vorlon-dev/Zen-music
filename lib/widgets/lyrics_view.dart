import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:flutter_lyric/utils/lyric_lrc_to_qrc.dart';
import '../services/appearance_prefs.dart';
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

  @override
  void initState() {
    super.initState();
    AppearancePrefs.load();
    _loadLyrics();

    widget.positionStream.listen((pos) {
      _lyricController.setProgress(pos);
    });

    _lyricController.setOnTapLineCallback((position) {
      widget.onSeek?.call(position);
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
        // Text size, line spacing and alignment follow the Appearance
        // settings live.
        ListenableBuilder(
          listenable: Listenable.merge([
            AppearancePrefs.lyricsTextSize,
            AppearancePrefs.lyricsLineSpacing,
            AppearancePrefs.lyricsPosition,
          ]),
          builder: (context, _) {
            final size = AppearancePrefs.lyricsTextSize.value;
            final gap = AppearancePrefs.lyricsLineSpacing.value;
            final pos = AppearancePrefs.lyricsPosition.value;
            final textAlign = switch (pos) {
              'center' => TextAlign.center,
              'right' => TextAlign.right,
              _ => TextAlign.left,
            };
            final contentAlign = switch (pos) {
              'center' => CrossAxisAlignment.center,
              'right' => CrossAxisAlignment.end,
              _ => CrossAxisAlignment.start,
            };
            return LyricView(
              controller: _lyricController,
              style: LyricStyles.default1.copyWith(
                // ── Idle line ──
                textStyle: TextStyle(
                  fontSize: size,
                  color: SpotifyColors.textPrimary.withOpacity(0.55),
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
                // ── Currently playing line ──
                activeStyle: TextStyle(
                  fontSize: size + 5,
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
                lineGap: 17 * gap,
                translationLineGap: 6,
                contentPadding: const EdgeInsets.fromLTRB(24, 110, 24, 110),
                // ── Progress highlight ──
                activeHighlightColor: SpotifyColors.green.withOpacity(0.15),
                // ── Alignment (from Appearance settings) ──
                textAlign: textAlign,
                contentAlignment: contentAlign,
                activeAnchorPosition: 0.4,
                // ── Smooth scroll & switch animation ──
                scrollCurve: Curves.easeOutCubic,
                enableSwitchAnimation: true,
                switchEnterDuration: const Duration(milliseconds: 400),
                switchExitDuration: const Duration(milliseconds: 300),
              ),
              width: double.infinity,
              height: double.infinity,
            );
          },
        ),

        // ── Pinned song identity strip ──
        // Title and artist only — no gradient overlay, no badge.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
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
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 1),
                        ),
                      ],
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
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}