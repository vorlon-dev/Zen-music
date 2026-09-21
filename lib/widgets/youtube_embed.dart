import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// ZenMusic — muted YouTube backdrop with a Dart ⇄ video bridge.
///
/// The player screen states WHAT should happen (videoId / playing /
/// positionStream); this widget makes the iframe obey. Audio
/// (just_audio) stays the single source of truth.
///
///   Dart → video : loadVideoById / play / pause / seekTo   (runJavaScript)
///   video → Dart : ready / ended / error / position        (JS channel)
///
/// The wrapper page is loaded with baseUrl https://www.youtube.com
/// so it has a real origin — the IFrame API's postMessage handshake
/// fails on a null origin (loadHtmlString's default), which made
/// embeds refuse to play (console error + YouTube error 153).
class YouTubeEmbed extends StatefulWidget {
  final String videoId;

  /// Mirror of the audio player. Defaults to true so plain
  /// call sites (videoId only) keep working unchanged.
  final bool playing;

  /// The audio clock. Without it the video follows play/pause
  /// but gets no drift correction.
  final Stream<Duration>? positionStream;

  /// Video can't be shown (embedding blocked, missing video, API
  /// timeout). Reported at most once per video.
  final void Function(String reason)? onUnavailable;

  const YouTubeEmbed({
    super.key,
    required this.videoId,
    this.playing = true,
    this.positionStream,
    this.onUnavailable,
  });

  @override
  State<YouTubeEmbed> createState() => _YouTubeEmbedState();
}

class _YouTubeEmbedState extends State<YouTubeEmbed> {
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

  late final WebViewController _web;
  late final String _initialVideoId;

  bool _ready = false;
  bool _errorSent = false;

  /// Video ran out before the audio did (shorter edit) — freeze on
  /// the last frame instead of seek-looping at the end.
  bool _videoEnded = false;

  /// Newest wanted videoId (may differ from _initialVideoId when the
  /// track changed while the player was still booting).
  String _wantedVideoId = '';

  double _videoPosition = -1; // last position pushed by the iframe (s)
  Duration _audioPosition = Duration.zero;
  bool _hasAudioPosition = false;

  StreamSubscription<Duration>? _positionSub;
  Timer? _bootTimer;

