import 'package:flutter/services.dart';

/// Bridge to the native Spotify engine (librespot via JNI).
class SpotifyBridge {
  static const _channel = MethodChannel('zen/spotify');
  static const _events = EventChannel('zen/spotify_events');

  static Stream<dynamic>? _eventStream;

  /// Events: {type: sessionReady|spircReady|spircFailed|loginSuccess|
  ///          loginFailed|trackChange|position|playingStatus|...}
  static Stream<dynamic> get eventStream =>
      _eventStream ??= _events.receiveBroadcastStream();

  /// Boot chain: libInit → Session. Readiness arrives via [eventStream].
  /// If login is required, call [startLogin] after sessionReady.
  static Future<bool> initialize({
    required String clientId,
    required String clientSecret,
  }) async {
    try {
      return await _channel.invokeMethod('initialize', {
        'clientId': clientId,
        'clientSecret': clientSecret,
      });
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> hasCachedCredentials() => _invoke('hasCachedCredentials');

  /// Opens the Spotify login page in the browser and starts the local
  /// callback catcher (127.0.0.1:5588). On success a `loginSuccess`
  /// event fires, then sessionReady → spircReady. Credentials persist.
  static Future<String?> startLogin() async {
    try {
      return await _channel.invokeMethod('startLogin');
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> logout() => _invoke('logout');

  static Future<bool> load(String uri, {String? playingTrackUri}) =>
      _invoke('load', {'uri': uri, if (playingTrackUri != null) 'playingTrack': playingTrackUri});

  static Future<bool> setQueue(List<String> uris, {String? playingTrackUri}) =>
      _invoke('setQueue', {
        'uris': uris,
        if (playingTrackUri != null) 'playingTrack': playingTrackUri,
      });

  static Future<bool> addToQueue(String uri) => _invoke('addToQueue', {'uri': uri});

  static Future<bool> play() => _invoke('play');
  static Future<bool> pause() => _invoke('pause');
  static Future<bool> playPause() => _invoke('playPause');
  static Future<bool> next() => _invoke('next');
  static Future<bool> previous() => _invoke('previous');

  static Future<bool> seekTo(int positionMs) =>
      _invoke('seekTo', {'positionMs': positionMs});

  static Future<bool> setShuffle(bool enabled) =>
      _invoke('shuffle', {'enabled': enabled});

  static Future<bool> setRepeat({required bool repeat, bool track = false}) =>
      _invoke('repeat', {'repeat': repeat, 'repeatTrack': track});

  static Future<bool> setVolume(int volume) =>
      _invoke('setVolume', {'volume': volume});

  static Future<String?> nextTracks() async {
    try {
      return await _channel.invokeMethod('nextTracks');
    } on PlatformException {
      return null;
    }
  }

  static Future<String?> previousTracks() async {
    try {
      return await _channel.invokeMethod('previousTracks');
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod(method, args);
    } on PlatformException {
      return false;
    }
  }
}