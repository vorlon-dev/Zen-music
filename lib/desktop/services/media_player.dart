// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../lossless/lossless_service.dart';
import 'native_equalizer.dart';
import '../utils/add_history.dart';
import '../utils/enhanced_image.dart';
import 'eq_models.dart';
import 'automix.dart';
import 'crossfade_engine.dart';
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

  bool _engineOwnsPlayback = false;
  bool _engineListenersAttached = false;

  final ValueNotifier<List<Map<String, dynamic>>> queueSnapshot =
  ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<bool> engineOwnsNotifier = ValueNotifier<bool>(false);

  void _setEngineOwns(bool v) {
    if (_engineOwnsPlayback != v) {
      _engineOwnsPlayback = v;
      engineOwnsNotifier.value = v;
    }
  }

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


  void _saveCurrentState() {
    if (queueSnapshot.value.isEmpty) return;
    final idx = _currentIndex.value ?? 0;
    final pos = _progressBarState.value.current;

    final box = Hive.box('SETTINGS');
    box.put('CACHE_QUEUE', queueSnapshot.value);
    box.put('CACHE_INDEX', idx);
    box.put('CACHE_POSITION', pos.inMilliseconds);
  }

  /// True between restoreLastSession() and the first play: the song is shown
  /// in the UI at its saved spot but nothing is loaded in the player yet.
  bool _restoredPending = false;
  int _restoredPositionMs = 0;
  DateTime _lastPositionSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cheap save (one int) for the periodic tick; the queue is written by
  /// _saveCurrentState on real changes only.
  void _savePositionOnly() {
    if (_restoredPending || queueSnapshot.value.isEmpty) return;
    try {
      Hive.box('SETTINGS').put(
          'CACHE_POSITION', _progressBarState.value.current.inMilliseconds);
    } catch (_) {}
  }

  /// Loads the restored song at its saved position and starts it.
  Future<void> _resumeRestored() async {
    final queue = queueSnapshot.value;
    final index = (_currentIndex.value ?? 0).clamp(0, queue.length - 1).toInt();
    final startAt = Duration(milliseconds: _restoredPositionMs);
    _restoredPending = false;
    _buttonState.value = ButtonState.loading;
    notifyListeners();
    try {
      _queueEpoch++;
      final source = await _getAudioSource(Map<String, dynamic>.from(queue[index]));
      await _player.setAudioSource(source, initialPosition: startAt);
      unawaited(_player.play());
      if (queue.length > 1) _queueAddRemaining(queue, index);
      _saveCurrentState();
    } catch (e) {
      print('resume restored session failed: $e');
      _restoredPending = true; // let the next tap retry
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
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
    // Spotify-engine tracks are resumed by their own engine, not here.
    _restoredPending = song['videoId'] != null;
    _restoredPositionMs = posMs;
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
    _disposeNotificationLike();
    _disposeSmtc();
    _disposeDiscord();
    _disposeLastfm();
    _disposeMiniPlayer();
    _disposeCrossfade();
    _disposeLyricsOverlay();
    _disposeBackdrop();
    super.dispose();
  }


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
        // SP-39d: a finished Spotify track advances the queue — the web
        // player never stalls on a rewound, paused tile. skipNext walks
        // the snapshot; when it is exhausted it releases the engine,
        // which is the old stop-at-end behavior. engine.play() re-arms
        // `ended` (false), so this fires exactly once per track.
        unawaited(skipNext());
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

    final sp = SpotifyPlayer.instance;
    final resolved = sp.lastResolvedSong;
    final neighbours = sp.lastAutoqueueNeighbours;
    final snapshot = queueSnapshot.value;
    final bool hasRealQueue = snapshot.length > 2 ||
        (snapshot.length == 2 &&
            snapshot.last['videoId'] != song['videoId']);
    if (resolved != null && !hasRealQueue) {
      queueSnapshot.value = [resolved, ...neighbours];
      print('[sp-engine] queue: radio fallback — resolved + '
          '${neighbours.length} neighbours');
    } else {
      print('[sp-engine] queue: kept caller queue '
          '(${snapshot.length} tracks)');
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
    unawaited(NativeEqualizer.instance.restore());
    unawaited(_initSmtc());
    unawaited(_initDiscord());
    unawaited(_initLastfm());
    unawaited(_initMiniPlayer());
    unawaited(_initLyricsOverlay());
    unawaited(_initBackdrop());
    _initNotificationLike();

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (currentSongNotifier.value != null && _player.playing) {
        GetIt.I<YTMusic>()
            .addPlayingStats(currentSongNotifier.value!.id, _player.position);
      }
    });
  }

  StreamSubscription<void>? _likePressSub;
  StreamSubscription<dynamic>? _favWatchSub;
  bool _likeWiringDone = false;

  void _initNotificationLike() {
    if (_likeWiringDone) return;
    _likeWiringDone = true;
    _likePressSub = JustAudioBackground.likePresses.listen((_) {
      unawaited(_toggleNotificationLike());
    });
    // Keep the notification icon in sync when the like is toggled from the
    // app UI (player page heart writes the same FAVOURITES box).
    _favWatchSub = Hive.box('FAVOURITES').watch().listen((dynamic _) {
      _pushLikeState();
    });
    currentSongNotifier.addListener(_pushLikeState);
    _pushLikeState();
  }

  void _disposeNotificationLike() {
    if (!_likeWiringDone) return;
    _likeWiringDone = false;
    _likePressSub?.cancel();
    _likePressSub = null;
    _favWatchSub?.cancel();
    _favWatchSub = null;
    currentSongNotifier.removeListener(_pushLikeState);
    JustAudioBackground.updateLikeState(visible: false);
  }

  /// Notification heart tapped → same toggle the player page performs:
  /// FAVOURITES box keyed by the track id (videoId), extras as the payload.
  Future<void> _toggleNotificationLike() async {
    final MediaItem? item = currentSongNotifier.value;
    if (item == null || item.id.isEmpty) return;
    final box = Hive.box('FAVOURITES');
    if (box.get(item.id) != null) {
      await box.delete(item.id);
    } else {
      final Map<String, dynamic>? extras = item.extras;
      await box.put(item.id, <String, dynamic>{
        ...?extras,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    }
    _pushLikeState();
  }

  /// Tell the fork's broadcast which heart to draw (or hide the button
  /// entirely when nothing is loaded).
  void _pushLikeState() {
    final MediaItem? item = currentSongNotifier.value;
    if (item == null || item.id.isEmpty) {
      JustAudioBackground.updateLikeState(visible: false);
      return;
    }
    JustAudioBackground.updateLikeState(
      visible: true,
      liked: Hive.box('FAVOURITES').get(item.id) != null,
    );
  }


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


  static const String _crossfadeKey = 'CROSSFADE_SECS';
  int _crossfadeSeconds = 0;

  int get crossfadeSeconds => _crossfadeSeconds;

  Future<void> setCrossfadeSeconds(int seconds) async {
    final int v = seconds.clamp(0, 12).toInt();
    _crossfadeSeconds = v;
    try {
      await Hive.box('SETTINGS').put(_crossfadeKey, v);
    } catch (_) {}
    // Changing the setting mid-blend returns to a clean state.
    unawaited(_xf?.cancel());
  }

  void _listenToCrossfade() {
    try {
      _crossfadeSeconds =
          (Hive.box('SETTINGS').get(_crossfadeKey, defaultValue: 0) as num?)
                  ?.toInt() ??
              0;
    } catch (_) {}
    // True two-deck overlap (see crossfade_engine.dart). It replaces the old
    // single-player fade-out/fade-in, which only ever dipped to silence.
    _xf = CrossfadeEngine(
      player: _player,
      buildSource: _getAudioSource,
      songAt: _songMapAt,
      nextSong: _nextSongMap,
      advance: skipNext,
      isBlocked: () =>
          _engineOwnsPlayback || _loopMode.value == LoopMode.one,
      plan: (outgoing, incoming) async {
        if (AutomixPrefs.enabled) return _automix.plan(outgoing, incoming);
        if (_crossfadeSeconds > 0) {
          return CrossfadePlan.plain(_crossfadeSeconds);
        }
        return null;
      },
    )..attach();
  }

  CrossfadeEngine? _xf;
  final Automix _automix = Automix();

  Map<String, dynamic>? _nextSongMap(int index) {
    final inSequence = _songMapAt(index + 1);
    if (inSequence != null) return inSequence;
    // Not preloaded yet: look in the wider queue.
    final snapshot = queueSnapshot.value;
    final currentId = _songMapAt(index)?['videoId'];
    final at = snapshot.indexWhere((s) => s['videoId'] == currentId);
    if (at < 0 || at + 1 >= snapshot.length) return null;
    return Map<String, dynamic>.from(snapshot[at + 1]);
  }

  Map<String, dynamic>? _songMapAt(int index) {
    final seq = _player.sequence;
    if (index < 0 || index >= seq.length) return null;
    final tag = seq[index].tag;
    if (tag is! MediaItem) return null;
    final extras = tag.extras;
    return extras == null ? null : Map<String, dynamic>.from(extras);
  }

  void _disposeCrossfade() {
    unawaited(_xf?.dispose());
  }


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
      if (_engineOwnsPlayback || _restoredPending) return;
      final oldState = _progressBarState.value;
      if (oldState.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: oldState.buffered,
          total: oldState.total,
        );
      }
      // Remember where we are every few seconds, so closing or killing the
      // app resumes at the right spot instead of the last song change.
      final now = DateTime.now();
      if (_player.playing &&
          now.difference(_lastPositionSave) > const Duration(seconds: 3)) {
        _lastPositionSave = now;
        _savePositionOnly();
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
                    'origin': 'https://open.spotify.com',
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
      if (song['isYtVideo'] != true) {
        try {
          final lossless = await LosslessService.instance
              .tryBuildSource(song, tag);
          if (lossless != null) return lossless;
        } catch (e) {
          print('[lossless] player fallback after error: $e');
        }
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
    _restoredPending = false;
    if (song['videoId'] == null) return;
    queueSnapshot.value = [Map<String, dynamic>.from(song)];
    _queueEpoch++;

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

  Future<void> playFromSection(
      List<Map<String, dynamic>> section, int index) async {
    _restoredPending = false;
    if (section.isEmpty) return;
    if (index < 0 || index >= section.length) return;

    queueSnapshot.value =
        section.map((s) => Map<String, dynamic>.from(s)).toList();
    _queueEpoch++;

    final song = Map<String, dynamic>.from(section[index]);

    if (Platform.isWindows &&
        (song['spotifyUri'] as String?)?.isNotEmpty == true) {
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
        _queueAddRemaining(section, index);
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
    _restoredPending = false;
    queueSnapshot.value =
        songs.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    _queueEpoch++;
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
        _queueAddRemaining(songs, index);
      }
      _saveCurrentState();
    } catch (e) {
      print('Error in playAll: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
  }

  int _queueEpoch = 0;

  void _queueAddRemaining(List songs, int playedIndex) {
    final epoch = _queueEpoch;
    Future(() => _addRemainingToPlaylist(songs, playedIndex, epoch));
  }

  Future<void> _addRemainingToPlaylist(List songs, int playedIndex,
      [int? epoch]) async {
    final stamp = epoch ?? _queueEpoch;
    try {
      final int maxPreload = 3;
      int added = 0;

      for (int i = playedIndex + 1;
      i < songs.length && added < maxPreload;
      i++) {
        if (stamp != _queueEpoch) return;
        try {
          final source =
          await _getAudioSource(Map<String, dynamic>.from(songs[i]));
          if (stamp != _queueEpoch) return;
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
    _queueEpoch++;
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
    _queueEpoch++;
    if (_engineOwnsPlayback) await _releaseEngine();
    await _player.stop();
    await _player.clearAudioSources();
    await _player.seek(Duration.zero, index: 0);
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
    Hive.box('SETTINGS').delete('CACHE_QUEUE');
  }


  Future<void> togglePlayPause() async {
    if (_restoredPending && !_engineOwnsPlayback) {
      await _resumeRestored();
      return;
    }
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
    if (_restoredPending && !_engineOwnsPlayback) {
      // Nothing is loaded yet: remember the spot, the first play starts there.
      _restoredPositionMs = d.inMilliseconds;
      final old = _progressBarState.value;
      _progressBarState.value = ProgressBarState(
          current: d, buffered: old.buffered, total: old.total);
      Hive.box('SETTINGS').put('CACHE_POSITION', d.inMilliseconds);
      return;
    }
    WindowsBackdropService.instance
        .seekTo(d);
    if (_engineOwnsPlayback) {
      await _engineSeek(d);
      _saveCurrentState();
      return;
    }
    await _player.seek(d);
    _saveCurrentState();
  }

  Future<void> skipNext() async {
    _restoredPending = false;
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
    if (_player.hasNext) {
      await _player.seekToNext();
      return;
    }
    await _playFromSnapshot(forward: true);
  }

  Future<void> skipPrevious() async {
    _restoredPending = false;
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
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      return;
    }
    await _playFromSnapshot(forward: false);
  }

  Future<void> _playFromSnapshot({required bool forward}) async {
    final snapshot = queueSnapshot.value;
    final currentId = _currentSongNotifier.value?.id;
    final idx = snapshot.indexWhere((s) => s['videoId'] == currentId);
    final target = forward ? idx + 1 : idx - 1;
    if (idx < 0 || target < 0 || target >= snapshot.length) {
      // Current track is outside the section, or the section ended —
      // nothing sane to walk to; leave playback exactly as it is.
      return;
    }
    final song = Map<String, dynamic>.from(snapshot[target]);
    // Invalidate any lazy preloader still resolving the OLD sequence so
    // it cannot land stale tracks behind the new playhead.
    _queueEpoch++;
    _buttonState.value = ButtonState.loading;
    notifyListeners();
    try {
      await _player.stop();
      await _player.clearAudioSources();
      final src = await _getAudioSource(song);
      await _player.setAudioSource(src);
      _player.play();
      // Refill the preloaded window ahead of the new playhead.
      if (target + 1 < snapshot.length) {
        _queueAddRemaining(snapshot, target);
      }
      _saveCurrentState();
    } catch (e) {
      print('[skip] snapshot walk error: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
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
    // The native equalizer replaces the device one; never run both at once.
    if (await NativeEqualizer.instance.isAvailable()) return;
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
