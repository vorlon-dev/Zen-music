// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:async' show StreamSubscription;
import 'package:audio_session/audio_session.dart'
    show AudioDevice, AudioSession;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:zenmusic/desktop/screens/player/widgets/apple_mesh.dart';
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show EventChannel, HapticFeedback, MethodChannel;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'package:zenmusic/desktop/screens/settings/player/equalizer_page.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';


enum PlayerSkin {
  classic('Classic', 'The standard Zen layout', Icons.music_note_outlined),
  appleMusicMesh('Apple Music',
      'Full-bleed artwork or canvas, round buttons, bare transport, volume',
      Icons.gradient),
  simpLiquid('SimpMusic · Liquid glass',
      'Full-bleed artwork, blurred backdrop, live lyric line',
      Icons.blur_on),
  simpM3('Material 3',
      'Connected buttons, squircle transport, rotating cookie play button',
      Icons.palette_outlined);

  const PlayerSkin(this.label, this.desc, this.icon);
  final String label, desc;
  final IconData icon;

  static PlayerSkin fromName(String? n) =>
      values.firstWhere((s) => s.name == n, orElse: () => classic);
}

/// Everything a skin needs from the player page.
class PlayerCtx {
  const PlayerCtx({
    required this.song,
    required this.index,
    required this.total,
    required this.quality,
    required this.hasLyrics,
    required this.showLyrics,
    required this.lyrics,
    required this.swipeArt,
    required this.art,
    required this.close,
    required this.openQueue,
    required this.openQuality,
    required this.toggleLyrics,
    required this.next,
    required this.prev,
    this.tint,
    this.canvas = const SizedBox.shrink(),
    this.canvasOn = false,
  });

  final MediaItem song;
  final int index, total; // 1-based position in the queue
  final String quality; // e.g. "High, 256 kbps" or "Auto"
  final bool hasLyrics, showLyrics;
  final Color? tint; // palette colour of the front artwork (if known)
  final Widget canvas; // Spotify canvas / reel / video backdrop (may be empty)
  final bool canvasOn; // true once the canvas is rendering → hide artwork
  final Widget Function(Size) lyrics; // the page's LyricsBox
  final Widget swipeArt; // swipe stack (fills its parent)
  final Widget Function(double radius) art; // plain square artwork
  final VoidCallback close, openQueue, openQuality, toggleLyrics, next, prev;
}

/// Saved player-screen choice. Self-contained (Hive).
class PlayerSkinPrefs {
  PlayerSkinPrefs._();
  static const _box = 'zen_player_skin';
  static final ValueNotifier<String> _n = ValueNotifier<String>('classic');
  static bool _started = false;

  static ValueNotifier<String> get skin {
    if (!_started) {
      _started = true;
      Hive.openBox(_box).then((b) {
        _n.value = b.get('skin', defaultValue: 'classic') as String;
      }).catchError((_) {});
    }
    return _n;
  }

  static Future<void> set(String name) async {
    skin;
    _n.value = name;
    final b = await Hive.openBox(_box);
    await b.put('skin', name);
  }
}

class PlayerSkinView extends StatelessWidget {
  const PlayerSkinView({super.key, required this.skin, required this.ctx});
  final PlayerSkin skin;
  final PlayerCtx ctx;

  @override
  Widget build(BuildContext context) => switch (skin) {
    PlayerSkin.appleMusicMesh => _EchoSkin(ctx, material: false),
    PlayerSkin.simpLiquid => _SimpLiquid(ctx),
    PlayerSkin.simpM3 => _EchoSkin(ctx, material: true),
    PlayerSkin.classic => const SizedBox.shrink(),
  };
}


class _Ic {
  _Ic._();
  static final bool _a = Platform.isIOS || Platform.isMacOS;

  static IconData get play =>
      _a ? CupertinoIcons.play_fill : Icons.play_arrow_rounded;
  static IconData get pause =>
      _a ? CupertinoIcons.pause_fill : Icons.pause_rounded;
  static IconData get next =>
      _a ? CupertinoIcons.forward_end_fill : Icons.skip_next_rounded;
  static IconData get prev =>
      _a ? CupertinoIcons.backward_end_fill : Icons.skip_previous_rounded;
  static IconData get volume =>
      _a ? CupertinoIcons.speaker_1 : Icons.volume_up_outlined;
}

MediaPlayer get _mp => GetIt.I<MediaPlayer>();

void _toggle() {
  HapticFeedback.selectionClick();
  _mp.togglePlayPause();
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

TextStyle _s(double size, Color c,
    {FontWeight w = FontWeight.w600,
      double ls = 0,
      double h = 1.2,
      bool tab = false}) =>
    TextStyle(
      fontSize: size,
      color: c,
      fontWeight: w,
      letterSpacing: ls,
      height: h,
      decoration: TextDecoration.none,
      fontFeatures: tab ? const [FontFeature.tabularFigures()] : null,
    );

Widget _playing(Widget Function(ButtonState) b) =>
    ValueListenableBuilder<ButtonState>(
      valueListenable: _mp.buttonState,
      builder: (_, s, __) => b(s),
    );

Widget _fav(MediaItem song, Widget Function(bool liked, VoidCallback tap) b) {
  final id = song.extras?['videoId'];
  return ValueListenableBuilder(
    valueListenable: Hive.box('FAVOURITES').listenable(),
    builder: (_, box, __) {
      final liked = id != null && box.get(id) != null;
      return b(liked, () async {
        HapticFeedback.lightImpact();
        if (id == null) return;
        if (liked) {
          await box.delete(id);
        } else {
          await box.put(id, {
            ...?song.extras,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
        }
      });
    },
  );
}

void _more(BuildContext c, MediaItem song) {
  if (song.extras == null) return;
  final rb = c.findRenderObject() as RenderBox;
  Modals.showPlayerOptionsModal(
    c,
    song.extras!,
    buttonPosition: rb.localToGlobal(Offset.zero),
    buttonSize: rb.size,
  );
}

Widget _progress(
    Widget Function(double f, Duration pos, Duration total, bool playing,
        ValueChanged<double> seek)
    b) =>
    ValueListenableBuilder<ProgressBarState>(
      valueListenable: _mp.progressBarState,
      builder: (_, v, __) {
        final t = v.total.inMilliseconds;
        return b(
          t > 0 ? (v.current.inMilliseconds / t).clamp(0.0, 1.0) : 0.0,
          v.current,
          v.total,
          _mp.buttonState.value == ButtonState.playing,
              (f) => _mp.seekTo(Duration(milliseconds: (f * t).round())),
        );
      },
    );

bool _isWide(BoxConstraints c) =>
    c.maxWidth >= 820 && c.maxWidth > c.maxHeight * 1.15;

Color _t(PlayerCtx x, [Color d = const Color(0xFF3A4A6B)]) => x.tint ?? d;
Color _dark(Color c, double k) => Color.lerp(const Color(0xFF0B0B0D), c, k)!;

Widget _grad(List<Color> cs, [List<double>? st]) => DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: cs,
      stops: st,
    ),
  ),
);

