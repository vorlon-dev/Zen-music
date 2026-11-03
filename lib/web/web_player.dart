// ZenMusic · vorlon-dev
//
// Playback state for the web player: queue, current track, synced lyrics.

import 'dart:async';

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

  List<WebSong> queue = const [];
  int index = -1;
  bool playing = false;
  bool loading = false;
  String? error;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  List<LyricLine> lyrics = const [];
  int lyricIndex = -1;
  int _token = 0;

  WebSong? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrevious => index > 0;

  /// Replaces the queue with [songs] and starts at [start].
  Future<void> playQueue(List<WebSong> songs, int start) async {
    queue = List<WebSong>.unmodifiable(songs);
    await _load(start);
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

    unawaited(_api.lyrics(queue[i]).then((l) {
      if (token != _token) return;
      lyrics = l;
      notifyListeners();
    }));

    try {
      await _audio.setUrl(queue[i].streamUrl);
      if (token != _token) return;
      loading = false;
      notifyListeners();
      unawaited(_audio.play());
    } catch (_) {
      if (token != _token) return;
      loading = false;
      error = 'Could not play this track.';
      notifyListeners();
    }
  }

  void _onState(PlayerState s) {
    playing = s.playing;
    if (s.processingState == ProcessingState.completed) {
      if (hasNext) {
        unawaited(next());
      } else {
        playing = false;
      }
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (_audio.playing) {
      await _audio.pause();
    } else {
      await _audio.play();
    }
  }

  Future<void> next() => hasNext ? _load(index + 1) : Future.value();

  Future<void> previous() async {
    if (position > const Duration(seconds: 3) || !hasPrevious) {
      await _audio.seek(Duration.zero);
    } else {
      await _load(index - 1);
    }
  }

  Future<void> seek(Duration to) => _audio.seek(to);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _audio.dispose();
    _api.close();
    super.dispose();
  }
}
