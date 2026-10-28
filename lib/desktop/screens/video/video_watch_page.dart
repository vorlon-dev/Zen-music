import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/services/yt_video_engine.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

// ─────────────────────────────────────────────────────────── design tokens
const Color _kRed = Color(0xFFFF0033);
const Color _kBg = Color(0xFF0A0A0B);
const Color _kSurface = Color(0xFF151517);
const Color _kSurfaceHi = Color(0xFF1E1E21);
const Color _kLine = Color(0x14FFFFFF);
const Color _kMuted = Color(0x99FFFFFF);
const List<double> _kSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
const List<int> _kSleepOptions = [15, 30, 45, 60];

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

String _thumb(String id) => 'https://i.ytimg.com/vi/$id/mqdefault.jpg';

// ───────────────────────────────────────────────────────────────── page
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
  final List<Map<String, String>> _history = [];

  late final Player _p;
  late final VideoController _vc;
  final List<StreamSubscription> _subs = [];

  // Live player state as notifiers: only the widgets that need them rebuild.
  final _pos = ValueNotifier<Duration>(Duration.zero);
  final _dur = ValueNotifier<Duration>(Duration.zero);
  final _bufd = ValueNotifier<Duration>(Duration.zero);
  final _playing = ValueNotifier<bool>(false);
  final _buffering = ValueNotifier<bool>(false);
  final _hasFrame = ValueNotifier<bool>(false);
  final _ended = ValueNotifier<bool>(false);
  final _drag = ValueNotifier<double?>(null);
  final _toast = ValueNotifier<String?>(null);
  final _accent = ValueNotifier<Color>(const Color(0xFF5A1020));

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
  bool _ambient = true;
  bool _cover = false;
  bool _advancing = false;
  int _volume = 100;
  double _speed = 1.0;
  double _speedBeforeHold = 1.0;
  bool _holding = false;
  int _flash = 0;
  int _sleepMin = 0;
  Offset _lastTap = Offset.zero;
  Timer? _hideTimer;
  Timer? _flashTimer;
  Timer? _toastTimer;
  Timer? _sleepTimer;
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
      {String? title,
        String? artist,
        bool keepMeta = false,
        bool fromHistory = false}) async {
    final token = ++_loadToken;
    _hideTimer?.cancel();

    if (!fromHistory && id != _id && _title.isNotEmpty) {
      _history.add({'id': _id, 'title': _title, 'artist': _artist});
      if (_history.length > 30) _history.removeAt(0);
    }

    // Start every slow thing at once.
    final streamF = _StreamCache.get(id, _height);
    final relatedF = YtVideoEngine.relatedSongs(id);
    final qualF = YtVideoEngine.videoQualities(id);
    _extractAmbient(id, token);
    // SP-12c: defer the pause OUT of the build phase (setState during build).
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

  Future<void> _open(YtVideoStreams s, {Duration? startAt, int? token}) async {
    try {
      // SP-12b: mpv must learn about the external audio track BEFORE the
      // main file is opened so both demuxers start in one session.
      final platform = _p.platform;
      if (platform is NativePlayer) {
        final ext =
        (s.audioUrl == null || s.audioUrl!.isEmpty) ? '' : s.audioUrl!;
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
    _say(height == 0 ? 'Quality: Auto' : 'Quality: ${height}p');
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

  /// Samples the thumbnail and derives a muted, vibrant accent used by the
  /// ambient background. No extra packages needed.
  Future<void> _extractAmbient(String id, int token) async {
    try {
      final stream = NetworkImage(_thumb(id)).resolve(ImageConfiguration.empty);
      final done = Completer<ui.Image>();
      late ImageStreamListener l;
      l = ImageStreamListener((info, _) {
        if (!done.isCompleted) done.complete(info.image);
        stream.removeListener(l);
      }, onError: (e, s) {
        if (!done.isCompleted) done.completeError(e);
        stream.removeListener(l);
      });
      stream.addListener(l);
      final img = await done.future.timeout(const Duration(seconds: 8));
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null || !mounted || token != _loadToken) return;
      double r = 0, g = 0, b = 0, wsum = 0;
      final step = (img.width * img.height ~/ 1800).clamp(1, 1 << 20);
      for (var i = 0; i < img.width * img.height; i += step) {
        final o = i * 4;
        final pr = bd.getUint8(o) / 255, pg = bd.getUint8(o + 1) / 255;
        final pb = bd.getUint8(o + 2) / 255;
        final mx = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
        final mn = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
        if (mx < 0.12) continue; // letterbox / pure black
        final sat = mx == 0 ? 0 : (mx - mn) / mx;
        final w = 0.15 + sat * sat * 1.6;
        r += pr * w;
        g += pg * w;
        b += pb * w;
        wsum += w;
      }
      if (wsum == 0) return;
      final base = Color.fromRGBO(
          (r / wsum * 255).round(), (g / wsum * 255).round(),
          (b / wsum * 255).round(), 1);
      final hsl = HSLColor.fromColor(base);
      final tuned = hsl
          .withSaturation(hsl.saturation.clamp(0.35, 0.8))
          .withLightness(hsl.lightness.clamp(0.22, 0.42))
          .toColor();
      if (mounted && token == _loadToken) _accent.value = tuned;
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
    _say('Nothing queued');
  }

  void _playPrevious() {
    if (_pos.value.inSeconds > 4 || _history.isEmpty) {
      _p.seek(Duration.zero);
      return;
    }
    final h = _history.removeLast();
    _load(h['id']!,
        title: h['title'], artist: h['artist'], fromHistory: true);
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

  void _say(String msg) {
    _toastTimer?.cancel();
    _toast.value = msg;
    _toastTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) _toast.value = null;
    });
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing.value && _drag.value == null) {
        setState(() => _controls = false);
      }
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

  void _seekBy(int seconds, {bool flash = true}) {
    var t = _pos.value + Duration(seconds: seconds);
    if (t < Duration.zero) t = Duration.zero;
    if (t > _dur.value) t = _dur.value;
    _p.seek(t);
    if (!flash) {
      _say('${seconds > 0 ? '+' : ''}$seconds s');
      return;
    }
    _flashTimer?.cancel();
    setState(() => _flash = seconds < 0 ? -1 : 1);
    _flashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _flash = 0);
    });
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    _p.setRate(s);
    _say(s == 1 ? 'Normal speed' : '${s}x');
  }

  void _toggleLoop() {
    setState(() => _loop = !_loop);
    _say(_loop ? 'Loop on' : 'Loop off');
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _p.setVolume(_muted ? 0 : _volume.toDouble());
    _say(_muted ? 'Muted' : 'Volume $_volume%');
    _poke();
  }

  void _nudgeVolume(int delta) {
    _volume = (_volume + delta).clamp(0, 100);
    _muted = _volume == 0;
    _p.setVolume(_volume.toDouble());
    setState(() {});
    _say('Volume $_volume%');
  }

  void _setSleep(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMin = minutes);
    if (minutes > 0) {
      _sleepTimer = Timer(Duration(minutes: minutes), () {
        _p.pause();
        if (mounted) setState(() => _sleepMin = 0);
      });
      _say('Sleep in $minutes min');
    } else {
      _say('Sleep timer off');
    }
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
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    _poke();
  }

  void _copyLink() {
    Clipboard.setData(
        ClipboardData(text: 'https://music.youtube.com/watch?v=$_id'));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _kSurfaceHi,
        width: 220,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const Text('Link copied', textAlign: TextAlign.center),
        duration: const Duration(seconds: 2),
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
          {'url': _thumb(_id)},
        ],
      });
      await mp.player.seek(at);
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-5, flash: false);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(5, flash: false);
    } else if (k == LogicalKeyboardKey.keyJ) {
      _seekBy(-10);
    } else if (k == LogicalKeyboardKey.keyL) {
      _seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _nudgeVolume(10);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _nudgeVolume(-10);
    } else if (k == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (k == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyN) {
      _playNextRelated();
    } else if (k == LogicalKeyboardKey.keyP) {
      _playPrevious();
    } else if (k == LogicalKeyboardKey.keyR) {
      _toggleLoop();
    } else if (k == LogicalKeyboardKey.keyA) {
      setState(() => _ambient = !_ambient);
      _say(_ambient ? 'Ambient mode on' : 'Ambient mode off');
    } else if (k == LogicalKeyboardKey.escape && _fullscreen) {
      _toggleFullscreen();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    _toastTimer?.cancel();
    _sleepTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    for (final n in [
      _pos, _dur, _bufd, _playing, _buffering, _hasFrame, _ended, _drag,
      _toast, _accent
    ]) {
      n.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // -------------------------------------------------------------- sheets

  void _sheet(String title, List<Widget> Function(StateSetter) build) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kSurface,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text(title.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.4,
                          color: _kMuted,
                          fontWeight: FontWeight.w700)),
                ),
                ...build(setS),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _opt(String label, bool selected, VoidCallback onTap) => ListTile(
    dense: true,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    title: Text(label,
        style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
    trailing: selected ? const Icon(Icons.check_rounded, color: _kRed) : null,
    onTap: () {
      Navigator.of(context).pop();
      onTap();
    },
  );

  void _qualitySheet() {
    final sorted = [..._qualities]..sort((a, b) => b.height.compareTo(a.height));
    _sheet('Quality', (_) => [
      _opt('Auto (best)', _height == 0, () => _switchQuality(0)),
      for (final q in sorted)
        _opt('${q.height}p', _height == q.height,
                () => _switchQuality(q.height)),
    ]);
  }

  void _speedSheet() {
    _sheet('Playback speed', (_) => [
      for (final s in _kSpeeds)
        _opt(s == 1.0 ? 'Normal' : '${s}x', _speed == s, () => _setSpeed(s)),
    ]);
  }

  void _sleepSheet() {
    _sheet('Sleep timer', (_) => [
      _opt('Off', _sleepMin == 0, () => _setSleep(0)),
      for (final m in _kSleepOptions)
        _opt('$m minutes', _sleepMin == m, () => _setSleep(m)),
    ]);
  }

  Widget _switchRow(IconData icon, String label, String? sub, bool value,
      ValueChanged<bool> onChanged) {
    return SwitchListTile(
      secondary: Icon(icon, color: Colors.white70),
      title: Text(label),
      subtitle: sub == null
          ? null
          : Text(sub, style: const TextStyle(color: _kMuted, fontSize: 12)),
      value: value,
      activeColor: Colors.white,
      activeTrackColor: _kRed,
      onChanged: onChanged,
    );
  }

  void _moreSheet() {
    _sheet('Settings', (setS) => [
      _switchRow(Icons.blur_on_rounded, 'Ambient mode',
          'Glow and colour from the video', _ambient, (v) {
            setState(() => _ambient = v);
            setS(() {});
          }),
      _switchRow(Icons.skip_next_rounded, 'Autoplay', 'Continue to next video',
          _autoplay, (v) {
            setState(() => _autoplay = v);
            setS(() {});
          }),
      _switchRow(Icons.repeat_one_rounded, 'Loop', null, _loop, (v) {
        setState(() => _loop = v);
        setS(() {});
      }),
      _switchRow(Icons.crop_free_rounded, 'Fill screen', 'Crop to fit the frame',
          _cover, (v) {
            setState(() => _cover = v);
            setS(() {});
          }),
      ListTile(
        leading: const Icon(Icons.high_quality_outlined),
        title: const Text('Quality'),
        trailing: Text(_height == 0 ? 'Auto' : '${_height}p',
            style: const TextStyle(color: _kMuted)),
        onTap: () {
          Navigator.of(context).pop();
          if (_qualities.isNotEmpty) _qualitySheet();
        },
      ),
      ListTile(
        leading: const Icon(Icons.speed_rounded),
        title: const Text('Playback speed'),
        trailing: Text(_speed == 1 ? 'Normal' : '${_speed}x',
            style: const TextStyle(color: _kMuted)),
        onTap: () {
          Navigator.of(context).pop();
          _speedSheet();
        },
      ),
      ListTile(
        leading: const Icon(Icons.bedtime_outlined),
        title: const Text('Sleep timer'),
        trailing: Text(_sleepMin == 0 ? 'Off' : '$_sleepMin min',
            style: const TextStyle(color: _kMuted)),
        onTap: () {
          Navigator.of(context).pop();
          _sleepSheet();
        },
      ),
    ]);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: PopScope(
        canPop: !_fullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _fullscreen) _toggleFullscreen();
        },
        child: Scaffold(
          backgroundColor: _kBg,
          body: _fullscreen
              ? SizedBox.expand(child: _player(full: true, radius: 0))
              : Stack(
            children: [
              Positioned.fill(child: _ambientBg()),
              SafeArea(child: LayoutBuilder(builder: _layout)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layout(BuildContext context, BoxConstraints box) {
    final w = box.maxWidth;

    // Phone in landscape: player left, details right.
    if (box.maxHeight < 480 && w > box.maxHeight) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: Center(
              child: AspectRatio(
                  aspectRatio: 16 / 9, child: _player(full: false, radius: 0)),
            ),
          ),
          SizedBox(
            width: 320,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [..._info(), ..._upNext()],
            ),
          ),
        ],
      );
    }

    // Desktop / large tablet: theatre on the left, queue panel on the right.
    if (w >= 1100) {
      return Row(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 20, 14, 40),
              children: [
                _framed(
                    AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _player(full: false, radius: 18)),
                    18),
                const SizedBox(height: 6),
                ..._info(),
              ],
            ),
          ),
          Container(
            width: w >= 1500 ? 440 : 380,
            margin: const EdgeInsets.fromLTRB(0, 20, 24, 20),
            decoration: BoxDecoration(
              color: _kSurface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kLine),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: ListView(
                padding: const EdgeInsets.only(top: 6),
                children: _upNext(),
              ),
            ),
          ),
        ],
      );
    }

    // Tablet / narrow desktop: centred single column.
    if (w >= 700) {
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              _framed(
                  AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _player(full: false, radius: 16)),
                  16),
              ..._info(),
              ..._upNext(),
            ],
          ),
        ),
      );
    }

    // Phone portrait.
    return Column(
      children: [
        AspectRatio(
            aspectRatio: 16 / 9, child: _player(full: false, radius: 0)),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [..._info(), ..._upNext()],
          ),
        ),
      ],
    );
  }

  /// Soft coloured halo behind the player when ambient mode is on.
  Widget _framed(Widget child, double radius) {
    return ValueListenableBuilder<Color>(
      valueListenable: _accent,
      builder: (_, c, __) => AnimatedContainer(
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: _ambient
              ? [
            BoxShadow(
                color: c.withValues(alpha: 0.55),
                blurRadius: 90,
                spreadRadius: -6,
                offset: const Offset(0, 20)),
          ]
              : const [
            BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 12))
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _ambientBg() {
    return ValueListenableBuilder<Color>(
      valueListenable: _accent,
      builder: (_, c, __) {
        final tint = _ambient ? c : const Color(0xFF1A1A1C);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: tint),
          duration: const Duration(milliseconds: 1000),
          builder: (_, col, __) {
            final k = col ?? tint;
            return RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_ambient)
                    Positioned(
                      left: -60,
                      right: -60,
                      top: -40,
                      height: 460,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black, Colors.transparent],
                        ).createShader(r),
                        child: ImageFiltered(
                          imageFilter: ui.ImageFilter.blur(
                              sigmaX: 36, sigmaY: 36, tileMode: TileMode.mirror),
                          child: Opacity(
                            opacity: 0.38,
                            child: Image.network(_thumb(_id),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink()),
                          ),
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.45, 1],
                        colors: [
                          k.withValues(alpha: _ambient ? 0.55 : 0.25),
                          _kBg.withValues(alpha: 0.92),
                          _kBg,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------- player

  Widget _backBtn() => Positioned(
    top: 4,
    left: 4,
    child: _roundBtn(
        Icons.keyboard_arrow_down_rounded, () => Navigator.of(context).maybePop()),
  );

  Widget _player({required bool full, required double radius}) {
    Widget body;
    if (_error != null) {
      body = Container(
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
                    FilledButton.tonal(
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
    } else {
      body = _stage(full);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: body);
  }

  Widget _stage(bool full) {
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
        child: MouseRegion(
          onHover: (_) {
            if (!_controls) _poke();
          },
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster: visible until the first frame arrives.
                ValueListenableBuilder<bool>(
                  valueListenable: _hasFrame,
                  builder: (_, has, __) => AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: has ? 0 : 0.55,
                    child: Image.network(_thumb(_id),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                ),
                Video(
                  controller: _vc,
                  controls: NoVideoControls,
                  fill: Colors.transparent,
                  fit: _cover ? BoxFit.cover : BoxFit.contain,
                ),
                // Spinner while opening or buffering.
                ListenableBuilder(
                  listenable: Listenable.merge([_buffering, _hasFrame]),
                  builder: (_, __) =>
                  (_loading || _buffering.value || !_hasFrame.value)
                      ? const Center(
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
                if (_flash != 0) _seekFlash(box),
                if (_holding)
                  Align(
                    alignment: Alignment.topCenter,
                    child: _tag('2x  ·  Holding', top: 14),
                  ),
                // Transient status message (volume, speed, shortcuts…).
                ValueListenableBuilder<String?>(
                  valueListenable: _toast,
                  builder: (_, t, __) => Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: t == null
                          ? const SizedBox.shrink()
                          : KeyedSubtree(
                          key: ValueKey(t), child: _tag(t, top: 56)),
                    ),
                  ),
                ),
                _overlay(full, box),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _tag(String text, {double top = 14}) => Container(
    margin: EdgeInsets.only(top: top),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.66),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
  );

  Widget _seekFlash(BoxConstraints box) => Align(
    alignment: _flash < 0 ? Alignment.centerLeft : Alignment.centerRight,
    child: Container(
      width: box.maxWidth / 2.6,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.horizontal(
          left: _flash < 0 ? Radius.zero : Radius.circular(box.maxHeight),
          right: _flash > 0 ? Radius.zero : Radius.circular(box.maxHeight),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
              _flash < 0
                  ? Icons.fast_rewind_rounded
                  : Icons.fast_forward_rounded,
              size: 32),
          const Text('10 seconds', style: TextStyle(fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _overlay(bool full, BoxConstraints box) {
    final compact = box.maxHeight < 260;
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
              stops: const [0, 0.3, 0.6, 1],
              colors: [
                Colors.black.withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.82),
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
                      full
                          ? Icons.arrow_back_rounded
                          : Icons.keyboard_arrow_down_rounded,
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
                    _roundBtn(
                        _ambient ? Icons.blur_on_rounded : Icons.blur_off_rounded,
                            () {
                          setState(() => _ambient = !_ambient);
                          _say(_ambient ? 'Ambient mode on' : 'Ambient mode off');
                          _poke();
                        }),
                    _roundBtn(
                        _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        _toggleMute),
                    _roundBtn(Icons.tune_rounded, _moreSheet),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_playing, _ended]),
                    builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ghostBtn(Icons.skip_previous_rounded, _playPrevious,
                            size: compact ? 26 : 32),
                        SizedBox(width: compact ? 10 : 22),
                        _ghostBtn(Icons.replay_10_rounded, () => _seekBy(-10),
                            size: compact ? 26 : 32),
                        SizedBox(width: compact ? 10 : 18),
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Container(
                            width: compact ? 52 : 66,
                            height: compact ? 52 : 66,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 18)
                              ],
                            ),
                            child: Icon(
                              _ended.value
                                  ? Icons.replay_rounded
                                  : (_playing.value
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded),
                              color: Colors.black,
                              size: compact ? 32 : 42,
                            ),
                          ),
                        ),
                        SizedBox(width: compact ? 10 : 18),
                        _ghostBtn(Icons.forward_10_rounded, () => _seekBy(10),
                            size: compact ? 26 : 32),
                        SizedBox(width: compact ? 10 : 22),
                        _ghostBtn(Icons.skip_next_rounded, _playNextRelated,
                            size: compact ? 26 : 32),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                child: Row(
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([_pos, _dur]),
                      builder: (_, __) => Text(
                        '${_fmt(_pos.value)}  /  ${_fmt(_dur.value)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          foregroundColor: Colors.white),
                      onPressed: _speedSheet,
                      child: Text(_speed == 1 ? '1x' : '${_speed}x',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _cover ? 'Fit' : 'Fill',
                      icon: Icon(_cover
                          ? Icons.fit_screen_rounded
                          : Icons.crop_free_rounded),
                      onPressed: () {
                        setState(() => _cover = !_cover);
                        _say(_cover ? 'Fill' : 'Fit');
                        _poke();
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(full
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded),
                      onPressed: _toggleFullscreen,
                    ),
                  ],
                ),
              ),
              _scrubber(),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scrubber() {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double frac(Offset p) => ((p.dx - 14) / (w - 28)).clamp(0.0, 1.0);
      return ListenableBuilder(
        listenable: Listenable.merge([_pos, _dur, _bufd, _drag]),
        builder: (_, __) {
          final total = _dur.value.inMilliseconds;
          final pos = _pos.value.inMilliseconds;
          final dragging = _drag.value != null;
          final played =
              _drag.value ?? (total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0);
          final buffered = total > 0
              ? (_bufd.value.inMilliseconds / total).clamp(0.0, 1.0)
              : 0.0;
          void commit() {
            final f = _drag.value;
            if (f != null && total > 0) {
              _p.seek(Duration(milliseconds: (f * total).round()));
            }
            _drag.value = null;
            _poke();
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              if (total > 0) {
                _p.seek(Duration(
                    milliseconds: (frac(d.localPosition) * total).round()));
              }
            },
            onHorizontalDragStart: (d) {
              _hideTimer?.cancel();
              _drag.value = frac(d.localPosition);
            },
            onHorizontalDragUpdate: (d) => _drag.value = frac(d.localPosition),
            onHorizontalDragEnd: (_) => commit(),
            onHorizontalDragCancel: commit,
            child: SizedBox(
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BarPainter(
                        played: played,
                        buffered: buffered,
                        active: dragging,
                      ),
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      left: (14 + played * (w - 28) - 28).clamp(0.0, w - 56),
                      top: -30,
                      width: 56,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _fmt(Duration(milliseconds: (played * total).round())),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [ui.FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => IconButton(
    icon: Icon(icon, color: Colors.white),
    onPressed: onTap,
  );

  Widget _ghostBtn(IconData icon, VoidCallback onTap, {double size = 32}) =>
      IconButton(
        iconSize: size,
        splashRadius: size,
        icon: Icon(icon, color: Colors.white),
        onPressed: () {
          onTap();
          _poke();
        },
      );

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------------------------------------------------------------- info

  List<Widget> _info() {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(
          _title.isEmpty ? 'Now watching' : _title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.2),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _meta(_height == 0 ? 'AUTO' : '${_height}P'),
            if (_speed != 1) _meta('${_speed}X'),
            if (_loop) _meta('LOOP'),
            if (_ambient) _meta('AMBIENT'),
            if (_sleepMin > 0) _meta('SLEEP $_sleepMin'),
          ],
        ),
      ),
      _channelCard(),
      SizedBox(
        height: 54,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          children: [
            ValueListenableBuilder(
              valueListenable: Hive.box('FAVOURITES').listenable(),
              builder: (context, box, _) {
                final liked = box.get(_id) != null;
                return _chip(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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
            _chip(Icons.headphones_rounded, 'Audio only', _audioOnly),
            _chip(Icons.link_rounded, 'Copy link', _copyLink),
            _chip(Icons.blur_on_rounded, 'Ambient', () {
              setState(() => _ambient = !_ambient);
            }, active: _ambient),
            _chip(Icons.repeat_one_rounded, _loop ? 'Loop on' : 'Loop', _toggleLoop,
                active: _loop),
            _chip(Icons.speed_rounded, _speed == 1 ? 'Speed' : '${_speed}x',
                _speedSheet,
                active: _speed != 1),
            if (_qualities.isNotEmpty)
              _chip(Icons.high_quality_outlined,
                  _height == 0 ? 'Quality' : '${_height}p', _qualitySheet),
            _chip(Icons.bedtime_outlined,
                _sleepMin == 0 ? 'Sleep' : '$_sleepMin min', _sleepSheet,
                active: _sleepMin > 0),
          ],
        ),
      ),
      const Divider(height: 1, color: _kLine),
    ];
  }

  Widget _meta(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white24),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(t,
        style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: _kMuted)),
  );

  /// Channel row: avatar with YouTube badge, name, branded source line.
  Widget _channelCard() {
    final name = _artist.isEmpty ? 'YouTube' : _artist;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kSurface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ValueListenableBuilder<Color>(
                  valueListenable: _accent,
                  builder: (_, c, __) => Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(c, Colors.white, 0.12),
                    ),
                    child: Text(
                      name.characters.first.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const _YtLogo(width: 17),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                const Row(
                  children: [
                    _YtLogo(width: 15),
                    SizedBox(width: 6),
                    Text('YouTube',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: _kMuted,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1)),
                  ],
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Copy YouTube link',
            style: IconButton.styleFrom(backgroundColor: _kSurfaceHi),
            onPressed: _copyLink,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, VoidCallback onTap,
      {bool active = false, Color? activeColor}) {
    final fg = active ? (activeColor ?? Colors.black) : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active && activeColor == null
            ? Colors.white
            : Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 7),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 4),
        child: Row(
          children: [
            const Text('Up next',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            if (!_relatedLoading && _related.isNotEmpty)
              Text('${_related.length}',
                  style: const TextStyle(color: _kMuted, fontSize: 13)),
            const Spacer(),
            const Text('Autoplay',
                style: TextStyle(fontSize: 12, color: _kMuted)),
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
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text('No related videos',
                style: TextStyle(color: Colors.white54)),
          ),
        )
      else
        for (final r in _related) _relatedTile(r),
      const SizedBox(height: 28),
    ];
  }

  Widget _skeleton() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    child: Row(
      children: [
        Container(
          width: 148,
          height: 83,
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
    final current = id == _id;
    return InkWell(
      onTap: current ? null : () => _load(id, title: title, artist: sub),
      child: Container(
        color: current ? Colors.white.withValues(alpha: 0.06) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 148,
                height: 83,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      _thumb(id),
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: const Icon(Icons.play_circle_outline_rounded,
                            color: Colors.white38),
                      ),
                    ),
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const _YtLogo(width: 13),
                      ),
                    ),
                    if (current)
                      Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: const Icon(Icons.equalizer_rounded, color: _kRed),
                      ),
                  ],
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
                        style: const TextStyle(fontSize: 12.5, color: _kMuted)),
                  ],
                  if (current) ...[
                    const SizedBox(height: 6),
                    const Text('NOW PLAYING',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: _kRed,
                            fontWeight: FontWeight.w800)),
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

// ──────────────────────────────────────────────────────────── painters

/// Seek bar: buffered + played segments, growing thumb while dragging.
class _BarPainter extends CustomPainter {
  _BarPainter(
      {required this.played, required this.buffered, required this.active});
  final double played;
  final double buffered;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    final w = size.width - pad * 2;
    final cy = size.height / 2;
    final h = active ? 5.0 : 3.0;
    RRect seg(double a, double b) => RRect.fromLTRBR(
        pad + w * a, cy - h / 2, pad + w * b, cy + h / 2, Radius.circular(h));

    canvas.drawRRect(
        seg(0, 1), Paint()..color = Colors.white.withValues(alpha: 0.2));
    canvas.drawRRect(
        seg(0, buffered), Paint()..color = Colors.white.withValues(alpha: 0.38));
    if (played > 0) {
      canvas.drawRRect(seg(0, played), Paint()..color = _kRed);
    }
    final tx = pad + w * played;
    canvas.drawCircle(Offset(tx, cy), active ? 15 : 0,
        Paint()..color = _kRed.withValues(alpha: 0.22));
    canvas.drawCircle(Offset(tx, cy), active ? 8 : 5.5, Paint()..color = _kRed);
  }

  @override
  bool shouldRepaint(_BarPainter o) =>
      o.played != played || o.buffered != buffered || o.active != active;
}

/// Compact YouTube play-button mark.
class _YtLogo extends StatelessWidget {
  const _YtLogo({this.width = 20});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 0.7,
    child: CustomPaint(painter: _YtLogoPainter()),
  );
}

class _YtLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & s, Radius.circular(s.height * 0.3));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFF0000));
    final tri = Path()
      ..moveTo(s.width * 0.41, s.height * 0.28)
      ..lineTo(s.width * 0.41, s.height * 0.72)
      ..lineTo(s.width * 0.66, s.height * 0.5)
      ..close();
    canvas.drawPath(tri, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}