Widget _mini(PlayerCtx x, double size, double r) => SizedBox(
  width: size,
  height: size,
  child: ClipRRect(borderRadius: BorderRadius.circular(r), child: x.art(r)),
);

Widget _titles(PlayerCtx x, Color ink, Color dim,
    {double size = 22, bool center = false, FontWeight w = FontWeight.w800}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
      center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(x.song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: _s(size, ink, w: w, ls: -0.3)),
        Text(x.song.artist ?? x.song.album ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: _s(size * 0.68, dim, w: FontWeight.w500)),
      ],
    );

Widget _times(Color c,
    {bool rem = false, double fs = 12, Widget? mid}) =>
    _progress((f, p, tot, pl, s) {
      final st = _s(fs, c, w: FontWeight.w500, tab: true);
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(_fmt(p), style: st),
        if (mid != null) mid,
        Text(rem ? '-${_fmt(tot > p ? tot - p : Duration.zero)}' : _fmt(tot),
            style: st),
      ]);
    });

class _Tap extends StatefulWidget {
  const _Tap({required this.child, required this.onTap, this.tip});
  final Widget child;
  final VoidCallback? onTap;
  final String? tip;

  @override
  State<_Tap> createState() => _TapState();
}

class _TapState extends State<_Tap> {
  bool _d = false;

  @override
  Widget build(BuildContext context) {
    final w = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _d = true),
        onTapUp: (_) => setState(() => _d = false),
        onTapCancel: () => setState(() => _d = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _d ? 0.93 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.child,
        ),
      ),
    );
    return widget.tip == null ? w : Tooltip(message: widget.tip!, child: w);
  }
}

Widget _ibtn(IconData i, VoidCallback? t, String tip,
    {double size = 24,
      Color c = Colors.white,
      bool on = true,
      bool? mark,
      double pad = 9}) {
  final icon = Icon(i, size: size, color: c);
  final child = mark == null
      ? icon
      : Column(mainAxisSize: MainAxisSize.min, children: [
    icon,
    const SizedBox(height: 3),
    Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mark ? c : Colors.transparent,
      ),
    ),
  ]);
  return Opacity(
    opacity: t == null ? 0.35 : (on ? 1 : 0.6),
    child: _Tap(
      onTap: t,
      tip: tip,
      child: Padding(padding: EdgeInsets.all(pad), child: child),
    ),
  );
}

class _Seeker extends StatefulWidget {
  const _Seeker({
    required this.f,
    required this.onSeek,
    required this.height,
    required this.paint,
    this.live = false,
  });
  final double f;
  final ValueChanged<double> onSeek;
  final double height;
  final bool live;
  final CustomPainter Function(double f) paint;

  @override
  State<_Seeker> createState() => _SeekerState();
}

class _SeekerState extends State<_Seeker> {
  double? _d;
  bool _drag = false;

  void _commit(double v) {
    widget.onSeek(v);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_drag) setState(() => _d = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, b) {
      double at(Offset o) => (o.dx / b.maxWidth).clamp(0.0, 1.0).toDouble();
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final v = at(d.localPosition);
            setState(() => _d = v);
            _commit(v);
          },
          onHorizontalDragStart: (d) => setState(() {
            _drag = true;
            _d = at(d.localPosition);
          }),
          onHorizontalDragUpdate: (d) {
            final v = at(d.localPosition);
            setState(() => _d = v);
            if (widget.live) widget.onSeek(v);
          },
          onHorizontalDragEnd: (_) {
            _drag = false;
            final v = _d;
            if (v != null) _commit(v);
          },
          onHorizontalDragCancel: () => setState(() {
            _drag = false;
            _d = null;
          }),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(painter: widget.paint(_d ?? widget.f)),
          ),
        ),
      );
    });
  }
}

enum _Thumb { dot, none }

class _LinePainter extends CustomPainter {
  const _LinePainter(this.f, this.active, this.inactive, this.t, this.thumb);
  final double f, t;
  final Color active, inactive;
  final _Thumb thumb;

  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2, x = f * s.width;
    final p = Paint()
      ..strokeWidth = t
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(0, y), Offset(s.width, y), p..color = inactive);
    c.drawLine(Offset(0, y), Offset(x, y), p..color = active);
    if (thumb == _Thumb.dot) {
      c.drawCircle(Offset(x, y), t * 2.2, Paint()..color = active);
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}

Widget _bar(Color a, Color i,
    {double h = 24, double t = 3, _Thumb th = _Thumb.dot}) =>
    _progress((f, p, tot, pl, seek) => _Seeker(
      f: f,
      onSeek: seek,
      height: h,
      paint: (v) => _LinePainter(v, a, i, t, th),
    ));

void _openEq(BuildContext c) => Navigator.of(c, rootNavigator: true)
    .push(MaterialPageRoute(builder: (_) => const EqualizerPage()));

void _addToPlaylist(BuildContext c, MediaItem song) {
  final e = song.extras;
  if (e == null) return;
  Modals.addToPlaylist(c, e);
}

void _swipeSong(PlayerCtx x, DragEndDetails d) {
  final v = d.primaryVelocity ?? 0;
  if (v > 350) {
    x.prev();
  } else if (v < -350) {
    x.next();
  }
}

Widget _volBoth(Color a, Color i, {double t = 8}) =>
    _SysVol(a: a, i: i, t: t);

/// Volume slider that drives the REAL media volume on Android (so lowering
/// it works with every playback path and stays in sync with the hardware
/// buttons). Other platforms fall back to the player volume.
class _SysVol extends StatefulWidget {
  const _SysVol(
      {required this.a, required this.i, this.t = 8, this.both = true});
  final Color a, i;
  final double t;
  final bool both;

  @override
  State<_SysVol> createState() => _SysVolState();
}

