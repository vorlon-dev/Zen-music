// ZenMusic Desktop — services/media_player.dart (GPL-3.0).
//
// FEATURES:
//  1. Android audio pipeline: AudioPipeline(AndroidEqualizer) gives
//     device-band EQ on phones. Desktop (Windows/Linux/macOS): plain
//     player — EQ arrives via the mpv arc. All EQ methods no-op safely
//     off-Android.
//  2. just_audio_background imported for the MediaItem tag class ONLY — never
//     initialized on desktop (its init is the recorded Windows crash); the
//     MOBILE entry (lib/main.dart) initializes it.
//  3. YT Music paths: stats timer, autofetch, startRelated,
//     startPlaylistSongs, online-playlist branches.
//  4. JioSaavn: direct 320kbps branch (jiosaavnStreamUrl in the song map).
//  5. Thumbnails upgraded via getEnhancedImage (regex size normalization).
//  6. playAll is chart-aware: isChart rows resolve via the search-and-play
//     path the tiles use, then play the resolved list.
//  7. Spotify branch: song maps from the Spotify search section carry
//     'spotifyUri'.
//     ANDROID: Widevine L3 DRM playback via the patched just_audio host.
//     DESKTOP (SP-5b): the hidden WebView2 EME engine owns playback for the
//     current track; just_audio listeners stand down while it's active.
//  8. SP-6 queue snapshot: queueSnapshot mirrors what the user tapped (a
//     whole search section, playlist, or liked songs). Fills the queue
//     drawer when the engine owns playback and provides a real queue for
//     JioSaavn sections that autofetch can't extend.
//  9. SP-7 Spotify autoqueue: when the engine plays a Spotify track, the
//     queue drawer is replaced with Spotify's OWN next-up list — the
//     resolved track plus the autoqueue neighbours from the same Dealer
//     payload (SpotifyPlayer.lastResolvedSong / lastAutoqueueNeighbours).
//     Non-Spotify paths keep the section snapshot from SP-6.
//  10. SP-11 Local Cache: Automatically saves and restores the last played
//      queue, index, and position using Hive so the app opens exactly where
//      the user left off.
//  11. Offline song cache: every YouTube song that becomes current is
//      silently downloaded in the background (SongCache) and every later
//      play comes straight from disk — no proxy, no headers, works with
//      zero internet. See song_cache_service.dart.
//  12. SP-22 Windows SMTC: system media keys (play/pause/next/previous),
//      the Windows volume-flyout card (title, artist, artwork, live
//      position) and overlay buttons — wired via smtc_bridge.dart and
//      driven by the existing notifiers, so every source (YT, JioSaavn,
//      Spotify engine, offline files, restored sessions) shows up in the
//      OS media overlay with zero per-path wiring.
//  13. SP-23 Discord Rich Presence: song, artist, artwork and a live
//      elapsed timer on the user's Discord profile — same notifier-driven
//      pattern, via discord_presence_bridge.dart. Disabled until a Discord
//      application id is set (see that file's header).
//  14. SP-25 Last.fm scrobbling: now-playing + scrobbles to the user's
//      Last.fm library (LastfmService) — same notifier-driven pattern.
//      Disabled until the API credentials are set in lastfm_service.dart
//      and the user connects their account from the Saved page.
//  15. SP-26 Mini player window: a floating bar in its own desktop window
//      (desktop_multi_window 0.2.1) mirroring the current track, play
//      state and live position, with transport buttons — wired via
//      mini_player_bridge.dart, same notifier-driven pattern. The mini
//      window is a second Flutter engine; the bridge is the only link.
//  16. SP-27 Crossfade: smooth volume fade between tracks — the current
//      track fades out over its last N seconds and the next track fades
//      in over its first N seconds (Hive 'CROSSFADE_SECS', 0 = off; the
//      Saved page's Crossfade card is the control). Volume-only — queue
//      routing, playback logic and the Spotify engine path are untouched,
//      every ramp self-cancels on pause/seek/skip/stop.
//  17. SP-28 Lyrics overlay: a floating always-on-top window (the SP-26
//      mini-window tech + a Win32 topmost helper) mirroring the current
//      track's synced lyrics and following the position live — wired via
//      lyrics_overlay_bridge.dart, same notifier-driven pattern. Lyrics
//      are fetched by the same chain the in-player LyricsBox uses.
//  18. SP-29 Windows video backdrop: the current track's YouTube video
//      plays muted as a blurred 16:9 canvas layer behind the player
//      screen (Windows only) — wired via backdrop/windows_backdrop_service
//      .dart, same notifier-driven pattern. The audio path is untouched;
//      the backdrop widget (backdrop/windows_backdrop.dart) goes in as
//      the first child of the player screen's Stack.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/add_history.dart';
import '../utils/enhanced_image.dart';
import 'eq_models.dart';
import 'settings_manager.dart';
import 'yt_audio_stream.dart';
import 'song_cache_service.dart';
import 'smtc_bridge.dart';
import 'discord_presence_bridge.dart';
import 'lastfm_service.dart';
import 'mini_player_bridge.dart';
import 'lyrics_overlay_bridge.dart';
import '../backdrop/windows_backdrop_service.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/spotify/spotify_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';
import 'package:zenmusic/desktop/spotify/spotify_desktop_engine.dart';
import 'package:zenmusic/hive/zen_duration_adapter.dart';


// Widevine license endpoint for web-player CENC audio. Consumed by the
// patched just_audio Android host.
const _kSpotifyWidevineLicenseUrl =
    'https://gae2-spclient.spotify.com/widevine-license/v1/audio/license';

class MediaPlayer extends ChangeNotifier {
  late final AudioPlayer _player;

  // Android-only session EQ (device bands). Null on every other platform —
  // all EQ methods no-op safely when null.
  AndroidEqualizer? _eq;
  AndroidEqualizerParameters? _eqParams;

  bool get eqAvailable => Platform.isAndroid && _eq != null;

  List<IndexedAudioSource> _songList = [];
  final ValueNotifier<MediaItem?> _currentSongNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<ButtonState> _buttonState =
  ValueNotifier(ButtonState.loading);
  Timer? _timer;
  final ValueNotifier<Duration?> _timerDuration = ValueNotifier(null);

  final ValueNotifier<LoopMode> _loopMode = ValueNotifier(LoopMode.off);

  final ValueNotifier<ProgressBarState> _progressBarState =
  ValueNotifier(ProgressBarState());

  bool _shuffleModeEnabled = false;

  bool autoFetching = false;

  // ── SP-5b engine wiring ──
  bool _engineOwnsPlayback = false;
  bool _engineListenersAttached = false;

  // ── SP-6 queue snapshot ──
  final ValueNotifier<List<Map<String, dynamic>>> queueSnapshot =
  ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<bool> engineOwnsNotifier = ValueNotifier<bool>(false);

  void _setEngineOwns(bool v) {
    if (_engineOwnsPlayback != v) {
      _engineOwnsPlayback = v;
      engineOwnsNotifier.value = v;
    }
  }

