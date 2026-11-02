// ZenMusic — ZenWall (SP-78): the playing song as the device wallpaper.
//
// When the ZenWall switch is on, every song change pushes the song's
// Spotify CANVAS to the Android home-screen wallpaper — natively, by
// grabbing a frame from the canvas mp4 (MediaMetadataRetriever inside
// ZenWallPlugin.kt; a static frame is all a wallpaper can hold). When the
// canvas is not available — no Spotify session, no canvas for the track,
// resolve failure, or the native frame grab failing — the song's normal
// ART COVER is applied instead, exactly as requested. Wallpaper updates
// ride the same currentSong pulse the player screen uses, so a song
// change is all it takes.
//
// Mobile only (Android): every entry point gates on Platform.isAndroid.
// iOS has no settable wallpaper API — the row is hidden there.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart';

/// Resolves the visual a song should put on the wall. Injectable for
/// tests; production uses Spotify canvas → null (caller falls back to
/// album art).
typedef ZenWallVisualResolver = Future<String?> Function(MediaItem song);

class ZenWallService {
  ZenWallService._();

  /// @visibleForTesting — a fresh instance for unit tests; production
  /// code always uses the [instance] singleton.
  @visibleForTesting
  factory ZenWallService.test() => ZenWallService._();

  static final ZenWallService instance = ZenWallService._();

  static const MethodChannel _channel = MethodChannel('zen/zenwall');

  /// Tests inject a fake here; production keeps null (Spotify resolve).
  ZenWallVisualResolver? resolverOverride;

  /// Tests inject the channel's answer; production leaves null (real
  /// platform channel).
  Future<bool> Function(String url, bool fromCanvas)? invokerOverride;

  /// Tests force the Android gate on a non-Android host; production
  /// leaves null (real Platform.isAndroid).
  static bool? androidForTest;

  bool get _android => androidForTest ?? Platform.isAndroid;

  ValueListenable<MediaItem?>? _songs;
  String? _lastSongId;

  /// Wire to the player's current-song pulse. Idempotent.
  void attach(ValueListenable<MediaItem?> currentSong) {
    _songs?.removeListener(_onSongChanged);
    _songs = currentSong;
    currentSong.addListener(_onSongChanged);
  }

  void detach() {
    _songs?.removeListener(_onSongChanged);
    _songs = null;
  }

  MediaItem? get currentSong => _songs?.value;

  /// Apply right now for the current song (the settings switch turning on).
  Future<bool> applyNow() async {
    final song = currentSong;
    if (song == null) return false;
    return applyForSong(song);
  }

  void _onSongChanged() {
    final song = _songs?.value;
    if (song == null || song.id.isEmpty) return;
    if (song.id == _lastSongId) return; // same song re-set — nothing to do
    _lastSongId = song.id;
    // Fire-and-forget: never let wallpaper I/O touch the UI path.
    unawaited(applyForSong(song).catchError((_) => false));
  }

  /// Resolve the visual for [song] and push it to the wallpaper. Canvas
  /// first; album art whenever the canvas path yields nothing — including
  /// a native failure on the canvas frame (then we retry with the art).
  Future<bool> applyForSong(MediaItem song) async {
    if (!AppearancePrefs.zenWall.value) return false;
    if (!_android) return false;
    if (song.id.isEmpty) return false;

    // Fast-skips through a queue must not let a STALE apply win: whatever
    // resolve/discard happens below, only the LATEST song may write.
    final token = song.id;
    _lastSongId = token;

    String? url;
    bool fromCanvas = false;
    final resolve = resolverOverride ?? _spotifyResolve;
    try {
      url = await resolve(song);
    } catch (_) {
      url = null; // resolve failure = canvas unavailable
    }
    if (_lastSongId != token) return false; // user skipped on mid-resolve
    if (url != null && url.isNotEmpty) fromCanvas = true;

    // Fallback #1 (the requested one): normal art cover as wallpaper.
    url ??= song.artUri?.toString();
    if (url == null || url.isEmpty) return false;
    if (_lastSongId != token) return false;

    final set = invokerOverride ?? _invokeSet;
    final ok = await set(url, fromCanvas);
    if (ok || !fromCanvas) return ok;

    // The native frame grab failed on the canvas (rare CDN/codec case) —
    // fall back to the art cover rather than leaving the old wallpaper.
    final art = song.artUri?.toString();
    if (art == null || art.isEmpty || art == url) return false;
    if (_lastSongId != token) return false;
    return set(art, false);
  }

  /// Production visual: the Spotify canvas for this song — matched on
  /// Spotify by id or title/artist — but ONLY while the user is signed
  /// in; anonymous runs answer null instantly and the art cover applies.
  static Future<String?> _spotifyResolve(MediaItem song) async {
    if (!SpotifyAuth.instance.loggedIn.value) return null;
    final spUri = song.extras?['spotifyUri'] as String?;
    final totalMs = song.duration?.inMilliseconds ?? 0;
    return SpotifyCanvas.instance.resolveCanvasUrl(
      spotifyUri: (spUri?.isNotEmpty ?? false) ? spUri : null,
      title: song.title,
      artist:
          (song.artist ?? song.album ?? song.extras?['subtitle'] ?? '')
              .toString(),
      album: song.album,
      durationMs: totalMs > 0 ? totalMs : null,
    );
  }

  static Future<bool> _invokeSet(String url, bool fromCanvas) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('set', {'url': url, 'fromCanvas': fromCanvas})
          .timeout(const Duration(seconds: 20));
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