class _SysVolState extends State<_SysVol> {
  static const _ch = MethodChannel('zen/audio');
  static const _ev = EventChannel('zen/volume_events');
  double _f = 1;
  int _max = 15;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<dynamic>? _sub;
  bool get _sys => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_sys) _init();
  }

  Future<void> _init() async {
    try {
      _apply(await _ch.invokeMapMethod<String, dynamic>('getVolume'));
    } catch (_) {}
    if (!mounted) return;
    _sub = _ev.receiveBroadcastStream().listen((e) {
      if (e is Map) _apply(e.cast<String, dynamic>());
    }, onError: (_) {});
  }

  void _apply(Map<String, dynamic>? m) {
    final v = (m?['volume'] as num?)?.toDouble();
    final mx = (m?['max'] as num?)?.toDouble();
    if (v == null || mx == null || mx <= 0) return;
    // ignore the echo of our own drag
    if (DateTime.now().difference(_last).inMilliseconds < 500) return;
    if (mounted) {
      setState(() {
        _max = mx.toInt();
        _f = (v / mx).clamp(0.0, 1.0).toDouble();
      });
    }
  }

  void _set(double n) {
    _last = DateTime.now();
    setState(() => _f = n);
    _ch
        .invokeMethod<void>('setVolume', (n * _max).round())
        .catchError((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Widget _row(double v, ValueChanged<double> set) {
    final a = widget.a;
    return Row(children: [
      Icon(widget.both ? Icons.volume_mute_rounded : _Ic.volume,
          size: widget.both ? 18 : 16, color: a.withValues(alpha: .7)),
      const SizedBox(width: 12),
      Expanded(
        child: _Seeker(
          f: v,
          live: true,
          height: 24,
          onSeek: set,
          paint: (n) => _LinePainter(n, a, widget.i, widget.t, _Thumb.none),
        ),
      ),
      if (widget.both) ...[
        const SizedBox(width: 12),
        Icon(Icons.volume_up_rounded, size: 18, color: a.withValues(alpha: .7)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_sys) return _row(_f, _set);
    return StreamBuilder<double>(
      stream: _mp.player.volumeStream,
      initialData: _mp.player.volume,
      builder: (_, s) => _row(
          (s.data ?? 1.0).clamp(0.0, 1.0).toDouble(),
          (n) => _mp.player.setVolume(n)),
    );
  }
}


/// Current audio output ("Nothing Phone (4a)", "AirPods Pro", …) shown as a
/// tiny caption under the dock, like SimpMusic. Android only.
class _OutputName extends StatefulWidget {
  const _OutputName();

  @override
  State<_OutputName> createState() => _OutputNameState();
}

class _OutputNameState extends State<_OutputName> {
  String? _name;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    if (!Platform.isAndroid) return;
    _load();
    AudioSession.instance.then((s) {
      if (!mounted) return;
      _sub = s.devicesChangedEventStream.listen((_) => _load());
    }).catchError((_) {});
  }

  static int _rank(AudioDevice d) {
    final t = d.type.name.toLowerCase();
    if (t.contains('bluetooth') ||
        t.contains('wired') ||
        t.contains('usb') ||
        t.contains('hdmi')) {
      return 2; // headphones / BT / USB win over the phone speaker
    }
    return t.contains('speaker') ? 1 : 0;
  }

  Future<void> _load() async {
    try {
      final s = await AudioSession.instance;
      final devs = await s.getDevices(includeInputs: false);
      AudioDevice? best;
      for (final d in devs) {
        if (!d.isOutput) continue;
        if (best == null || _rank(d) > _rank(best)) best = d;
      }
      if (mounted) setState(() => _name = best?.name);
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _name?.trim();
    if (n == null || n.isEmpty) return const SizedBox(height: 14);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(n,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _s(10.5, Colors.white.withValues(alpha: .5),
              w: FontWeight.w500)),
    );
  }
}

/// Player ⇄ full-screen lyrics page (SimpMusic). The page replaces the whole
/// player while lyrics are on.
Widget _lyricsLayer(
        PlayerCtx x, Widget main, Widget Function(bool shown) page) {
  final on = x.hasLyrics && x.showLyrics;
  return Stack(children: [
    Positioned.fill(
      child: IgnorePointer(
        ignoring: on,
        child: AnimatedOpacity(
          opacity: on ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: main,
        ),
      ),
    ),
    Positioned.fill(child: HeldCrossfade(on: on, builder: (_, shown) => page(shown))),
  ]);
}

class _LyricsPage extends StatelessWidget {
  const _LyricsPage({
    required this.x,
    required this.shown,
    required this.ink,
    required this.dim,
    required this.prim,
    required this.onPrim,
    required this.chip,
    required this.chipInk,
    this.scrim,
  });
  final PlayerCtx x;
  final bool shown;
  final Color ink, dim, prim, onPrim, chip, chipInk;
  final Color? scrim;

  Widget _c(IconData i, VoidCallback? t, String tip) => Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: chip),
            child: Icon(i, size: 21, color: chipInk),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scrim ?? Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: Column(children: [
                Row(children: [
                  _c(Icons.keyboard_arrow_down_rounded, x.toggleLyrics,
                      'Close lyrics'),
                  const SizedBox(width: 12),
                  _mini(x, 44, 10),
                  const SizedBox(width: 12),
                  Expanded(child: _titles(x, ink, dim, size: 16)),
                  Builder(
                    builder: (c) =>
                        _c(Icons.more_vert_rounded, () => _more(c, x.song), 'More'),
                  ),
                ]),
                const SizedBox(height: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => x.lyrics(
                        shown ? Size(c.maxWidth, c.maxHeight) : Size.zero),
                  ),
                ),
                const SizedBox(height: 4),
                _bar(ink, Colors.white24, h: 18, t: 6, th: _Thumb.none),
                _times(dim, fs: 11.5),
                const SizedBox(height: 2),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: ink, pad: 10),
                  _playing((s) => _Tap(
                        onTap: _toggle,
                        tip: s == ButtonState.playing ? 'Pause' : 'Play',
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration:
                              BoxDecoration(shape: BoxShape.circle, color: prim),
                          child: s == ButtonState.loading
                              ? Padding(
                                  padding: const EdgeInsets.all(19),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 3, color: onPrim))
                              : Icon(
                                  s == ButtonState.playing
                                      ? _Ic.pause
                                      : _Ic.play,
                                  size: 30,
                                  color: onPrim),
                        ),
                      )),
                  _ibtn(_Ic.next, x.next, 'Next', size: 34, c: ink, pad: 10),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ 1 · Blur style – Liquid glass ═════════════════
class _SimpLiquid extends StatelessWidget {
  const _SimpLiquid(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;
  static final Color _dim = Colors.white.withValues(alpha: .62);
  static const _star = Color(0xFFFFD54F);

  /// Pre-blurred artwork behind everything (cached by the RepaintBoundary,
  /// only redone when the song changes).
  Widget _bg(Color t) => Stack(fit: StackFit.expand, children: [
    RepaintBoundary(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: 44, sigmaY: 44, tileMode: TileMode.decal),
          child: Transform.scale(
              scale: 1.7, child: SizedBox.expand(child: x.art(0))),
        ),
      ),
    ),
    _grad([
      _dark(t, .34).withValues(alpha: .55),
      _dark(t, .22).withValues(alpha: .84),
      _dark(t, .10),
    ]),
  ]);

  /// Full-bleed artwork that fades into the blurred backdrop. Lyrics replace
  /// it (dark scrim) when the lyrics toggle is on.
  /// Top area: artwork OR the canvas video, full-bleed, fading into the
  /// blurred gradient below (where the controls live).
  Widget _hero(BuildContext context, {double radius = 0, bool fade = true}) {
    return LayoutBuilder(builder: (_, c) {
      final side = math.max(c.maxWidth, c.maxHeight);
      final art = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox.square(dimension: side, child: x.art(0)),
        ),
      );
      Widget media = Stack(fit: StackFit.expand, children: [
        AnimatedOpacity(
          opacity: x.canvasOn ? 0 : 1,
          duration: const Duration(milliseconds: 320),
          child: art,
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: x.canvasOn ? 1 : 0,
            duration: const Duration(milliseconds: 320),
            child: ClipRect(child: x.canvas),
          ),
        ),
      ]);
      if (fade) {
        media = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, .78, 1],
          ).createShader(r),
          child: media,
        );
      } else {
        media = ClipRRect(
            borderRadius: BorderRadius.circular(radius), child: media);
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) => _swipeSong(x, d),
        child: media,
      );
    });
  }

  Widget _top() => Row(children: [
    Expanded(child: _titles(x, _w, _dim, size: 22, w: FontWeight.w800)),
    Builder(
      builder: (c) => _ibtn(Icons.add_circle_outline_rounded,
              () => _addToPlaylist(c, x.song), 'Add to playlist',
          size: 26, c: _w, pad: 7),
    ),
    _fav(
      x.song,
          (l, t) => _ibtn(l ? Icons.star_rounded : Icons.star_border_rounded, t,
          l ? 'Remove from favourites' : 'Add to favourites',
          size: 26, c: l ? _star : _w, pad: 7),
    ),
    Builder(
      builder: (c) => _ibtn(Icons.more_vert_rounded,
              () => _more(c, x.song), 'More',
          size: 26, c: _w, pad: 7),
    ),
  ]);

  Widget _quality() => _Tap(
    onTap: x.openQuality,
    tip: 'Audio quality',
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.headphones_rounded, size: 13, color: _dim),
      const SizedBox(width: 5),
      Flexible(
        child: Text(x.quality,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _s(11.5, _dim, w: FontWeight.w500)),
      ),
    ]),
  );

  Widget _transport() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      _ibtn(Icons.fast_rewind_rounded, x.prev, 'Previous',
          size: 46, c: _w, pad: 12),
      _playing((s) => _Tap(
        onTap: _toggle,
        tip: s == ButtonState.playing ? 'Pause' : 'Play',
        child: SizedBox(
          width: 84,
          height: 84,
          child: s == ButtonState.loading
              ? const Padding(
            padding: EdgeInsets.all(26),
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Colors.white),
          )
              : Icon(
              s == ButtonState.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 76,
              color: _w),
        ),
      )),
      _ibtn(Icons.fast_forward_rounded, x.next, 'Next',
          size: 46, c: _w, pad: 12),
    ],
  );

  Widget _seg(IconData i, String tip, VoidCallback? t, {bool on = false}) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: Container(
            width: 62,
            height: 44,
            alignment: Alignment.center,
            color: on ? _w.withValues(alpha: .16) : Colors.transparent,
            child: Icon(i, size: 22, color: _w),
          ),
        ),
      );

  Widget _div() => Container(
      width: 1, height: 44, color: _w.withValues(alpha: .14));

  /// [quality]   ( 🎧 | ⏲ | 💬 )   [queue]
  Widget _dock() => Builder(
    builder: (ctx) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ibtn(Icons.high_quality_rounded, x.openQuality, 'Audio quality',
            size: 24, c: _w, pad: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(color: _w.withValues(alpha: .12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _seg(Icons.headphones_rounded, 'Equalizer',
                      () => _openEq(ctx)),
              _div(),
              _seg(Icons.timer_outlined, 'Sleep timer',
                      () => Modals.showTimerModal(ctx)),
              _div(),
              _seg(Icons.chat_bubble_outline_rounded,
                  x.showLyrics ? 'Hide lyrics' : 'Show lyrics',
                  x.hasLyrics ? x.toggleLyrics : null,
                  on: x.showLyrics && x.hasLyrics),
            ]),
          ),
        ),
        _ibtn(Icons.queue_music_rounded, x.openQueue, 'Queue',
            size: 26, c: _w, pad: 10),
      ],
    ),
  );

  Widget _controls({required bool compact}) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        _top(),
        const SizedBox(height: 2),
        AppleLyricStrip(
            onTap: x.hasLyrics ? x.toggleLyrics : null, fontSize: 16),
        const SizedBox(height: 6),
        _bar(_w, Colors.white24, h: 18, t: 8, th: _Thumb.none),
        _times(_dim, rem: true, fs: 11.5, mid: Flexible(child: _quality())),
        SizedBox(height: compact ? 0 : 4),
        _transport(),
        if (!compact) ...[
          const SizedBox(height: 4),
          _volBoth(_w, Colors.white24),
          const SizedBox(height: 6),
          _dock(),
        ] else ...[
          _dock(),
        ],
        const _OutputName(),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return Material(
      type: MaterialType.transparency,
      child: Stack(fit: StackFit.expand, children: [
        _bg(t),
        _lyricsLayer(
          x,
          _main(),
          (shown) => _LyricsPage(
            x: x,
            shown: shown,
            ink: _w,
            dim: _dim,
            prim: _w,
            onPrim: Colors.black,
            chip: _w.withValues(alpha: .14),
            chipInk: _w,
            scrim: Colors.black.withValues(alpha: .34),
          ),
        ),
      ]),
    );
  }

  Widget _main() => LayoutBuilder(builder: (ctx, c) {
          if (_isWide(c)) return _wide(ctx);
          final compact = c.maxHeight < 660;
          return Stack(children: [
            Positioned.fill(
              child: Column(children: [
                Expanded(child: _hero(ctx)),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _controls(compact: compact),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]);
        });

  Widget _wide(BuildContext ctx) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(36, 12, 36, 20),
      child: Row(children: [
        Expanded(
          child: Column(children: [
            const SizedBox(height: 10),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _hero(ctx, radius: 30, fade: false),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 40),
        SizedBox(
          width: 440,
          child: Center(
              child: SingleChildScrollView(
                  child: _controls(compact: false))),
        ),
      ]),
    ),
  );
}

// ═════════════════════ Echo-style players (Apple · Material 3) ═══════════════
//
// Both follow the Echo Music player layout: full-bleed artwork (or the Spotify
// canvas) on top fading into a tinted gradient, a Song / Lyrics / Queue pill,
// title row with action buttons, thick seek bar with the quality chip, and the
// transport row. `material: false` is the Apple look (round translucent
// buttons, bare transport glyphs, volume row); `material: true` is the
// Material 3 look (connected white buttons, squircle transport, a rotating
// scalloped play button, bottom action group).

/// Press feedback with a small overshoot, like Echo's spring(0.6, 500).
class _Press extends StatefulWidget {
  const _Press({required this.child, required this.onTap, this.tip});
  final Widget child;
  final VoidCallback? onTap;
  final String? tip;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _d = false;

  @override
  Widget build(BuildContext context) {
    final w = MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _d = true),
        onTapUp: (_) => setState(() => _d = false),
        onTapCancel: () => setState(() => _d = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _d ? 0.9 : 1,
          duration: Duration(milliseconds: _d ? 90 : 320),
          curve: _d ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
    return widget.tip == null ? w : Tooltip(message: widget.tip!, child: w);
  }
}

/// Heart that pops and throws a ring of sparks when it becomes liked.
class _HeartBurst extends StatefulWidget {
  const _HeartBurst(
      {required this.liked, required this.color, this.size = 24});
  final bool liked;
  final Color color;
  final double size;

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 620));

  @override
  void didUpdateWidget(_HeartBurst o) {
    super.didUpdateWidget(o);
    if (widget.liked && !o.liked) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final pop = t == 0 || t == 1
              ? 1.0
              : 1 + .38 * math.sin(math.pi * Curves.easeOut.transform(t));
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            if (t > 0 && t < 1)
              Positioned.fill(
                child: CustomPaint(
                    painter: _SparkPainter(t, widget.color.withValues(alpha: 1))),
              ),
            Transform.scale(
              scale: pop,
              child: Icon(
                widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: s,
                color: widget.liked ? const Color(0xFFFF5C7A) : widget.color,
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas c, Size s) {
    final mid = s.center(Offset.zero);
    final e = Curves.easeOutCubic.transform(t);
    final p = Paint()
      ..color = const Color(0xFFFF5C7A).withValues(alpha: (1 - t).clamp(0, 1))
      ..style = PaintingStyle.fill;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final r = s.width * (.55 + .55 * e);
      c.drawCircle(
          mid + Offset(math.cos(a), math.sin(a)) * r, 2.2 * (1 - t) + .4, p);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.t != t;
}

/// Seek bar like Echo's slim slider: 10 px track that (Apple look) swells to
/// 16 px with a bouncy spring while you drag.
class _EchoBar extends StatefulWidget {
  const _EchoBar({required this.active, required this.inactive, this.swell = false});
  final Color active, inactive;
  final bool swell;

  @override
  State<_EchoBar> createState() => _EchoBarState();
}

class _EchoBarState extends State<_EchoBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController.unbounded(vsync: this, value: 10);
  double? _d;
  bool _drag = false;

  void _to(double target) {
    if (!widget.swell) return;
    _c.animateWith(SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: .5),
        _c.value,
        target,
        _c.velocity));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _progress((f, p, tot, pl, seek) => LayoutBuilder(builder: (_, b) {
      double at(Offset o) => (o.dx / b.maxWidth).clamp(0.0, 1.0).toDouble();
      void commit(double v) {
        seek(v);
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted && !_drag) setState(() => _d = null);
        });
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final v = at(d.localPosition);
          setState(() => _d = v);
          commit(v);
        },
        onHorizontalDragStart: (d) {
          _drag = true;
          _to(16);
          setState(() => _d = at(d.localPosition));
        },
        onHorizontalDragUpdate: (d) => setState(() => _d = at(d.localPosition)),
        onHorizontalDragEnd: (_) {
          _drag = false;
          _to(10);
          final v = _d;
          if (v != null) commit(v);
        },
        onHorizontalDragCancel: () {
          _drag = false;
          _to(10);
          setState(() => _d = null);
        },
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _LinePainter(_d ?? f, widget.active, widget.inactive,
                  _c.value.clamp(6.0, 22.0).toDouble(), _Thumb.none),
            ),
          ),
        ),
      );
    }));
  }
}

