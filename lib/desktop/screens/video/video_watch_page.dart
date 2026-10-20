// ZenMusic — YouTube-style video watch page (Desktop; YtVideoEngine extraction).
//
// SP-12 — YouTube desktop video engine:
//  * Data source swapped from InnertubexBridge (Android-native extraction;
//    its platform channel does not exist on Windows) to
//    lib/desktop/services/yt_video_engine.dart — the SAME proven pipeline
//    that powers desktop YT audio: vendored youtube_explode_dart fork,
//    client chain visionOs → ios → android, per-client header replay.
//  * videoUrl / audioUrl are LOCAL loopback proxy URLs; the engine adds the
//    minted-client headers upstream and re-resolves expired URLs on every
//    request. Muxed (≤360p) needs no audio track; adaptive plays the audio
//    URL as mpv's external track in the same Player (one clock).
//  * libmpv (media_kit) is the C engine doing demux/decode/render —
//    media_kit_libs_windows_video is already compiled in (Route B swap).
//  * UI, gestures, quality/speed sheets, related list, autoplay: unchanged
//    from the previous version of this file.
//
// SP-12b — A/V SYNC FIX ("audio plays separate from video"):
//  * Old: open(video) → setAudioTrack(AudioTrack.uri(audio)) → play().
//    That maps to mpv's `audio-add` on an ALREADY-PRIMED video demuxer;
//    the audio track then opens/buffers/seeks on its own timeline, which
//    surfaces as audio and video running "separately".
//  * New: mpv option `audio-files` is set BEFORE open(). mpv now opens
//    BOTH demuxers together in one session and interleaves them with
//    proper A/V sync from t=0 — the same mechanism as
//    `mpv video.webm --audio-file=audio.webm` (standard yt-dlp playback).
//    Seeks and `start:` offsets apply to both tracks. For muxed playback
//    the option is set to '' (cleared) so no stale track lingers.
//
// ONE PLAYER, NO SYNC. The extractor returns separate video and audio URLs.
// media_kit (libmpv) opens the video and attaches the audio URL as an
// external track in the same player, so both share one clock.
//
// pubspec.yaml:
//   media_kit: ^1.1.11
//   media_kit_video: ^1.2.5
//   media_kit_libs_android_video: ^1.3.6   (Android)
//   media_kit_libs_windows_video: ^1.0.11  (Windows — Route B swap)
//
// SPEED
//  * Stream URL, related list and quality list are requested in parallel.
//  * The thumbnail shows instantly as a poster until the first frame.
//  * Stream URLs are cached; the first "Up next" video is prefetched.
//  * One Player is reused for every video (no re-create, no black flash).
//  * Starts at _kStartHeight; the chosen quality sticks for later videos.
//  * Scrubbing seeks once, on release.

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/services/yt_video_engine.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

const Color _kRed = Color(0xFFFF0033);
const Color _kSurface = Color(0xFF181818);
const List<double> _kSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// First-frame speed knob: 360 fastest, 720 / 1080 sharper.
const int _kStartHeight = 480;

/// Caches extraction results (URLs stay valid for hours) and dedupes
/// in-flight requests.
class _StreamCache {
  static final Map<String, ({Future<YtVideoStreams?> f, DateTime at})> _m = {};

  static Future<YtVideoStreams?> get(String id, int height) {
    final k = '$id@$height';
    final e = _m[k];
    if (e != null &&
        DateTime.now().difference(e.at) < const Duration(hours: 3)) {
      return e.f;
    }
    if (_m.length > 12) _m.remove(_m.keys.first);
    final f = YtVideoEngine.extractVideo(id, maxHeight: height).then((s) {
      if (s == null || s.videoUrl == null) _m.remove(k);
      return s;
    });
    _m[k] = (f: f, at: DateTime.now());
    return f;
  }
}

class VideoWatchPage extends StatefulWidget {
  const VideoWatchPage({super.key, required this.videoId, this.item});
  final String videoId;
  final Map? item;

