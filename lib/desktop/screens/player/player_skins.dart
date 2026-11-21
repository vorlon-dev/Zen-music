// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:async' show StreamSubscription;
import 'package:audio_session/audio_session.dart'
    show AudioDevice, AudioSession;
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'package:zenmusic/desktop/screens/player/widgets/apple_mesh.dart';
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show EventChannel, HapticFeedback, MethodChannel;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'package:zenmusic/desktop/screens/settings/player/equalizer_page.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';


enum PlayerSkin {
  classic('Classic', 'The standard Zen layout', Icons.music_note_outlined),
  appleMusicMesh('Apple Music · Mesh',
      'Artwork-colour mesh, live lyric line, full-screen lyrics tab',
      Icons.gradient),
  simpLiquid('SimpMusic · Liquid glass',
      'Full-bleed artwork, blurred backdrop, live lyric line',
      Icons.blur_on),
  simpM3('SimpMusic · Material 3 Expressive',
      'Artwork-tinted palette, wavy seek bar, connected buttons',
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
    PlayerSkin.appleMusicMesh => _AppleMesh(ctx),
    PlayerSkin.simpLiquid => _SimpLiquid(ctx),
    PlayerSkin.simpM3 => _SimpM3(ctx),
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
  static IconData get shuffle =>
      _a ? CupertinoIcons.shuffle : Icons.shuffle_rounded;
  static IconData get repeat =>
      _a ? CupertinoIcons.repeat : Icons.repeat_rounded;
  static IconData get repeatOne =>
      _a ? CupertinoIcons.repeat_1 : Icons.repeat_one_rounded;
  static IconData get heart =>
      _a ? CupertinoIcons.heart : Icons.favorite_border_rounded;
  static IconData get heartFill =>
      _a ? CupertinoIcons.heart_fill : Icons.favorite_rounded;
  static IconData get queue =>
      _a ? CupertinoIcons.music_note_list : Icons.queue_music_rounded;
  static IconData get lyrics =>
      _a ? CupertinoIcons.text_quote : Icons.lyrics_outlined;
  static IconData get more =>
      _a ? CupertinoIcons.ellipsis : Icons.more_horiz_rounded;
  static IconData get down =>
      _a ? CupertinoIcons.chevron_down : Icons.keyboard_arrow_down_rounded;
  static IconData get volume =>
      _a ? CupertinoIcons.speaker_1 : Icons.volume_up_outlined;
  static IconData get quality =>
      _a ? CupertinoIcons.waveform : Icons.graphic_eq_rounded;
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

Widget _shuffle(Widget Function(bool on, VoidCallback tap) b) =>
    StreamBuilder<bool>(
      stream: _mp.player.shuffleModeEnabledStream,
      initialData: false,
      builder: (_, snap) {
        final on = snap.data ?? false;
        return b(on, () async {
          await _mp.player.setShuffleModeEnabled(!on);
          if (!on) await _mp.player.shuffle();
        });
      },
    );

Widget _repeat(Widget Function(LoopMode m, VoidCallback tap) b) =>
    ValueListenableBuilder<LoopMode>(
      valueListenable: _mp.loopMode,
      builder: (_, m, __) => b(m, () => _mp.changeLoopMode()),
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

/// Artwork slot that swaps to lyrics. The lyrics box stays mounted so lyrics
/// keep being discovered, and is only measured when visible.
Widget _media(PlayerCtx x, Size size,
    {required Widget art, Color bg = Colors.black, double radius = 0}) {
  final on = x.hasLyrics && x.showLyrics;
  return SizedBox.fromSize(
    size: size,
    child: Stack(children: [
      Positioned.fill(child: Offstage(offstage: on, child: art)),
      Positioned.fill(
        child: Offstage(
          offstage: !on,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: ColoredBox(
              color: bg,
              child: x.lyrics(on ? size : Size.zero),
            ),
          ),
        ),
      ),
    ]),
  );
}


bool _isWide(BoxConstraints c) =>
    c.maxWidth >= 820 && c.maxWidth > c.maxHeight * 1.15;

Color _t(PlayerCtx x, [Color d = const Color(0xFF3A4A6B)]) => x.tint ?? d;
Color _dark(Color c, double k) => Color.lerp(const Color(0xFF0B0B0D), c, k)!;

List<BoxShadow> _shadow(double blur, double dy, double a) => [
  BoxShadow(
      color: Colors.black.withValues(alpha: a),
      blurRadius: blur,
      offset: Offset(0, dy)),
];

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

Widget _shell(Widget bg, Widget child) => Material(
  type: MaterialType.transparency,
  child: Stack(fit: StackFit.expand, children: [
    bg,
    SafeArea(child: child),
  ]),
);

/// Square artwork that fills the free space of its parent.
/// [swap] lets the lyrics button swap the artwork for lyrics (phones).
Widget _art(PlayerCtx x,
    {double r = 8,
      bool swap = true,
      bool shadow = true,
      Color lbg = Colors.black54,
      Alignment al = Alignment.center}) =>
    LayoutBuilder(builder: (_, c) {
      final s = math.max(60.0, math.min(c.maxWidth, c.maxHeight));
      final img = ClipRRect(
          borderRadius: BorderRadius.circular(r), child: x.swipeArt);
      Widget a = swap
          ? _media(x, Size.square(s), radius: r, bg: lbg, art: img)
          : SizedBox.square(dimension: s, child: img);
      if (shadow) {
        a = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            boxShadow: _shadow(30, 14, .45),
          ),
          child: a,
        );
      }
      return Align(alignment: al, child: a);
    });

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