  // ── SP-22 Windows SMTC ──
  StreamSubscription<SmtcButton>? _smtcSub;

  MediaPlayer() {
    if (Platform.isAndroid) {
      _eq = AndroidEqualizer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [_eq!]),
      );
    } else {
      _player = AudioPlayer();
    }
    _init();
  }

  AudioPlayer get player => _player;
  List<IndexedAudioSource> get songList => List.unmodifiable(_songList);
  ValueNotifier<MediaItem?> get currentSongNotifier => _currentSongNotifier;
  ValueNotifier<int?> get currentIndex => _currentIndex;
  ValueNotifier<ButtonState> get buttonState => _buttonState;
  ValueNotifier<ProgressBarState> get progressBarState => _progressBarState;
  bool get shuffleModeEnabled => _shuffleModeEnabled;
  ValueNotifier<LoopMode> get loopMode => _loopMode;
  ValueNotifier<Duration?> get timerDuration => _timerDuration;
  bool get engineOwnsPlayback => _engineOwnsPlayback;

  Stream<
      ({
      List<IndexedAudioSource>? sequence,
      int? currentIndex,
      MediaItem? currentItem
      })> get currentTrackStream => Rx.combineLatest2<
      List<IndexedAudioSource>?,
      int?,
      ({
      List<IndexedAudioSource>? sequence,
      int? currentIndex,
      MediaItem? currentItem
      })>(
    _player.sequenceStream,
    _player.currentIndexStream,
        (sequence, currentIndex) {
      MediaItem? currentItem;
      if (sequence != null &&
          currentIndex != null &&
          currentIndex >= 0 &&
          currentIndex < sequence.length) {
        final tag = sequence[currentIndex].tag;
        if (tag is MediaItem) currentItem = tag;
      }
      return (
      sequence: sequence,
      currentIndex: currentIndex,
      currentItem: currentItem,
      );
    },
  );

  // ═══════════════════════════════════════════════════════════════════
  // SP-11 LOCAL CACHE (Save / Restore Session)
  // ═══════════════════════════════════════════════════════════════════

  void _saveCurrentState() {
    if (queueSnapshot.value.isEmpty) return;
    final idx = _currentIndex.value ?? 0;
    final pos = _progressBarState.value.current;

    final box = Hive.box('SETTINGS');
    box.put('CACHE_QUEUE', queueSnapshot.value);
    box.put('CACHE_INDEX', idx);
    box.put('CACHE_POSITION', pos.inMilliseconds);
  }

  Future<void> restoreLastSession() async {
    final box = Hive.box('SETTINGS');
    final rawQueue = box.get('CACHE_QUEUE') as List?;
    if (rawQueue == null || rawQueue.isEmpty) return;

    final queue = rawQueue.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final int index = (box.get('CACHE_INDEX') as int? ?? 0).clamp(0, queue.length - 1).toInt();
    final posMs = box.get('CACHE_POSITION') as int? ?? 0;

    queueSnapshot.value = queue;
    _currentIndex.value = index;

    final song = queue[index];
    final tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((a) => a['name']).join(','),
      extras: song,
    );

    _currentSongNotifier.value = tag;
    _progressBarState.value = ProgressBarState(
      current: Duration(milliseconds: posMs),
      total: Duration.zero,
    );
    _buttonState.value = ButtonState.paused;
    notifyListeners();
  }

  @override
  void dispose() {
    _saveCurrentState();
    _disposeSmtc();
    _disposeDiscord();
    _disposeLastfm();
    _disposeMiniPlayer();
    _disposeCrossfade();
    _disposeLyricsOverlay();
    _disposeBackdrop();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════
  // SP-5b / SP-6 / SP-7 — SpotifyDesktopEngine bridge
  // ═══════════════════════════════════════════════════════════════════

  // Engine transport wrappers. Future<void>.sync() accepts BOTH a void and
  // a Future<void> return from the engine, so these compile and correctly
  // await the engine no matter how its methods are declared — and they can
  // never trip "this expression has a type of 'void'" again.
  Future<void> _engineStop() async {
    await Future<void>.sync(() => SpotifyDesktopEngine.instance.stop());
  }

  Future<void> _enginePause() async {
    await Future<void>.sync(() => SpotifyDesktopEngine.instance.pause());
  }

  Future<void> _engineResume() async {
    await Future<void>.sync(() => SpotifyDesktopEngine.instance.resume());
  }

  Future<void> _engineSeek(Duration d) async {
    await Future<void>.sync(() => SpotifyDesktopEngine.instance.seek(d));
  }

  void _attachEngineListeners() {
    if (_engineListenersAttached) return;
    _engineListenersAttached = true;
    final engine = SpotifyDesktopEngine.instance;

    engine.position.addListener(() {
      if (!_engineOwnsPlayback) return;
      final old = _progressBarState.value;
      if (old.current != engine.position.value) {
        _progressBarState.value = ProgressBarState(
          current: engine.position.value,
          buffered: old.buffered,
          total: old.total,
        );
      }
    });
    engine.duration.addListener(() {
      if (!_engineOwnsPlayback) return;
      final old = _progressBarState.value;
      if (old.total != engine.duration.value) {
        _progressBarState.value = ProgressBarState(
          current: old.current,
          buffered: old.buffered,
          total: engine.duration.value,
        );
      }
    });
    engine.playing.addListener(() {
      if (!_engineOwnsPlayback) return;
      _buttonState.value = engine.playing.value
          ? ButtonState.playing
          : ButtonState.paused;
    });
    engine.ended.addListener(() {
      if (!_engineOwnsPlayback) return;
      if (engine.ended.value) {
        unawaited(_engineSeek(Duration.zero));
        unawaited(_enginePause());
        _buttonState.value = ButtonState.paused;
      }
    });
  }

  Future<bool> _tryEnginePlay(Map<String, dynamic> song) async {
    if (!Platform.isWindows) return false;
    if (_engineOwnsPlayback) {
      await _engineStop();
      _setEngineOwns(false);
    }
    try {
      _player.pause();
      await _player.stop();
      await _player.clearAudioSources();
    } catch (_) {}

    _attachEngineListeners();

    final tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((a) => a['name']).join(','),
      extras: song,
    );
    _currentSongNotifier.value = tag;
    _buttonState.value = ButtonState.loading;
    _progressBarState.value = ProgressBarState();
    notifyListeners();

    final ok = await SpotifyDesktopEngine.instance.play(song);
    if (!ok) {
      print('[sp-engine] play() failed for ${song['spotifyUri']}');
      _buttonState.value = ButtonState.paused;
      return false;
    }
    _setEngineOwns(true);

    // ★ SP-7: Spotify owns the queue. Use the autoqueue neighbours Spotify
    // pushed in the state-machine payload — those are the real "next"
    // tracks, not the search-section list. Falls back to the caller's song
    // if metadata capture missed (e.g. cached file_id path).
    final sp = SpotifyPlayer.instance;
    final resolved = sp.lastResolvedSong;
    final neighbours = sp.lastAutoqueueNeighbours;
    if (resolved != null) {
      queueSnapshot.value = [resolved, ...neighbours];
      print('[sp-engine] queue: resolved + ${neighbours.length} neighbours');
    }

    _buttonState.value = ButtonState.playing;
    _progressBarState.value = ProgressBarState(
      current: Duration.zero,
      buffered: Duration.zero,
      total: SpotifyDesktopEngine.instance.duration.value,
    );
    notifyListeners();
    _saveCurrentState();
    return true;
  }

  Future<void> _releaseEngine() async {
    if (!_engineOwnsPlayback) return;
    _setEngineOwns(false);
    await _engineStop();
    _currentSongNotifier.value = null;
    _buttonState.value = ButtonState.paused;
    _progressBarState.value = ProgressBarState();
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════

  Future<void> _init() async {
    _listenToChangesInPlaylist();
    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToChangesInSong();
    _listenToShuffle();
    _listenToAutofetch();
    _listenToPlayerErrors();
    _listenToCrossfade();
    unawaited(_restoreEq());
    unawaited(_initSmtc());
    unawaited(_initDiscord());
    unawaited(_initLastfm());
    unawaited(_initMiniPlayer());
    unawaited(_initLyricsOverlay());
    unawaited(_initBackdrop());

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (currentSongNotifier.value != null && _player.playing) {
        GetIt.I<YTMusic>()
            .addPlayingStats(currentSongNotifier.value!.id, _player.position);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-22 WINDOWS SMTC (media keys + volume-flyout card)
  // ═══════════════════════════════════════════════════════════════
  // Driven entirely by the existing notifiers: currentSongNotifier gives
  // the OS the track metadata, progressBarState feeds the flyout progress
  // bar (throttled inside the bridge), buttonState maps to playing/paused.
  // Engine and just_audio paths both update these, so nothing per-path.

  Future<void> _initSmtc() async {
    if (!Platform.isWindows) return;
    await SmtcBridge.instance.init();
    _smtcSub = SmtcBridge.instance.buttonPresses.listen(_onSmtcButton);
    currentSongNotifier.addListener(_smtcPushMetadata);
    progressBarState.addListener(_smtcPushTimeline);
    buttonState.addListener(_smtcPushStatus);
    _smtcPushMetadata();
    _smtcPushStatus();
  }

  void _onSmtcButton(SmtcButton b) {
    switch (b) {
      case SmtcButton.play:
        if (_buttonState.value != ButtonState.playing) {
          unawaited(togglePlayPause());
        }
        break;
      case SmtcButton.pause:
        if (_buttonState.value == ButtonState.playing) {
          unawaited(togglePlayPause());
        }
        break;
      case SmtcButton.next:
        unawaited(skipNext());
        break;
      case SmtcButton.previous:
        unawaited(skipPrevious());
        break;
      case SmtcButton.stop:
      // Gentle stop: the media-key stop behaves like pause so the queue
      // stays intact (real stop() wipes the session queue).
        if (_buttonState.value == ButtonState.playing) {
          unawaited(togglePlayPause());
        }
        break;
    }
  }

  void _smtcPushMetadata() {
    final MediaItem? item = currentSongNotifier.value;
    if (item == null) {
      SmtcBridge.instance.stopped();
      return;
    }
    final String? thumb = item.artUri?.toString();
    SmtcBridge.instance.updateTrack(SmtcTrack(
      title: item.title,
      artist: item.artist ?? '',
      album: item.album ?? '',
      thumbnailUrl: (thumb != null &&
          (thumb.startsWith('http://') || thumb.startsWith('https://')))
          ? thumb
          : null,
      duration: progressBarState.value.total,
    ));
    _smtcPushTimeline(force: true);
  }

  void _smtcPushStatus() {
    switch (_buttonState.value) {
      case ButtonState.playing:
        SmtcBridge.instance.playing();
        break;
      case ButtonState.paused:
        SmtcBridge.instance.paused();
        break;
      case ButtonState.loading:
        break; // transient — resolves to playing/paused within a tick
    }
  }

  void _smtcPushTimeline({bool force = false}) {
    final ProgressBarState p = progressBarState.value;
    SmtcBridge.instance.position(p.current, p.total, force: force);
  }

  void _disposeSmtc() {
    _smtcSub?.cancel();
    _smtcSub = null;
    currentSongNotifier.removeListener(_smtcPushMetadata);
    progressBarState.removeListener(_smtcPushTimeline);
    buttonState.removeListener(_smtcPushStatus);
    unawaited(SmtcBridge.instance.dispose());
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-23 DISCORD RICH PRESENCE
  // ═══════════════════════════════════════════════════════════════
  // Same notifier-driven pattern as SP-22: currentSongNotifier carries the
  // track, buttonState carries play/pause. The bridge dedupes and only
  // talks to Discord on real changes, never per position tick. Self-noops
  // without an application id and off Windows/Linux.

  Future<void> _initDiscord() async {
    await DiscordPresenceBridge.instance.init();
    currentSongNotifier.addListener(_discordPushTrack);
    buttonState.addListener(_discordPushStatus);
    _discordPushTrack();
    _discordPushStatus();
  }

  void _discordPushTrack() {
    final MediaItem? item = currentSongNotifier.value;
    if (item == null) {
      DiscordPresenceBridge.instance.stopped();
      return;
    }
    final String? thumb = item.artUri?.toString();
    DiscordPresenceBridge.instance.updateTrack(
      title: item.title,
      artist: item.artist ?? '',
      artUrl: (thumb != null &&
          (thumb.startsWith('http://') || thumb.startsWith('https://')))
          ? thumb
          : null,
      trackKey: item.id,
    );
  }

  void _discordPushStatus() {
    switch (_buttonState.value) {
      case ButtonState.playing:
        DiscordPresenceBridge.instance.playing(
          position: _progressBarState.value.current,
        );
        break;
      case ButtonState.paused:
        DiscordPresenceBridge.instance.paused();
        break;
      case ButtonState.loading:
        break; // transient — resolves to playing/paused within a tick
    }
  }

  void _disposeDiscord() {
    currentSongNotifier.removeListener(_discordPushTrack);
    buttonState.removeListener(_discordPushStatus);
    DiscordPresenceBridge.instance.stopped();
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-25 LAST.FM SCROBBLING
  // ═══════════════════════════════════════════════════════════════
  // Same notifier-driven pattern as SP-22/SP-23: track metadata comes from
  // currentSongNotifier, positions from progressBarState. The service
  // applies the Last.fm client rules itself (≥ half the track or ≥ 4 min,
  // > 30 s tracks), sends "now playing" at track start and queues offline
  // scrobbles in Hive. No-ops on every platform until the user connects
  // Last.fm from the Saved page — calls are safe in any state.

  Future<void> _initLastfm() async {
    await LastfmService.instance.init();
    currentSongNotifier.addListener(_lastfmPushTrack);
    progressBarState.addListener(_lastfmPushProgress);
  }

  void _lastfmPushTrack() {
    final MediaItem? item = currentSongNotifier.value;
    if (item == null) return;
    LastfmService.instance.trackChanged(
      title: item.title,
      artist: item.artist ?? '',
      album: item.album,
    );
  }

  void _lastfmPushProgress() {
    final ProgressBarState p = progressBarState.value;
    LastfmService.instance.progress(p.current, p.total);
  }

  void _disposeLastfm() {
    currentSongNotifier.removeListener(_lastfmPushTrack);
    progressBarState.removeListener(_lastfmPushProgress);
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-26 MINI PLAYER WINDOW (floating desktop_multi_window bar)
  // ═══════════════════════════════════════════════════════════════
  // Same notifier-driven pattern as SP-22/23/25: track metadata, play
  // state and position are mirrored into the mini window and its
  // transport buttons come back as commands. The mini window is a second
  // Flutter engine sharing nothing with this isolate — the bridge is the
  // only link, every push is fire-and-swallow, and a missing/dead mini
  // window can never affect playback.

  Future<void> _initMiniPlayer() async {
    await MiniPlayerBridge.instance.init();
    MiniPlayerBridge.instance.onCommand = _onMiniCommand;
    currentSongNotifier.addListener(_miniPushTrack);
    buttonState.addListener(_miniPushPlaying);
    progressBarState.addListener(_miniPushProgress);
    // Seed the bridge so a window opened later is never blank.
    _miniPushTrack();
    _miniPushPlaying();
  }

  void _onMiniCommand(String cmd) {
    switch (cmd) {
      case 'toggle':
        unawaited(togglePlayPause());
        break;
      case 'next':
        unawaited(skipNext());
        break;
      case 'previous':
        unawaited(skipPrevious());
        break;
    }
  }

  void _miniPushTrack() {
    final MediaItem? item = currentSongNotifier.value;
    MiniPlayerBridge.instance.pushTrack(item == null
        ? null
        : MiniTrack(
      title: item.title,
      artist: item.artist ?? '',
      artUri: item.artUri?.toString(),
    ));
  }

  void _miniPushPlaying() {
    MiniPlayerBridge.instance
        .pushPlaying(_buttonState.value == ButtonState.playing);
  }

  void _miniPushProgress() {
    final ProgressBarState p = progressBarState.value;
    MiniPlayerBridge.instance.pushProgress(p.current, p.total);
  }

  void _disposeMiniPlayer() {
    currentSongNotifier.removeListener(_miniPushTrack);
    buttonState.removeListener(_miniPushPlaying);
    progressBarState.removeListener(_miniPushProgress);
    MiniPlayerBridge.instance.onCommand = null;
    unawaited(MiniPlayerBridge.instance.shutdown());
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-27 CROSSFADE (smooth volume fade between tracks)
  // ═══════════════════════════════════════════════════════════════
  // Volume-only transition: the last N seconds of a track fade out, the
  // next track fades in. No second player, no queue surgery — every ramp
  // is token-guarded and re-checks its preconditions on every tick, so it
  // self-cancels (and restores the volume) on pause, seek, skip, stop or
  // the Spotify engine taking over. The volume can never stay stuck.
  // Control surface: crossfade_page.dart (Saved → Crossfade).

  static const String _crossfadeKey = 'CROSSFADE_SECS';
  int _crossfadeSeconds = 0;
  Timer? _fadeTimer;
  int _fadeToken = 0;
  bool _fadedOut = false;

  int get crossfadeSeconds => _crossfadeSeconds;

  Future<void> setCrossfadeSeconds(int seconds) async {
    final int v = seconds.clamp(0, 12).toInt();
    _crossfadeSeconds = v;
    try {
      await Hive.box('SETTINGS').put(_crossfadeKey, v);
    } catch (_) {}
    // Changing the setting mid-fade returns to a clean state.
    _cancelFade(restore: true);
  }

  void _listenToCrossfade() {
    try {
      _crossfadeSeconds =
          (Hive.box('SETTINGS').get(_crossfadeKey, defaultValue: 0) as num?)
              ?.toInt() ??
              0;
    } catch (_) {}
    _player.positionStream.listen((_) {
      if (_engineOwnsPlayback) return;
      _maybeStartFadeOut();
    });
    _player.currentIndexStream.listen((int? index) {
      if (_engineOwnsPlayback) return;
      if (index == null) {
        // Queue cleared (stop / fresh play) — never leave a ramp running.
        _cancelFade(restore: true);
        return;
      }
      // Every track boundary (auto-advance or manual skip) starts a fresh
      // fade-in when crossfade is on. Registered AFTER
      // _listenToChangesInSong, so _currentSongNotifier is already the new
      // track by the time this runs.
      _maybeStartFadeIn();
    });
  }

  void _maybeStartFadeOut() {
    final int window = _crossfadeSeconds;
    if (window <= 0 || _fadedOut) return;
    if (_buttonState.value != ButtonState.playing) return;
    final ProgressBarState p = _progressBarState.value;
    final Duration total = p.total;
    if (total <= Duration.zero || total <= Duration(seconds: window * 2)) {
      return;
    }
    final Duration remaining = total - p.current;
    if (remaining <= Duration.zero ||
        remaining > Duration(seconds: window)) {
      return;
    }
    final String? trackId = _currentSongNotifier.value?.id;
    if (trackId == null) return;
    _startFadeOut(trackId, Duration(seconds: window));
  }

  void _startFadeOut(String trackId, Duration window) {
    ++_fadeToken;
    _fadeTimer?.cancel();
    final int token = _fadeToken;
    final DateTime start = DateTime.now();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 80), (Timer t) {
      final ProgressBarState p = _progressBarState.value;
      final bool invalid = token != _fadeToken ||
          _engineOwnsPlayback ||
          _crossfadeSeconds <= 0 ||
          _currentSongNotifier.value?.id != trackId ||
          _buttonState.value != ButtonState.playing ||
          p.total <= Duration.zero ||
          (p.total - p.current) > window + const Duration(milliseconds: 600);
      if (invalid) {
        t.cancel();
        _restoreVolume();
        return;
      }
      final double f = DateTime.now().difference(start).inMilliseconds /
          window.inMilliseconds;
      if (f >= 1.0) {
        t.cancel();
        try {
          unawaited(_player.setVolume(0.0));
        } catch (_) {}
        _fadedOut = true;
        // Queue end (or loop-one): nothing advances and the completed
        // handler pauses at 0 — bring the volume back shortly after so
        // replay is never silent. If a next track IS advancing, the
        // fade-in below owns the volume anyway.
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (token == _fadeToken &&
              _currentSongNotifier.value?.id == trackId &&
              !_engineOwnsPlayback) {
            _fadedOut = false;
            _restoreVolume();
          }
        });
        return;
      }
      try {
        unawaited(_player.setVolume((1.0 - f).clamp(0.0, 1.0)));
      } catch (_) {}
    });
  }

  void _maybeStartFadeIn() {
    // Any boundary cancels whatever ramp was running.
    ++_fadeToken;
    _fadeTimer?.cancel();
    _fadedOut = false;
    final int window = _crossfadeSeconds;
    final String? trackId = _currentSongNotifier.value?.id;
    if (window <= 0 || trackId == null) {
      _restoreVolume();
      return;
    }
    _startFadeIn(trackId, Duration(seconds: window));
  }

  void _startFadeIn(String trackId, Duration window) {
    final int token = _fadeToken;
    final DateTime start = DateTime.now();
    try {
      unawaited(_player.setVolume(0.0));
    } catch (_) {}
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 80), (Timer t) {
      final bool invalid = token != _fadeToken ||
          _engineOwnsPlayback ||
          _crossfadeSeconds <= 0 ||
          _currentSongNotifier.value?.id != trackId ||
          _buttonState.value == ButtonState.paused;
      if (invalid) {
        t.cancel();
        _restoreVolume();
        return;
      }
      final double f = DateTime.now().difference(start).inMilliseconds /
          window.inMilliseconds;
      if (f >= 1.0) {
        t.cancel();
        _restoreVolume();
        return;
      }
      try {
        unawaited(_player.setVolume(f.clamp(0.0, 1.0)));
      } catch (_) {}
    });
  }

  void _restoreVolume() {
    try {
      unawaited(_player.setVolume(1.0));
    } catch (_) {}
  }

  void _cancelFade({bool restore = true}) {
    ++_fadeToken;
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadedOut = false;
    if (restore) _restoreVolume();
  }

  void _disposeCrossfade() {
    _cancelFade(restore: true);
  }

  // ═══════════════════════════════════════════════════════════════
  // SP-28 LYRICS OVERLAY WINDOW
  // ═══════════════════════════════════════════════════════════════
  // Same notifier-driven pattern as SP-22/23/25/26: the bridge mirrors
  // track + position into the overlay engine and fetches lyrics for the
  // current track (SP-10 Spotify Color Lyrics → SP-15 LRCLIB — the same
  // chain the in-player LyricsBox uses). Fire-and-swallow everywhere; the
  // overlay can never affect playback. Control surface: Saved →
  // Lyrics overlay.

  Future<void> _initLyricsOverlay() async {
    await LyricsOverlayBridge.instance.init();
    currentSongNotifier.addListener(_overlayPushTrack);
    progressBarState.addListener(_overlayPushPosition);
    _overlayPushTrack();
  }

  void _overlayPushTrack() {
    final MediaItem? item = currentSongNotifier.value;
    LyricsOverlayBridge.instance.pushTrack(item == null
        ? null
        : OverlayTrack(
      title: item.title,
      artist: item.artist ?? '',
      artUri: item.artUri?.toString(),
      album: item.album,
      durationMs: item.duration?.inMilliseconds,
      spotifyUri: item.extras?['spotifyUri'] as String?,
    ));
  }

  void _overlayPushPosition() {
    final ProgressBarState p = progressBarState.value;
    LyricsOverlayBridge.instance.pushPosition(p.current, p.total);
  }

  void _disposeLyricsOverlay() {
    currentSongNotifier.removeListener(_overlayPushTrack);
    progressBarState.removeListener(_overlayPushPosition);
    unawaited(LyricsOverlayBridge.instance.shutdown());
  }

  // ═════════════════════════════════════════════════════════════
  // SP-29 WINDOWS VIDEO BACKDROP
  // ═════════════════════════════════════════════════════════════
  // Same notifier-driven pattern as SP-22/23/25/26/28: the service
  // mirrors track + play state + seeks into a dedicated MUTED media_kit
  // video player (lib/desktop/backdrop/) whose texture the player screen
  // renders as the blurred 16:9 backdrop (windows_backdrop.dart, first
  // child of the screen's Stack). Windows-only; fire-and-swallow — the
  // backdrop can never affect playback. Control surface: Saved → Video
  // backdrop.

  Future<void> _initBackdrop() async {
    await WindowsBackdropService.instance.init();
    currentSongNotifier.addListener(_backdropPushTrack);
    buttonState.addListener(_backdropPushState);
    _backdropPushTrack();
  }

  void _backdropPushTrack() {
    final MediaItem? item = currentSongNotifier.value;
    // Spotify-engine tracks: MediaItem.id carries the YT *fallback* videoId
    // (not the spotify URI), so the service's 'spotify:' filter never sees
    // them — guard here instead, or the backdrop would show the wrong
    // song's video behind Spotify audio. Audio owns the canvas: none.
    final String? sp = item?.extras?['spotifyUri'] as String?;
    if (sp != null && sp.isNotEmpty) {
      WindowsBackdropService.instance.trackChanged(videoId: null);
      return;
    }
    WindowsBackdropService.instance.trackChanged(videoId: item?.id);
  }

  void _backdropPushState() {
    switch (buttonState.value) {
      case ButtonState.playing:
        WindowsBackdropService.instance.playing();
        break;
      case ButtonState.paused:
      case ButtonState.loading:
        WindowsBackdropService.instance.paused();
        break;
    }
  }

  void _disposeBackdrop() {
    currentSongNotifier.removeListener(_backdropPushTrack);
    buttonState.removeListener(_backdropPushState);
    unawaited(WindowsBackdropService.instance.shutdown());
  }

  void _listenToChangesInPlaylist() {
    _player.sequenceStream.listen((playlist) {
      if (_engineOwnsPlayback) return;
      final List<IndexedAudioSource> newList =
      (playlist ?? const <IndexedAudioSource>[]).cast<IndexedAudioSource>();

      if (listEquals(newList, _songList)) return;

      final bool shouldAdd = (_songList.isEmpty && newList.isNotEmpty);

      if (newList.isEmpty) {
        _currentSongNotifier.value = null;
        _currentIndex.value = null;
        _songList = [];
      } else {
        _songList = newList;

        _currentIndex.value ??= 0;
        _currentSongNotifier.value =
        (_songList.length > (_currentIndex.value ?? 0))
            ? _songList[_currentIndex.value ?? 0].tag
            : null;
      }

      if (shouldAdd == true && _currentSongNotifier.value != null) {
        addHistory(_currentSongNotifier.value!.extras!);
      }

      notifyListeners();
    });
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((event) {
      if (_engineOwnsPlayback) return;
      final isPlaying = event.playing;
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        _buttonState.value = ButtonState.loading;
      } else if (processingState == ProcessingState.ready) {
        _buttonState.value =
        isPlaying ? ButtonState.playing : ButtonState.paused;
        _saveCurrentState();
      } else if (processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        _buttonState.value = ButtonState.paused;
      } else {
        _buttonState.value = ButtonState.paused;
      }
    });
  }

  void _listenToPlayerErrors() {
    _player.playbackEventStream.listen(
          (event) {},
      onError: (Object e, StackTrace st) {
        if (_engineOwnsPlayback) return;
        _buttonState.value = ButtonState.paused;
        notifyListeners();
      },
    );
  }

  void _listenToCurrentPosition() {
    _player.positionStream.listen((position) {
      if (_engineOwnsPlayback) return;
      final oldState = _progressBarState.value;
      if (oldState.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: oldState.buffered,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((position) {
      if (_engineOwnsPlayback) return;
      final oldState = _progressBarState.value;
      if (oldState.buffered != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: position,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((position) {
      if (_engineOwnsPlayback) return;
      final oldState = _progressBarState.value;
      if (oldState.total != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: oldState.buffered,
          total: position ?? Duration.zero,
        );
      }
    });
  }

  void _listenToShuffle() {
    _player.shuffleModeEnabledStream.listen((data) {
      _shuffleModeEnabled = data;
      notifyListeners();
    });
  }

  void _listenToChangesInSong() {
    _player.currentIndexStream.listen((index) {
      if (_engineOwnsPlayback) return;
      if (_songList.isNotEmpty && _currentIndex.value != index) {
        _currentIndex.value = index;
        _currentSongNotifier.value =
        index != null && _songList.isNotEmpty && index < _songList.length
            ? _songList[index].tag
            : null;
        if (_songList.isNotEmpty && _currentIndex.value != null) {
          final MediaItem item = _songList[_currentIndex.value!].tag;
          addHistory(item.extras!);
          _kickCache(item.extras!);
        }
        notifyListeners();
        _saveCurrentState();
      }
    });
  }

  // ── Offline cache: silent background download ──
  // Single funnel for every "song became current" path (playSong,
  // playFromSection, playAll, skipNext, radio/related, playlists). Only
  // videoId songs are cached; Spotify, JioSaavn and DOWNLOADED files are
  // skipped. First play streams instantly; the file fills in the
  // background and every later play replays from disk.
  void _kickCache(Map<String, dynamic> song) {
    final videoId = song['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return;
    if ((song['spotifyUri'] as String?)?.isNotEmpty == true) return;
    if ((song['jiosaavnStreamUrl'] as String?)?.isNotEmpty == true) return;
    if (song['status'] == 'DOWNLOADED') return;
    unawaited(SongCache.ensureCached(videoId));
  }

  void changeLoopMode() {
    switch (_loopMode.value) {
      case LoopMode.off:
        _loopMode.value = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode.value = LoopMode.one;
        break;
      default:
        _loopMode.value = LoopMode.off;
        break;
    }
    _player.setLoopMode(_loopMode.value);
  }

  Future<void> skipSilence(bool value) async {
    await _player.setSkipSilenceEnabled(value);
    GetIt.I<SettingsManager>().skipSilence = value;
  }

  Future<AudioSource> _getAudioSource(Map<String, dynamic> song) async {
    MediaItem tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );

    final bool isDownloaded = song['status'] == 'DOWNLOADED' &&
        song['path'] != null &&
        (await File(song['path']).exists());

    if (isDownloaded) {
      return AudioSource.file(song['path'], tag: tag);
    } else {
      final spotifyUri = song['spotifyUri'] as String?;
      if (spotifyUri != null && spotifyUri.isNotEmpty) {
        if (Platform.isAndroid) {
          try {
            final cdn = await SpotifyPlayer.instance.resolveTrack(spotifyUri);
            final token = await SpotifyAuth.instance.getAccessToken();
            if (cdn != null && token != null && cdn.isNotEmpty) {
              final clientToken =
              await SpotifyAuth.instance.getClientToken();
              print('[spotify-play] DRM source for $spotifyUri');
              return AudioSource.uri(Uri.parse(cdn), tag: tag, headers: {
                'User-Agent': SpotifyConfig.userAgent,
                'Origin': 'https://open.spotify.com',
                'Referer': 'https://open.spotify.com/',
                'x-zen-drm': jsonEncode({
                  'licenseUri': _kSpotifyWidevineLicenseUrl,
                  'headers': {
                    'authorization': 'Bearer $token',
                    'client-token': clientToken,
                    'app-platform': SpotifyConfig.appPlatform,
                    'spotify-app-version': SpotifyConfig.spotifyAppVersion,
                    'origin': 'https://open.spotify.com/',
                    'referer': 'https://open.spotify.com/',
                    'user-agent': SpotifyConfig.userAgent,
                  },
                }),
              });
            }
            print('[spotify-play] DRM resolve failed, falling back to YT');
          } catch (e) {
            print('[spotify-play] DRM error: $e, falling back to YT');
          }
        }
        return _ytFallbackSource(song, tag);
      }
      final saavnUrl = song['jiosaavnStreamUrl'] as String?;
      if (saavnUrl != null && saavnUrl.isNotEmpty) {
        return AudioSource.uri(Uri.parse(saavnUrl), tag: tag);
      }
      // Offline cache: a YouTube song already on disk replays from the
      // file instead of the network.
      final cached = await SongCache.lookup(song['videoId'] ?? '');
      if (cached != null && await File(cached.filePath).exists()) {
        return AudioSource.file(cached.filePath, tag: tag);
      }
      if (Platform.isMacOS) {
        final quality =
        GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase();
        return await getDirectUrlAudioSource(song['videoId'], quality, tag);
      }
      return YouTubeAudioSource(
        videoId: song['videoId'],
        quality: GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase(),
        tag: tag,
      );
    }
  }

  Future<AudioSource> _ytFallbackSource(
      Map<String, dynamic> song, MediaItem tag) async {
    try {
      final query = '${song['title'] ?? ''} ${song['artist'] ?? ''}'.trim();
      final result = await GetIt.I<YTMusic>().search(query, filter: 'songs');
      final sections = result['sections'] as List?;
      if (sections != null && sections.isNotEmpty) {
        final contents = sections[0]['contents'] as List?;
        if (contents != null && contents.isNotEmpty) {
          final ytSong = Map<String, dynamic>.from(contents[0] as Map);
          print('[spotify-play] YT fallback: ${ytSong['videoId']}');
          return YouTubeAudioSource(
            videoId: ytSong['videoId'],
            quality: GetIt.I<SettingsManager>()
                .streamingQuality
                .name
                .toLowerCase(),
            tag: tag,
          );
        }
      }
    } catch (e) {
      print('[spotify-play] YT fallback error: $e');
    }
    throw Exception('Spotify playback unavailable (no YT fallback match)');
  }

  int _lastPlayRequestId = 0;

  Future<void> playSong(Map<String, dynamic> song) async {
    if (song['videoId'] == null) return;
    queueSnapshot.value = [Map<String, dynamic>.from(song)];

    // SP-5b: Windows + Spotify URI -> engine takes over.
    if (Platform.isWindows) {
      final spUri = song['spotifyUri'] as String?;
      if (spUri != null && spUri.isNotEmpty) {
        if (await _tryEnginePlay(song)) return;
      }
    }

    final int requestId = DateTime.now().millisecondsSinceEpoch;
    _lastPlayRequestId = requestId;

    MediaItem tempTag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );
    _currentSongNotifier.value = tempTag;
    _buttonState.value = ButtonState.loading;
    notifyListeners();

    try {
      _player.pause();
      await _player.stop();
      if (_lastPlayRequestId != requestId) return;
      await _player.clearAudioSources();
      if (_lastPlayRequestId != requestId) return;
    } catch (e) {
      // Ignore stop errors
    }

    try {
      final source = await _getAudioSource(song);
      if (_lastPlayRequestId != requestId) return;
      await _player.setAudioSource(source);
      if (_lastPlayRequestId != requestId) return;
      await _player.play();
      _saveCurrentState();
    } catch (e) {
      if (_lastPlayRequestId == requestId) {
        print("Error playing song: $e");
        _buttonState.value = ButtonState.paused;
        notifyListeners();
      }
    }
  }

  /// SP-6: section-aware tap. The whole section becomes the "session":
  /// queueSnapshot mirrors it, engine takes over for Spotify on Windows,
  /// and everything else plays through just_audio with the tapped song first
  /// and the rest of the section lazily preloaded.
  Future<void> playFromSection(
      List<Map<String, dynamic>> section, int index) async {
    if (section.isEmpty) return;
    if (index < 0 || index >= section.length) return;

    queueSnapshot.value =
        section.map((s) => Map<String, dynamic>.from(s)).toList();

    final song = Map<String, dynamic>.from(section[index]);

    if (Platform.isWindows &&
        (song['spotifyUri'] as String?)?.isNotEmpty == true) {
      // SP-7: _tryEnginePlay replaces queueSnapshot with the Spotify
      // autoqueue on success. Falls through to just_audio on failure.
      if (await _tryEnginePlay(song)) return;
    }

    _buttonState.value = ButtonState.loading;
    notifyListeners();
    try {
      await _player.stop();
      await _player.clearAudioSources();
      final first = await _getAudioSource(song);
      await _player.setAudioSource(first);
      _player.play();
      if (section.length > 1) {
        Future(() => _addRemainingToPlaylist(section, index));
      }
      _saveCurrentState();
    } catch (e) {
      print('playFromSection error: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
  }

  Future<void> playNext(Map<String, dynamic> mediaItem) async {
    if (_engineOwnsPlayback) await _releaseEngine();

    if (mediaItem['videoId'] != null) {
      final audioSource = await _getAudioSource(mediaItem);

      final currentIndex = _player.currentIndex ?? -1;
      final sequenceLength = _player.sequence.length;
      final int insertIndex = (currentIndex + 1).clamp(0, sequenceLength).toInt();

      if (sequenceLength > 0) {
        await _player.insertAudioSource(insertIndex, audioSource);
      } else {
        await _player.setAudioSource(audioSource);
      }
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: true);
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
          .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: true);
    }
  }

  Future<void> playAll(List songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    queueSnapshot.value =
        songs.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    if (_engineOwnsPlayback) await _releaseEngine();

    _buttonState.value = ButtonState.loading;
    notifyListeners();

    try {
      await _player.stop();

      final selectedSong = Map<String, dynamic>.from(songs[index]);

      if (selectedSong['isChart'] == true) {
        final resolved = <Map<String, dynamic>>[];
        for (final s in songs) {
          final m = Map<String, dynamic>.from(s);
          if (m['isChart'] != true) {
            resolved.add(m);
            continue;
          }
          try {
            final query = '${m['title']} ${m['subtitle'] ?? ''}';
            final result =
            await GetIt.I<YTMusic>().search(query, filter: 'songs');
            final sections = result['sections'] as List?;
            if (sections != null && sections.isNotEmpty) {
              final sec = sections[0];
              final contents = sec['contents'] as List?;
              if (contents != null && contents.isNotEmpty) {
                resolved.add(Map<String, dynamic>.from(contents[0]));
              }
            }
          } catch (_) {}
        }
        if (resolved.isEmpty) {
          _buttonState.value = ButtonState.paused;
          notifyListeners();
          return;
        }
        songs = resolved;
        index = index.clamp(0, resolved.length - 1).toInt();
      }

      final selectedSong2 = Map<String, dynamic>.from(songs[index]);
      final firstSource = await _getAudioSource(selectedSong2);

      await _player.setAudioSource(firstSource);
      _player.play();

      if (songs.length > 1) {
        Future(() => _addRemainingToPlaylist(songs, index));
      }
      _saveCurrentState();
    } catch (e) {
      print('Error in playAll: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
  }

  Future<void> _addRemainingToPlaylist(List songs, int playedIndex) async {
    try {
      final int maxPreload = 3;
      int added = 0;

      for (int i = playedIndex + 1;
      i < songs.length && added < maxPreload;
      i++) {
        try {
          final source =
          await _getAudioSource(Map<String, dynamic>.from(songs[i]));
          await _player.addAudioSource(source);
          added++;
        } catch (e) {
          // Skip failed songs silently
        }
      }
    } catch (e) {
      print('Error adding remaining songs: $e');
    }
  }

  Future<void> addToQueue(Map<String, dynamic> mediaItem) async {
    if (mediaItem['videoId'] != null) {
      await _player.addAudioSource(await _getAudioSource(mediaItem));
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: false);
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
          .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: false);
    }
  }

  Future<void> startRelated(Map<String, dynamic> song,
      {bool radio = false, bool shuffle = false, bool isArtist = false}) async {
    if (_engineOwnsPlayback) await _releaseEngine();
    await _player.clearAudioSources();
    if (!isArtist) {
      await addToQueue(song);
    }
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        videoId: song['videoId'],
        playlistId: song['playlistRadioId'],
        radio: radio,
        shuffle: shuffle);
    if (songs.isNotEmpty) songs.removeAt(0);
    await _addSongListToQueue(songs, isNext: false);
    await _player.play();
  }

  Future<void> startPlaylistSongs(Map endpoint) async {
    if (_engineOwnsPlayback) await _releaseEngine();
    await _player.clearAudioSources();
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        playlistId: endpoint['playlistId'], params: endpoint['params']);

    if (songs.isNotEmpty && songs.first['videoId'] == null) {
      // if API returned a placeholder, convert or handle accordingly
    }

    await _addSongListToQueue(songs);
    await _player.play();
  }

  Future<void> stop() async {
    if (_engineOwnsPlayback) await _releaseEngine();
    await _player.stop();
    await _player.clearAudioSources();
    await _player.seek(Duration.zero, index: 0);
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
    Hive.box('SETTINGS').delete('CACHE_QUEUE');
  }

  // ── SP-5b transport routing ──

  Future<void> togglePlayPause() async {
    if (_engineOwnsPlayback) {
      final engine = SpotifyDesktopEngine.instance;
      if (engine.playing.value) {
        await _enginePause();
      } else {
        await _engineResume();
      }
      _saveCurrentState();
      return;
    }
    if (_player.playing) {
      _player.pause();
      _saveCurrentState();
    } else {
      await _player.play();
    }
  }

  Future<void> seekTo(Duration d) async {
    WindowsBackdropService.instance
        .seekTo(d); // SP-29: realign the backdrop layer
    if (_engineOwnsPlayback) {
      await _engineSeek(d);
      _saveCurrentState();
      return;
    }
    await _player.seek(d);
    _saveCurrentState();
  }

  /// SP-6 / SP-7: when the engine owns playback, walk the queue snapshot.
  /// For Spotify tracks the snapshot is [resolved, ...autoqueueNeighbours]
  /// (SP-7). For everything else it's whatever the caller set (SP-6).
  Future<void> skipNext() async {
    if (_engineOwnsPlayback) {
      final snapshot = queueSnapshot.value;
      final currentId = _currentSongNotifier.value?.id;
      final idx = snapshot.indexWhere((s) => s['videoId'] == currentId);
      if (idx >= 0 && idx + 1 < snapshot.length) {
        final next = Map<String, dynamic>.from(snapshot[idx + 1]);
        if (Platform.isWindows &&
            (next['spotifyUri'] as String?)?.isNotEmpty == true) {
          if (await _tryEnginePlay(next)) return;
        }
        _setEngineOwns(false);
        await _engineStop();
        try {
          await _player.stop();
          await _player.clearAudioSources();
          final src = await _getAudioSource(next);
          await _player.setAudioSource(src);
          await _player.play();
          _saveCurrentState();
        } catch (e) {
          print('[skipNext] fallback error: $e');
        }
        return;
      }
      await _releaseEngine();
      return;
    }
    await _player.seekToNext();
  }

  Future<void> skipPrevious() async {
    if (_engineOwnsPlayback) {
      final snapshot = queueSnapshot.value;
      final currentId = _currentSongNotifier.value?.id;
      final idx = snapshot.indexWhere((s) => s['videoId'] == currentId);
      if (idx > 0) {
        final prev = Map<String, dynamic>.from(snapshot[idx - 1]);
        if (Platform.isWindows &&
            (prev['spotifyUri'] as String?)?.isNotEmpty == true) {
          if (await _tryEnginePlay(prev)) return;
        }
        _setEngineOwns(false);
        await _engineStop();
        try {
          await _player.stop();
          await _player.clearAudioSources();
          final src = await _getAudioSource(prev);
          await _player.setAudioSource(src);
          await _player.play();
          _saveCurrentState();
        } catch (e) {
          print('[skipPrevious] fallback error: $e');
        }
        return;
      }
      await _releaseEngine();
      return;
    }
    await _player.seekToPrevious();
  }

  Future<void> _addSongListToQueue(List songs, {bool isNext = false}) async {
    if (songs.isEmpty) return;

    final newSources = await Future.wait(songs.map((song) async {
      final mapSong = Map<String, dynamic>.from(song);
      return await _getAudioSource(mapSong);
    }));

    final queueLength = _player.sequence.length;

    if (isNext) {
      final currentIndex = _player.currentIndex ?? -1;
      int insertIndex = (currentIndex + 1).clamp(0, queueLength).toInt();
      await _player.insertAudioSources(insertIndex, newSources);
    } else {
      await _player.addAudioSources(newSources);
    }
  }

  void _listenToAutofetch() {
    player.currentIndexStream.listen((index) async {
      if (_engineOwnsPlayback) return;
      if (index == null) return;
      if (player.sequence.length - index < 5 &&
          GetIt.I<SettingsManager>().autofetchSongs &&
          autoFetching == false) {
        autoFetching = true;
        List nextSongs = await GetIt.I<YTMusic>()
            .getNextSongList(videoId: player.sequence[index].tag.id);
        if (nextSongs.isNotEmpty) nextSongs.removeAt(0);
        await _addSongListToQueue(nextSongs);
        autoFetching = false;
      }
    });
  }

  void setTimer(Duration duration) {
    int seconds = duration.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds--;
      _timerDuration.value = Duration(seconds: seconds);
      if (seconds == 0) {
        cancelTimer();
        _player.pause();
      }
      notifyListeners();
    });
  }

  void cancelTimer() {
    _timerDuration.value = null;
    _timer?.cancel();
    notifyListeners();
  }

  // ── EQUALIZER (Android session EQ) ──

  static const _eqEnabledKey = 'EQ_ENABLED';
  static const _eqBandsKey = 'EQ_BANDS';

  Future<EqParams?> getEqParameters() async {
    final eq = _eq;
    if (eq == null || !Platform.isAndroid) return null;
    try {
      _eqParams ??= await eq.parameters;
      final p = _eqParams!;
      return EqParams(
        minDb: p.minDecibels,
        maxDb: p.maxDecibels,
        bands: [
          for (final b in p.bands)
            EqBand(centerHz: b.centerFrequency, gain: b.gain),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setEqEnabled(bool enabled) async {
    final box = Hive.box('SETTINGS');
    await box.put(_eqEnabledKey, enabled);
    try {
      await _eq?.setEnabled(enabled);
    } catch (_) {}
  }

  Future<bool> getEqEnabled() async {
    return Hive.box('SETTINGS').get(_eqEnabledKey, defaultValue: false);
  }

  Future<void> setEqBandGain(int index, double gain) async {
    final p = _eqParams;
    if (p == null || index < 0 || index >= p.bands.length) return;
    try {
      await p.bands[index].setGain(gain);
      final stored = Hive.box('SETTINGS').get(_eqBandsKey);
      final gains = stored is List
          ? List<double>.from(stored.map((e) => (e as num?)?.toDouble() ?? 0.0))
          : <double>[];
      if (gains.length != p.bands.length) {
        gains.length = p.bands.length;
        for (var i = 0; i < gains.length; i++) {
          gains[i] ??= 0.0;
        }
      }
      gains[index] = gain;
      await Hive.box('SETTINGS').put(_eqBandsKey, gains);
    } catch (_) {}
  }

  Future<void> resetEq() async {
    final p = _eqParams;
    if (p == null) return;
    try {
      for (final b in p.bands) {
        await b.setGain(0);
      }
      await Hive.box('SETTINGS').put(
          _eqBandsKey, List<double>.filled(p.bands.length, 0));
    } catch (_) {}
  }

  Future<void> _restoreEq() async {
    final eq = _eq;
    if (eq == null || !Platform.isAndroid) return;
    try {
      _eqParams ??= await eq.parameters;
      final p = _eqParams!;
      final box = Hive.box('SETTINGS');
      final enabled = box.get(_eqEnabledKey, defaultValue: false);
      if (enabled) await eq.setEnabled(true);
      final stored = box.get(_eqBandsKey);
      final gains = stored is List
          ? List<double>.from(stored.map((e) => (e as num?)?.toDouble() ?? 0.0))
          : <double>[];
      if (gains.length == p.bands.length) {
        for (var i = 0; i < gains.length; i++) {
          await p.bands[i].setGain(gains[i]);
        }
      }
    } catch (_) {}
  }
}

enum ButtonState { loading, paused, playing }

enum LoopState { off, all, one }

class ProgressBarState {
  Duration current;
  Duration buffered;
  Duration total;
  ProgressBarState(
      {this.current = Duration.zero,
        this.buffered = Duration.zero,
        this.total = Duration.zero});
}