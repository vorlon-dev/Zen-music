// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import 'package:zenmusic/desktop/services/jam_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class JamPlaybackSync {
  JamPlaybackSync._();

  static final JamPlaybackSync instance = JamPlaybackSync._();

  static const int _driftSeekThresholdMs = 1500;
  static const int _maxLatencyCompensationMs = 3000;
  static const int _quietSameTrackMs = 800;
  static const int _quietTrackChangeMs = 2500;
  static const int _quietAfterBroadcastMs = 800;
  static const int _quietAfterBroadcastTrackMs = 1000;

  static final RegExp _ytId = RegExp(r'^[a-zA-Z0-9_-]{11}$');

  JamController? _controller;
  MediaPlayer? _player;
  StreamSubscription<JamRemote>? _remoteSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  VoidCallback? _songListener;
  VoidCallback? _queueListener;
  Timer? _queueDebounce;
  bool _started = false;

  int _quietUntil = 0;
  String? _lastTrack;
  bool? _lastPlaying;
  int _lastPosition = 0;
  int _lastWall = 0;
  String? _lastQueueKey;
  bool _applyingRemote = false;

  /// Wires the bridge to the app's singletons. Safe to call once; both
  /// entry points (mobile + desktop mains) call it right after MediaPlayer
  /// is registered, so sync survives navigation and runs app-lifetime.
  void start({required JamController controller, required MediaPlayer player}) {
    if (_started) return;
    _started = true;
    _controller = controller;
    _player = player;

    _remoteSub = controller.remote.listen(_apply);
    controller.addListener(_onSessionChanged);

    final audio = player.player;
    _positionSub = audio.positionStream.listen((_) => _broadcast());
    _playingSub = audio.playingStream.listen((_) {
      _broadcast();
      _publishQueue(immediate: false);
    });
    _songListener = () {
      _broadcast();
      // Song advance moves the index: the shared "up next" follows.
      _publishQueue(immediate: false);
    };
    player.currentSongNotifier.addListener(_songListener!);
    _queueListener = () => _publishQueue(immediate: false);
    player.queueSnapshot.addListener(_queueListener!);
  }

  /// A room join/leave resets the broadcast history; becoming the main host
  /// mid-session republishes the queue (both reference behaviours).
  void _onSessionChanged() {
    final jam = _controller;
    if (jam == null) return;
    if (jam.state.phase != JamPhase.active) {
      _lastTrack = null;
      _lastPlaying = null;
      _lastPosition = 0;
      _lastWall = 0;
      _quietUntil = 0;
      _lastQueueKey = null;
      _wasMainHost = false;
      return;
    }
    final now = jam.state.phase == JamPhase.active && jam.state.isMainHost;
    if (now && !_wasMainHost) {
      _lastQueueKey = null;
      _publishQueue(immediate: true);
    }
    _wasMainHost = now;
  }

  bool _wasMainHost = false;


  Future<void> _apply(JamRemote event) async {
    final jam = _controller;
    final mp = _player;
    if (jam == null || mp == null) return;
    final session = jam.state;
    if (session.phase != JamPhase.active) return;
    final from = switch (event) {
      JamRemotePlay(:final fromUserId) => fromUserId,
      JamRemotePause(:final fromUserId) => fromUserId,
      JamRemoteSeek(:final fromUserId) => fromUserId,
      JamRemoteTrack(:final fromUserId) => fromUserId,
      JamRemoteFull() => null,
    };
    // Echo loop suppression: ignore events that originated from ourselves.
    if (from != null && from == session.userId) return;

    final audio = mp.player;
    final local = _localSnapshot();
    switch (event) {
      case JamRemoteTrack(:final track, :final isPlaying, :final positionMs):
        await _change(track, isPlaying, positionMs);
      case JamRemoteFull(
          :final track,
          :final isPlaying,
          :final positionMs,
          :final serverTimeMs,
        ):
        if (track == null) return;
        await _change(track, isPlaying, positionMs + _latency(serverTimeMs));
      case JamRemotePlay(:final positionMs, :final serverTimeMs):
        final target = positionMs + _latency(serverTimeMs);
        _quietUntil = _now() + _quietSameTrackMs;
        if (local == null && session.track != null) {
          await _change(session.track!, true, target);
          return;
        }
        if (local != null) {
          if ((local.positionMs - target).abs() > _driftSeekThresholdMs) {
            await audio.seek(Duration(milliseconds: target));
          }
          if (!local.playing && audio.processingState == ProcessingState.ready) {
            await audio.play();
          }
        }
      case JamRemotePause(:final positionMs):
        _quietUntil = _now() + _quietSameTrackMs;
        if (local != null) {
          if (local.playing) await audio.pause();
          if ((local.positionMs - positionMs).abs() > _driftSeekThresholdMs) {
            await audio.seek(Duration(milliseconds: positionMs));
          }
        }
      case JamRemoteSeek(:final positionMs):
        _quietUntil = _now() + _quietSameTrackMs;
        if (local != null &&
            (local.positionMs - positionMs).abs() > _driftSeekThresholdMs) {
          await audio.seek(Duration(milliseconds: positionMs));
        }
    }
  }

  ({String id, String title, String artist, bool playing, int positionMs,
          bool buffering})?
      _localSnapshot() {
    final mp = _player;
    if (mp == null) return null;
    final song = mp.currentSongNotifier.value;
    final audio = mp.player;
    if (song == null) return null;
    final buffering = audio.processingState == ProcessingState.loading ||
        audio.processingState == ProcessingState.buffering;
    return (
      id: song.id,
      title: song.title,
      artist: song.artist ?? '',
      playing: audio.playing,
      positionMs: audio.position.inMilliseconds,
      buffering: buffering,
    );
  }

  Future<void> _change(JamTrack track, bool isPlaying, int positionMs) async {
    final mp = _player;
    if (mp == null) return;
    final audio = mp.player;
    final current = mp.currentSongNotifier.value;
    final currentArtist = current?.artist ?? '';
    final same = current != null &&
        ((current.id.isNotEmpty && current.id == track.id) ||
            (current.title.toLowerCase() == track.title.toLowerCase() &&
                (currentArtist.isEmpty ||
                    track.artist.isEmpty ||
                    currentArtist
                        .toLowerCase()
                        .startsWith(track.artist.toLowerCase()))));
    _quietUntil = _now() + (same ? _quietSameTrackMs : _quietTrackChangeMs);
    _lastTrack = track.id.isNotEmpty ? track.id : track.title;
    _lastPlaying = isPlaying;
    _lastPosition = positionMs;
    _applyingRemote = true;
    try {
      if (!same) {
        final song = await _songFromTrack(track);
        if (song == null) return;
        await mp.playSong(song);
        if (positionMs > 800) {
          await audio.seek(Duration(milliseconds: positionMs));
        }
        if (!isPlaying) await audio.pause();
        return;
      }
      if ((audio.position.inMilliseconds - positionMs).abs() >
          _driftSeekThresholdMs) {
        await audio.seek(Duration(milliseconds: positionMs));
      }
      if (isPlaying && !audio.playing) {
        await audio.play();
      } else if (!isPlaying && audio.playing) {
        await audio.pause();
      }
    } finally {
      _applyingRemote = false;
    }
  }

  /// Room track → the app's song map. Non-YouTube ids are resolved with a
  /// YTMusic title search (the reference lets its player layer do this).
  Future<Map<String, dynamic>?> _songFromTrack(JamTrack t) async {
    String id = t.id;
    if (!_ytId.hasMatch(id)) {
      id = await _searchFirstVideoId('${t.title} ${t.artist}'.trim()) ?? '';
    }
    if (!_ytId.hasMatch(id)) {
      print('[jam] cannot resolve room track "${t.title}" locally');
      return null;
    }
    return {
      'videoId': id,
      'title': t.title,
      'artists': [
        {'name': t.artist}
      ],
      if (t.album != null && t.album!.isNotEmpty)
        'album': {'name': t.album},
      if (t.artworkUrl != null && t.artworkUrl!.isNotEmpty)
        'thumbnails': [
          {'url': t.artworkUrl}
        ],
    };
  }


  void _broadcast() {
    if (_applyingRemote) return;
    final jam = _controller;
    final mp = _player;
    if (jam == null || mp == null) return;
    final session = jam.state;
    if (session.phase != JamPhase.active) return;
    if (!session.canControl) return;
    final now = _now();
    if (now < _quietUntil) return;
    final song = mp.currentSongNotifier.value;
    if (song == null) return;
    final audio = mp.player;
    final playing = audio.playing;
    final position = audio.position.inMilliseconds;
    final buffering = audio.processingState == ProcessingState.loading ||
        audio.processingState == ProcessingState.buffering;
    final key = song.id.isNotEmpty ? song.id : song.title;

    if (key != _lastTrack) {
      _lastTrack = key;
      _lastPlaying = playing;
      _lastPosition = position;
      _lastWall = now;
      _quietUntil = now + _quietAfterBroadcastTrackMs;
      jam.broadcastTrack(
        JamTrack(
          id: song.id,
          title: song.title,
          artist: song.artist ?? '',
          album: song.album,
          artworkUrl: song.artUri?.toString(),
          durationMs: audio.duration?.inMilliseconds ?? 0,
        ),
        positionMs: position,
        isPlaying: playing,
      );
      return;
    }
    if (playing != _lastPlaying) {
      // A buffering stall is not a pause (reference guard).
      if (!playing && buffering) return;
      _lastPlaying = playing;
      _lastPosition = position;
      _lastWall = now;
      _quietUntil = now + _quietAfterBroadcastMs;
      if (playing) {
        jam.broadcastPlay(position);
      } else {
        jam.broadcastPause(position);
      }
      return;
    }
    // Seek detection: position far from the wall-clock expectation soon
    // after the last sample = the user dragged the slider / hit ±10 s.
    final wall = now - _lastWall;
    final expected = _lastPosition + (playing ? wall : 0);
    if ((position - expected).abs() > 2000 && wall < 4000) {
      _lastPosition = position;
      _lastWall = now;
      _quietUntil = now + _quietAfterBroadcastMs;
      jam.broadcastSeek(position);
      return;
    }
    _lastPosition = position;
    _lastWall = now;
  }

  /// Publishes the admin's upcoming queue (debounced, only when changed).
  void _publishQueue({required bool immediate}) {
    final jam = _controller;
    final mp = _player;
    if (jam == null || mp == null) return;
    final session = jam.state;
    if (session.phase != JamPhase.active || !session.isMainHost) return;
    _queueDebounce?.cancel();
    void send() {
      final snapshot = mp.queueSnapshot.value;
      final start = (mp.currentIndex.value ?? -1) + 1;
      final upcoming = start >= 0 && start < snapshot.length
          ? snapshot.sublist(start)
          : const <Map<String, dynamic>>[];
      final tracks = [
        for (final s in upcoming.take(5))
          JamTrack(
            id: '${s['videoId'] ?? ''}',
            title: '${s['title'] ?? ''}',
            artist: (s['artists'] as List?)?.isNotEmpty == true
                ? '${(((s['artists'] as List).first as Map)['name']) ?? ''}'
                : '',
            album: (s['album'] as Map?)?['name']?.toString(),
            artworkUrl: (s['thumbnails'] as List?)?.isNotEmpty == true
                ? '${(((s['thumbnails'] as List).first as Map)['url']) ?? ''}'
                : null,
          ),
      ];
      final key = tracks.map((t) => t.id).join('|');
      if (key == _lastQueueKey) return;
      _lastQueueKey = key;
      jam.broadcastQueue(tracks);
    }

    if (immediate) {
      send();
    } else {
      _queueDebounce = Timer(const Duration(milliseconds: 600), send);
    }
  }

  Future<String?> _searchFirstVideoId(String query) async {
    try {
      final result = await GetIt.I<YTMusic>().search(query, filter: 'songs');
      final sections = result['sections'] as List?;
      final contents = sections?.isNotEmpty == true
          ? sections!.first['contents'] as List?
          : null;
      if (contents != null && contents.isNotEmpty) {
        final song = Map<String, dynamic>.from(contents.first as Map);
        final id = song['videoId']?.toString();
        return (id != null && id.isNotEmpty) ? id : null;
      }
    } catch (e) {
      print('[jam] track resolve failed: $e');
    }
    return null;
  }

  int _latency(int serverTimeMs) {
    if (serverTimeMs <= 0) return 0;
    final delta = _now() - serverTimeMs;
    if (delta <= 0) return 0;
    return math.min(delta, _maxLatencyCompensationMs);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  void dispose() {
    _remoteSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    final mp = _player;
    if (mp != null && _songListener != null) {
      mp.currentSongNotifier.removeListener(_songListener!);
    }
    if (mp != null && _queueListener != null) {
      mp.queueSnapshot.removeListener(_queueListener!);
    }
    _controller?.removeListener(_onSessionChanged);
    _queueDebounce?.cancel();
  }
}
