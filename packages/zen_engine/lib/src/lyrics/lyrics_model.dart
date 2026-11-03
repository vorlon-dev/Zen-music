enum LyricsProvider {
  lrcnet,
  kugou,
  betterLyrics,
  none,
}

/// A line or word in time-synced lyrics.
class ParsedLyric {
  final String text;
  final Duration start;

  const ParsedLyric({
    required this.text,
    required this.start,
  });

  @override
  String toString() => '${start.inSeconds}s : $text';
}

/// Parsed time-synced lyrics with line-by-line timing.
class ParsedLyrics {
  final List<ParsedLyric> lyrics;
  final String syncedLyrics;
  final String duration;

  ParsedLyrics({
    required this.syncedLyrics,
    required this.duration,
  }) : lyrics = _parse(syncedLyrics);

  static List<ParsedLyric> _parse(String raw) {
    final list = <ParsedLyric>[];
    final regex = RegExp(r'\[(\d+):(\d+)\.(\d+)\] (.*)');
    final matches = regex.allMatches(raw);

    for (final match in matches) {
      final min = int.tryParse(match.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
      final milli = int.tryParse(match.group(3) ?? '0') ?? 0;
      final text = match.group(4) ?? '';
      list.add(
        ParsedLyric(
          text: text,
          start: Duration(
            minutes: min,
            seconds: sec,
            milliseconds: milli,
          ),
        ),
      );
    }
    return list;
  }
}

/// Unified lyrics model holding plain lyrics, synced LRC lyrics, and parsed timed items.
class Lyrics {
  final String id;
  final String artist;
  final String title;
  final String lyricsPlain;
  final LyricsProvider provider;
  final String? album;
  final String? lyricsSynced;
  final ParsedLyrics? parsedLyrics;
  final String? duration;

  Lyrics({
    required this.id,
    required this.artist,
    required this.title,
    required this.lyricsPlain,
    required this.provider,
    this.album,
    this.lyricsSynced,
    this.duration,
    ParsedLyrics? parsedLyrics,
  }) : parsedLyrics = parsedLyrics ??
            (lyricsSynced != null
                ? ParsedLyrics(syncedLyrics: lyricsSynced, duration: duration ?? '')
                : null);

  bool get hasSyncedLyrics => lyricsSynced != null && lyricsSynced!.isNotEmpty;
}