/// Echo's play/pause shape: a rounded square while paused that blooms into a
/// 9-lobed cookie (indent 0.08) while playing; the lobes rotate every 8 s.
class _CookieClipper extends CustomClipper<Path> {
  const _CookieClipper(this.k, this.rot, this.corner);
  final double k; // 0 = squircle … 1 = cookie
  final double rot; // radians
  final double corner; // squircle corner radius as a fraction of half-size

  static const int _n = 120;
  static final Map<double, List<double>> _sq = {};

  /// Polar radius (0..√2) of a rounded square of half-size 1.
  static List<double> _squircle(double r) => _sq.putIfAbsent(r, () {
    final out = List<double>.filled(_n + 1, 1);
    final inner = 1 - r;
    double sd(double x, double y) {
      final qx = x.abs() - inner, qy = y.abs() - inner;
      final ox = math.max(qx, 0.0), oy = math.max(qy, 0.0);
      return math.sqrt(ox * ox + oy * oy) +
          math.min(math.max(qx, qy), 0.0) -
          r;
    }

    for (var i = 0; i <= _n; i++) {
      final a = i * 2 * math.pi / _n;
      final cx = math.cos(a), cy = math.sin(a);
      var lo = 0.0, hi = 1.5;
      for (var j = 0; j < 22; j++) {
        final m = (lo + hi) / 2;
        if (sd(cx * m, cy * m) > 0) {
          hi = m;
        } else {
          lo = m;
        }
      }
      out[i] = (lo + hi) / 2;
    }
    return out;
  });