Widget _shufBtn(Color c, {Color? onC, double size = 22}) =>
    _shuffle((on, t) => _ibtn(
        _Ic.shuffle, t, on ? 'Shuffle: on' : 'Shuffle: off',
        size: size, c: on ? (onC ?? c) : c, on: on, mark: on));

Widget _repBtn(Color c, {Color? onC, double size = 22}) =>
    _repeat((m, t) => _ibtn(
        m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
        t,
        m == LoopMode.off
            ? 'Repeat: off'
            : m == LoopMode.one
            ? 'Repeat: one'
            : 'Repeat: all',
        size: size,
        c: m != LoopMode.off ? (onC ?? c) : c,
        on: m != LoopMode.off,
        mark: m != LoopMode.off));

Widget _lyrBtn(PlayerCtx x, Color c, {Color? onC, double size = 22}) {
  final on = x.showLyrics && x.hasLyrics;
  return _ibtn(_Ic.lyrics, x.hasLyrics ? x.toggleLyrics : null,
      on ? 'Hide lyrics' : 'Show lyrics',
      size: size, c: on ? (onC ?? c) : c, on: on, mark: on);
}

/// Play/pause drawn as a bare icon (Apple Music).
Widget _bare(Color ink, double size) => _playing((s) => _Tap(
  onTap: _toggle,
  tip: s == ButtonState.playing ? 'Pause' : 'Play',
  child: SizedBox(
    width: size + 12,
    height: size + 12,
    child: s == ButtonState.loading
        ? Padding(
      padding: EdgeInsets.all(size * 0.3),
      child: CircularProgressIndicator(strokeWidth: 3, color: ink),
    )
        : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
        size: size, color: ink),
  ),
));

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

Widget _vol(Color a, Color i) => _SysVol(a: a, i: i, t: 4, both: false);


class _WavyPainter extends CustomPainter {
  _WavyPainter(this.f, this.on, this.off, this.anim) : super(repaint: anim);
  final double f;
  final Color on, off;
  final Animation<double>? anim;

  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2, x = f * s.width;
    final ph = anim == null ? 0.0 : anim!.value * 2 * math.pi;
    const a = 4.2; // wave amplitude

    Path wave(double from, double to) {
      final path = Path()..moveTo(from, y + a * math.sin(from / 7 + ph));
      for (double i = from + 2; i <= to; i += 2) {
        path.lineTo(i, y + a * math.sin(i / 7 + ph));
      }
      return path;
    }

    // Unplayed rest of the track — the same wave, faded.
    c.drawPath(
        wave(x, s.width),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = off);

    // Played part — bright wave all the way to the playhead.
    c.drawPath(
        wave(0, x),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = on);

    // Round playhead riding the wave crest.
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y + a * math.sin(x / 7 + ph)),
                width: 5,
                height: 24),
            const Radius.circular(3)),
        Paint()..color = on);
  }

  @override
  bool shouldRepaint(_WavyPainter o) => f != o.f || on != o.on || off != o.off;
}

class _WavyBar extends StatefulWidget {
  const _WavyBar(this.on, this.off);
  final Color on, off;

  @override
  State<_WavyBar> createState() => _WavyBarState();
}

