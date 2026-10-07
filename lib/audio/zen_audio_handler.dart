import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/buffered_stream_source.dart';
import '../services/downloads_service.dart';
import '../services/listening_stats_service.dart';
import '../services/song_source_resolver.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';

/// A playback load failure surfaced to the UI. [halted] is true when
/// the queue could NOT advance after the failure — i.e. playback
/// actually stopped; false when the handler skipped to the next track.
class PlaybackFailure {
  const PlaybackFailure({
    required this.songId,
    required this.title,
    required this.rawMessage,
    required this.halted,
    this.code,
  });

  final String songId;
  final String title;
  final String rawMessage;
  final bool halted;
  final int? code;
}

class ZenAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _equalizer = AndroidEqualizer();
  late final _player = AudioPlayer(
    audioPipeline: AudioPipeline(
      androidAudioEffects: [_equalizer],
    ),
  );
  final _yt = YoutubeService();
  final StorageService storage;

  List<Song> _queue = [];
  int _currentIndex = 0;
  bool _isAppending = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  // Bumped on every load; stale loads (rapid skips) are abandoned.
  int _loadGeneration = 0;

  // Listen Together: when true this device follows a remote host —
  // failed loads and natural completions must not auto-advance, and the
  // host's change_track is the only source of queue movement.
  bool followRemote = false;

  // Set when a remote-controlled load failed (no stream URL available).
  String? lastFailedSongId;

  // Fired when a remote-controlled load fails (Listen Together guest).
  void Function(String songId)? onRemoteLoadFailed;

  // Listen Together guest lockout: when true, user-initiated transport
  // and queue mutations are ignored. Host-driven calls are wrapped in
  // runRemote() and bypass the guard.
  bool hostControlsPlayback = false;
  bool _remoteApplying = false;

  /// Runs a host-driven mutation with the guest lockout bypassed.
  Future<T> runRemote<T>(Future<T> Function() action) async {
    _remoteApplying = true;
    try {
      return await action();
    } finally {
      _remoteApplying = false;
    }
  }

  bool get _lockoutActive => hostControlsPlayback && !_remoteApplying;

  // Fired after a locally-initiated seek (Listen Together host broadcast
  // hooks in here; guests ignore it via their own guard).
  void Function(Duration position)? onLocalSeek;

  // Timestamp of the last USER-driven transport action.
  DateTime _lastTransportActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, VideoStreamResult> _urlCache = {};
  final Set<String> _staleStreamIds = {};

  // ═════════════════════════════════════════════
  // PLAYBACK ERRORS — UI surfacing (PlaybackError port). Published
  // when the 5-attempt load loop exhausts. The queue still auto-
  // advances when it can (halted=false); when it cannot (halted=true)
  // playback has actually stopped and the UI should show the retry
  // card.
  // ═════════════════════════════════════════════

  final _playbackErrorController =
  StreamController<PlaybackFailure>.broadcast();

  /// Load failures, newest last. Skips carry halted=false; stops carry
  /// halted=true.
  Stream<PlaybackFailure> get playbackErrorStream =>
      _playbackErrorController.stream;

  Song? _failedSong;
  int _failedIndex = -1;

  void _publishPlaybackFailure(Song song, int index, Object error,
      {required bool halted}) {
    _failedSong = song;
    _failedIndex = index;
    if (_playbackErrorController.isClosed) return;
    _playbackErrorController.add(PlaybackFailure(
      songId: song.id,
      title: song.title,
      rawMessage: error.toString(),
      halted: halted,
      code: _errorCodeOf(error),
    ));
  }

  /// just_audio surfaces platform errors with a numeric code; duck-typed
  /// here so no compile-time dependency on the exception class name.
  int? _errorCodeOf(Object e) {
    try {
      final c = (e as dynamic).code;
      if (c is int) return c;
    } catch (_) {}
    return null;
  }

  /// True when [e] indicates the resolved URL ITSELF is dead —
  /// 410 Gone (expired signed URL) or 403 Forbidden. Retrying the same
  /// URL can never succeed; every cache layer must be busted so the
  /// next attempt resolves fresh. Matches both the buffered source's
  /// "Buffered download failed: HTTP 410" and ExoPlayer's
  /// "Response code: 410" shapes.
  static final _deadUrlRe = RegExp(r'(?:HTTP|Response code:) ?(410|403)');
  static bool _isDefinitiveStreamDeath(Object e) =>
      _deadUrlRe.hasMatch(e.toString());

  /// Re-attempts the last failed song (Retry on the error card):
  /// plays it in place when still in the queue, else as a
  /// single-song queue.
  Future<void> retryFailedSong() async {
    if (_lockoutActive) return;
    final song = _failedSong;
    if (song == null) return;
    _markTransportAction();
    final index = _failedIndex;
    if (index >= 0 &&
        index < _queue.length &&
        _queue[index].id == song.id) {
      await _playIndex(index);
    } else {
      await setQueue([song], startIndex: 0);
    }
  }

  // ═════════════════════════════════════════════
  // STRICT SOURCE POLICY — resolve non-JioSaavn songs to proper
  // zen-catalog songs (JioSaavn 320kbps / YTMusic song) before
  // playing. The whole queue is resolved ahead in the background, so
  // no raw YouTube entries (16:9 thumbnails, video-only sources) stay
  // in the queue.
  // ═════════════════════════════════════════════

  bool _strictSources = true;
  bool _queueResolving = false;

  // Origin video ids: when a raw YouTube song is swapped for a
  // resolved catalog song, its original video id is kept here so the
  // artist page can still resolve the REAL uploader channel via
  // oEmbed (the resolved song's own id points at the catalog version,
  // not at the video the user actually picked).
  final Map<String, String> _originVideoIds = {};

  /// The original YouTube video id a queue song was resolved from
  /// (strict source policy), or null when it was never swapped.
  String? originalVideoIdFor(String songId) => _originVideoIds[songId];

  void setStrictSources(bool enabled) {
    _strictSources = enabled;
  }

  /// Resolves [song] to a proper zen-catalog song when needed, swaps
  /// it into the queue at [index], and returns the song to play.
  Future<Song> _resolveSongSource(Song song, int index) async {
    if (followRemote || song.isFromJiosaavn || storage.getOfflineMode()) {
      return song;
    }
    if (!_strictSources) return song;

    final resolved = await SongSourceResolver.instance.resolve(song);
    if (resolved == null) return song;

    // Preserve the origin video id so the artist page can still show
    // the REAL uploader channel of the video the user picked.
    if (resolved.id != song.id) {
      _originVideoIds[resolved.id] = song.id;
    }

    if (index >= 0 && index < _queue.length && _queue[index].id == song.id) {
      _queue[index] = resolved;
      queue.add(_queue.map(_toMediaItem).toList());
    }
    return resolved;
  }

  /// Resolves the songs ahead of the current one in the background.
  Future<void> _resolveQueueAhead() async {
    if (_queueResolving || followRemote || !_strictSources) return;
    _queueResolving = true;
    try {
      for (var i = 0; i < _queue.length; i++) {
        if (i == _currentIndex) continue; // resolved by _playIndex
        final s = _queue[i];
        if (s.isFromJiosaavn) continue;
        final resolved = await SongSourceResolver.instance.resolve(s);
        if (resolved != null && i < _queue.length && _queue[i].id == s.id) {
          if (resolved.id != s.id) {
            _originVideoIds[resolved.id] = s.id;
          }
          _queue[i] = resolved;
          queue.add(_queue.map(_toMediaItem).toList());
        }
      }
    } finally {
      _queueResolving = false;
    }
  }

  // ═════════════════════════════════════════════
  // CROSSFADE — second hidden player, real audio overlap.
  // ═════════════════════════════════════════════

  bool _crossfadeEnabled = false;
  int _crossfadeSeconds = 4;

  AudioPlayer? _xfade;
  bool _xfadeInProgress = false;
  int _xfadeTargetIndex = -1;
  Timer? _xfadeRamp;
  Timer? _xfadeTick;
  Song? _xfadeSong;

  // Crossfade state broadcast for the UI (status chip). Every change
  // to _xfadeInProgress goes through _setCrossfadeInProgress so the
  // stream always mirrors the field.
  final _crossfadeStateController = StreamController<bool>.broadcast();

  /// True while two tracks are actually overlapping in a crossfade.
  Stream<bool> get crossfadeStream => _crossfadeStateController.stream;

  void _setCrossfadeInProgress(bool v) {
    if (_xfadeInProgress == v) return;
    _xfadeInProgress = v;
    if (!_crossfadeStateController.isClosed) {
      _crossfadeStateController.add(v);
    }
  }

  void applyCrossfadeSettings({required bool enabled, required int seconds}) {
    _crossfadeEnabled = enabled;
    _crossfadeSeconds = seconds.clamp(1, 12);
    if (!enabled) _abortCrossfade();
  }

  bool get _crossfadeAllowed {
    if (!_crossfadeEnabled || _xfadeInProgress) return false;
    if (_isRadioMode || followRemote || _lockoutActive) return false;
    if (_repeatMode == AudioServiceRepeatMode.one) return false;
    if (_sleepAtEndOfSong) return false;
    if (_queue.isEmpty) return false;
    if (_player.processingState != ProcessingState.ready) return false;
    if (!_player.playing) return false;
    return _nextCrossfadeIndex() != null;
  }

  int? _nextCrossfadeIndex() {
    if (_currentIndex + 1 < _queue.length) return _currentIndex + 1;
    if (_repeatMode == AudioServiceRepeatMode.all && _queue.isNotEmpty) {
      return 0;
    }
    return null;
  }

  void _startCrossfadeMonitor() {
    _xfadeTick?.cancel();
    _xfadeTick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _crossfadeTick();
    });
  }

  Future<void> _crossfadeTick() async {
    if (!_crossfadeAllowed) return;
    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    final remaining = duration - _player.position;
    final fade = Duration(seconds: _crossfadeSeconds);
    if (remaining <= Duration.zero || remaining > fade) return;
    await _triggerCrossfade();
  }

  Future<void> _triggerCrossfade() async {
    final targetIndex = _nextCrossfadeIndex();
    if (targetIndex == null) return;
    final generation = _loadGeneration;
    _setCrossfadeInProgress(true);
    _xfadeTargetIndex = targetIndex;
    try {
      // Resolve first, so the fade plays the proper song version.
      final nextSong =
      await _resolveSongSource(_queue[targetIndex], targetIndex);
      if (generation != _loadGeneration) {
        _setCrossfadeInProgress(false);
        return;
      }
      _xfadeSong = nextSong;
      final stream = await _getStreamUrl(nextSong);
      if (generation != _loadGeneration) {
        _setCrossfadeInProgress(false);
        return;
      }

      final xf = _xfade ??= AudioPlayer(handleInterruptions: false);
      await xf.setUrl(
        stream.url,
        headers: stream.headers.isNotEmpty ? stream.headers : null,
      );
      if (generation != _loadGeneration) {
        _setCrossfadeInProgress(false);
        await xf.stop();
        return;
      }
      await xf.setVolume(0);
      await xf.play();

      final fade = Duration(seconds: _crossfadeSeconds);
      final started = DateTime.now();
      const step = Duration(milliseconds: 50);
      _xfadeRamp?.cancel();
      _xfadeRamp = Timer.periodic(step, (t) {
        if (generation != _loadGeneration || !_xfadeInProgress) {
          t.cancel();
          return;
        }
        final p = DateTime.now().difference(started).inMilliseconds /
            fade.inMilliseconds;
        final clamped = p.clamp(0.0, 1.0);
        _player.setVolume(1.0 - clamped);
        xf.setVolume(clamped);
        if (p >= 1.0) t.cancel();
      });
    } catch (e) {
      print('Crossfade failed: $e');
      _setCrossfadeInProgress(false);
      _player.setVolume(1.0);
      await _disposeXfade();
    }
  }

  /// The old track completed while a crossfade was running — adopt the
  /// incoming track on the primary player.
  Future<void> _adoptCrossfadedTrack() async {
    final xf = _xfade;
    if (xf != null) {
      try {
        await xf.pause();
      } catch (_) {}
    }
    final adoptedPos = xf?.position ?? Duration.zero;

    final song = _xfadeSong;
    final index = _xfadeTargetIndex;
    _setCrossfadeInProgress(false);
    _xfadeRamp?.cancel();
    _xfadeRamp = null;

    VideoStreamResult? url;
    if (song != null) {
      try {
        url = await _getStreamUrl(song);
      } catch (_) {}
    }
    if (url == null ||
        song == null ||
        index < 0 ||
        index >= _queue.length) {
      _player.setVolume(1.0);
      await _disposeXfade();
      return;
    }

    _currentIndex = index;
    mediaItem.add(_toMediaItem(song));
    _broadcastAudioQuality(song, url);

    try {
      await _player.setUrl(
        url.url,
        headers: url.headers.isNotEmpty ? url.headers : null,
        tag: _toMediaItem(song),
      );
      await _player.seek(adoptedPos);
      await _player.setVolume(1.0);
      await play();
      lastFailedSongId = null;
      _staleStreamIds.remove(song.id);
      listeningStatsService.handlePlayerPlaying(true,
          currentSong: songToStatsMap(song));
      await storage.savePlayedSong(song);
      await _saveCurrentSession();
    } catch (e) {
      print('Crossfade adopt failed: $e');
      _player.setVolume(1.0);
    } finally {
      try {
        await xf?.stop();
        await xf?.setVolume(0);
      } catch (_) {}
      _prefetchNext();
    }
  }

  Future<void> _abortCrossfade() async {
    if (!_xfadeInProgress) return;
    _setCrossfadeInProgress(false);
    _xfadeRamp?.cancel();
    _xfadeRamp = null;
    _player.setVolume(1.0);
    await _disposeXfade();
  }

  Future<void> _disposeXfade() async {
    final xf = _xfade;
    _xfade = null;
    if (xf == null) return;
    try {
      await xf.stop();
      await xf.dispose();
    } catch (_) {}
  }

  // ═════════════════════════════════════════════
  // BUFFERED STREAMING
  // ═════════════════════════════════════════════

  bool _bufferedStreaming = true;

  void setBufferedStreaming(bool enabled) {
    _bufferedStreaming = enabled;
  }

  Future<int> _contentLength(VideoStreamResult stream) async {
    try {
      final resp = await http.head(Uri.parse(stream.url),
          headers: stream.headers);
      final len = resp.headers['content-length'];
      return int.tryParse(len ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ═════════════════════════════════════════════

  Timer? _saveTimer;
  void setAudioQualitySetting(String quality) {
    _yt.setAudioQualitySetting(quality);
  }
  // Sleep timer state.
  Timer? _sleepTick;
  DateTime? _sleepEndAt;
  bool _sleepAtEndOfSong = false;
  final _sleepTimerController = StreamController<Duration?>.broadcast();

  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;

  // Radio (live stream) mode.
  bool _isRadioMode = false;
  final _radioStationController = StreamController<String?>.broadcast();

  bool get isRadioMode => _isRadioMode;

  Stream<String?> get radioStationStream => _radioStationController.stream;

  final _audioQualityController =
  StreamController<Map<String, String?>>.broadcast();

  Stream<Map<String, String?>> get audioQualityStream =>
      _audioQualityController.stream;

  ZenAudioHandler({required this.storage}) {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object e, StackTrace st) {
        print('ZenAudioHandler playback error: $e');
      },
    );

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackCompleted();
    });

    _saveTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _saveCurrentSession(),
    );

    _yt.setAudioQualitySetting(storage.getAudioQuality());

    _restoreLastSession();
    unawaited(_restoreEqualizer());
    _startCrossfadeMonitor();
  }

  void _markTransportAction() {
    _lastTransportActionAt = DateTime.now();
  }

  // ═════════════════════════════════════════════
  // SLEEP TIMER
  // ═════════════════════════════════════════════

  void _notifySleepTimer(Duration? remaining) {
    if (!_sleepTimerController.isClosed) _sleepTimerController.add(remaining);
  }

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepEndAt = DateTime.now().add(duration);
    _notifySleepTimer(duration);
    _sleepTick = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _sleepEndAt;
      if (end == null) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _sleepEndAt = null;
        _notifySleepTimer(null);
        pause();
      } else {
        _notifySleepTimer(remaining);
      }
    });
  }

  void setSleepTimerEndOfSong() {
    cancelSleepTimer();
    _sleepAtEndOfSong = true;
    _notifySleepTimer(Duration.zero);
  }

  void cancelSleepTimer() {
    _sleepTick?.cancel();
    _sleepTick = null;
    _sleepEndAt = null;
    _sleepAtEndOfSong = false;
    _notifySleepTimer(null);
  }

  // ═════════════════════════════════════════════
  // RADIO (live stream mode)
  // ═════════════════════════════════════════════

  Future<bool> playRadioStream({
    required String id,
    required String name,
    required String streamUrl,
    String? image,
    String? genre,
  }) async {
    try {
      _markTransportAction();
      _loadGeneration++;
      await _abortCrossfade();
      await _player.stop();
      _isRadioMode = true;
      _radioStationController.add(name);

      mediaItem.add(MediaItem(
        id: id,
        title: name,
        artist: genre ?? 'Radio',
        artUri: (image != null && image.isNotEmpty) ? Uri.parse(image) : null,
      ));

      await _player.setUrl(streamUrl);
      await play();
      return true;
    } catch (e) {
      print('Radio play failed: $e');
      _isRadioMode = false;
      _radioStationController.add(null);
      return false;
    }
  }

  Future<void> _exitRadioMode() async {
    if (!_isRadioMode) return;
    _isRadioMode = false;
    _radioStationController.add(null);
    await _player.stop();
  }

  // ═════════════════════════════════════════════
  // EXTENSION (raw stream playback — live-source mode)
  // ═════════════════════════════════════════════

  Future<bool> playStream({
    required String url,
    Map<String, String> headers = const {},
    required String id,
    required String title,
    String? artist,
    String? image,
  }) async {
    try {
      _markTransportAction();
      _loadGeneration++;
      await _abortCrossfade();
      await _player.stop();
      _isRadioMode = true;
      _radioStationController.add(null);

      mediaItem.add(MediaItem(
        id: id,
        title: title,
        artist: artist ?? 'Extension',
        artUri: (image != null && image.isNotEmpty) ? Uri.parse(image) : null,
      ));

      await _player.setUrl(url, headers: headers.isNotEmpty ? headers : null);
      await play();
      return true;
    } catch (e) {
      print('Extension stream play failed: $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════
  // TRACK END / REPEAT (handler-owned)
  // ═════════════════════════════════════════════

  Future<void> _onTrackCompleted() async {
    if (DateTime.now().difference(_lastTransportActionAt) <
        const Duration(milliseconds: 800)) {
      return;
    }
    if (_isRadioMode) return;

    if (_xfadeInProgress) {
      await _adoptCrossfadedTrack();
      return;
    }

    listeningStatsService.finishListeningSession(countCurrentTick: true);

    if (followRemote) return;

    if (_sleepAtEndOfSong) {
      _sleepAtEndOfSong = false;
      _notifySleepTimer(null);
      await pause();
      return;
    }
    if (_repeatMode == AudioServiceRepeatMode.one) {
      await _player.seek(Duration.zero);
      await play();
      return;
    }
    if (_currentIndex + 1 < _queue.length) {
      await _playIndex(_currentIndex + 1);
      _prefetchNext();
      return;
    }
    if (_repeatMode == AudioServiceRepeatMode.all && _queue.isNotEmpty) {
      await _playIndex(0);
      _prefetchNext();
    }
  }

  // ═════════════════════════════════════════════
  // EQUALIZER
  // ═════════════════════════════════════════════

  Future<AndroidEqualizerParameters?> getEqualizerParameters() async {
    try {
      return await _equalizer.parameters;
    } catch (e) {
      print('getEqualizerParameters failed: $e');
      return null;
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    try {
      await _equalizer.setEnabled(enabled);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('eq_enabled', enabled);
    } catch (_) {}
  }

  Future<void> setEqualizerBandGain(int index, double gain) async {
    try {
      final params = await _equalizer.parameters;
      if (index < 0 || index >= params.bands.length) return;
      await params.bands[index].setGain(gain);
    } catch (_) {}
  }

  Future<void> resetEqualizerBands() async {
    try {
      final params = await _equalizer.parameters;
      for (final band in params.bands) {
        await band.setGain(0);
      }
    } catch (_) {}
  }

  Future<void> _restoreEqualizer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('eq_enabled') ?? false) {
        await _equalizer.setEnabled(true);
      }
    } catch (_) {}
  }

  // ═════════════════════════════════════════════
  // PERSISTENCE
  // ═════════════════════════════════════════════

  Future<void> _restoreLastSession() async {
    final session = storage.getLastSession();
    if (session == null || session.queue.isEmpty) return;

    print('🔄 Restoring last session: ${session.queue.length} songs');

    _queue = List<Song>.from(session.queue);
    _currentIndex = session.currentIndex.clamp(0, _queue.length - 1);
    queue.add(_queue.map(_toMediaItem).toList());
    mediaItem.add(_toMediaItem(_queue[_currentIndex]));

    try {
      final song = _queue[_currentIndex];
      final stream = await _getStreamUrl(song);
      await _player.setUrl(
        stream.url,
        headers: stream.headers.isNotEmpty ? stream.headers : null,
        tag: _toMediaItem(song),
      );
      await _player.seek(session.position);
      print('🔄 Restored at ${session.position.inSeconds}s');
    } catch (e) {
      print('Failed to restore session: $e');
    }
  }

  Future<void> _saveCurrentSession() async {
    if (_queue.isEmpty) return;
    try {
      await storage.saveLastSession(
        queue: _queue,
        currentIndex: _currentIndex,
        position: _player.position,
      );
    } catch (_) {}
  }

  // ═════════════════════════════════════════════
  // PUBLIC API
  // ═════════════════════════════════════════════

  /// Inserts [song] at [index] — position-faithful undo for queue
  /// removal (swipe/clear). Index is clamped; the current index shifts
  /// when the insertion lands at or before it (mirror of
  /// removeFromQueue's decrement).
  Future<void> insertQueueAt(int index, Song song) async {
    if (_lockoutActive) return;
    final i = index.clamp(0, _queue.length);
    _queue.insert(i, song);
    if (i <= _currentIndex) _currentIndex++;
    queue.add(_queue.map(_toMediaItem).toList());
    await _prefetchUrl(song);
  }

  void seedStreamUrl(String id, String url, Map<String, String> headers) {
    _staleStreamIds.remove(id);
    _urlCache[id] = VideoStreamResult(url, headers);
    unawaited(storage.cacheStream(id, url, headers));
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_lockoutActive) return;
    _markTransportAction();
    await _abortCrossfade();
    await _exitRadioMode();
    _queue = List<Song>.from(songs);
    _currentIndex = startIndex;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playIndex(_currentIndex);
    _prefetchNext();
  }

  Future<void> startRadio(Song seedSong) async {
    if (_lockoutActive) return;
    _markTransportAction();
    await _abortCrossfade();
    await _exitRadioMode();
    _queue = [seedSong];
    _currentIndex = 0;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playIndex(0);
    await storage.savePlayedSong(seedSong);
    _loadRadioFill(seedSong);
  }

  Future<void> addToQueue(Song song) async {
    if (_lockoutActive) return;
    _queue.add(song);
    queue.add(_queue.map(_toMediaItem).toList());
    await _prefetchUrl(song);
  }

  Future<void> playNext(Song song) async {
    if (_lockoutActive) return;
    final insertAt = _currentIndex + 1;
    _queue.insert(insertAt, song);
    queue.add(_queue.map(_toMediaItem).toList());
    await _prefetchUrl(song);
  }

  Future<void> removeFromQueue(int index) async {
    if (_lockoutActive) return;
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) _currentIndex--;
    queue.add(_queue.map(_toMediaItem).toList());
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_lockoutActive) return;
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex > _queue.length) {
      return;
    }
    var insertAt = newIndex;
    if (insertAt > oldIndex) insertAt--;

    final moved = _queue.removeAt(oldIndex);
    _queue.insert(insertAt, moved);

    if (oldIndex == _currentIndex) {
      _currentIndex = insertAt;
    } else if (oldIndex < _currentIndex && insertAt >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && insertAt <= _currentIndex) {
      _currentIndex++;
    }

    queue.add(_queue.map(_toMediaItem).toList());
  }

  Future<void> clearQueue() async {
    if (_lockoutActive) return;
    await _abortCrossfade();
    _queue.clear();
    _urlCache.clear();
    _currentIndex = 0;
    await _player.stop();
    await storage.clearLastSession();
    _audioQualityController.add({'type': null, 'bitrate': null});
    queue.add(const []);
  }

  Future<List<Song>> getRelatedForUI(Song song) async {
    try {
      return await _yt.getRelatedSongs(song);
    } catch (e) {
      return [];
    }
  }

  // ═════════════════════════════════════════════
  // CORE PLAYBACK
  // ═════════════════════════════════════════════

  Future<VideoStreamResult> _getStreamUrl(Song song) async {
    final localPath = await DownloadsService().localPath(song.id);
    if (localPath != null) {
      final result = VideoStreamResult('file://$localPath', const {});
      _urlCache[song.id] = result;
      return result;
    }

    final mem = _urlCache[song.id];
    if (mem != null) return mem;

    final cached = _staleStreamIds.contains(song.id)
        ? null
        : storage.getCachedStream(song.id);
    if (cached != null) {
      print('💾 URL cache hit for ${song.title}');
      final result = VideoStreamResult(cached.url, cached.headers);
      _urlCache[song.id] = result;
      return result;
    }

    if (followRemote && song.id.length != 11) {
      throw Exception('no stream hint for ${song.id}');
    }

    final result = await _yt.getAudioStreamUrl(song);
    _urlCache[song.id] = result;
    await storage.cacheStream(song.id, result.url, result.headers);
    return result;
  }


  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final generation = ++_loadGeneration;
    await _abortCrossfade();
    _currentIndex = index;
    // STRICT SOURCE POLICY: resolve to a proper zen-catalog song
    // (JioSaavn / YTMusic) BEFORE the player shows it, so the artwork
    // is the 1:1 album art and the stream is the high-quality version.
    final song = await _resolveSongSource(_queue[index], index);
    final mediaItem = _toMediaItem(song);
    this.mediaItem.add(mediaItem);

    try {
      await _player.stop();
    } catch (_) {}
    await _player.setVolume(1.0);

    // Resolve the rest of the queue in the background — no raw YouTube
    // entries (16:9 thumbnails) remain behind the playing song.
    unawaited(_resolveQueueAhead());

    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (generation != _loadGeneration) return;
      try {
        final stream = await _getStreamUrl(song);
        _broadcastAudioQuality(song, stream);
        if (generation != _loadGeneration) return;

        if (_bufferedStreaming && !stream.url.startsWith('file://')) {
          // ignore: experimental_member_use
          final source = BufferedStreamAudioSource(
            songId: song.id,
            streamUrl: stream.url,
            headers: stream.headers,
            totalBytes: await _contentLength(stream),
          );
          if (generation != _loadGeneration) return;
          try {
            await _player.setAudioSource(source);
          } on Exception {
            await _player.setUrl(
              stream.url,
              headers: stream.headers.isNotEmpty ? stream.headers : null,
              tag: mediaItem,
            );
          }
        } else {
          await _player.setUrl(
            stream.url,
            headers: stream.headers.isNotEmpty ? stream.headers : null,
            tag: mediaItem,
          );
        }

        if (generation != _loadGeneration) return;
        await play();
        lastFailedSongId = null;
        _staleStreamIds.remove(song.id);
        listeningStatsService.handlePlayerPlaying(true,
            currentSong: songToStatsMap(song));
        await storage.savePlayedSong(song);
        await _saveCurrentSession();
        return;
      } catch (e) {
        if (generation != _loadGeneration) return;
        if (_isDefinitiveStreamDeath(e)) {
          // 410 Gone / 403 Forbidden: this exact URL can never work
          // again. Bust the memory cache AND stop trusting the
          // persisted cache immediately — the old loop re-served the
          // same dead URL from Hive on attempts 2 and 3 before
          // distrusting it at attempt 4. The fresh resolve below
          // also overwrites the stale persisted entry.
          _urlCache.remove(song.id);
          _staleStreamIds.add(song.id);
          print('🪦 Dead URL for ${song.title} — caches busted, '
              'next attempt resolves fresh');
        } else {
          // Non-definitive failure (timeout, flake): drop the memory
          // copy so the retry re-resolves; the persisted cache stops
          // being trusted after three failed attempts.
          _urlCache.remove(song.id);
          if (attempt >= 4) _staleStreamIds.add(song.id);
        }
        if (attempt < maxAttempts) {
          print('🔁 Load attempt $attempt/$maxAttempts failed for '
              '${song.title} — retrying');
          await Future.delayed(Duration(milliseconds: 120 * attempt));
          continue;
        }
        print('Failed to play ${song.title} after $maxAttempts attempts: $e');
        if (generation == _loadGeneration) {
          if (followRemote) {
            lastFailedSongId = song.id;
            final cb = onRemoteLoadFailed;
            if (cb != null) cb(song.id);
            return;
          }
          final canAdvance = _currentIndex + 1 < _queue.length;
          // Surface the failure to the UI: halted=true means playback
          // actually stopped (error card); halted=false = skip snackbar.
          _publishPlaybackFailure(song, index, e, halted: !canAdvance);
          if (canAdvance) {
            await _playIndex(_currentIndex + 1);
          }
          // else: playback halted — the error UI is responsible now.
        }
      }
    }
  }

  Future<void> _prefetchNext() async {
    if (_currentIndex + 1 < _queue.length) {
      await _prefetchUrl(_queue[_currentIndex + 1]);
    }
    if (!followRemote && _currentIndex >= _queue.length - 2) {
      _appendRelatedSongs();
    }
  }

  Future<void> _prefetchUrl(Song song) async {
    if (await DownloadsService().localPath(song.id) != null) {
      return;
    }
    if (_urlCache.containsKey(song.id)) return;
    final cached = storage.getCachedStream(song.id);
    if (cached != null) {
      _urlCache[song.id] = VideoStreamResult(cached.url, cached.headers);
      return;
    }
    if (followRemote) return;
    try {
      final result = await _yt.getAudioStreamUrl(song);
      _urlCache[song.id] = result;
      await storage.cacheStream(song.id, result.url, result.headers);
    } catch (_) {}
  }

  // ═════════════════════════════════════════════
  // RADIO FILL
  // ═════════════════════════════════════════════

  Future<void> _loadRadioFill(Song seedSong) async {
    if (_isAppending) return;
    _isAppending = true;
    try {
      final related = await _yt.getRelatedSongs(seedSong);
      final existingIds = _queue.map((s) => s.id).toSet();
      final newSongs = related
          .where((s) => !existingIds.contains(s.id))
          .take(20)
          .toList();
      if (newSongs.isEmpty) {
        print('📻 Radio fill: no related songs for "${seedSong.title}"');
        return;
      }
      _queue.addAll(newSongs);
      queue.add(_queue.map(_toMediaItem).toList());
      if (_queue.length > 1) await _prefetchUrl(_queue[1]);
      print('📻 Radio queued ${newSongs.length}');
    } catch (e) {
      print('Radio fill failed: $e');
    } finally {
      _isAppending = false;
    }
  }

  Future<void> _appendRelatedSongs() async {
    if (_isAppending || _queue.isEmpty) return;
    _isAppending = true;
    try {
      final seed = _queue.last;
      final related = await _yt.getRelatedSongs(seed);
      final existingIds = _queue.map((s) => s.id).toSet();
      final newSongs = related
          .where((s) => !existingIds.contains(s.id))
          .take(15)
          .toList();
      if (newSongs.isEmpty) return;
      _queue.addAll(newSongs);
      queue.add(_queue.map(_toMediaItem).toList());
    } catch (e) {
      print('Auto-append failed: $e');
    } finally {
      _isAppending = false;
    }
  }

  // ═════════════════════════════════════════════
  // AUDIO SERVICE OVERRIDES
  // ═════════════════════════════════════════════

  @override
  Future<void> play() async {
    if (_lockoutActive) return;
    await _player.play();
    if (_xfadeInProgress && _xfade != null) {
      try {
        await _xfade!.play();
      } catch (_) {}
    }
  }

  @override
  Future<void> pause() async {
    if (_lockoutActive) return;
    listeningStatsService.handlePlayerPlaying(false);
    await _player.pause();
    if (_xfadeInProgress && _xfade != null) {
      try {
        await _xfade!.pause();
      } catch (_) {}
    }
    await _saveCurrentSession();
    await listeningStatsService.flush();
  }

  @override
  Future<void> stop() async {
    await _abortCrossfade();
    await _saveCurrentSession();
    await listeningStatsService.flush();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_lockoutActive) return;
    await _abortCrossfade();
    await _player.seek(position);
    final cb = onLocalSeek;
    if (cb != null) cb(position);
  }

  Future<bool> seekSafe(Duration position) async {
    if (_lockoutActive) return false;
    if (_player.processingState != ProcessingState.ready) return false;
    try {
      await _player.seek(position);
      final cb = onLocalSeek;
      if (cb != null) cb(position);
      return true;
    } catch (e) {
      print('seekSafe failed: $e');
      return false;
    }
  }

  @override
  Future<void> skipToNext() async {
    if (_lockoutActive) return;
    _markTransportAction();
    await _abortCrossfade();
    if (_isRadioMode) return;
    if (_currentIndex + 1 < _queue.length) {
      await _playIndex(_currentIndex + 1);
    } else if (_repeatMode == AudioServiceRepeatMode.all &&
        _queue.isNotEmpty) {
      await _playIndex(0);
    }
    _prefetchNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_lockoutActive) return;
    _markTransportAction();
    await _abortCrossfade();
    if (_isRadioMode) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      await _playIndex(_currentIndex - 1);
    } else {
      await _player.seek(Duration.zero);
      await play();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_lockoutActive) return;
    _markTransportAction();
    await _abortCrossfade();
    if (index < 0 || index >= _queue.length) return;
    await _playIndex(index);
    _prefetchNext();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    if (mode == AudioServiceShuffleMode.all &&
        _currentIndex + 1 < _queue.length) {
      final upcoming = _queue.sublist(_currentIndex + 1);
      upcoming.shuffle();
      _queue = [
        ..._queue.sublist(0, _currentIndex + 1),
        ...upcoming,
      ];
      queue.add(_queue.map(_toMediaItem).toList());
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    _repeatMode = mode;
    await _player.setLoopMode(LoopMode.off);
  }

  // ═════════════════════════════════════════════
  // HELPERS
  // ═════════════════════════════════════════════

  MediaItem _toMediaItem(Song s) => MediaItem(
    id: s.id,
    title: s.title,
    artist: s.artist,
    artUri: Uri.parse(s.thumbnail),
    duration: s.duration,
  );

  void _broadcastAudioQuality(Song song, VideoStreamResult stream) {
    final type = song.isFromJiosaavn ? 'AAC' : (stream.audioType ?? 'AUDIO');
    final bitrate = song.isFromJiosaavn
        ? '320'
        : (stream.bitrateKbps?.toString() ?? '');
    _audioQualityController.add({'type': type, 'bitrate': bitrate});
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.setShuffleMode,
          MediaAction.setRepeatMode,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  Stream<Song?> get currentSongStream =>
      _player.currentIndexStream.map((_) => currentSong);

  List<Song> get queueSongs => List.unmodifiable(_queue);

  int get currentQueueIndex => _currentIndex;

  Song? get currentSong {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return null;
    return _queue[_currentIndex];
  }

  Stream<List<Song>> get queueStream =>
      Stream.periodic(const Duration(milliseconds: 500))
          .map((_) => List<Song>.unmodifiable(_queue));

  @override
  Future<void> onTaskRemoved() async {
    _saveTimer?.cancel();
    await _saveCurrentSession();
    await listeningStatsService.flush();
    await stop();
    await super.onTaskRemoved();
  }
}