  @override
  void initState() {
    super.initState();
    _initialVideoId = _safeId(widget.videoId);
    _wantedVideoId = _initialVideoId;

    if (_initialVideoId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportError('invalid_video_id');
      });
    }

    _subscribeToPosition();

    // Safety net: IFrame API never booted (offline / blocked) →
    // tell the parent instead of showing a black void forever.
    _bootTimer = Timer(const Duration(seconds: 15), () {
      if (!_ready && mounted) _reportError('api_timeout');
    });

    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('ZenEmbed', onMessageReceived: _onMessage)
    // baseUrl gives the page a real origin (https://www.youtube.com)
    // instead of the opaque "null" — required for the IFrame API's
    // postMessage handshake; fixes embed refusals (error 153).
      ..loadHtmlString(_buildHtml(), baseUrl: 'https://www.youtube.com');
  }

  @override
  void didUpdateWidget(covariant YouTubeEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.videoId != oldWidget.videoId) {
      _errorSent = false; // new video, new chance
      _videoEnded = false;
      _videoPosition = -1;
      _wantedVideoId = _safeId(widget.videoId);
      if (_ready && _wantedVideoId.isNotEmpty) {
        _loadVideo(_wantedVideoId);
      }
    }

    if (widget.playing != oldWidget.playing) {
      _applyPlaying();
    }

    if (!identical(widget.positionStream, oldWidget.positionStream)) {
      _positionSub?.cancel();
      _subscribeToPosition();
    }
  }

  @override
  void dispose() {
    _bootTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  // ── audio position ────────────────────────────────────────

  void _subscribeToPosition() {
    final stream = widget.positionStream;
    if (stream == null) return;
    _positionSub = stream.listen((position) {
      if (!mounted) return;
      // Seeked backwards → a frozen (ended) video gets another life.
      if (position + const Duration(seconds: 3) < _audioPosition) {
        _videoEnded = false;
      }
      _audioPosition = position;
      _hasAudioPosition = true;
    });
  }

  // ── video → Dart ──────────────────────────────────────────

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return; // malformed event — ignore
    }

    switch (data['event']) {
      case 'ready':
        _bootTimer?.cancel();
        _ready = true;
        setState(() {}); // drop the black veil
        if (_wantedVideoId != _initialVideoId && _wantedVideoId.isNotEmpty) {
          _loadVideo(_wantedVideoId);
        } else if (_hasAudioPosition && _audioPosition > Duration.zero) {
          _seekTo(_audioPosition); // join the song mid-flight
        }
        _applyPlaying();
        break;
      case 'position':
        final seconds = (data['seconds'] as num?)?.toDouble() ?? -1;
        if (seconds >= 0) {
          _videoPosition = seconds;
          _correctDrift();
        }
        break;
      case 'ended':
        _videoEnded = true;
        break;
      case 'error':
        _reportError(_errorReason((data['code'] as num?)?.toInt()));
        break;
    }
  }

  // ── Dart → video ──────────────────────────────────────────

  void _loadVideo(String videoId) {
    _videoEnded = false;
    _videoPosition = -1;
    // loadVideoById autoplays — chain a pause when audio is stopped.
    final pauseAfter = widget.playing ? '' : ' player.pauseVideo();';
    unawaited(_run('player.loadVideoById(${jsonEncode(videoId)});$pauseAfter'));
  }

  void _applyPlaying() {
    if (!_ready) return; // re-applied when 'ready' arrives
    unawaited(
      _run(widget.playing ? 'player.playVideo();' : 'player.pauseVideo();'),
    );
  }

  void _seekTo(Duration position) {
    final seconds = (position.inMilliseconds / 1000).toStringAsFixed(2);
    unawaited(_run('player.seekTo($seconds, true);'));
  }

  Future<void> _run(String js) async {
    if (!mounted) return;
    try {
      await _web.runJavaScript(js);
    } catch (_) {
      // Page gone mid-command — nothing to do.
    }
  }

  // ── drift correction (channel-fed, no return values) ──────

  void _correctDrift() {
    if (!_ready || !widget.playing || _videoEnded) return;
    if (!_hasAudioPosition || _videoPosition < 0) return;

    final audioSec = _audioPosition.inMilliseconds / 1000.0;
    if ((audioSec - _videoPosition).abs() > 1.0) {
      _seekTo(_audioPosition);
      _videoPosition = audioSec; // provisional; next push confirms
    }
  }

  // ── errors ────────────────────────────────────────────────

  void _reportError(String reason) {
    if (_errorSent) return;
    _errorSent = true;
    _bootTimer?.cancel();
    widget.onUnavailable?.call(reason);
  }

  String _errorReason(int? code) {
    switch (code) {
      case 2:
        return 'invalid_video_id';
      case 5:
        return 'html5_player_error';
      case 100:
        return 'video_not_found';
      case 101:
      case 150:
      case 153:
      // 153 isn't official but behaves like the 101/150 family:
      // YouTube refuses to play this embed.
        return 'embedding_blocked';
      case -999:
        return 'api_timeout';
      default:
        return 'player_error_$code';
    }
  }

  String _safeId(String id) => _idPattern.hasMatch(id) ? id : '';

  // ── build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Pure backdrop — every tap belongs to the player UI above it.
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _web),
          // Black veil until the player is actually live.
          if (!_ready) const ColoredBox(color: Colors.black),
        ],
      ),
    );
  }

  // ── HTML / IFrame Player API ──────────────────────────────

  String _buildHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
  #v { position:absolute; top:0; left:0; width:100%; height:100%; }
  #v iframe { position:absolute; top:0; left:0; width:100% !important; height:100% !important; border:0; }
</style>
</head>
<body>
<div id="v"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
  var player = null;

  function zenPost(payload) {
    try { ZenEmbed.postMessage(JSON.stringify(payload)); } catch (e) {}
  }

  function onYouTubeIframeAPIReady() {
    player = new YT.Player('v', {
      videoId: '$_initialVideoId',
      width: '100%',
      height: '100%',
      playerVars: {
        autoplay: 1,
        origin: location.origin,
        mute: 1,
        controls: 0,
        playsinline: 1,
        rel: 0,
        iv_load_policy: 3,
        disablekb: 1,
        fs: 0,
        modestbranding: 1
      },
      events: {
        onReady: function () { zenPost({ event: 'ready' }); },
        onStateChange: function (e) {
          if (e.data === 0) { zenPost({ event: 'ended' }); }
        },
        onError: function (e) { zenPost({ event: 'error', code: e.data }); }
      }
    });
  }

  // Watchdog: API script never arrived (offline / blocked).
  setTimeout(function () {
    if (!player) { zenPost({ event: 'error', code: -999 }); }
  }, 15000);

  // Position feed — the Dart side does drift correction with this.
  setInterval(function () {
    if (player && player.getCurrentTime) {
      try {
        zenPost({ event: 'position', seconds: player.getCurrentTime() });
      } catch (e) {}
    }
  }, 1000);
</script>
</body>
</html>
''';
  }
}