class _WavyBarState extends State<_WavyBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _progress(
        (f, pos, tot, pl, seek) => _Seeker(
          f: f,
          onSeek: seek,
          height: 32,
          paint: (v) => _WavyPainter(v, widget.on, widget.off, _c),
        ),
      );
}

/// Canvas video layer + legibility scrim, drawn between a skin's backdrop
/// and its content. Does nothing when there is no canvas.
Widget _canvasBg(PlayerCtx x) => Positioned.fill(
      child: Stack(fit: StackFit.expand, children: [
        x.canvas,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: x.canvasOn ? 1 : 0,
            duration: const Duration(milliseconds: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .18),
                    Colors.black.withValues(alpha: .22),
                    Colors.black.withValues(alpha: .74),
                  ],
                  stops: const [0, .42, 1],
                ),
              ),
            ),
          ),
        ),
      ]),
    );

/// Artwork fades out while the canvas owns the screen.
Widget _hideForCanvas(PlayerCtx x, Widget child) => AnimatedOpacity(
      opacity: x.canvasOn ? 0 : 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      child: child,
    );

class _Pal {
  const _Pal(this.prim, this.onPrim, this.surf, this.tonal);
  factory _Pal.of(Color t) {
    final h = HSLColor.fromColor(t);
    final prim = h.withLightness(.8).withSaturation(.55).toColor();
    final surf = Color.lerp(const Color(0xFF121316), t, .18)!;
    return _Pal(prim, _dark(t, .25), surf, Color.lerp(surf, prim, .22)!);
  }
  final Color prim, onPrim, surf, tonal;
}


