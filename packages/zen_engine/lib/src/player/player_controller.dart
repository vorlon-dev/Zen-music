import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:audio_service/audio_service.dart';
import 'package:hive/hive.dart';

import '../models/song_model.dart';
import '../lossless/lossless_engine.dart';
import '../ytmusic/yt_engine.dart';
import '../ytmusic/yt_audio_stream_server.dart';
import '../ytmusic/potoken_service.dart';
import '../jiosaavn/jiosaavn_service.dart';
import '../downloads/download_engine.dart';
import 'player_state.dart';

/// Complete, headless Playback & Queue Controller for ZenEngine.
class ZenPlayerController extends ChangeNotifier {
  ZenPlayerController({
    ja.AudioPlayer? audioPlayer,
    LosslessEngine? lossless,
    YouTubeEngine? youtube,
    JioSaavnService? jioSaavn,
    DownloadEngine? downloads,
    PoTokenService? poTokenService,
  })  : _player = audioPlayer ?? ja.AudioPlayer(),
        _lossless = lossless ?? LosslessEngine(),
        youtube = youtube ?? YouTubeEngine(),
        _jioSaavn = jioSaavn ?? JioSaavnService(),
        _downloads = downloads ?? DownloadEngine(),
        poTokenService = poTokenService ?? PoTokenService() {
    _initSubscriptions();
  }

  final ja.AudioPlayer _player;
  final LosslessEngine _lossless;
  final YouTubeEngine youtube;
  final JioSaavnService _jioSaavn;
  final DownloadEngine _downloads;
  final PoTokenService poTokenService;

  ZenPlayerState _state = const ZenPlayerState();
  ZenPlayerState get state => _state;

  final StreamController<ZenPlayerState> _stateController =
      StreamController<ZenPlayerState>.broadcast();
  Stream<ZenPlayerState> get stateStream => _stateController.stream;

  List<ZenSong> _queue = [];
  int? _currentIndex;

  ja.AudioPlayer get audioPlayer => _player;
  List<ZenSong> get queue => List.unmodifiable(_queue);
  ZenSong? get currentSong => _state.currentSong;
  int? get currentIndex => _currentIndex;
  bool get isPlaying => _state.isPlaying;

  static const String _sessionBox = 'ZEN_SESSION';

  void _initSubscriptions() {
    _player.playerStateStream.listen((ps) {
      PlayerPlaybackStatus status;
      if (ps.processingState == ja.ProcessingState.loading ||
          ps.processingState == ja.ProcessingState.buffering) {
        status = PlayerPlaybackStatus.loading;
      } else if (ps.processingState == ja.ProcessingState.ready) {
        status = ps.playing
            ? PlayerPlaybackStatus.playing
            : PlayerPlaybackStatus.paused;
      } else if (ps.processingState == ja.ProcessingState.completed) {
        status = PlayerPlaybackStatus.completed;
        _onTrackCompleted();
      } else {
        status = PlayerPlaybackStatus.idle;
      }
      _updateState(_state.copyWith(status: status));
    });

    _player.positionStream.listen((pos) {
      _updateState(_state.copyWith(
        positionState: _state.positionState.copyWith(position: pos),
      ));
    });

    _player.bufferedPositionStream.listen((buf) {
      _updateState(_state.copyWith(
        positionState: _state.positionState.copyWith(buffered: buf),
      ));
    });

    _player.durationStream.listen((dur) {
      _updateState(_state.copyWith(
        positionState: _state.positionState.copyWith(total: dur ?? Duration.zero),
      ));
    });
  }

