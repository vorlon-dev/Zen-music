import 'dart:async';

import 'artwork_service.dart';
import 'jiosaavn_service.dart';
import 'yt_music_service.dart';
import '../models/song.dart';

/// Strict source policy resolver (Echo/Musify parity).
///
/// Given a song identified only by a YouTube video id (from radio,
/// related, charts, home shelves…), find the PROPER song version:
///
///   1. JioSaavn match — 320 kbps AAC, square 1:1 album artwork.
///   2. YTMusic song match — high-bitrate music-catalog stream with
///      the square, high-quality album cover (never a 16:9 video
///      thumbnail).
///
/// Returns the upgraded Song, or null when no confident match exists
/// (the caller then falls back to raw YouTube extraction — which is
/// the path used for explicitly-picked videos).
class SongSourceResolver {
  SongSourceResolver._();
  static final SongSourceResolver instance = SongSourceResolver._();

  final JiosaavnService _jiosaavn = JiosaavnService();
  final YtMusicService _ytm = YtMusicService();

  final Map<String, Song?> _cache = {};
  final Map<String, Future<Song?>> _inFlight = {};

  /// Ids the user explicitly picked (a pasted link). These are NEVER
  /// substituted — the resolver always returns null for them so the
  /// handler streams that exact video's audio.
  final Set<String> _explicit = {};

  /// Marks a song as the user's explicit pick (a pasted link). The
  /// resolver then always returns null for its id, so the handler
  /// falls back to streaming THAT exact video's audio instead of
  /// fuzzy-matching a different catalog song.
  void markExplicit(Song song) {
    _explicit.add(song.id);
    _cache[song.id] = null;
  }

  Future<Song?> resolve(Song song) {
    final key = song.id;
    // Explicit user picks (pasted links) are never substituted.
    if (_explicit.contains(key)) return Future.value(null);
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final inFlight = _inFlight[key];
    if (inFlight != null) return inFlight;

    final future = _resolve(song);
    _inFlight[key] = future;
    return future.then((r) {
      _inFlight.remove(key);
      _cache[key] = r;
      return r;
    });
  }

  Future<Song?> _resolve(Song song) async {
    final title = song.title.trim();
    final artist = song.artist.split(',').first.trim();
    if (title.isEmpty) return null;

    // Placeholder metadata (a bare video id with no fetched title)
    // must never be fuzzy-matched. Returning null makes the caller
    // fall back to the exact video — correct for explicit picks.
    final normTitle = _norm(title);
    if (normTitle.isEmpty || normTitle == 'youtube') return null;

    // ── 1. JioSaavn: 320 kbps AAC + square 1:1 artwork ──
    try {
      final results = await _jiosaavn
          .search('$title $artist', limit: 5)
          .timeout(const Duration(seconds: 8));
      final best = _pickBest(results, song);
      if (best != null) {
        print('🎼 Source: JioSaavn match for "${song.title}" '
            '→ "${best.title}"');
        // JioSaavn artwork is already 1:1 and high quality.
        return best;
      }
    } catch (e) {
      print('🎼 Source: JioSaavn lookup failed — $e');
    }

    // ── 2. YTMusic song (music catalog) ──
    try {
      final results = await _ytm
          .searchSongs('$title $artist', limit: 5)
          .timeout(const Duration(seconds: 8));
      final best = _pickBest(results, song);
      if (best != null) {
        // YTMusic entries can carry 16:9 video thumbnails — upgrade to
        // the square, high-quality album cover.
        final art =
        await ArtworkService.instance.squareArt(best.thumbnail, best.id);
        print('🎼 Source: YTMusic match for "${song.title}" '
            '→ "${best.title}" (square art)');
        return Song(
          id: best.id,
          title: best.title,
          artist: best.artist,
          thumbnail: art,
          duration: best.duration,
        );
      }
    } catch (e) {
      print('🎼 Source: YTMusic lookup failed — $e');
    }

    print('🎼 Source: no song match for "${song.title}" — '
        'falling back to video extraction');
    return null;
  }

  /// Scores candidates by title and artist similarity. Returns null for
  /// rejects, otherwise the score (higher = better).
  static int? _score(Song candidate, Song original) {
    final ct = _norm(candidate.title);
    final ot = _norm(original.title);
    final ca = _norm(candidate.artist);
    final oa = _norm(original.artist);
    if (ct.isEmpty || ot.isEmpty) return null;

    var score = 0;

    // Title: exact > containment > word overlap.
    if (ct == ot) {
      score += 30;
    } else if (ct.contains(ot) || ot.contains(ct)) {
      score += 18;
    } else {
      final overlap = _wordOverlap(ct, ot);
      if (overlap < 0.5) return null;
      score += (overlap * 14).round();
    }

    // Artist: required to overlap, exact match scores higher.
    // An empty original artist carries no identity — never a free
    // pass (that hole once matched "YouTube video" to random songs).
    final artistMatch = oa.isNotEmpty && (ca.contains(oa) || oa.contains(ca));
    final artistWords = oa.isEmpty ? 0.0 : _wordOverlap(ca, oa);
    if (!artistMatch && artistWords < 0.4) return null;
    score += artistMatch ? 12 : (artistWords * 8).round();

    // Bonus: duration close to the original (when known).
    if (original.duration > Duration.zero &&
        candidate.duration > Duration.zero) {
      final diff =
          (candidate.duration - original.duration).abs().inSeconds;
      if (diff <= 3) {
        score += 10;
      } else if (diff <= 10) {
        score += 5;
      } else if (diff > 45) {
        score -= 8; // live version / remix length mismatch
      }
    }

    // Penalty: candidates that are clearly not the studio song.
    final lower = candidate.title.toLowerCase();
    for (final bad in ['live', 'cover', 'karaoke', 'nightcore', '8d']) {
      if (lower.contains(bad) && !ot.contains(bad)) score -= 10;
    }

    return score;
  }

  /// Picks the best candidate above the confidence threshold.
  static Song? _pickBest(List<Song> candidates, Song original) {
    Song? best;
    var bestScore = 0;
    for (final c in candidates) {
      final s = _score(c, original);
      if (s == null) continue;
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    // Confidence floor — better safe than a wrong song.
    return bestScore >= 18 ? best : null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'official|video|audio|lyrical|lyrics|hd|4k'), '')
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static double _wordOverlap(String a, String b) {
    final aw = a.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    final bw = b.split(RegExp(r'\s+')).where((w) => w.length > 2).toSet();
    if (aw.isEmpty || bw.isEmpty) return 0;
    final hit = aw.where(bw.contains).length;
    return hit / (aw.length > bw.length ? aw.length : bw.length);
  }
}