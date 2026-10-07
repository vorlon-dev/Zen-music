/// Cache versioning constants for artist-related data.
/// Bump a version to invalidate all cached entries of that kind
/// (schema change, parser fix) without wiping the whole cache box.
const int artistCatalogCacheVersion = 1;
const int artistSearchCacheVersion = 1;
const int artistProfileCacheVersion = 1;
const int artistAlbumCacheVersion = 1;
const int artistChannelCacheVersion = 1;

/// Request timeouts for artist API calls.
const Duration artistRequestTimeout = Duration(seconds: 12);
const Duration artistProfileTimeout = Duration(seconds: 25);
const Duration musicAlbumTimeout = Duration(seconds: 12);
const int musicAlbumBatchSize = 6;

/// Regex patterns for artist name and text normalization.
/// Compiled once for efficiency across multiple function calls.
final class ArtistPatterns {
  ArtistPatterns._(); // Prevent instantiation

  // Patterns for removing common suffixes and labels
  static final topicChannel = RegExp(
    r'\s*topic channel\s*$',
    caseSensitive: false,
  );
  static final topicSuffix = RegExp(r'\s*-\s*topic\s*$', caseSensitive: false);
  static final officialArtistChannel = RegExp(
    r'\s*official artist channel\s*$',
    caseSensitive: false,
  );
  static final vevo = RegExp(r'\s*vevo\s*$', caseSensitive: false);

  // Word boundary patterns for strict matching
  static final officialChannel = RegExp(r'\bofficial channel\b');
  static final musicChannel = RegExp(r'\bmusic channel\b');
  static final official = RegExp(r'\bofficial\b');
  static final vevoWord = RegExp(r'\bvevo\b');

  // Patterns for canonicalization
  static final audioVideoLyrics = RegExp(
    r'\b(official|audio|video|lyrics?|visuali[sz]er)\b',
  );
  static final nonAlphanumeric = RegExp('[^a-z0-9&]+');
  static final multipleSpaces = RegExp(r'\s+');

  // Patterns for splitting featured artists
  static final feature = RegExp(
    r'\s+(?:feat\.?|ft\.?|featuring|with)\s+',
    caseSensitive: false,
  );
  static final collaboration = RegExp(
    r'\s+(?:x|\+|&)\s+',
    caseSensitive: false,
  );

  // Pattern for YouTube Music counters (e.g., "331M plays")
  static final countToken = RegExp(r'^\d+(?:[\.,]\d+)?\s?[KMBkmb]?\b');
}

/// Unicode ranges for styled character normalization (bold, italic,
/// fullwidth etc.) — converts styled Unicode letters/digits to ASCII.
final class StyledCharacterRanges {
  StyledCharacterRanges._(); // Prevent instantiation

  static const List<(int, int)> charRanges = [
    (0x1D400, 0x1D41A), // Bold
    (0x1D434, 0x1D44E), // Italic
    (0x1D468, 0x1D482), // Bold Italic
    (0x1D4D0, 0x1D4EA), // Double-struck
    (0x1D56C, 0x1D586), // Bold Fraktur
    (0x1D5A0, 0x1D5BA), // Script
    (0x1D5D4, 0x1D5EE), // Bold Script
    (0x1D608, 0x1D622), // Fraktur
    (0x1D63C, 0x1D656), // Double-struck Script
    (0x1D670, 0x1D68A), // Bold Fraktur
    (0xFF21, 0xFF41), // Fullwidth Latin Letters
  ];

  static const List<int> digitStarts = [
    0x1D7CE, // Bold Digits
    0x1D7D8, // Double-struck Digits
    0x1D7E2, // Bold Fraktur Digits
    0x1D7EC, // Bold Script Digits
    0x1D7F6, // Bold Monospace Digits
    0xFF10, // Fullwidth Digits
  ];
}