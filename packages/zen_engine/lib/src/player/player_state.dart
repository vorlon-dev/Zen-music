import '../models/song_model.dart';

enum PlayerPlaybackStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  completed,
  error,
}

enum LoopMode {
  off,
  all,
  one,
}

class PlayerPositionState {
  final Duration position;
  final Duration buffered;
  final Duration total;

  const PlayerPositionState({
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.total = Duration.zero,
  });

  PlayerPositionState copyWith({
    Duration? position,
    Duration? buffered,
    Duration? total,
  }) {
    return PlayerPositionState(
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      total: total ?? this.total,
    );
  }
}

class ZenPlayerState {
  final ZenSong? currentSong;
  final int? currentIndex;
  final List<ZenSong> queue;
  final PlayerPlaybackStatus status;
  final PlayerPositionState positionState;
  final LoopMode loopMode;
  final bool shuffleMode;
  final String? errorMessage;

  const ZenPlayerState({
    this.currentSong,
    this.currentIndex,
    this.queue = const [],
    this.status = PlayerPlaybackStatus.idle,
    this.positionState = const PlayerPositionState(),
    this.loopMode = LoopMode.off,
    this.shuffleMode = false,
    this.errorMessage,
  });

  bool get isPlaying => status == PlayerPlaybackStatus.playing;
  bool get isLoading => status == PlayerPlaybackStatus.loading || status == PlayerPlaybackStatus.buffering;

  ZenPlayerState copyWith({
    ZenSong? currentSong,
    bool clearCurrentSong = false,
    int? currentIndex,
    bool clearCurrentIndex = false,
    List<ZenSong>? queue,
    PlayerPlaybackStatus? status,
    PlayerPositionState? positionState,
    LoopMode? loopMode,
    bool? shuffleMode,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ZenPlayerState(
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
      currentIndex: clearCurrentIndex ? null : (currentIndex ?? this.currentIndex),
      queue: queue ?? this.queue,
      status: status ?? this.status,
      positionState: positionState ?? this.positionState,
      loopMode: loopMode ?? this.loopMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
