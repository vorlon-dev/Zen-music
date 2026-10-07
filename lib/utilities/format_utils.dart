import 'package:flutter/material.dart';

/// Shared formatting/list utilities. Title-cleanup logic ported from
/// Musify (GPL-3.0, gokadzev/Musify) — MIT-era headers on the source
/// files are decorative; the project is GPL, and ZenMusic is GPL-3.0,
/// so the port is license-compatible with attribution here.

// ── Title cleanup (Musify formatter.dart) ──

const _noiseTerms =
    'official music video|official lyric video|official lyrics video|'
    'official video|official 4k video|official audio|lyric video|'
    'lyrics video|official hd video|lyric visualizer|lyric vizualizer|'
    'official visualizer|official vizualiser|official visualiser|official vizualiser|lyrics|lyric|official song clip|'
    'official|karaoke';

/// Bracket groups containing a noise term anywhere inside: (Official Video)
final _bracketedNoisePattern = RegExp(
  r'[\(\[][^\)\]]*(?:' + _noiseTerms + r')[^\)\]]*[\)\]]',
  caseSensitive: false,
);

/// Unbracketed noise phrases at the end of a title.
final _trailingNoisePattern = RegExp(
  r'\s*[-–—]?\s*\b(?:' + _noiseTerms + r'|audio)\b\s*$',
  caseSensitive: false,
);

/// Strips "(Official Video)", "[Lyrics]", trailing "… | Official" and
/// similar noise from YouTube titles.
///
/// Deviation from Musify's version, documented: if cleaning produces
/// an empty string, the trimmed ORIGINAL is returned — callers can
/// use the result unguarded.
String formatSongTitle(String title) {
  // Remove bracketed groups first to avoid false matches on real
  // title words.
  var t = title.replaceAll(_bracketedNoisePattern, '');

  // Strip lone brackets, pipes, and decode HTML entities.
  t = t
      .replaceAll(RegExp(r'[\[\]()|]'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&#039;', "'")
      .replaceAll('&quot;', '"')
      .trimLeft();

  // Strip trailing unbracketed noise; loop for stacked suffixes.
  String prev;
  do {
    prev = t;
    t = t.replaceAll(_trailingNoisePattern, '');
  } while (t != prev);

  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  return t.isEmpty ? title.trim() : t;
}

// ── List-block corner radii (Musify app_utils) ──

const double _zenBarRadius = 12.0;

final BorderRadius zenBarRadius = BorderRadius.circular(_zenBarRadius);
final BorderRadius zenBarRadiusFirst =
BorderRadius.vertical(top: Radius.circular(_zenBarRadius));
final BorderRadius zenBarRadiusLast =
BorderRadius.vertical(bottom: Radius.circular(_zenBarRadius));

/// First/last rounded corners for an item inside a visual list block.
BorderRadius getItemBorderRadius(
    int index,
    int totalLength, {
      bool hasItemsBefore = false,
      bool hasItemsAfter = false,
    }) {
  final isAbsoluteFirst = index == 0 && !hasItemsBefore;
  final isAbsoluteLast = index == totalLength - 1 && !hasItemsAfter;

  if (isAbsoluteFirst && isAbsoluteLast) return zenBarRadius;
  if (isAbsoluteFirst) return zenBarRadiusFirst;
  if (isAbsoluteLast) return zenBarRadiusLast;
  return BorderRadius.zero;
}

// ── Filtering / sorting (Musify song_utils + sort utils) ──

/// Case-insensitive title/artist filter. Empty query → input as-is.
List<dynamic> filterSongsByQuery(List<dynamic> songsList, String searchQuery) {
  if (searchQuery.isEmpty) return songsList;

  final q = searchQuery.toLowerCase();
  return songsList.where((s) {
    final title = (s['title'] ?? '').toString().toLowerCase();
    final artist = (s['artist'] ?? '').toString().toLowerCase();
    return title.contains(q) || artist.contains(q);
  }).toList();
}

/// Returns a new list sorted by [sortKey] (case-insensitive).
/// Stable: ties keep their input order (List.sort alone is not stable).
List<dynamic> sortSongsByKey(List<dynamic> songs, String sortKey) {
  String keyOf(dynamic song) =>
      (song is Map ? song[sortKey] ?? '' : '').toString().toLowerCase();

  final indexed = [
    for (var i = 0; i < songs.length; i++) (index: i, key: keyOf(songs[i])),
  ]..sort((a, b) {
    final byKey = a.key.compareTo(b.key);
    return byKey != 0 ? byKey : a.index.compareTo(b.index);
  });
  return [for (final entry in indexed) songs[entry.index]];
}

/// Returns a new list with the most recently appended songs first.
List<dynamic> sortSongsNewestFirst(List<dynamic> songs) =>
    List<dynamic>.of(songs.reversed);

/// Returns a new list ordered by newest [dateKey] (ms epoch), ties stable.
List<dynamic> sortSongsByDateAdded(
    List<dynamic> songs, {
      String dateKey = 'dateAdded',
    }) {
  int dateOf(dynamic song) {
    final value = song is Map ? song[dateKey] : null;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  final indexed = [
    for (var i = 0; i < songs.length; i++)
      (index: i, date: dateOf(songs[i])),
  ]..sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : a.index.compareTo(b.index);
  });
  return [for (final entry in indexed) songs[entry.index]];
}

// ── Duration parsing (Musify media_duration.dart) ──

/// Converts duration formats used by song maps into a positive
/// Duration. Zero is treated as unknown — publishing zero to Android's
/// media session renders a misleading 00:00 total.
Duration? readMediaDuration(dynamic value) {
  Duration? duration;

  if (value is Duration) {
    duration = value;
  } else if (value is num) {
    if (!value.isFinite) return null;
    duration = Duration(milliseconds: (value * 1000).round());
  } else {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;

    final numericSeconds = double.tryParse(text);
    if (numericSeconds != null && numericSeconds.isFinite) {
      duration = Duration(milliseconds: (numericSeconds * 1000).round());
    } else {
      final parts = text.split(':').map(int.tryParse).toList();
      if (parts.any((part) => part == null)) return null;
      if (parts.length == 2) {
        duration = Duration(minutes: parts[0]!, seconds: parts[1]!);
      } else if (parts.length == 3) {
        duration = Duration(
          hours: parts[0]!,
          minutes: parts[1]!,
          seconds: parts[2]!,
        );
      }
    }
  }

  return duration != null && duration > Duration.zero ? duration : null;
}

/// Chooses a reported player duration without letting an unknown
/// report replace a valid value. [preserveLongerKnown] guards against
/// clipped sources reporting only their current segment's length.
Duration? preferStableMediaDuration(
    Duration? known,
    Duration? reported, {
      bool preserveLongerKnown = false,
    }) {
  final validKnown = readMediaDuration(known);
  final validReported = readMediaDuration(reported);

  if (validReported == null) return validKnown;
  if (preserveLongerKnown && validKnown != null && validReported < validKnown) {
    return validKnown;
  }
  return validReported;
}