  @override
  Path getClip(Size s) {
    final path = Path();
    final sq = _squircle(corner);
    final ind = .08 * k;
    final cx = s.width / 2, cy = s.height / 2;
    for (var i = 0; i <= _n; i++) {
      final a = i * 2 * math.pi / _n;
      final cookie = 1 - ind + ind * math.cos(9 * (a - rot));
      final r = sq[i] * (1 - k) + cookie * k;
      final x = cx + cx * r * math.cos(a), y = cy + cy * r * math.sin(a);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }

  @override
  bool shouldReclip(_CookieClipper o) =>
      o.k != k || o.rot != rot || o.corner != corner;
}

class _CookiePlay extends StatefulWidget {
  const _CookiePlay({required this.size, required this.playing, required this.child});
  final double size;
  final bool playing;
  final Widget child;

  @override
  State<_CookiePlay> createState() => _CookiePlayState();
}

class _CookiePlayState extends State<_CookiePlay> with TickerProviderStateMixin {
  late final AnimationController _bloom = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: widget.playing ? 1 : 0);
  late final AnimationController _spin =
  AnimationController(vsync: this, duration: const Duration(seconds: 8));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(_CookiePlay o) {
    super.didUpdateWidget(o);
    if (widget.playing == o.playing) return;
    if (widget.playing) {
      _bloom.forward();
      _spin.repeat();
    } else {
      _bloom.reverse().whenComplete(() {
        if (mounted && !widget.playing) _spin.stop();
      });
    }
  }

