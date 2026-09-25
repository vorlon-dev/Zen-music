import 'dart:async';
import 'package:flutter/material.dart';
import '../services/appearance_prefs.dart';
import '../services/lyrics_service.dart';
import '../theme/spotify_theme.dart';

/// A single, synced lyric line shown inline on the main player screen,
/// between the cover art and the title — the line that's playing right
/// now, updating as playback moves through the song. Tapping it opens
/// the full lyrics screen. Shows nothing at all if no lyrics are found,
/// so it never leaves an empty box behind.
/// Text position and size follow the Appearance settings live.
class CurrentLyricLine extends StatefulWidget {
  final String title;
  final String artist;
  final Duration? duration;
  final Stream<Duration> positionStream;
  final VoidCallback? onTap;
  final void Function(bool synced)? onSyncStatus;

  const CurrentLyricLine({
    super.key,
    required this.title,
    required this.artist,
    this.duration,
    required this.positionStream,
    this.onTap,
    this.onSyncStatus,
  });

  @override
  State<CurrentLyricLine> createState() => _CurrentLyricLineState();
}

class _LyricCue {
  final Duration time;
  final String text;
  const _LyricCue(this.time, this.text);
}

class _CurrentLyricLineState extends State<CurrentLyricLine> {
  final _lyricsService = LyricsService();
  StreamSubscription<Duration>? _positionSub;

  List<_LyricCue> _cues = [];
  String? _currentLine;

  @override
  void initState() {
    super.initState();
    AppearancePrefs.load();
    _load();
  }

  @override
  void didUpdateWidget(covariant CurrentLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title || oldWidget.artist != widget.artist) {
      _positionSub?.cancel();
      _cues = [];
      _currentLine = null;
      widget.onSyncStatus?.call(false);
      _load();
    }
  }

  Future<void> _load() async {
    final result = await _lyricsService.fetchLyrics(
      title: widget.title,
      artist: widget.artist,
      duration: widget.duration,
    );
    if (!mounted || !result.found) {
      widget.onSyncStatus?.call(false);
      return;
    }

    final lrc = result.syncedLyrics ?? _estimateLrc(result.plainLyrics ?? '');
    final cues = _parseLrc(lrc);
    if (cues.isEmpty) return;

    widget.onSyncStatus?.call(result.syncedLyrics != null);
    _positionSub?.cancel();
    _cues = cues;
    _positionSub = widget.positionStream.listen(_onPosition);
  }

  void _onPosition(Duration pos) {
    if (_cues.isEmpty) return;
    String? line;
    for (final cue in _cues) {
      if (cue.time <= pos) {
        line = cue.text;
      } else {
        break;
      }
    }
    if (line != _currentLine && mounted) {
      setState(() => _currentLine = line);
    }
  }

  // Same one-line-every-five-seconds estimate used as a fallback when a
  // track only has plain, untimed lyrics.
  String _estimateLrc(String plain) {
    final buffer = StringBuffer();
    var i = 0;
    for (final raw in plain.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final minutes = (i * 5) ~/ 60;
      final seconds = (i * 5) % 60;
      buffer.writeln(
        '[${minutes.toString().padLeft(2, '0')}:'
            '${seconds.toString().padLeft(2, '0')}.00]$line',
      );
      i++;
    }
    return buffer.toString();
  }

  List<_LyricCue> _parseLrc(String lrc) {
    final tag = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    final cues = <_LyricCue>[];
    for (final raw in lrc.split('\n')) {
      final matches = tag.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.replaceAll(tag, '').trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = double.parse(m.group(2)!);
        cues.add(_LyricCue(
          Duration(milliseconds: minutes * 60000 + (seconds * 1000).round()),
          text,
        ));
      }
    }
    cues.sort((a, b) => a.time.compareTo(b.time));
    return cues;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = _currentLine;
    if (line == null || line.isEmpty) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: Listenable.merge(
          [AppearancePrefs.lyricsPosition, AppearancePrefs.lyricsTextSize]),
      builder: (context, _) {
        final align = switch (AppearancePrefs.lyricsPosition.value) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        };
        return InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  line,
                  key: ValueKey(line),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: align,
                  style: TextStyle(
                    fontSize: AppearancePrefs.lyricsTextSize.value,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}