/// Apple Music · Mesh. Based on SimpMusic's Apple Music player: a colour mesh
/// from the artwork, the sung line above the bar, and a lyrics tab that
/// replaces the artwork (the lyrics box stays mounted so lyrics keep loading).
class _AppleMesh extends StatelessWidget {
  const _AppleMesh(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;
  static final Color _dim = Colors.white.withValues(alpha: .6);

  ImageProvider? _provider() {
    final u = x.song.artUri;
    if (u == null) return null;
    if (u.scheme == 'file') return FileImage(File(u.toFilePath()));
    return NetworkImage(u.toString());
  }

  Widget _rb(Widget child, VoidCallback? t, String tip) => _Tap(
        onTap: t,
        tip: tip,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.white.withValues(alpha: .18)),
          child: child,
        ),
      );

  Widget _heart() => _fav(
        x.song,
        (l, t) => _rb(Icon(l ? _Ic.heartFill : _Ic.heart, size: 17, color: _w), t,
            'Favourite'),
      );

  Widget _moreB() => Builder(
        builder: (c) =>
            _rb(Icon(_Ic.more, size: 17, color: _w), () => _more(c, x.song), 'More'),
      );

  Widget _dock() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _shufBtn(_w),
          _lyrBtn(x, _w),
          _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w),
          _repBtn(_w),
        ]),
      );

  Widget _transport(double play, double skip) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ibtn(_Ic.prev, x.prev, 'Previous', size: skip, c: _w),
        _bare(_w, play),
        _ibtn(_Ic.next, x.next, 'Next', size: skip, c: _w),
      ]);

  Widget _mainLayer() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
        child: Column(children: [
          const SizedBox(height: 10),
          Expanded(
            child: _playing((s) => AnimatedScale(
                  scale: s == ButtonState.playing ? 1 : 0.86,
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  child: _hideForCanvas(x, _art(x, r: 16, swap: false)),
                )),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _titles(x, _w, _dim, size: 22, w: FontWeight.w700)),
            _heart(),
            const SizedBox(width: 10),
            _moreB(),
          ]),
          const SizedBox(height: 6),
          AppleLyricStrip(onTap: x.hasLyrics ? x.toggleLyrics : null),
          const SizedBox(height: 6),
          _bar(_w, Colors.white24, h: 18, t: 7, th: _Thumb.none),
          _times(
            _dim,
            rem: true,
            mid: _Tap(
              onTap: x.openQuality,
              tip: 'Audio quality',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.white38),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(x.quality, style: _s(10, _dim, w: FontWeight.w700, ls: .5)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _transport(70, 46),
          const SizedBox(height: 4),
          _vol(_w, Colors.white24),
          const SizedBox(height: 10),
          _dock(),
        ]),
      );

  Widget _lyricsLayer(bool shown) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
        child: Column(children: [
          const SizedBox(height: 10),
          Row(children: [
            _mini(x, 52, 10),
            const SizedBox(width: 12),
            Expanded(child: _titles(x, _w, _dim, size: 17, w: FontWeight.w700)),
            _heart(),
            const SizedBox(width: 10),
            _moreB(),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) =>
                  x.lyrics(shown ? Size(c.maxWidth, c.maxHeight) : Size.zero),
            ),
          ),
          const SizedBox(height: 6),
          _bar(_w, Colors.white24, h: 18, t: 5, th: _Thumb.none),
          _times(_dim, rem: true),
          const SizedBox(height: 2),
          _transport(56, 38),
          const SizedBox(height: 8),
          _dock(),
        ]),
      );

  Widget _body() {
    final on = x.hasLyrics && x.showLyrics;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          ignoring: on,
          child: AnimatedOpacity(
            opacity: on ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            child: _mainLayer(),
          ),
        ),
      ),
      Positioned.fill(
        child: HeldCrossfade(on: on, builder: (_, shown) => _lyricsLayer(shown)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return _shell(
      Stack(fit: StackFit.expand, children: [
        AppleMeshBackdrop(
          artKey: x.song.id,
          provider: _provider(),
          fallback: _t(x),
        ),
        _canvasBg(x),
      ]),
      LayoutBuilder(
        builder: (_, c) => _isWide(c)
            ? Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480), child: _body()))
            : _body(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  SimpMusic skins (Blur/Liquid glass + Material 3 Expressive)
// ─────────────────────────────────────────────────────────────────────────

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

/// SimpMusic Material 3 progress bar: wavy played part, straight thin
/// remainder with an end dot, round thumb.
class _M3Wave extends StatefulWidget {
  const _M3Wave(this.on, this.off);
  final Color on, off;

  @override
  State<_M3Wave> createState() => _M3WaveState();
}

class _M3WaveState extends State<_M3Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _progress(
        (f, pos, tot, pl, seek) => _Seeker(
          f: f,
          onSeek: seek,
          height: 30,
          paint: (v) => _M3WavePainter(v, widget.on, widget.off, _c, pl),
        ),
      );
}

class _M3WavePainter extends CustomPainter {
  _M3WavePainter(this.f, this.on, this.off, this.anim, this.playing)
      : super(repaint: anim);
  final double f;
  final Color on, off;
  final Animation<double> anim;
  final bool playing;

  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2;
    final x = (f * s.width).clamp(0.0, s.width).toDouble();
    final ph = playing ? anim.value * 2 * math.pi : 0.0;
    const amp = 3.4, k = 2 * math.pi / 22;

    // unplayed: straight thin line + end dot
    c.drawLine(
        Offset(x, y),
        Offset(math.max(x, s.width - 5), y),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..color = off);
    c.drawCircle(Offset(s.width - 3, y), 2.6, Paint()..color = on);

    // played: wave
    final path = Path()..moveTo(0, y + amp * math.sin(-ph));
    for (double i = 2; i <= x; i += 2) {
      path.lineTo(i, y + amp * math.sin(k * i - ph));
    }
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = on);

    // thumb
    c.drawCircle(Offset(x, y + amp * math.sin(k * x - ph)), 7.5,
        Paint()..color = on);
  }

  @override
  bool shouldRepaint(_M3WavePainter o) =>
      f != o.f || on != o.on || off != o.off || playing != o.playing;
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
    this.wavy = false,
    this.scrim,
  });
  final PlayerCtx x;
  final bool shown, wavy;
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
                wavy
                    ? _M3Wave(prim, prim.withValues(alpha: .32))
                    : _bar(ink, Colors.white24, h: 18, t: 6, th: _Thumb.none),
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
    _canvasBg(x),
  ]);

  /// Full-bleed artwork that fades into the blurred backdrop. Lyrics replace
  /// it (dark scrim) when the lyrics toggle is on.
  Widget _hero(BuildContext context, {double radius = 0, bool fade = true}) {
    return LayoutBuilder(builder: (_, c) {
      final side = math.max(c.maxWidth, c.maxHeight);
      Widget art = ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox.square(dimension: side, child: x.art(0)),
        ),
      );
      if (fade) {
        art = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, .80, 1],
          ).createShader(r),
          child: art,
        );
      } else {
        art = ClipRRect(borderRadius: BorderRadius.circular(radius), child: art);
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) => _swipeSong(x, d),
        child: _hideForCanvas(x, art),
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