  @override
  void dispose() {
    _bloom.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: AnimatedBuilder(
      animation: Listenable.merge([_bloom, _spin]),
      builder: (_, child) => ClipPath(
        clipper: _CookieClipper(_bloom.value, _spin.value * 2 * math.pi, 26 / 44),
        child: ColoredBox(color: Colors.white, child: child),
      ),
      child: Center(child: widget.child),
    ),
  );
}

class _EchoSkin extends StatelessWidget {
  const _EchoSkin(this.x, {required this.material});
  final PlayerCtx x;
  final bool material;

  static const _w = Colors.white;
  static final Color _dim = Colors.white.withValues(alpha: .78);
  static const double _pad = 28;

  // ── backdrop (blurred artwork + tinted gradient) ─────────────────────────
  Widget _bg(Color t) => Stack(fit: StackFit.expand, children: [
    RepaintBoundary(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(
              sigmaX: 44, sigmaY: 44, tileMode: TileMode.decal),
          child: Transform.scale(
              scale: 1.7, child: SizedBox.expand(child: x.art(0))),
        ),
      ),
    ),
    _grad([
      _dark(t, .34).withValues(alpha: .55),
      _dark(t, .22).withValues(alpha: .86),
      _dark(t, .10),
    ]),
  ]);

  // ── artwork / canvas hero (canvas replaces the artwork when it plays) ────
  Widget _hero({double radius = 0, bool fade = true, double t = 0}) =>
      LayoutBuilder(builder: (_, c) {
        final side = math.max(c.maxWidth, c.maxHeight);
        final art = ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox.square(dimension: side, child: x.art(0)),
          ),
        );
        Widget media = Stack(fit: StackFit.expand, children: [
          AnimatedOpacity(
            opacity: x.canvasOn ? 0 : 1,
            duration: const Duration(milliseconds: 320),
            child: art,
          ),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: x.canvasOn ? 1 : 0,
              duration: const Duration(milliseconds: 320),
              child: ClipRect(child: x.canvas),
            ),
          ),
        ]);
        if (fade) {
          // t = 0: full-bleed cover fading into the controls; t = 1: the
          // small rounded thumbnail of the lyrics sheet (no fade).
          media = ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Colors.white, Colors.transparent],
              stops: [0, .8 + .2 * t, 1],
            ).createShader(r),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(14 * t), child: media),
          );
        } else {
          media = ClipRRect(
              borderRadius: BorderRadius.circular(radius), child: media);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) => _swipeSong(x, d),
          child: media,
        );
      });

  // ── Song · Lyrics · Queue pill ───────────────────────────────────────────
  Widget _tab(IconData i, String label, bool sel, VoidCallback? t) => Opacity(
    opacity: t == null ? .45 : 1,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: t == null
          ? null
          : () {
        HapticFeedback.selectionClick();
        t();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? Colors.white.withValues(alpha: .22) : Colors.transparent,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 15, color: sel ? _w : Colors.white.withValues(alpha: .72)),
          const SizedBox(width: 5),
          Text(label,
              style: _s(12, sel ? _w : Colors.white.withValues(alpha: .72),
                  w: sel ? FontWeight.w700 : FontWeight.w600, ls: .2)),
        ]),
      ),
    ),
  );

  Widget _pill() {
    final lyr = x.hasLyrics && x.showLyrics;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _tab(Icons.music_note_rounded, 'Song', !lyr, lyr ? x.toggleLyrics : null),
        _tab(Icons.lyrics_outlined, 'Lyrics', lyr,
            x.hasLyrics && !lyr ? x.toggleLyrics : null),
        _tab(Icons.queue_music_rounded, 'Queue', false, x.openQueue),
      ]),
    );
  }

  // ── title row + action buttons ───────────────────────────────────────────
  static BorderRadius _grp(int i, int n) {
    const o = Radius.circular(50), s = Radius.circular(3);
    return BorderRadius.horizontal(
      left: i == 0 ? o : s,
      right: i == n - 1 ? o : s,
    );
  }

  /// M3: connected 42 dp filled buttons (outer corners round, inner 3 dp).
  Widget _filled(Widget icon, VoidCallback? t, String tip, int i, int n,
      {Color bg = _w}) =>
      _Press(
        onTap: t,
        tip: tip,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: _grp(i, n)),
          child: icon,
        ),
      );

  /// Apple: 40 dp circle, 20 % white.
  Widget _round(Widget icon, VoidCallback? t, String tip) => _Press(
    onTap: t,
    tip: tip,
    child: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: Colors.white.withValues(alpha: .2)),
      child: icon,
    ),
  );

  Widget _actions() => Builder(builder: (c) {
    final Color ink = material ? Colors.black : _w;
    Widget heart(bool l) => _HeartBurst(liked: l, color: ink, size: 24);
    if (material) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _filled(Icon(Icons.playlist_add_rounded, size: 24, color: ink),
                () => _addToPlaylist(c, x.song), 'Add to playlist', 0, 3),
        const SizedBox(width: 6),
        _filled(Icon(Icons.more_horiz_rounded, size: 24, color: ink),
                () => _more(c, x.song), 'More', 1, 3),
        const SizedBox(width: 6),
        _fav(x.song,
                (l, t) => _filled(heart(l), t,
                l ? 'Remove from favourites' : 'Add to favourites', 2, 3)),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _round(Icon(Icons.more_vert_rounded, size: 24, color: _w),
              () => _more(c, x.song), 'More'),
      const SizedBox(width: 10),
      _round(Icon(Icons.playlist_add_rounded, size: 24, color: _w),
              () => _addToPlaylist(c, x.song), 'Add to playlist'),
      const SizedBox(width: 10),
      _fav(x.song,
              (l, t) => _round(heart(l), t,
              l ? 'Remove from favourites' : 'Add to favourites')),
    ]);
  });

  Widget _titleRow() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _pad),
    child: Row(children: [
      Expanded(child: _titles(x, _w, _dim, size: 26, w: FontWeight.w700)),
      const SizedBox(width: 12),
      _actions(),
    ]),
  );

  // ── bar + times (quality chip in the middle) ─────────────────────────────
  Widget _chip() => _Press(
    onTap: x.openQuality,
    tip: 'Audio quality',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: .32)),
      ),
      child: Text(x.quality.replaceAll(', ', ' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _s(11, Colors.white.withValues(alpha: .8),
              w: FontWeight.w600, ls: .8)),
    ),
  );

  Widget _barRow() => Column(mainAxisSize: MainAxisSize.min, children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      child: _EchoBar(
        active: material ? _w : _w.withValues(alpha: .7),
        inactive: _w.withValues(alpha: material ? .3 : .2),
        swell: !material,
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pad + 4),
      child: _times(_w, fs: 12.5, mid: Flexible(child: _chip())),
    ),
  ]);

  // ── transport ────────────────────────────────────────────────────────────
  Widget _playGlyph(ButtonState s, double size, Color ink) {
    if (s == ButtonState.loading) {
      return Padding(
        padding: EdgeInsets.all(size * .24),
        child: CircularProgressIndicator(strokeWidth: 3.2, color: ink),
      );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (c, a) => ScaleTransition(
          scale: a, child: FadeTransition(opacity: a, child: c)),
      child: Icon(
          s == ButtonState.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(s == ButtonState.playing),
          size: size,
          color: ink),
    );
  }

  Widget _transportApple() => Row(children: [
    Expanded(
      child: Center(
        child: _Press(
          onTap: x.prev,
          tip: 'Previous',
          child: const Icon(Icons.fast_rewind_rounded, size: 48, color: _w),
        ),
      ),
    ),
    _playing((s) => _Press(
      onTap: _toggle,
      tip: s == ButtonState.playing ? 'Pause' : 'Play',
      child: SizedBox(
          width: 84, height: 84, child: Center(child: _playGlyph(s, 72, _w))),
    )),
    Expanded(
      child: Center(
        child: _Press(
          onTap: x.next,
          tip: 'Next',
          child: const Icon(Icons.fast_forward_rounded, size: 48, color: _w),
        ),
      ),
    ),
  ]);

  Widget _squircle(IconData i, VoidCallback? t, String tip, double size) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Press(
          onTap: t,
          tip: tip,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(size * 26 / 88),
            ),
            child: Icon(i, size: size * 36 / 88, color: _w),
          ),
        ),
      );

  Widget _transportM3(double size) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _squircle(Icons.skip_previous_rounded, x.prev, 'Previous', size),
      const SizedBox(width: 16),
      _playing((s) => _Press(
        onTap: _toggle,
        tip: s == ButtonState.playing ? 'Pause' : 'Play',
        child: _CookiePlay(
          size: size,
          playing: s == ButtonState.playing,
          child: _playGlyph(s, size * 36 / 88, Colors.black),
        ),
      )),
      const SizedBox(width: 16),
      _squircle(Icons.skip_next_rounded, x.next, 'Next', size),
    ],
  );

  // ── bottom: M3 action group · Apple volume ───────────────────────────────
  Widget _dockM3() => Builder(builder: (c) {
    Widget b(IconData i, String tip, VoidCallback? t, int idx, {bool on = false}) =>
        Opacity(
          opacity: t == null ? .4 : 1,
          child: _filled(Icon(i, size: 22, color: _w), t, tip, idx, 4,
              bg: Colors.white.withValues(alpha: on ? .34 : .2)),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      b(Icons.lyrics_outlined, x.showLyrics ? 'Hide lyrics' : 'Show lyrics',
          x.hasLyrics ? x.toggleLyrics : null, 0, on: x.showLyrics && x.hasLyrics),
      const SizedBox(width: 6),
      b(Icons.timer_outlined, 'Sleep timer', () => Modals.showTimerModal(c), 1),
      const SizedBox(width: 6),
      b(Icons.equalizer_rounded, 'Equalizer', () => _openEq(c), 2),
      const SizedBox(width: 6),
      b(Icons.queue_music_rounded, 'Queue', x.openQueue, 3),
    ]);
  });

  Widget _volApple() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _pad),
    child: _volBoth(_w, Colors.white.withValues(alpha: .18), t: 10),
  );

  Widget _controls({required bool compact}) {
    final gap = compact ? 14.0 : 24.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _titleRow(),
      SizedBox(height: gap - 4),
      _barRow(),
      SizedBox(height: gap - 6),
      if (material) ...[
        _transportM3(compact ? 72 : 88),
        SizedBox(height: compact ? 14 : 22),
        _dockM3(),
      ] else ...[
        _transportApple(),
        SizedBox(height: compact ? 4 : 10),
        _volApple(),
        const _OutputName(),
      ],
    ]);
  }

  // ── layouts ──────────────────────────────────────────────────────────────
  Widget _main() => LayoutBuilder(builder: (ctx, c) {
    if (_isWide(c)) return _wide();
    final compact = c.maxHeight < 700;
    return _EchoMorph(
      x: x,
      hero: (t) => _hero(t: t),
      pill: _pill(),
      controls: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _controls(compact: compact),
      ),
    );
  });

  Widget _wide() => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(36, 12, 36, 20),
      child: Row(children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: _hero(radius: 30, fade: false),
            ),
          ),
        ),
        const SizedBox(width: 40),
        SizedBox(
          width: 460,
          child: Center(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _pill(),
                const SizedBox(height: 22),
                _controls(compact: false),
              ]),
            ),
          ),
        ),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return Material(
      type: MaterialType.transparency,
      child: Stack(fit: StackFit.expand, children: [
        _bg(t),
        LayoutBuilder(builder: (ctx, c) {
          // Narrow (phone): the player morphs into the lyrics sheet.
          if (!_isWide(c)) return _main();
          return _lyricsLayer(
            x,
            _main(),
            (shown) => _LyricsPage(
              x: x,
              shown: shown,
              ink: _w,
              dim: _dim,
              prim: _w,
              onPrim: Colors.black,
              chip: _w.withValues(alpha: .14),
              chipInk: _w,
              scrim: Colors.black.withValues(alpha: .34),
            ),
          );
        }),
      ]),
    );
  }
}