  void _updateState(ZenPlayerState newState) {
    _state = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  /// Play a single song immediately
  Future<void> playSong(ZenSong song) async {
    _queue = [song];
    _currentIndex = 0;
    _updateState(_state.copyWith(
      currentSong: song,
      currentIndex: 0,
      queue: _queue,
      status: PlayerPlaybackStatus.loading,
    ));

    await _loadAndPlay(song);
  }

  /// Play a playlist or song list from a specific index
  Future<void> playQueue(List<ZenSong> songs, {int initialIndex = 0}) async {
    if (songs.isEmpty) return;
    _queue = List.from(songs);
    _currentIndex = initialIndex.clamp(0, songs.length - 1);
    final song = _queue[_currentIndex!];

    _updateState(_state.copyWith(
      currentSong: song,
      currentIndex: _currentIndex,
      queue: _queue,
      status: PlayerPlaybackStatus.loading,
    ));

    await _loadAndPlay(song);
  }

  /// Add a song next in queue
  void playNext(ZenSong song) {
    if (_queue.isEmpty || _currentIndex == null) {
      playSong(song);
      return;
    }
    _queue.insert(_currentIndex! + 1, song);
    _updateState(_state.copyWith(queue: _queue));
  }

  /// Add a song to the end of queue
  void addToQueue(ZenSong song) {
    if (_queue.isEmpty) {
      playSong(song);
      return;
    }
    _queue.add(song);
    _updateState(_state.copyWith(queue: _queue));
  }

  /// Remove a song at given index
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex != null && index < _currentIndex!) {
      _currentIndex = _currentIndex! - 1;
    }
    _updateState(_state.copyWith(queue: _queue, currentIndex: _currentIndex));
  }

  Future<void> _loadAndPlay(ZenSong song) async {
    try {
      final source = await _resolveAudioSource(song);
      await _player.stop();
      await _player.setAudioSource(source);
      await _player.play();
      _saveSession();
    } catch (e) {
      _updateState(_state.copyWith(
        status: PlayerPlaybackStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<ja.AudioSource> _resolveAudioSource(ZenSong song) async {
    final mediaItem = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      duration: song.duration,
      artUri: song.thumbnailUrl != null ? Uri.tryParse(song.thumbnailUrl!) : null,
      extras: song.raw,
    );

    // 1. Check offline downloaded file
    final localPath = _downloads.getDownloadedPath(song.id);
    if (localPath != null && File(localPath).existsSync()) {
      return ja.AudioSource.file(localPath, tag: mediaItem);
    }

    // 2. JioSaavn direct stream
    if (song.source == ZenSongSource.jiosaavn) {
      String? saavnUrl = song.streamUrl;
      saavnUrl ??= await _jioSaavn.fetchStreamUrl(song.id);
      if (saavnUrl != null && saavnUrl.isNotEmpty) {
        return ja.AudioSource.uri(Uri.parse(saavnUrl), tag: mediaItem);
      }
    }

    // 3. Lossless Stream Resolver
    final losslessUrl = await _lossless.resolveStreamUrl(song.id);
    if (losslessUrl != null && losslessUrl.isNotEmpty) {
      return ja.AudioSource.uri(Uri.parse(losslessUrl), tag: mediaItem);
    }

    // 4. Safe YouTube stream proxy through local server (guarantees no 403 HTTP error)
    final serverUrl = await ZenAudioStreamServer.instance.start();
    final proxyUri = Uri.parse('$serverUrl?id=${song.id}');
    return ja.AudioSource.uri(proxyUri, tag: mediaItem);
  }

  Future<void> pause() async {
    await _player.pause();
    _saveSession();
  }

  Future<void> resume() async {
    await _player.play();
    _saveSession();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _updateState(_state.copyWith(
      clearCurrentSong: true,
      clearCurrentIndex: true,
      status: PlayerPlaybackStatus.idle,
      positionState: const PlayerPositionState(),
    ));
    _clearSession();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _saveSession();
  }

  Future<void> skipNext() async {
    if (_queue.isEmpty || _currentIndex == null) return;
    if (_currentIndex! + 1 < _queue.length) {
      _currentIndex = _currentIndex! + 1;
      final nextSong = _queue[_currentIndex!];
      _updateState(_state.copyWith(
        currentSong: nextSong,
        currentIndex: _currentIndex,
        status: PlayerPlaybackStatus.loading,
      ));
      await _loadAndPlay(nextSong);
    } else if (_state.loopMode == LoopMode.all) {
      _currentIndex = 0;
      final nextSong = _queue[0];
      _updateState(_state.copyWith(
        currentSong: nextSong,
        currentIndex: 0,
        status: PlayerPlaybackStatus.loading,
      ));
      await _loadAndPlay(nextSong);
    }
  }

  Future<void> skipPrevious() async {
    if (_queue.isEmpty || _currentIndex == null) return;
    if (_currentIndex! > 0) {
      _currentIndex = _currentIndex! - 1;
      final prevSong = _queue[_currentIndex!];
      _updateState(_state.copyWith(
        currentSong: prevSong,
        currentIndex: _currentIndex,
        status: PlayerPlaybackStatus.loading,
      ));
      await _loadAndPlay(prevSong);
    }
  }

  void setLoopMode(LoopMode mode) {
    _updateState(_state.copyWith(loopMode: mode));
  }

  void toggleShuffle() {
    final next = !_state.shuffleMode;
    if (next && _queue.isNotEmpty && _currentIndex != null) {
      final current = _queue[_currentIndex!];
      final others = List<ZenSong>.from(_queue)..removeAt(_currentIndex!);
      others.shuffle();
      _queue = [current, ...others];
      _currentIndex = 0;
    }
    _updateState(_state.copyWith(shuffleMode: next, queue: _queue, currentIndex: _currentIndex));
  }

  void _onTrackCompleted() {
    if (_state.loopMode == LoopMode.one && _state.currentSong != null) {
      _player.seek(Duration.zero);
      _player.play();
    } else {
      skipNext();
    }
  }

  Future<void> _saveSession() async {
    try {
      if (!Hive.isBoxOpen(_sessionBox)) return;
      final box = Hive.box(_sessionBox);
      box.put('QUEUE', _queue.map((s) => s.toMap()).toList());
      box.put('INDEX', _currentIndex ?? 0);
      box.put('POSITION', _state.positionState.position.inMilliseconds);
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    try {
      if (Hive.isBoxOpen(_sessionBox)) {
        await Hive.box(_sessionBox).clear();
      }
    } catch (_) {}
  }

  /// Restore previous playback session
  Future<void> restoreSession() async {
    try {
      if (!Hive.isBoxOpen(_sessionBox)) {
        await Hive.openBox(_sessionBox);
      }
      final box = Hive.box(_sessionBox);
      final rawQueue = box.get('QUEUE') as List?;
      if (rawQueue == null || rawQueue.isEmpty) return;

      final restoredSongs = rawQueue
          .map((m) => ZenSong.fromYouTube(Map<String, dynamic>.from(m as Map)))
          .toList();
      final index = (box.get('INDEX') as int? ?? 0).clamp(0, restoredSongs.length - 1);
      final posMs = box.get('POSITION') as int? ?? 0;

      _queue = restoredSongs;
      _currentIndex = index;

      final song = _queue[index];
      _updateState(_state.copyWith(
        currentSong: song,
        currentIndex: index,
        queue: _queue,
        status: PlayerPlaybackStatus.paused,
        positionState: PlayerPositionState(
          position: Duration(milliseconds: posMs),
          total: song.duration,
        ),
      ));
    } catch (_) {}
  }

  @override
  void dispose() {
    _stateController.close();
    _player.dispose();
    super.dispose();
  }
}
