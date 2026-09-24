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

  // Timestamp of the last USER-driven transport action (skip, queue jump,
  // new queue). The natural-completion handler ignores completions that
  // land right after a manual action — otherwise a manual skip AND the
  // completion event both advance, skipping a song.
  DateTime _lastTransportActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<String, VideoStreamResult> _urlCache = {};
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

  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) async {
    _markTransportAction();
    await _exitRadioMode();
    _queue = List<Song>.from(songs);
    _currentIndex = startIndex;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playIndex(_currentIndex);
    _prefetchNext();
  }

  Future<void> startRadio(Song seedSong) async {
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
    _queue.add(song);
    queue.add(_queue.map(_toMediaItem).toList());
    await _prefetchUrl(song);
  }

  Future<void> playNext(Song song) async {
    final insertAt = _currentIndex + 1;
    _queue.insert(insertAt, song);
    queue.add(_queue.map(_toMediaItem).toList());
    await _prefetchUrl(song);
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (index < _currentIndex) _currentIndex--;
    queue.add(_queue.map(_toMediaItem).toList());
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
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

    final cached = storage.getCachedStream(song.id);
    if (cached != null) {
      print('💾 URL cache hit for ${song.title}');
      final result = VideoStreamResult(cached.url, cached.headers);
      _urlCache[song.id] = result;
      return result;
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

    try {
      final stream = await _getStreamUrl(song);
      _broadcastAudioQuality(song, stream);
      // A newer skip started while we were resolving — abandon this
      // load so the wrong song never wins the race.
      if (generation != _loadGeneration) return;
      await _player.setUrl(
        stream.url,
        headers: stream.headers.isNotEmpty ? stream.headers : null,
        tag: mediaItem,
      );
      if (generation != _loadGeneration) return;
      await play();
      listeningStatsService.handlePlayerPlaying(true,
          currentSong: songToStatsMap(song));
      await storage.savePlayedSong(song);
      await _saveCurrentSession();
    } catch (e) {
      print('Failed to play ${song.title}: $e');
      if (generation == _loadGeneration && _currentIndex + 1 < _queue.length) {
        await _playIndex(_currentIndex + 1);
      }
    }
  }

  Future<void> _prefetchNext() async {
    if (_currentIndex + 1 < _queue.length) {
      await _prefetchUrl(_queue[_currentIndex + 1]);
    }
    if (_currentIndex >= _queue.length - 2) {
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() async {
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
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
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