  @override
  State<VideoWatchPage> createState() => _VideoWatchPageState();
}

class _VideoWatchPageState extends State<VideoWatchPage> {
  late String _id = widget.videoId;
  String _title = '';
  String _artist = '';

  late final Player _p;
  late final VideoController _vc;
  final List<StreamSubscription> _subs = [];

  // Live player state, as notifiers so only the widgets that need them rebuild.
  final _pos = ValueNotifier<Duration>(Duration.zero);
  final _dur = ValueNotifier<Duration>(Duration.zero);
  final _bufd = ValueNotifier<Duration>(Duration.zero);
  final _playing = ValueNotifier<bool>(false);
  final _buffering = ValueNotifier<bool>(false);
  final _hasFrame = ValueNotifier<bool>(false);
  final _ended = ValueNotifier<bool>(false);
  final _drag = ValueNotifier<double?>(null);

  List<YtVideoQuality> _qualities = const [];
  int _height = _kStartHeight; // 0 = auto (best)
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _related = const [];
  bool _relatedLoading = true;

  bool _controls = true;
  bool _fullscreen = false;
  bool _loop = false;
  bool _muted = false;
  bool _autoplay = true;
  bool _advancing = false;
  double _speed = 1.0;
  double _speedBeforeHold = 1.0;
  bool _holding = false;
  int _flash = 0;
  Offset _lastTap = Offset.zero;
  Timer? _hideTimer;
  Timer? _flashTimer;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _p = Player(
        configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024));
    _vc = VideoController(_p);
    _subs.addAll([
      _p.stream.position.listen((d) => _pos.value = d),
      _p.stream.duration.listen((d) => _dur.value = d),
      _p.stream.buffer.listen((d) => _bufd.value = d),
      _p.stream.playing.listen((v) => _playing.value = v),
      _p.stream.buffering.listen((v) => _buffering.value = v),
      _p.stream.width.listen((w) {
        if ((w ?? 0) > 0) _hasFrame.value = true;
      }),
      _p.stream.completed.listen((done) {
        _ended.value = done;
        if (done) _onCompleted();
      }),
    ]);

    final cur = _safeCurrentSong();
    if (cur != null && cur.id == _id) {
      _title = cur.title;
      _artist = cur.artist ?? cur.album ?? '';
    } else if (widget.item != null) {
      _title = _titleOf(widget.item!);
      _artist = _subOf(widget.item!);
    }
    _load(_id, keepMeta: true);
  }

  dynamic _safeCurrentSong() {
    try {
      return GetIt.I<MediaPlayer>().currentSongNotifier.value;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- loading

  Future<void> _load(String id,
      {String? title, String? artist, bool keepMeta = false}) async {
    final token = ++_loadToken;
    _hideTimer?.cancel();

    // Start every slow thing at once.
    final streamF = _StreamCache.get(id, _height);
    final relatedF = YtVideoEngine.relatedSongs(id);
    final qualF = YtVideoEngine.videoQualities(id);
    // SP-12c: defer the pause OUT of the build phase. Pausing the app
    // player makes just_audio broadcast SequenceState synchronously, and
    // any StreamBuilder listening to it would call setState while THIS
    // page is still mounting ("setState() called during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_pauseAppAudio());
    });

    setState(() {
      _id = id;
      if (!keepMeta) {
        _title = title ?? '';
        _artist = artist ?? '';
      }
      _loading = true;
      _error = null;
      _related = const [];
      _relatedLoading = true;
      _advancing = false;
    });
    _hasFrame.value = false;
    _ended.value = false;
    _pos.value = Duration.zero;

    relatedF.then((r) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _related = r;
        _relatedLoading = false;
      });
      _prefetchNext();
    });
    qualF.then((q) {
      if (!mounted || token != _loadToken) return;
      setState(() => _qualities = q);
    });

    final s = await streamF;
    if (!mounted || token != _loadToken) return;
    if (s == null || s.videoUrl == null) {
      setState(() {
        _loading = false;
        _error = 'Video could not be loaded. Check your connection and retry.';
      });
      return;
    }
    await _open(s, token: token);
  }

  Future<void> _open(YtVideoStreams s,
      {Duration? startAt, int? token}) async {
    try {
      // SP-12b: mpv must learn about the external audio track BEFORE the
      // main file is opened. `audio-files` opens BOTH demuxers in one
      // session (proper A/V sync from t=0); setAudioTrack/AudioTrack.uri
      // after open() maps to `audio-add`, which bolts a second demuxer
      // onto an already-primed video — the "audio separate" bug.
      // '' clears the option for muxed playback (no stale track).
      final platform = _p.platform;
      if (platform is NativePlayer) {
        final ext = (s.audioUrl == null || s.audioUrl!.isEmpty)
            ? ''
            : s.audioUrl!;
        await platform.setProperty('audio-files', ext);
      }
      await _p.open(
        Media(s.videoUrl!, httpHeaders: s.headers, start: startAt),
        play: false,
      );
      if (!mounted || (token != null && token != _loadToken)) return;
      if (_speed != 1.0) await _p.setRate(_speed);
      await _p.play();
    } catch (_) {
      if (mounted && (token == null || token == _loadToken)) {
        setState(() {
          _loading = false;
          _error = 'Could not play this video.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = null;
    });
    _poke();
  }

  Future<void> _switchQuality(int height) async {
    final at = _pos.value;
    setState(() => _height = height);
    final s = await _StreamCache.get(_id, height);
    if (!mounted || s?.videoUrl == null) return;
    await _open(s!, startAt: at);
  }

  void _prefetchNext() {
    for (final r in _related) {
      final id = _idOf(r);
      if (id != null && id != _id) {
        _StreamCache.get(id, _height); // warms the cache
        return;
      }
    }
  }

  Future<void> _pauseAppAudio() async {
    try {
      await GetIt.I<MediaPlayer>().player.pause();
    } catch (_) {}
  }

  void _onCompleted() {
    if (_advancing) return;
    if (_loop) {
      _p.seek(Duration.zero);
      _p.play();
    } else if (_autoplay) {
      _playNextRelated();
    }
  }

  void _playNextRelated() {
    for (final r in _related) {
      final id = _idOf(r);
      if (id != null && id != _id) {
        _advancing = true;
        _load(id, title: _titleOf(r), artist: _subOf(r));
        return;
      }
    }
  }

  // -------------------------------------------------------- map helpers

  String? _idOf(Map m) {
    final s = (m['videoId'] ?? m['id'])?.toString() ?? '';
    return s.length == 11 ? s : null;
  }

  String _titleOf(Map m) => (m['title'] ?? m['name'] ?? '').toString();

  String _subOf(Map m) {
    final v = m['subtitle'] ?? m['artist'] ?? m['artists'] ?? '';
    if (v is List) {
      return v
          .map((e) => e is Map ? (e['name'] ?? '') : e)
          .where((e) => e.toString().isNotEmpty)
          .join(', ');
    }
    return v.toString();
  }

  // ----------------------------------------------------------- controls

  void _poke() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing.value) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    if (_controls) {
      _hideTimer?.cancel();
      setState(() => _controls = false);
    } else {
      _poke();
    }
  }

  void _togglePlay() {
    if (_ended.value) {
      _p.seek(Duration.zero);
      _p.play();
    } else {
      _p.playOrPause();
    }
    _poke();
  }

  void _seekBy(int seconds) {
    var t = _pos.value + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > _dur.value) t = _dur.value;
    _p.seek(t);
    _flashTimer?.cancel();
    setState(() => _flash = seconds < 0 ? -1 : 1);
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flash = 0);
    });
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _p.setRate(s);
  }

  void _toggleLoop() => setState(() => _loop = !_loop);

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _p.setVolume(_muted ? 0 : 100);
    _poke();
  }

  Future<void> _toggleFullscreen() async {
    final next = !_fullscreen;
    setState(() => _fullscreen = next);
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    _poke();
  }

  void _copyLink() {
    Clipboard.setData(
        ClipboardData(text: 'https://music.youtube.com/watch?v=$_id'));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('Link copied'),
        duration: Duration(seconds: 2),
      ));
  }

  /// Hand the current position to the audio player and leave the page.
  Future<void> _audioOnly() async {
    final at = _pos.value;
    await _p.pause();
    try {
      final mp = GetIt.I<MediaPlayer>();
      await mp.playSong({
        'videoId': _id,
        'title': _title,
        'subtitle': _artist,
        'thumbnails': [
          {'url': 'https://i.ytimg.com/vi/$_id/mqdefault.jpg'},
        ],
      });
      await mp.player.seek(at);
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    for (final n in [
      _pos, _dur, _bufd, _playing, _buffering, _hasFrame, _ended, _drag
    ]) {
      n.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // -------------------------------------------------------------- sheets

  void _sheet(String title, List<Widget> children) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _opt(String label, bool selected, VoidCallback onTap) => ListTile(
    dense: true,
    title: Text(label),
    trailing: selected ? const Icon(Icons.check, color: _kRed) : null,
    onTap: () {
      Navigator.of(context).pop();
      onTap();
    },
  );

  void _qualitySheet() {
    final sorted = [..._qualities]
      ..sort((a, b) => b.height.compareTo(a.height));
    _sheet('Quality', [
      _opt('Auto (best)', _height == 0, () => _switchQuality(0)),
      for (final q in sorted)
        _opt('${q.height}p', _height == q.height,
            () => _switchQuality(q.height)),
    ]);
  }

  void _speedSheet() {
    _sheet('Playback speed', [
      for (final s in _kSpeeds)
        _opt(s == 1.0 ? 'Normal' : '${s}x', _speed == s, () => _setSpeed(s)),
    ]);
  }

  void _moreSheet() {
    _sheet('Settings', [
      ListTile(
        leading: const Icon(Icons.high_quality_outlined),
        title: const Text('Quality'),
        trailing: Text(_height == 0 ? 'Auto' : '${_height}p',
            style: const TextStyle(color: Colors.white60)),
        onTap: () {
          Navigator.of(context).pop();
          if (_qualities.isNotEmpty) _qualitySheet();
        },
      ),
      ListTile(
        leading: const Icon(Icons.speed),
        title: const Text('Playback speed'),
        trailing: Text(_speed == 1 ? 'Normal' : '${_speed}x',
            style: const TextStyle(color: Colors.white60)),
        onTap: () {
          Navigator.of(context).pop();
          _speedSheet();
        },
      ),
    ]);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _fullscreen
            ? SizedBox.expand(child: _player(full: true))
            : SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 900;
            if (wide) {
              return Row(
                children: [
                  Expanded(
                    child: ListView(
                      children: [
                        AspectRatio(
                            aspectRatio: 16 / 9,
                            child: _player(full: false)),
                        ..._info(),
                      ],
                    ),
                  ),
                  Container(
                    width: 400,
                    color: const Color(0xFF0F0F0F),
                    child: ListView(
                      padding: const EdgeInsets.only(top: 8),
                      children: _upNext(),
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                AspectRatio(
                    aspectRatio: 16 / 9, child: _player(full: false)),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [..._info(), ..._upNext()],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- player

  Widget _backBtn() => Positioned(
    top: 4,
    left: 4,
    child: _roundBtn(
        Icons.keyboard_arrow_down, () => Navigator.of(context).maybePop()),
  );

  Widget _player({required bool full}) {
    if (_error != null) {
      return Container(
        color: const Color(0xFF0B0B0B),
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_off_outlined,
                        size: 38, color: Colors.white38),
                    const SizedBox(height: 10),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: () => _load(_id, keepMeta: true),
                        child: const Text('Retry')),
                  ],
                ),
              ),
            ),
            _backBtn(),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onDoubleTapDown: (d) => _lastTap = d.localPosition,
        onDoubleTap: () {
          final third = box.maxWidth / 3;
          if (_lastTap.dx < third) {
            _seekBy(-10);
          } else if (_lastTap.dx > third * 2) {
            _seekBy(10);
          } else {
            _togglePlay();
          }
        },
        onLongPressStart: (_) {
          _speedBeforeHold = _speed;
          setState(() => _holding = true);
          _p.setRate(2.0);
        },
        onLongPressEnd: (_) {
          setState(() => _holding = false);
          _p.setRate(_speedBeforeHold);
        },
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster: visible until the first frame arrives.
              ValueListenableBuilder<bool>(
                valueListenable: _hasFrame,
                builder: (_, has, __) => has
                    ? const SizedBox.shrink()
                    : Opacity(
                  opacity: 0.55,
                  child: Image.network(
                    'https://i.ytimg.com/vi/$_id/mqdefault.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                    const SizedBox.shrink(),
                  ),
                ),
              ),
              Video(
                controller: _vc,
                controls: NoVideoControls,
                fill: Colors.transparent,
                fit: BoxFit.contain,
              ),
              // Spinner while opening or buffering.
              ListenableBuilder(
                listenable: Listenable.merge([_buffering, _hasFrame]),
                builder: (_, __) => (_loading ||
                    _buffering.value ||
                    !_hasFrame.value)
                    ? const Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  ),
                )
                    : const SizedBox.shrink(),
              ),
              if (_flash != 0)
                Align(
                  alignment: _flash < 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Container(
                    width: box.maxWidth / 2.6,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.horizontal(
                        left: _flash < 0
                            ? Radius.zero
                            : Radius.circular(box.maxHeight),
                        right: _flash > 0
                            ? Radius.zero
                            : Radius.circular(box.maxHeight),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _flash < 0
                                ? Icons.fast_rewind_rounded
                                : Icons.fast_forward_rounded,
                            size: 34),
                        const Text('10 seconds',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              if (_holding)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('2x',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              _overlay(full),
            ],
          ),
        ),
      );
    });
  }

  Widget _overlay(bool full) {
    return IgnorePointer(
      ignoring: !_controls,
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.65),
                Colors.black.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.75),
              ],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    _roundBtn(
                      full ? Icons.fullscreen_exit : Icons.keyboard_arrow_down,
                      full
                          ? _toggleFullscreen
                          : () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: full
                          ? Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600))
                          : const SizedBox.shrink(),
                    ),
                    _roundBtn(_muted ? Icons.volume_off : Icons.volume_up,
                        _toggleMute),
                    _roundBtn(Icons.more_vert, _moreSheet),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_playing, _ended]),
                    builder: (_, __) => GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _ended.value
                              ? Icons.replay_rounded
                              : (_playing.value
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
                child: Row(
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([_pos, _dur]),
                      builder: (_, __) => Text(
                        '${_fmt(_pos.value)} / ${_fmt(_dur.value)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                          full ? Icons.fullscreen_exit : Icons.fullscreen),
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
              _scrubber(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrubber() {
    return ListenableBuilder(
      listenable: Listenable.merge([_pos, _dur, _bufd, _drag]),
      builder: (_, __) {
        final total = _dur.value.inMilliseconds;
        final pos = _pos.value.inMilliseconds;
        final buffered = total > 0
            ? (_bufd.value.inMilliseconds / total).clamp(0.0, 1.0)
            : 0.0;
        return SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: buffered,
                      child: Container(
                        height: 3,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: _kRed,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                  thumbColor: _kRed,
                  overlayColor: _kRed.withValues(alpha: 0.2),
                  thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: _drag.value ??
                      (total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0),
                  onChangeStart: (_) => _hideTimer?.cancel(),
                  // Move the thumb while dragging; seek once on release.
                  onChanged: (f) => _drag.value = f,
                  onChangeEnd: (f) {
                    _p.seek(Duration(milliseconds: (f * total).round()));
                    _drag.value = null;
                    _poke();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => IconButton(
    icon: Icon(icon, color: Colors.white),
    onPressed: onTap,
  );

  String _fmt(Duration d) {
    final h = d.inHours;
    final m =
    d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------------------------------------------------------------- info

  List<Widget> _info() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _title.isEmpty ? 'Now watching' : _title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, height: 1.25),
            ),
            if (_artist.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.white12,
                    child: Text(
                      _artist.characters.first.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            ValueListenableBuilder(
              valueListenable: Hive.box('FAVOURITES').listenable(),
              builder: (context, box, _) {
                final liked = box.get(_id) != null;
                return _chip(
                  liked ? Icons.favorite : Icons.favorite_border,
                  liked ? 'Liked' : 'Like',
                      () async {
                    HapticFeedback.lightImpact();
                    if (liked) {
                      await box.delete(_id);
                    } else {
                      await box.put(_id, {
                        'videoId': _id,
                        'title': _title,
                        'subtitle': _artist,
                        'createdAt': DateTime.now().millisecondsSinceEpoch,
                      });
                    }
                  },
                  active: liked,
                  activeColor: const Color(0xFFFF4D6D),
                );
              },
            ),
            _chip(Icons.link, 'Copy link', _copyLink),
            _chip(Icons.repeat_one, _loop ? 'Loop on' : 'Loop', _toggleLoop,
                active: _loop),
            _chip(Icons.speed, _speed == 1 ? 'Speed' : '${_speed}x',
                _speedSheet,
                active: _speed != 1),
            if (_qualities.isNotEmpty)
              _chip(Icons.high_quality_outlined,
                  _height == 0 ? 'Quality' : '${_height}p', _qualitySheet),
            _chip(Icons.headphones, 'Audio only', _audioOnly),
          ],
        ),
      ),
      const Divider(height: 1, color: Colors.white10),
    ];
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap,
      {bool active = false, Color? activeColor}) {
    final fg = active ? (activeColor ?? Colors.black) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active && activeColor == null
            ? Colors.white
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- up next

  List<Widget> _upNext() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
        child: Row(
          children: [
            const Text('Up next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            const Text('Autoplay',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
            Switch(
              value: _autoplay,
              activeColor: Colors.white,
              activeTrackColor: _kRed,
              onChanged: (v) => setState(() => _autoplay = v),
            ),
          ],
        ),
      ),
      if (_relatedLoading)
        for (var i = 0; i < 5; i++) _skeleton()
      else if (_related.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('No related videos',
                style: TextStyle(color: Colors.white54)),
          ),
        )
      else
        for (final r in _related) _relatedTile(r),
      const SizedBox(height: 24),
    ];
  }

  Widget _skeleton() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Row(
      children: [
        Container(
          width: 160,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 12, color: Colors.white10),
              const SizedBox(height: 8),
              Container(height: 10, width: 90, color: Colors.white10),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _relatedTile(Map<String, dynamic> r) {
    final id = _idOf(r);
    final title = _titleOf(r);
    if (id == null || title.isEmpty) {
      return SectionItem(section: {
        'title': 'Related',
        'contents': [r],
      });
    }
    final sub = _subOf(r);
    return InkWell(
      onTap: () => _load(id, title: title, artist: sub),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 160,
                height: 90,
                child: Image.network(
                  'https://i.ytimg.com/vi/$id/mqdefault.jpg',
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.white10,
                    child: const Icon(Icons.play_circle_outline,
                        color: Colors.white38),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.25)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.white60)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
