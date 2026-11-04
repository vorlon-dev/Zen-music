// ZenMusic · vorlon-dev
//
// Dart side of web/yt_bridge.js (YouTube IFrame Player API). Web only.

import 'dart:convert';
import 'dart:js_interop';

@JS('zenYT.load')
external void _load(JSString id);
@JS('zenYT.play')
external void _play();
@JS('zenYT.pause')
external void _pause();
@JS('zenYT.stop')
external void _stop();
@JS('zenYT.seek')
external void _seek(JSNumber seconds);
@JS('zenYT.setVolume')
external void _setVolume(JSNumber percent);
@JS('zenYT.setRate')
external void _setRate(JSNumber rate);
@JS('zenYT.state')
external JSString _state();

/// Snapshot of the embedded YouTube player.
class YtState {
  const YtState({
    required this.state,
    required this.position,
    required this.duration,
    required this.error,
  });

  /// YouTube player state: 0 ended, 1 playing, 2 paused, 3 buffering.
  final int state;
  final Duration position;
  final Duration duration;
  final int error;

  bool get playing => state == 1 || state == 3;
  bool get ended => state == 0;

  static YtState parse(String raw) {
    final m = jsonDecode(raw);
    num n(String k) => m is Map && m[k] is num ? m[k] as num : 0;
    return YtState(
      state: n('s').toInt(),
      position: Duration(milliseconds: (n('t') * 1000).round()),
      duration: Duration(milliseconds: (n('d') * 1000).round()),
      error: n('e').toInt(),
    );
  }
}

class YtBridge {
  const YtBridge._();

  static void load(String videoId) => _load(videoId.toJS);
  static void play() => _play();
  static void pause() => _pause();
  static void stop() => _stop();
  static void seek(Duration to) => _seek((to.inMilliseconds / 1000).toJS);
  static void setVolume(double v) => _setVolume((v * 100).toJS);
  static void setRate(double r) => _setRate(r.toJS);

  static YtState state() => YtState.parse(_state().toDart);
}
