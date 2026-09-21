import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
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

  final Map<String, String> _urlCache = {};
  Timer? _saveTimer;

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

    _restoreLastSession();
    unawaited(_restoreEqualizer());
  }

  // ═════════════════════════════════════════════
  // TRACK END / REPEAT (handler-owned — player loop modes are
  // useless here: the player always holds a single item)
  // ═════════════════════════════════════════════

  Future<void> _onTrackCompleted() async {
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
      final url = await _getStreamUrl(song);
      await _player.setUrl(url, tag: _toMediaItem(song));
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
    _queue = List<Song>.from(songs);
    _currentIndex = startIndex;
    queue.add(_queue.map(_toMediaItem).toList());
    await _playIndex(_currentIndex);
    _prefetchNext();
  }

  Future<void> startRadio(Song seedSong) async {
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

  Future<void> clearQueue() async {
    _queue.clear();
    _urlCache.clear();
    _currentIndex = 0;
    await _player.stop();
    await storage.clearLastSession();
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

  Future<String> _getStreamUrl(Song song) async {
    if (_urlCache.containsKey(song.id)) {
      return _urlCache[song.id]!;
    }

    final cached = storage.getCachedUrl(song.id);
    if (cached != null && cached.isNotEmpty) {
      print('💾 URL cache hit for ${song.title}');
      _urlCache[song.id] = cached;
      return cached;
    }

    final url = await _yt.getAudioStreamUrl(song);
    _urlCache[song.id] = url;
    await storage.cacheUrl(song.id, url);
    return url;
  }

  Future<void> _playIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final generation = ++_loadGeneration;
    _currentIndex = index;
    final song = _queue[index];
    final mediaItem = _toMediaItem(song);
    this.mediaItem.add(mediaItem);

    try {
      final url = await _getStreamUrl(song);
      // A newer skip started while we were resolving — abandon this
      // load so the wrong song never wins the race.
      if (generation != _loadGeneration) return;
      await _player.setUrl(url, tag: mediaItem);
      if (generation != _loadGeneration) return;
      await play();
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
    if (_urlCache.containsKey(song.id)) return;
    final cached = storage.getCachedUrl(song.id);
    if (cached != null && cached.isNotEmpty) {
      _urlCache[song.id] = cached;
      return;
    }
    try {
      final url = await _yt.getAudioStreamUrl(song);
      _urlCache[song.id] = url;
      await storage.cacheUrl(song.id, url);
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
      if (newSongs.isEmpty) return;
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
    await _player.pause();
    await _saveCurrentSession();
  }

  @override
  Future<void> stop() async {
    await _saveCurrentSession();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// Next: advance; wrap ONLY on repeat-all. Never jumps into
  /// radio-filled songs unexpectedly from a manual press.
  @override
  Future<void> skipToNext() async {
    if (_currentIndex + 1 < _queue.length) {
      await _playIndex(_currentIndex + 1);
    } else if (_repeatMode == AudioServiceRepeatMode.all &&
        _queue.isNotEmpty) {
      await _playIndex(0);
    }
    _prefetchNext();
  }

  /// Previous: restart if >3 s in, else step back. At the very start
  /// of the first song: restart — NEVER wrap into radio songs.
  @override
  Future<void> skipToPrevious() async {
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
    if (index < 0 || index >= _queue.length) return;
    await _playIndex(index);
    _prefetchNext();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode mode) async {
    // Shuffle the upcoming part of the queue (current song stays).
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
    // Loop modes are meaningless on a single-item player — repeat is
    // handled in _onTrackCompleted / skipToNext instead.
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
    await stop();
    await super.onTaskRemoved();
  }
}