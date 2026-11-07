// ZenMusic · vorlon-dev
//
// Shared contract for the extra lyric providers (ported from BitChord,
// GPL-3.0: https://github.com/kushagrasinghx/BitChord).

/// What a provider hands back: one lyric document as text, plus what kind
/// of timing it carries. The text is then parsed by `LyricsService`
/// (TTML, karaoke `[start,dur](start,dur,0)word` rows, enhanced LRC,
/// plain LRC or plain text are all understood).
class LyricDoc {
  const LyricDoc({
    required this.payload,
    required this.wordSynced,
    this.lineSynced = false,
    this.isPlain = false,
  });

  /// The document text.
  final String payload;

  /// Real per-word / per-syllable timing (never interpolated).
  final bool wordSynced;

  /// Whole-line timestamps (`[mm:ss.xx] line`), no word timing.
  final bool lineSynced;

  /// Untimed text only.
  final bool isPlain;
}

/// What a provider is asked for. Titles and artists are already cleaned by
/// `MetadataCleaner`.
class LyricQuery {
  const LyricQuery({
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.videoId,
    this.isrc,
  });

  final String title;
  final String artist;
  final String? album;
  final int? durationMs;

  /// YouTube video id of the playing track, when known.
  final String? videoId;

  /// ISRC of the recording, when known.
  final String? isrc;

  int? get durationSec =>
      durationMs != null && durationMs! > 0 ? durationMs! ~/ 1000 : null;
}

/// Providers the app can ask, in default priority order. Names are stored
/// in settings, so do not rename them.
enum LyricSourceId {
  lrcRed('lrc.red', 'Apple timings by recording, syllable by syllable', true),
  biniLyrics('BiniLyrics', 'The same Apple timings, matched on the recording', true),
  betterLyrics('BetterLyrics', 'Apple Music timings, word by word', true),
  paxSenix('PaxSenix', 'Apple Music timings through the keyless provider', true),
  lyricsPlus('LyricsPlus', 'Syllable by syllable, on community mirrors', true),
  unison('Unison', 'Contributed by listeners', true),
  musixmatch('Musixmatch', 'Whole lines, from the biggest lyrics database', false),
  kugou('KuGou', 'Whole lines, strong outside the English catalogue', false),
  lrclib('LRCLIB', 'Whole lines only, and always up', false),
  megalobiz('Megalobiz', 'Community-made, whole-line LRC', false),
  genius('Genius', 'Plain text fallback, massive web catalogue', false);

  const LyricSourceId(this.label, this.detail, this.wordSynced);

  final String label;
  final String detail;

  /// Whether it can return per-word timings.
  final bool wordSynced;
}