/// Player ⇄ lyrics sheet, the way Echo does it: ONE offset (0 = player,
/// 1 = lyrics) drives every element together — cover shrinks to a corner
/// thumbnail, the controls slide down and fade out within the first third,
/// the title row slides in from above, the tab pill glides below it and the
/// lyrics rise from the bottom. The offset follows a finger on the pill /
/// cover / header (drag up to open, down to close) and settles with a
/// critically damped spring, so it never overshoots.
class _EchoMorph extends StatefulWidget {
  const _EchoMorph({
    required this.x,
    required this.hero,
    required this.pill,
    required this.controls,
  });
  final PlayerCtx x;
  final Widget Function(double t) hero;
  final Widget pill;
  final Widget controls;

  @override
  State<_EchoMorph> createState() => _EchoMorphState();
}

class _EchoMorphState extends State<_EchoMorph>
    with SingleTickerProviderStateMixin {
  static const double _thumb = 56; // collapsed cover
  static const double _gutter = 16;
  static const double _range = 280; // px of drag for a full open
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 1);

  late final AnimationController _c = AnimationController(
    vsync: this,
    value: _on ? 1 : 0,
  );
  bool _dragging = false;
  double _ctrlH = 330;

  bool get _on => widget.x.hasLyrics && widget.x.showLyrics;

  @override
  void didUpdateWidget(_EchoMorph old) {
    super.didUpdateWidget(old);
    if (!_dragging) _settle(_on ? 1 : 0, 0);
  }

  void _settle(double target, double velocity) {
    if ((_c.value - target).abs() < .001 && velocity.abs() < .01) {
      _c.value = target;
      return;
    }
    _c.animateWith(SpringSimulation(_spring, _c.value, target, velocity));
  }

  void _dragStart(DragStartDetails _) {
    _dragging = true;
    _c.stop();
  }

  void _dragUpdate(DragUpdateDetails d) {
    // Without lyrics there is nothing to open: just a little rubber band.
    final max = widget.x.hasLyrics ? 1.0 : .06;
    _c.value = (_c.value - d.delta.dy / _range).clamp(0.0, max);
  }

  void _dragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond.dy; // negative = upwards
    var target = _c.value > .5 ? 1.0 : 0.0;
    if (v.abs() > 700) target = v < 0 ? 1.0 : 0.0;
    if (!widget.x.hasLyrics) target = 0;
    if (target != (_on ? 1.0 : 0.0)) {
      HapticFeedback.selectionClick();
      widget.x.toggleLyrics();
    }
    _settle(target, -v / _range);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    final pad = MediaQuery.paddingOf(context);
    // Wraps a handle widget so a vertical drag on it scrubs the offset.
    Widget grab(Widget child) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _dragStart,
          onVerticalDragUpdate: _dragUpdate,
          onVerticalDragEnd: _dragEnd,
          child: child,
        );
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final topY = pad.top + 8;
      final headerBottom = topY + _thumb;
      const pillH = 44.0;
      final pillRestY = pad.top + 10;
      final pillOpenY = headerBottom + 12;
      final lyricsTop = pillOpenY + pillH + 8;
      final heroH = (h - _ctrlH - pad.bottom - 10).clamp(120.0, h);

      return AnimatedBuilder(
        animation: _c,
        child: _MeasureSize(
          onSize: (s) {
            if ((s.height - _ctrlH).abs() > 1) {
              setState(() => _ctrlH = s.height);
            }
          },
          child: widget.controls,
        ),
        builder: (context, controls) {
          final t = _c.value;
          final out = (1 - (t * 3)).clamp(0.0, 1.0); // controls: gone by 1/3
          final hero = Rect.lerp(
            Rect.fromLTWH(0, 0, w, heroH),
            Rect.fromLTWH(_gutter, topY, _thumb, _thumb),
            t,
          )!;
          return Stack(children: [
            // lyrics: rise from the bottom, fade in with the offset
            if (t > 0.001)
              Positioned(
                left: 0,
                right: 0,
                top: lyricsTop,
                bottom: pad.bottom + 140, // above the seek bar + transport
                child: IgnorePointer(
                  ignoring: t < .9,
                  child: Opacity(
                    opacity: Curves.easeIn.transform(t),
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 60),
                      child: LayoutBuilder(
                        builder: (_, lc) => x.lyrics(t > .02
                            ? Size(lc.maxWidth, lc.maxHeight)
                            : Size.zero),
                      ),
                    ),
                  ),
                ),
              ),
            // controls: slide down + fade out
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: t > .15,
                child: Opacity(
                  opacity: out,
                  child: Transform.translate(
                    offset: Offset(0, 120 * t),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: controls,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // cover → thumbnail
            Positioned.fromRect(
              rect: hero,
              child: grab(GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: t > .9 ? x.toggleLyrics : null,
                child: widget.hero(t),
              )),
            ),
            // title row: slides in from above, alpha = offset
            if (t > 0.001)
              Positioned(
                left: _gutter + _thumb + 12,
                right: _gutter,
                top: topY,
                height: _thumb,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, -(1 - t) * _thumb * 2),
                    child: grab(Row(children: [
                      Expanded(
                        child: _titles(x, Colors.white,
                            Colors.white.withValues(alpha: .78), size: 15),
                      ),
                      _playing((s) => _Tap(
                            onTap: _toggle,
                            tip: s == ButtonState.playing ? 'Pause' : 'Play',
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                  shape: BoxShape.circle, color: Colors.white),
                              child: Icon(
                                  s == ButtonState.playing
                                      ? _Ic.pause
                                      : _Ic.play,
                                  size: 24,
                                  color: Colors.black),
                            ),
                          )),
                      const SizedBox(width: 6),
                      _ibtn(Icons.keyboard_arrow_down_rounded, x.toggleLyrics,
                          'Close lyrics',
                          size: 26, c: Colors.white, pad: 8),
                    ])),
                  ),
                ),
              ),
            // Song · Lyrics · Queue pill: glides from the top edge to just
            // under the title row
            Positioned(
              top: pillRestY + (pillOpenY - pillRestY) * t,
              left: 0,
              right: 0,
              child: Center(child: grab(widget.pill)),
            ),
            // seek bar + transport, fade in at the bottom with the lyrics
            if (t > 0.001)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: t < .9,
                  child: Opacity(
                    opacity: Curves.easeIn.transform(t),
                    child: Transform.translate(
                      offset: Offset(0, (1 - t) * 40),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                          child: _lyricsFooter(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      );
    });
  }

  Widget _lyricsFooter() => Column(mainAxisSize: MainAxisSize.min, children: [
        _bar(Colors.white, Colors.white24, h: 18, t: 6, th: _Thumb.none),
        _times(Colors.white.withValues(alpha: .78), fs: 11.5),
        const SizedBox(height: 2),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ibtn(_Ic.prev, widget.x.prev, 'Previous',
              size: 34, c: Colors.white, pad: 10),
          _playing((s) => _Tap(
                onTap: _toggle,
                tip: s == ButtonState.playing ? 'Pause' : 'Play',
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.white),
                  child: s == ButtonState.loading
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: Colors.black))
                      : Icon(
                          s == ButtonState.playing ? _Ic.pause : _Ic.play,
                          size: 30,
                          color: Colors.black),
                ),
              )),
          _ibtn(_Ic.next, widget.x.next, 'Next',
              size: 34, c: Colors.white, pad: 10),
        ]),
      ]);
}

/// Reports its child's size after layout (no rebuild when it is unchanged).
class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onSize, required this.child});
  final ValueChanged<Size> onSize;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && mounted) widget.onSize(box.size);
    });
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

class PlayerSkinPage extends StatelessWidget {
  const PlayerSkinPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Player screen'.tr)),
      body: ValueListenableBuilder<String>(
        valueListenable: PlayerSkinPrefs.skin,
        builder: (context, name, _) {
          final cur = PlayerSkin.fromName(name);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                children: [
                  ZenSection(children: [
                    for (final s in PlayerSkin.values)
                      ZenRow(
                        icon: s.icon,
                        title: s.label,
                        subtitle: s.desc,
                        onTap: () => PlayerSkinPrefs.set(s.name),
                        trailing: s == cur
                            ? Icon(ZenIcons.check, size: 22, color: cs.primary)
                            : null,
                      ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
