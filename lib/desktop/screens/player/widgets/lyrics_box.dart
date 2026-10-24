// ZenMusic Desktop — LRCLIB-synced lyrics upgrade for LyricsBox.
//
// SAME WIDGET CONTRACT as before (currentSong / size / onLyricsFound) —
// player_page.dart and player_skins.dart need ZERO changes. Only the
// internals changed:
//
//   BEFORE: SpotifyLyrics → old LyricsService (lrcnet_api) → hand-rolled
//           ScrollablePositionedList renderer.
//   AFTER:  SpotifyLyrics (kept, converted to LRC) → LRCLIB
//           LyricsService.lookup (metadata cleaning + duration gate +
//           Hive cache) → SyncedLyricsView (auto-follow, tap-to-seek,
//           interlude "♪ ♪ ♪", plain-text fallback).
//
// Preserved verbatim from the old file:
//   * LyricsBox widget signature + onLyricsFound contract
//   * Spotify Color Lyrics path — LRC string building
//   * Wakelock while playing with lyrics loaded
//   * AppearancePrefs.load() hydration + lyricsTextSize → text scale
//   * ShaderMask top/bottom fade
//
// NOTE: this file imports services/lyrics_service.dart (static API).
// The OLD services/lyrics.dart ALSO declares a class named LyricsService —
// never import both in the same file. The old service is now unused by this
// file and can be deleted once nothing else imports it.
//
// ZERO new pubspec deps. R5 print policy: nothing printed here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:zenmusic/desktop/screens/player/synced_lyrics_view.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/lyrics_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_lyrics.dart';

class LyricsBox extends StatefulWidget {
  const LyricsBox({
    required this.currentSong,
    required this.size,
    this.onLyricsFound,
    super.key,
  });
  final MediaItem currentSong;
  final Size size;
  final Function(bool)? onLyricsFound;

  @override
  State<LyricsBox> createState() => _LyricsBoxState();
}

class _LyricsBoxState extends State<LyricsBox> {
  Future<LyricsData?>? _fetchLyricsFuture;
  bool _lyricsLoaded = false;

  /// MediaPlayer's progressBarState (a ValueNotifier) bridged into the
  /// Stream<Duration> that SyncedLyricsView expects.
  final StreamController<Duration> _posCtrl =
  StreamController<Duration>.broadcast();

  @override
  void initState() {
    super.initState();
    unawaited(AppearancePrefs.load());
    GetIt.I<MediaPlayer>().progressBarState.addListener(_onProgress);
    _initFetchLyrics();
    _initWakelock();
  }

  void _initFetchLyrics() {
    _fetchLyrics();
  }

  void _initWakelock() {
    GetIt.I<MediaPlayer>().buttonState.addListener(_updateWakelock);
  }

  void _updateWakelock() {
    if (!mounted) return;
    final isPlaying =
        GetIt.I<MediaPlayer>().buttonState.value == ButtonState.playing;
    if (isPlaying && _lyricsLoaded) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  void _onProgress() {
    if (!_posCtrl.isClosed) {
      _posCtrl.add(GetIt.I<MediaPlayer>().progressBarState.value.current);
    }
  }

  @override
  void didUpdateWidget(covariant LyricsBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSong.id != oldWidget.currentSong.id) {
      _initFetchLyrics();
    }
  }

  void _fetchLyrics() {
    if (!mounted) return;
    setState(() {
      _lyricsLoaded = false;
      _fetchLyricsFuture = _loadLyricsInternal();
    });
    _fetchLyricsFuture!.then((data) {
      if (!mounted) return;
      _lyricsLoaded = _hasContent(data);
      widget.onLyricsFound?.call(_lyricsLoaded);
      _updateWakelock();
    }).catchError((_) {
      if (!mounted) return;
      _lyricsLoaded = false;
      widget.onLyricsFound?.call(false);
      _updateWakelock();
    });
  }

  static bool _hasContent(LyricsData? d) =>
      d != null &&
          ((d.synced?.isNotEmpty ?? false) ||
              (d.plain?.trim().isNotEmpty ?? false) ||
              d.instrumental);

  Future<LyricsData?> _loadLyricsInternal() async {
    // 1. Spotify Color Lyrics (kept) → LRC → parsed lines.
    final spUri = widget.currentSong.extras?['spotifyUri'] as String?;
    if (spUri != null && spUri.isNotEmpty) {
      final coverUrl = widget.currentSong.artUri?.toString();
      final spLyrics = await SpotifyLyricsService.instance.fetchColorLyrics(
        spUri,
        coverUrl: coverUrl,
      );
      if (spLyrics != null && spLyrics.lines.isNotEmpty) {
        final lines = LrcParser.parse(_spotifyToLrc(spLyrics));
        if (lines.isNotEmpty) {
          return LyricsData(
            trackName: widget.currentSong.title,
            artistName: widget.currentSong.artist ?? '',
            synced: lines,
            plain: null,
            instrumental: false,
            wordSync: false,
          );
        }
      }
    }

    // 2. LRCLIB: cleaned metadata, ±5 s duration gate, Hive cache.
    return LyricsService.lookup(
      title: widget.currentSong.title,
      artist: widget.currentSong.artist ?? '',
      album: widget.currentSong.album,
      durationMs: widget.currentSong.duration?.inMilliseconds,
    );
  }

  /// Same LRC formatting the old _convertSpotifyLyrics used.
  String _spotifyToLrc(SpotifyColorLyrics sp) {
    final syncedBuffer = StringBuffer();
    for (final line in sp.lines) {
      final minutes = (line.startTimeMs ~/ 60000).toString().padLeft(2, '0');
      final seconds = ((line.startTimeMs % 60000) / 1000)
          .toStringAsFixed(2)
          .padLeft(5, '0');
      syncedBuffer.writeln('[$minutes:$seconds] ${line.words}');
    }
    return syncedBuffer.toString().trim();
  }

  @override
  void dispose() {
    GetIt.I<MediaPlayer>().progressBarState.removeListener(_onProgress);
    GetIt.I<MediaPlayer>().buttonState.removeListener(_updateWakelock);
    WakelockPlus.disable();
    _posCtrl.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _fetchLyricsFuture != null
            ? FutureBuilder<LyricsData?>(
          future: _fetchLyricsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ExpressiveLoadingIndicator();
            }
            final data = snapshot.data;
            if (!_hasContent(data)) {
              // The player page renders its own "No lyrics" state.
              return const SizedBox.shrink();
            }
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent
                  ],
                  stops: [0.0, 0.15, 0.85, 1.0],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: SyncedLyricsView(
                lyrics: data,
                positionStream: _posCtrl.stream,
                initialPosition: GetIt.I<MediaPlayer>()
                    .progressBarState
                    .value
                    .current,
                onSeek: (d) => GetIt.I<MediaPlayer>().seekTo(d),
                accentColor: Colors.white,
                inactiveColor: Colors.white,
                // AppearancePrefs.lyricsTextSize is the user's base
                // font; the view's base is 20 px → scale accordingly.
                textScale: AppearancePrefs.lyricsTextSize.value / 20,
              ),
            );
          },
        )
            : const ExpressiveLoadingIndicator(),
      ),
    );
  }
}