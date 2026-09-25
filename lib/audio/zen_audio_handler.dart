import 'dart:async';
import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/downloads_service.dart';
import '../services/listening_stats_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';

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
  // Listen Together clears it on the next successful load and uses it to
  // retry once the host's shared URL arrives.
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

  // Timestamp of the last USER-driven transport action (skip, queue jump,
  // new queue). The natural-completion handler ignores completions that
  // land right after a manual action — otherwise a manual skip AND the
  // completion event both advance, skipping a song.
  DateTime _lastTransportActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, VideoStreamResult> _urlCache = {};
  // Songs whose cached URL failed to load — bypassed until a fresh
  // resolve or a new host-seeded URL overwrites them.
  final Set<String> _staleStreamIds = {};
  Timer? _saveTimer;
  void setAudioQualitySetting(String quality) {
    _yt.setAudioQualitySetting(quality);
  }
  // Sleep timer state.
  Timer? _sleepTick;
  DateTime? _sleepEndAt;
  bool _sleepAtEndOfSong = false;
  final _sleepTimerController = StreamController<Duration?>.broadcast();

  /// null = off · Duration.zero = end-of-song armed · >0 = countdown
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;

  // Radio (live stream) mode.
  bool _isRadioMode = false;
  final _radioStationController = StreamController<String?>.broadcast();

  bool get isRadioMode => _isRadioMode;

  /// Name of the currently playing radio station (null = not radio).
  Stream<String?> get radioStationStream => _radioStationController.stream;

  // Quality/type badge stream.
  final _audioQualityController =
  StreamController<Map<String, String?>>.broadcast();

  /// {'type': 'OPUS'|'AAC'|..., 'bitrate': '128'} — nulled when queue clears.
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
      _loadGeneration++; // abandon any in-flight music load
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

  /// Plays a direct stream (url + headers) outside the music queue —
  /// used by the extension engine until extension playback is merged
  /// into the queue system.
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
      await _player.stop();
      _isRadioMode = true; // live-source mode: no queue advance
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
    // Guard 1: a manual transport action just happened — the completed
    // event is stale (the user already moved on). Advancing here would
    // double-skip.
    if (DateTime.now().difference(_lastTransportActionAt) <
        const Duration(milliseconds: 800)) {
      return;
    }
    // Guard 2: radio/extension streams don't auto-advance.
    if (_isRadioMode) return;

    listeningStatsService.finishListeningSession(countCurrentTick: true);

    // Guard 3: remote-controlled queue (Listen Together guest) — the host
    // broadcasts the next change_track; local advance would fight it.
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
  // EQUALIZER (Android system EQ via just_audio)
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

  /// Listen Together: guests preload the host's resolved stream here —
  /// straight into the memory cache (plus persistent cache) so the next
  /// load is instant, with no Hive round-trip on the load path.
  void seedStreamUrl(String id, String url, Map<String, String> headers) {
    _staleStreamIds.remove(id);
    _urlCache[id] = VideoStreamResult(url, headers);
    unawaited(storage.cacheStream(id, url, headers));
  }

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    if (_lockoutActive) return;
    _markTransportAction();
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
    // Tier 0: offline download — zero network.
    final localPath = await DownloadsService().localPath(song.id);
    if (localPath != null) {
      final result = VideoStreamResult('file://$localPath', const {});
      _urlCache[song.id] = result;
      return result;
    }

    final mem = _urlCache[song.id];
    if (mem != null) return mem;

    // Stale ids skip the persistent cache — its URL already failed once.
    final cached = _staleStreamIds.contains(song.id)
        ? null
        : storage.getCachedStream(song.id);
    if (cached != null) {
      print('💾 URL cache hit for ${song.title}');
      final result = VideoStreamResult(cached.url, cached.headers);
      _urlCache[song.id] = result;
      return result;
    }

    // Remote-controlled queue: songs rebuilt from room metadata carry no
    // source info — without the host's shared URL they cannot resolve.
    // Fail fast instead of burning the whole extractor chain.
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
    _currentIndex = index;
    final song = _queue[index];
    final mediaItem = _toMediaItem(song);
    this.mediaItem.add(mediaItem);

    // Kill the previous track's audio immediately. If setUrl failed later,
    // the old song used to keep playing — never fall back to it.
    try {
      await _player.stop();
    } catch (_) {}

    // Up to 5 attempts: transient network hiccups retry the SAME URL,
    // late attempts force a fresh resolve (caches bypassed) so a dead
    // cached URL can never strand us on the previous track.
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (generation != _loadGeneration) return;
      try {
        VideoStreamResult stream;
        if (attempt == 1) {
          stream = await _getStreamUrl(song);
        } else {
          // Fresh attempt: drop the memoized result; from attempt 4 on,
          // also bypass the persistent cache for this song.
          _urlCache.remove(song.id);
          if (attempt >= 4) _staleStreamIds.add(song.id);
          stream = await _getStreamUrl(song);
        }
        _broadcastAudioQuality(song, stream);
        if (generation != _loadGeneration) return;
        await _player.setUrl(
          stream.url,
          headers: stream.headers.isNotEmpty ? stream.headers : null,
          tag: mediaItem,
        );
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
        if (attempt < maxAttempts) {
          print('🔁 Load attempt $attempt/$maxAttempts failed for '
              '${song.title} — retrying');
          await Future.delayed(Duration(milliseconds: 120 * attempt));
          continue;
        }
        print('Failed to play ${song.title} after $maxAttempts attempts: $e');
        if (generation == _loadGeneration) {
          // Remote-controlled queue: never self-advance on failure — the
          // host decides what plays next. Flag it so Listen Together can
          // retry when a fresh stream URL becomes available.
          if (followRemote) {
            lastFailedSongId = song.id;
            final cb = onRemoteLoadFailed;
            if (cb != null) cb(song.id);
            return;
          }
          if (_currentIndex + 1 < _queue.length) {
            await _playIndex(_currentIndex + 1);
          }
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
      // Downloaded — playback will resolve locally; nothing to prefetch.
      return;
    }
    if (_urlCache.containsKey(song.id)) return;
    final cached = storage.getCachedStream(song.id);
    if (cached != null) {
      _urlCache[song.id] = VideoStreamResult(cached.url, cached.headers);
      return;
    }
    if (followRemote) return; // host shares resolved URLs; don't re-resolve
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
  }

  @override
  Future<void> pause() async {
    if (_lockoutActive) return;
    listeningStatsService.handlePlayerPlaying(false);
    await _player.pause();
    await _saveCurrentSession();
    await listeningStatsService.flush();
  }

  @override
  Future<void> stop() async {
    await _saveCurrentSession();
    await listeningStatsService.flush();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_lockoutActive) return;
    await _player.seek(position);
    final cb = onLocalSeek;
    if (cb != null) cb(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_lockoutActive) return;
    _markTransportAction();
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