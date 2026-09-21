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
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SpotifyColors.textSecondary,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Looking for lyrics…',
                style: TextStyle(
                  fontSize: 13,
                  color: SpotifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!_found) return const SizedBox.shrink();

    return _card(
      child: InkWell(
        onTap: widget.onShowFull,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lyrics_rounded,
                    size: 17,
                    color: SpotifyColors.textSecondary.withOpacity(0.9),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Lyrics',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: SpotifyColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: SpotifyColors.textTertiary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ..._previewLines.asMap().entries.map((entry) {
                final isLast = entry.key == _previewLines.length - 1;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                  child: Opacity(
                    opacity: isLast ? 0.55 : 1.0,
                    child: Text(
                      entry.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        color: SpotifyColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}