import 'package:flutter/material.dart';
import '../services/lyrics_service.dart';
import '../theme/spotify_theme.dart';

class LyricsPreviewCard extends StatefulWidget {
  final String title;
  final String artist;
  final Duration? duration;
  final VoidCallback onShowFull;

  const LyricsPreviewCard({
    super.key,
    required this.title,
    required this.artist,
    this.duration,
    required this.onShowFull,
  });

  @override
  State<LyricsPreviewCard> createState() => _LyricsPreviewCardState();
}

class _LyricsPreviewCardState extends State<LyricsPreviewCard> {
  final _lyricsService = LyricsService();
  List<String> _previewLines = [];
  bool _loading = true;
  bool _found = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LyricsPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.artist != widget.artist) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _found = false;
      _previewLines = [];
    });

    final result = await _lyricsService.fetchLyrics(
      title: widget.title,
      artist: widget.artist,
      duration: widget.duration,
    );

    if (!mounted) return;

    if (result.found) {
      // Take first 4 non-empty lines from synced or plain
      final source = result.syncedLyrics ?? result.plainLyrics ?? '';
      final lines = <String>[];
      for (final raw in source.split('\n')) {
        // Strip LRC timestamps if present
        final line = raw.replaceAll(RegExp(r'\[\d+:\d+\.\d+\]'), '').trim();
        if (line.isEmpty) continue;
        lines.add(line);
        if (lines.length >= 4) break;
      }
      setState(() {
        _previewLines = lines;
        _loading = false;
        _found = lines.isNotEmpty;
      });
    } else {
      setState(() {
        _loading = false;
        _found = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: SpotifyColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    if (!_found) return const SizedBox.shrink();

    return _card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lyrics preview',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: SpotifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ..._previewLines.map(
                  (line) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.3,
                    color: SpotifyColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onShowFull,
              style: OutlinedButton.styleFrom(
                foregroundColor: SpotifyColors.textPrimary,
                side: const BorderSide(color: SpotifyColors.textTertiary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Show lyrics',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}