// ═════════════════════════ 2 · Material 3 Expressive ═════════════════════
class _M3Pal {
  const _M3Pal(this.bg, this.prim, this.onPrim, this.cont, this.onCont,
      this.dim);
  factory _M3Pal.of(Color t) {
    final h = HSLColor.fromColor(t);
    final s = h.saturation.clamp(.28, .85).toDouble();
    Color c(double sat, double l) =>
        HSLColor.fromAHSL(1, h.hue, sat.clamp(0.0, 1.0).toDouble(), l)
            .toColor();
    return _M3Pal(
      c(s * .55, .07), // page
      c(s, .82), // primary (play, wave, thumb)
      c(s, .14), // on primary
      c(s * .45, .27), // tonal container
      c(s, .90), // on container
      c(s * .30, .76), // secondary text
    );
  }
  final Color bg, prim, onPrim, cont, onCont, dim;
}

class _SimpM3 extends StatelessWidget {
  const _SimpM3(this.x);
  final PlayerCtx x;

  Widget _btn(_M3Pal p, IconData i, VoidCallback? t, String tip,
      {double s = 44, double r = 22, bool on = false}) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: s,
            height: s,
            decoration: BoxDecoration(
              color: on ? p.prim : p.cont,
              borderRadius: BorderRadius.circular(r),
            ),
            child: Icon(i, size: s * .5, color: on ? p.onPrim : p.onCont),
          ),
        ),
      );

  Widget _head(_M3Pal p) => Row(children: [
    _btn(p, Icons.keyboard_arrow_down_rounded, x.close, 'Close'),
    Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('NOW PLAYING', style: _s(10.5, p.dim, ls: 1.2)),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            x.song.album?.isNotEmpty == true
                ? x.song.album!
                : '${x.index} of ${x.total}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _s(15, Colors.white, w: FontWeight.w700),
          ),
        ),
      ]),
    ),
    Builder(
      builder: (c) => _btn(p, Icons.more_vert_rounded,
              () => _more(c, x.song), 'More', r: 16),
    ),
  ]);

  Widget _info(_M3Pal p) => Row(children: [
    Expanded(
      child: _titles(x, Colors.white, p.dim, size: 22, w: FontWeight.w800),
    ),
    const SizedBox(width: 10),
    Builder(
      builder: (c) => _btn(p, Icons.add_circle_outline_rounded,
              () => _addToPlaylist(c, x.song), 'Add to playlist'),
    ),
    const SizedBox(width: 8),
    _fav(
      x.song,
          (l, t) => _btn(p, l ? _Ic.heartFill : _Ic.heart, t,
          l ? 'Remove from favourites' : 'Add to favourites',
          on: l),
    ),
  ]);

  Widget _seek(_M3Pal p) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        _M3Wave(p.prim, p.prim.withValues(alpha: .32)),
        _times(p.dim, fs: 12),
      ]);

  Widget _slot(_M3Pal p, Widget child, VoidCallback? t, String tip,
      BorderRadius r, double h,
      {Color? bg}) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: h,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg ?? p.cont, borderRadius: r),
            child: child,
          ),
        ),
      );

  /// [ ⏮ ]  [ ━━ ⏸ ━━ ]  [ ⏭ ]
  Widget _transport(_M3Pal p, double h) => Row(children: [
    Expanded(
      flex: 10,
      child: _slot(p, Icon(_Ic.prev, size: 30, color: p.onCont), x.prev,
          'Previous', BorderRadius.circular(h * .4), h),
    ),
    const SizedBox(width: 8),
    Expanded(
      flex: 22,
      child: _playing((s) => _slot(
        p,
        s == ButtonState.loading
            ? SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: p.onPrim))
            : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
            size: 36, color: p.onPrim),
        _toggle,
        s == ButtonState.playing ? 'Pause' : 'Play',
        // morph: squarer while playing, full pill when paused
        BorderRadius.circular(s == ButtonState.playing ? h * .38 : h / 2),
        h,
        bg: p.prim,
      )),
    ),
    const SizedBox(width: 8),
    Expanded(
      flex: 10,
      child: _slot(p, Icon(_Ic.next, size: 30, color: p.onCont), x.next,
          'Next', BorderRadius.circular(h * .4), h),
    ),
  ]);

  /// Connected tonal group: info · EQ · shuffle · repeat · timer · queue · lyrics
  Widget _actions(_M3Pal p) {
    const h = 52.0;
    const cap = Radius.circular(26);
    const inner = Radius.circular(8);
    BorderRadius r(bool first, bool last) => BorderRadius.only(
      topLeft: first ? cap : inner,
      bottomLeft: first ? cap : inner,
      topRight: last ? cap : inner,
      bottomRight: last ? cap : inner,
    );
    Widget ic(IconData i, Color c) => Icon(i, size: 22, color: c);

    return Builder(
      builder: (ctx) => Row(children: [
        Expanded(
          child: _slot(p, ic(Icons.info_outline_rounded, p.onCont),
              x.openQuality, 'Audio quality', r(true, false), h),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _slot(p, ic(Icons.headphones_rounded, p.onCont),
                  () => _openEq(ctx), 'Equalizer', r(false, false), h),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _shuffle((on, t) => _slot(
              p,
              ic(_Ic.shuffle, on ? p.onPrim : p.onCont),
              t,
              on ? 'Shuffle: on' : 'Shuffle: off',
              r(false, false),
              h,
              bg: on ? p.prim : null)),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _repeat((m, t) => _slot(
              p,
              ic(m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
                  m != LoopMode.off ? p.onPrim : p.onCont),
              t,
              m == LoopMode.off
                  ? 'Repeat: off'
                  : m == LoopMode.one
                  ? 'Repeat: one'
                  : 'Repeat: all',
              r(false, false),
              h,
              bg: m != LoopMode.off ? p.prim : null)),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _slot(p, ic(Icons.timer_outlined, p.onCont),
                  () => Modals.showTimerModal(ctx), 'Sleep timer',
              r(false, false), h),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _slot(p, ic(Icons.queue_music_rounded, p.onCont),
              x.openQueue, 'Queue', r(false, false), h),
        ),
        const SizedBox(width: 3),
        Expanded(
          child: _slot(
              p,
              ic(Icons.chat_bubble_outline_rounded,
                  x.showLyrics && x.hasLyrics ? p.onPrim : p.onCont),
              x.hasLyrics ? x.toggleLyrics : null,
              x.showLyrics ? 'Hide lyrics' : 'Show lyrics',
              r(false, true),
              h,
              bg: x.showLyrics && x.hasLyrics ? p.prim : null),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _M3Pal.of(_t(x));
    return Material(
      type: MaterialType.transparency,
      child: Stack(fit: StackFit.expand, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          color: p.bg,
        ),
        _canvasBg(x),
        _lyricsLayer(
          x,
          SafeArea(
            child: LayoutBuilder(
              builder: (_, c) => _isWide(c) ? _wide(p) : _phone(p, c),
            ),
          ),
          (shown) => _LyricsPage(
            x: x,
            shown: shown,
            ink: Colors.white,
            dim: p.dim,
            prim: p.prim,
            onPrim: p.onPrim,
            chip: p.cont,
            chipInk: p.onCont,
            wavy: true,
          ),
        ),
      ]),
    );
  }

  Widget _phone(_M3Pal p, BoxConstraints c) {
    final compact = c.maxHeight < 640;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 10, 24, compact ? 8 : 16),
          child: Column(children: [
            _head(p),
            SizedBox(height: compact ? 8 : 18),
            Expanded(
              child: _playing((s) => AnimatedScale(
                scale: s == ButtonState.playing ? 1 : .94,
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                child: _hideForCanvas(
                    x, _art(x, r: 30, shadow: false, swap: false)),
              )),
            ),
            SizedBox(height: compact ? 8 : 18),
            _info(p),
            const SizedBox(height: 2),
            _seek(p),
            SizedBox(height: compact ? 4 : 10),
            _transport(p, compact ? 60 : 72),
            SizedBox(height: compact ? 8 : 12),
            _actions(p),
          ]),
        ),
      ),
    );
  }

  Widget _wide(_M3Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 12, 32, 22),
    child: Row(children: [
      Expanded(
        child: Column(children: [
          _head(p),
          const SizedBox(height: 16),
          Expanded(
            child: _playing((s) => AnimatedScale(
              scale: s == ButtonState.playing ? 1 : .95,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              child: _hideForCanvas(
                  x, _art(x, r: 32, swap: false, shadow: false)),
            )),
          ),
        ]),
      ),
      const SizedBox(width: 40),
      SizedBox(
        width: 460,
        child: Column(children: [
          const Spacer(),
          const SizedBox(height: 16),
          _info(p),
          const SizedBox(height: 2),
          _seek(p),
          const SizedBox(height: 10),
          _transport(p, 72),
          const SizedBox(height: 12),
          _actions(p),
        ]),
      ),
    ]),
  );
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
