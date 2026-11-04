// ZenMusic · vorlon-dev
//
// Playback state for the web player: queue, current track, synced lyrics,
// shuffle / repeat, volume, speed and a sleep timer.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:zenmusic/web/web_api.dart';
import 'package:zenmusic/web/web_models.dart';

class WebPlayer extends ChangeNotifier {
  WebPlayer(this._api) {
    _subs.add(_audio.playerStateStream.listen(_onState));
    _subs.add(_audio.positionStream.listen((p) {
      position = p;
      final i = activeLyricIndex(lyrics, p);
      if (i != lyricIndex) lyricIndex = i;
      notifyListeners();
    }));
    _subs.add(_audio.durationStream.listen((d) {
      if (d != null) {
        duration = d;
        notifyListeners();
      }
    }));
  }

  final WebApi _api;
  final AudioPlayer _audio = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  final Random _random = Random();

  /// Called each time a track starts (used for listening history).
  void Function(WebSong song)? onTrackStarted;

  List<WebSong> queue = const [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  String? error;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  List<LyricLine> lyrics = const [];
  int lyricIndex = -1;
  bool shuffle = false;
  WebRepeat repeat = WebRepeat.off;
  double volume = 1.0;
  double speed = 1.0;
  DateTime? sleepEndsAt;
  Timer? _sleepTimer;
  int _token = 0;

  WebSong? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;
  bool get hasNext => queue.length > 1 || index + 1 < queue.length;
  bool get hasPrevious => index > 0;

  /// Replaces the queue with [songs] and starts at [start].
  Future<void> playQueue(List<WebSong> songs, int start) async {
    if (songs.isEmpty) return;
    queue = List<WebSong>.unmodifiable(songs);
    await _load(start.clamp(0, songs.length - 1).toInt());
  }

  /// Plays [songs] in random order.
  Future<void> playShuffled(List<WebSong> songs) async {
    if (songs.isEmpty) return;
    shuffle = true;
    await playQueue(songs, _random.nextInt(songs.length));
  }

  /// Appends [song] without interrupting playback.
  void enqueue(WebSong song) {
    queue = List<WebSong>.unmodifiable([...queue, song]);
    if (index < 0) {
      unawaited(_load(0));
    } else {
      notifyListeners();
    }
  }

  /// Inserts [song] right after the current one.
  void playNext(WebSong song) {
    if (index < 0) {
      enqueue(song);
      return;
    }
    final list = List<WebSong>.of(queue)..insert(index + 1, song);
    queue = List<WebSong>.unmodifiable(list);
    notifyListeners();
  }

  void removeFromQueue(int i) {
    if (i < 0 || i >= queue.length || i == index) return;
    final list = List<WebSong>.of(queue)..removeAt(i);
    if (i < index) index -= 1;
    queue = List<WebSong>.unmodifiable(list);
    notifyListeners();
  }

  Future<void> jumpTo(int i) => _load(i);

  Future<void> _load(int i) async {
    if (i < 0 || i >= queue.length) return;
    final token = ++_token;
    index = i;
    loading = true;
    error = null;
    position = Duration.zero;
    duration = queue[i].duration;
    lyrics = const [];
    lyricIndex = -1;
    notifyListeners();

    final song = queue[i];
    onTrackStarted?.call(song);
    unawaited(_api.lyrics(song).then((l) {
      if (token != _token) return;
      lyrics = l;
      notifyListeners();
    }));

    var ok = await _tryUrl(song.streamUrl);
    if (!ok && token == _token) {
      // Saved links can expire; fetch a fresh one once.
      final fresh = await _api.song(song.id);
      if (fresh != null && token == _token) {
        final list = List<WebSong>.of(queue);
        if (i < list.length && list[i].id == song.id) {
          list[i] = fresh;
          queue = List<WebSong>.unmodifiable(list);
        }
        ok = await _tryUrl(fresh.streamUrl);
      }
    }
    if (token != _token) return;
    loading = false;
    if (ok) {
      unawaited(_audio.play());
    } else {
      error = 'Could not play this track.';
    }
    notifyListeners();
  }

  Future<bool> _tryUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      await _audio.setUrl(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onState(PlayerState s) {
    playing = s.playing;
    if (s.processingState == ProcessingState.completed) {
      unawaited(_onCompleted());
    }
    notifyListeners();
  }

  Future<void> _onCompleted() async {
    if (repeat == WebRepeat.one) {
      await _audio.seek(Duration.zero);
      await _audio.play();
      return;
    }
    if (shuffle && queue.length > 1) {
      await _load(_randomOther());
    } else if (index + 1 < queue.length) {
      await _load(index + 1);
    } else if (repeat == WebRepeat.all && queue.isNotEmpty) {
      await _load(0);
    } else {
      playing = false;
      notifyListeners();
    }
  }

  int _randomOther() {
    var n = _random.nextInt(queue.length);
    if (n == index) n = (n + 1) % queue.length;
    return n;
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    if (shuffle && queue.length > 1) {
      await _load(_randomOther());
    } else if (index + 1 < queue.length) {
      await _load(index + 1);
    } else if (repeat == WebRepeat.all) {
      await _load(0);
    }
  }

  Future<void> previous() async {
    if (position > const Duration(seconds: 3) || !hasPrevious) {
      await _audio.seek(Duration.zero);
    } else {
      await _load(index - 1);
    }
  }

  Future<void> seek(Duration to) => _audio.seek(to);

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = WebRepeat.values[(repeat.index + 1) % WebRepeat.values.length];
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0).toDouble();
    await _audio.setVolume(volume);
    notifyListeners();
  }

  Future<void> setSpeed(double v) async {
    speed = v;
    await _audio.setSpeed(v);
    notifyListeners();
  }

  /// Pauses playback after [after]; pass null to cancel.
  void setSleepTimer(Duration? after) {
    _sleepTimer?.cancel();
    if (after == null) {
      sleepEndsAt = null;
    } else {
      sleepEndsAt = DateTime.now().add(after);
      _sleepTimer = Timer(after, () {
        sleepEndsAt = null;
        unawaited(_audio.pause());
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _audio.dispose();
    _api.close();
    super.dispose();
  }
}
