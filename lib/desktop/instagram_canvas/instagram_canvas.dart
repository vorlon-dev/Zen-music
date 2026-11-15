// ZenMusic · vorlon-dev
//
// Instagram reel canvas — public facade.
//
// The player page and the discover tab import this ONE file. Nothing in
// this folder modifies existing project files beyond those two wiring
// points (which ship already applied in the zip).
//
// Put at: lib/desktop/instagram_canvas/instagram_canvas.dart

import 'package:zenmusic/desktop/instagram_canvas/instagram_reel_finder.dart';

export 'package:zenmusic/desktop/instagram_canvas/instagram_reel_finder.dart'
    show InstagramReelFinder, ReelResult;

/// Facade for the "related public reel as canvas" feature.
///
/// The canvas comes from the song itself: related-tag queries (song videos /
/// edits / dance videos) are built from the title + artist, searched keylessly,
/// validated and played through the self-hosted resolver service.
/// Instagram reels only — nothing else in the chain.
///
/// Fully fail-soft: bounded timeouts everywhere, results cached in memory,
/// misses cooled down — playback is never blocked or delayed beyond the
/// configured budgets.
class InstagramCanvas {
  InstagramCanvas._();

  static final InstagramCanvas instance = InstagramCanvas._();

  /// Resolve a muted-loop backdrop for a song.
  ///
  /// [songKey]  — stable per-song id (used for caching / determinism).
  /// [title]    — song title.
  /// [artist]   — song artist (may be empty).
  ///
  /// Returns null when nothing suitable was found.
  Future<ReelResult?> resolveBackdrop({
    required String songKey,
    required String title,
    required String artist,
  }) {
    return InstagramReelFinder.instance.resolve(
      songKey: songKey,
      title: title,
      artist: artist,
    );
  }

  /// Convenience: just the playback URL (headers are always empty).
  Future<String?> resolveReelUrl({
    required String songKey,
    required String title,
    required String artist,
  }) async {
    final result = await resolveBackdrop(
      songKey: songKey,
      title: title,
      artist: artist,
    );
    return result?.url;
  }

  /// Forget the cached resolution for a song.
  void invalidate(String songKey) =>
      InstagramReelFinder.instance.invalidate(songKey);
}
