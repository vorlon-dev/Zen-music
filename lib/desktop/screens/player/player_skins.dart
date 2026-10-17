// ZenMusic Desktop — full-screen player layouts ("skins").
//
// Classic is the app's default player page (this file draws nothing for it).
// The seven skins below are complete screens: each has its own header,
// controls, seek control and gestures. All of them drive the same engine
// (MediaPlayer via GetIt) and the callbacks in PlayerCtx, so every button
// and gesture does the real thing:
//
//   vinyl       Turntable. Record spins while playing, tonearm follows the
//               song. Tap record = play/pause, swipe = previous/next,
//               long-press = lyrics.
//   editorial   Big type, plain text controls. Swipe the artwork to skip.
//   lyricsFirst Lyrics fill the screen; compact controls below.
//   polaroid    Artwork as a printed photo. Swipe the photo to skip.
//   radio       Tuning dial = seek bar. Knobs set volume and speed
//               (drag or scroll wheel, double-tap resets).
//   studio      Fader seek bar, volume fader, speed presets.
//   ring        Drag around the artwork to seek. Tap = play/pause,
//               double-tap = favourite, swipe = previous/next.
//
// Every skin is drawn on a fixed design canvas and scaled with FittedBox, so
// it looks the same on phones and desktop windows.
//
// Icons follow the platform: Cupertino on iOS/macOS, Material elsewhere.

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:just_audio_background/just_audio_background.dart'
    show MediaItem;

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';

// ════════════════════════════════════════════════════════════════════
// SKIN LIST + CONTEXT
// ════════════════════════════════════════════════════════════════════

enum PlayerSkin {
  classic('Classic', 'The standard Zen layout', Icons.music_note_outlined),
  vinyl('Turntable', 'Spinning record with a tonearm that follows the song',
      Icons.album_outlined),
  editorial('Editorial', 'Large type with plain text controls',
      Icons.article_outlined),
  lyricsFirst('Lyrics', 'Lyrics fill the screen, compact controls below',
      Icons.lyrics_outlined),
  polaroid('Polaroid', 'Artwork as a printed photo, swipe to change song',
      Icons.photo_outlined),
  radio('Tabletop radio',
      'Tuning dial for seeking, knobs for volume and speed',
      Icons.radio_outlined),
  studio('Studio', 'Fader seek bar, volume fader and speed presets',
      Icons.tune),
  ring('Ring', 'Drag around the artwork to seek',
      Icons.radio_button_unchecked);

  const PlayerSkin(this.label, this.desc, this.icon);
  final String label, desc;
  final IconData icon;

  /// Safe restore from a saved `skin.name` (unknown or removed skins fall
  /// back to classic).
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
  });

  final MediaItem song;
  final int index, total; // 1-based position in the queue
  final String quality; // e.g. "High, 256 kbps" or "Auto"
  final bool hasLyrics, showLyrics;
  final Color? tint; // palette colour of the front artwork (if known)
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

  /// Listen to this (ValueListenableBuilder). First access starts the load.
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
    skin; // make sure loading has started
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
    PlayerSkin.vinyl => _Vinyl(ctx),
    PlayerSkin.editorial => _Editorial(ctx),
    PlayerSkin.lyricsFirst => _LyricsFirst(ctx),
    PlayerSkin.polaroid => _Polaroid(ctx),
    PlayerSkin.radio => _Radio(ctx),
    PlayerSkin.studio => _Studio(ctx),
    PlayerSkin.ring => _Ring(ctx),
    PlayerSkin.classic => const SizedBox.shrink(),
  };
}

// ════════════════════════════════════════════════════════════════════
// SHARED: icons
// ════════════════════════════════════════════════════════════════════

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
  static IconData get photo =>
      _a ? CupertinoIcons.photo : Icons.image_outlined;
}

// ════════════════════════════════════════════════════════════════════
// SHARED: engine hooks
// ════════════════════════════════════════════════════════════════════

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
      FontStyle? st,
      double ls = 0,
      double h = 1.2,
      bool tab = false}) =>
    TextStyle(
      fontSize: size,
      color: c,
      fontWeight: w,
      fontStyle: st,
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

/// Progress feed: fraction, position, total, playing, seek(fraction).
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

/// Artwork slot that swaps to lyrics. The lyrics box stays mounted (so
/// lyrics keep being discovered) and is only measured when visible.
/// [invert] shows lyrics by default and artwork when toggled.
Widget _media(PlayerCtx x, Size size,
    {required Widget art,
      Color bg = Colors.black,
      double radius = 0,
      bool invert = false}) {
  final on = x.hasLyrics && (invert ? !x.showLyrics : x.showLyrics);
  return SizedBox.fromSize(
    size: size,
    child: Stack(
      children: [
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
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════
// SHARED: small widgets
// ════════════════════════════════════════════════════════════════════

/// Press-scale + pointer cursor + optional tooltip.
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

/// Fixed design canvas scaled to fit; `back` fills the whole window.
class _Stage extends StatelessWidget {
  const _Stage(
      {required this.w,
        required this.h,
        required this.back,
        required this.child});
  final double w, h;
  final Widget back, child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Stack(
      fit: StackFit.expand,
      children: [
        back,
        SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(width: w, height: h, child: child),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Icon button. [mark] (when not null) reserves and shows a small dot under
/// the icon, used for on/off toggles.
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
    opacity: t == null ? 0.35 : (on ? 1 : 0.55),
    child: _Tap(
      onTap: t,
      tip: tip,
      child: Padding(padding: EdgeInsets.all(pad), child: child),
    ),
  );
}

Widget _favBtn(PlayerCtx x, Color c, Color onC, {double size = 24}) =>
    _fav(
      x.song,
          (l, t) => _ibtn(l ? _Ic.heartFill : _Ic.heart, t,
          l ? 'Remove from favourites' : 'Add to favourites',
          size: size, c: l ? onC : c),
    );

Widget _shufBtn(Color c, {double size = 22}) => _shuffle((on, t) => _ibtn(
    _Ic.shuffle, t, on ? 'Shuffle: on' : 'Shuffle: off',
    size: size, c: c, on: on, mark: on));

Widget _repBtn(Color c, {double size = 22}) => _repeat((m, t) => _ibtn(
    m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
    t,
    m == LoopMode.off
        ? 'Repeat: off'
        : m == LoopMode.one
        ? 'Repeat: one'
        : 'Repeat: all',
    size: size,
    c: c,
    on: m != LoopMode.off,
    mark: m != LoopMode.off));

Widget _lyrBtn(PlayerCtx x, Color c, {double size = 22}) {
  final on = x.showLyrics && x.hasLyrics;
  return _ibtn(_Ic.lyrics, x.hasLyrics ? x.toggleLyrics : null,
      on ? 'Hide lyrics' : 'Show lyrics',
      size: size, c: c, on: on, mark: on);
}

Widget _moreBtn(PlayerCtx x, Color c) => Builder(
  builder: (ctx) =>
      _ibtn(_Ic.more, () => _more(ctx, x.song), 'More', c: c),
);

/// Round play/pause button with a loading spinner state.
Widget _playBtn({required double size, required Color bg, required Color fg}) =>
    _playing((s) => _Tap(
      onTap: _toggle,
      tip: s == ButtonState.playing ? 'Pause' : 'Play',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
        child: s == ButtonState.loading
            ? Padding(
          padding: EdgeInsets.all(size * 0.3),
          child: CircularProgressIndicator(strokeWidth: 3, color: fg),
        )
            : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
            size: size * 0.46, color: fg),
      ),
    ));

/// Swipe left = next, right = previous, optional tap / long-press / double-tap.
Widget _swipe(PlayerCtx x, Widget child,
    {VoidCallback? onTap, VoidCallback? onLong, VoidCallback? onDouble}) =>
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onDoubleTap: onDouble,
      onLongPress: onLong,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) {
          x.next();
        } else if (v > 300) {
          x.prev();
        }
      },
      child: child,
    );

/// Horizontal drag / tap seeker. While dragging it previews locally and
/// commits on release (or continuously when [live], e.g. for volume).
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

enum _Thumb { dot, tick, cap, none }

class _LinePainter extends CustomPainter {
  const _LinePainter(
      this.f, this.active, this.inactive, this.t, this.thumb, this.thumbColor);
  final double f, t;
  final Color active, inactive, thumbColor;
  final _Thumb thumb;

  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2, x = f * s.width;
    final p = Paint()
      ..strokeWidth = t
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(0, y), Offset(s.width, y), p..color = inactive);
    c.drawLine(Offset(0, y), Offset(x, y), p..color = active);
    final tp = Paint()..color = thumbColor;
    switch (thumb) {
      case _Thumb.dot:
        c.drawCircle(Offset(x, y), t * 2.2, tp);
      case _Thumb.tick:
        c.drawRect(
            Rect.fromCenter(
                center: Offset(x, y), width: 3, height: s.height * 0.7),
            tp);
      case _Thumb.cap:
        final r = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 16, height: 28),
            const Radius.circular(4));
        c.drawRRect(r, tp);
        c.drawLine(Offset(x, y - 8), Offset(x, y + 8),
            Paint()..color = Colors.black38..strokeWidth = 2);
      case _Thumb.none:
        break;
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) => true;
}

/// Seek bar wired to the engine.
Widget _bar(Color a, Color i,
    {double h = 28,
      double t = 3,
      _Thumb th = _Thumb.dot,
      Color? thumb}) =>
    _progress((f, p, tot, pl, seek) => _Seeker(
      f: f,
      onSeek: seek,
      height: h,
      paint: (v) => _LinePainter(v, a, i, t, th, thumb ?? a),
    ));

Widget _times(TextStyle st, {bool remaining = false}) =>
    _progress((f, p, tot, pl, s) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(_fmt(p), style: st),
        Text(
            remaining
                ? '-${_fmt(tot > p ? tot - p : Duration.zero)}'
                : _fmt(tot),
            style: st),
      ],
    ));

// ════════════════════════════════════════════════════════════════════
// 1. TURNTABLE
// ════════════════════════════════════════════════════════════════════

class _Vinyl extends StatefulWidget {
  const _Vinyl(this.x);
  final PlayerCtx x;

  @override
  State<_Vinyl> createState() => _VinylState();
}

class _VinylState extends State<_Vinyl> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _bg = Color(0xFF1B1C1E);
  static const _plinth = Color(0xFF26282B);
  static const _ink = Color(0xFFECEAE6);
  static const _dim = Color(0xFF9A9893);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _mp.buttonState.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (!mounted) return;
    if (_mp.buttonState.value == ButtonState.playing) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _mp.buttonState.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  Widget _deck(PlayerCtx x) => SizedBox(
    width: 360,
    height: 360,
    child: Stack(children: [
      Positioned(
        left: 20,
        top: 40,
        width: 300,
        height: 300,
        child: _swipe(
          x,
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Transform.rotate(
              angle: _c.value * 2 * math.pi,
              child: Stack(children: [
                const Positioned.fill(
                    child: CustomPaint(painter: _Grooves())),
                Center(
                  child: ClipOval(
                    child: SizedBox(width: 108, height: 108, child: x.art(0)),
                  ),
                ),
              ]),
            ),
          ),
          onTap: _toggle,
          onLong: x.hasLyrics ? x.toggleLyrics : null,
        ),
      ),
      const Positioned(
        left: 20,
        top: 40,
        width: 300,
        height: 300,
        child: IgnorePointer(child: CustomPaint(painter: _Sheen())),
      ),
      Positioned(
        left: 166,
        top: 186,
        child: IgnorePointer(
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: _plinth),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: _playing((s) => _progress(
                (f, p, t, pl, seek) => TweenAnimationBuilder<double>(
              tween: Tween<double>(
                  end: s == ButtonState.playing ? 0.12 + 0.34 * f : -0.08),
              duration: const Duration(milliseconds: 350),
              builder: (_, v, __) =>
                  CustomPaint(painter: _Arm(v)),
            ),
          )),
        ),
      ),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final x = widget.x;
    return _Stage(
      w: 400,
      h: 780,
      back: const ColoredBox(color: _bg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _ink),
            Expanded(
              child: Center(
                child: _Tap(
                  onTap: x.openQuality,
                  tip: 'Audio quality',
                  child: Text(x.quality,
                      style: _s(13, _dim, w: FontWeight.w500)),
                ),
              ),
            ),
            _moreBtn(x, _ink),
          ]),
          const SizedBox(height: 10),
          Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              color: _plinth,
              borderRadius: BorderRadius.circular(24),
            ),
            child: _media(x, const Size(360, 360),
                bg: _plinth, radius: 24, art: _deck(x)),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(x.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(24, _ink, w: FontWeight.w700, ls: -0.3)),
                  Text(x.song.artist ?? x.song.album ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(16, _dim, w: FontWeight.w500)),
                ],
              ),
            ),
            _favBtn(x, _dim, _ink, size: 26),
          ]),
          const SizedBox(height: 6),
          _bar(_ink, Colors.white24),
          _times(_s(12, _dim, w: FontWeight.w500, tab: true)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shufBtn(_ink),
            _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _ink),
            _playBtn(size: 72, bg: _ink, fg: _bg),
            _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _ink),
            _repBtn(_ink),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _lyrBtn(x, _ink),
            const SizedBox(width: 28),
            _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _ink, size: 22),
          ]),
        ]),
      ),
    );
  }
}

class _Grooves extends CustomPainter {
  const _Grooves();

  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero), r = s.width / 2;
    c.drawCircle(o, r, Paint()..color = const Color(0xFF0F0F10));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (double g = 60; g < r - 3; g += 3.6) {
      final k = (g / 3.6).floor() % 5 == 0;
      p.color = Colors.white.withValues(alpha: k ? 0.07 : 0.035);
      c.drawCircle(o, g, p);
    }
    c.drawCircle(
        o,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF2A2A2C));
    c.drawCircle(
        o,
        57,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFB9B5AB));
  }

  @override
  bool shouldRepaint(_Grooves o) => false;
}

class _Sheen extends CustomPainter {
  const _Sheen();

  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero), r = s.width / 2;
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0x14FFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x0FFFFFFF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, .07, .14, .5, .57, .64, 1],
        ).createShader(Rect.fromCircle(center: o, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_Sheen o) => false;
}

/// Tonearm. [t] is the angle from straight down, towards the record.
class _Arm extends CustomPainter {
  const _Arm(this.t);
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final p = const Offset(322, 34);
    final dir = Offset(-math.sin(t), math.cos(t));
    final tip = p + dir * 226;
    final tail = p - dir * 40;
    Paint line(Color col, double w) => Paint()
      ..color = col
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    c.drawLine(p + const Offset(3, 5), tip + const Offset(3, 5),
        line(Colors.black.withValues(alpha: 0.25), 6));
    c.drawLine(tail, p, line(const Color(0xFF7D7B77), 11));
    c.drawLine(p, tip, line(const Color(0xFFC9C7C2), 5));
    c.drawCircle(p, 17, Paint()..color = const Color(0xFF34363A));
    c.drawCircle(
        p,
        17,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF55575B));
    c.drawCircle(p, 6, Paint()..color = const Color(0xFFC9C7C2));
    c.drawCircle(tip, 6, Paint()..color = const Color(0xFFE8E6E1));
    c.drawCircle(
        tip,
        6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF8D8B87));
  }

  @override
  bool shouldRepaint(_Arm o) => o.t != t;
}

// ════════════════════════════════════════════════════════════════════
// 2. EDITORIAL
// ════════════════════════════════════════════════════════════════════

class _Editorial extends StatelessWidget {
  const _Editorial(this.x);
  final PlayerCtx x;

  static const _paper = Color(0xFFE8EAEB);
  static const _ink = Color(0xFF141414);
  static const _red = Color(0xFFD8352A);

  Widget _link(String t, VoidCallback? tap, bool on) => _Tap(
    onTap: tap,
    child: Opacity(
      opacity: tap == null ? 0.35 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 15,
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
            color: on ? _ink : _ink.withValues(alpha: 0.6),
            decoration: on ? TextDecoration.underline : TextDecoration.none,
            decorationColor: _red,
            decorationThickness: 2.5,
          ),
        ),
      ),
    ),
  );

  Widget _box(Widget child, VoidCallback t, String tip, {bool filled = false}) =>
      _Tap(
        onTap: t,
        tip: tip,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? _ink : Colors.transparent,
            border: Border.all(color: _ink, width: 1.5),
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _Stage(
      w: 400,
      h: 780,
      back: const ColoredBox(color: _paper),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _link('Close', x.close, false),
              const Spacer(),
              Builder(
                builder: (c) => _link('More', () => _more(c, x.song), false),
              ),
            ]),
            Container(height: 2, color: _ink),
            const SizedBox(height: 14),
            SizedBox(
              height: 260,
              child: Row(children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                      border: Border.all(color: _ink, width: 1.5)),
                  child: _media(x, const Size(257, 257),
                      bg: _ink, art: x.swipeArt),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${x.index}'.padLeft(2, '0'),
                          style: _s(46, _ink, w: FontWeight.w800, h: 1)),
                      Text('of ${x.total}',
                          style: _s(14, _ink.withValues(alpha: 0.6),
                              w: FontWeight.w500)),
                      const Spacer(),
                      _Tap(
                        onTap: x.openQuality,
                        tip: 'Audio quality',
                        child: Text(x.quality,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _ink.withValues(alpha: 0.7),
                              decoration: TextDecoration.underline,
                              decorationColor: _ink.withValues(alpha: 0.4),
                            )),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            Text(x.song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _s(40, _ink, w: FontWeight.w800, ls: -1.2, h: 1.0)),
            const SizedBox(height: 6),
            Text(x.song.artist ?? x.song.album ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _s(20, _ink.withValues(alpha: 0.7), w: FontWeight.w500)),
            const SizedBox(height: 12),
            _bar(_ink, _ink.withValues(alpha: 0.18),
                h: 24, t: 2, th: _Thumb.tick),
            _times(_s(12, _ink.withValues(alpha: 0.65),
                w: FontWeight.w500, tab: true)),
            const Spacer(),
            Row(children: [
              Expanded(
                child: _box(Icon(_Ic.prev, size: 28, color: _ink), x.prev,
                    'Previous'),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _playing((s) {
                  final p = s == ButtonState.playing;
                  return _box(
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      s == ButtonState.loading
                          ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: _paper))
                          : Icon(p ? _Ic.pause : _Ic.play,
                          size: 26, color: _paper),
                      const SizedBox(width: 10),
                      Text(p ? 'Pause' : 'Play',
                          style: _s(18, _paper, w: FontWeight.w700)),
                    ]),
                    _toggle,
                    p ? 'Pause' : 'Play',
                    filled: true,
                  );
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _box(
                    Icon(_Ic.next, size: 28, color: _ink), x.next, 'Next'),
              ),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _fav(x.song, (l, t) => _link(l ? 'Liked' : 'Like', t, l)),
              _link('Lyrics', x.hasLyrics ? x.toggleLyrics : null,
                  x.showLyrics && x.hasLyrics),
              _shuffle((on, t) => _link('Shuffle', t, on)),
              _repeat((m, t) => _link(
                  m == LoopMode.off
                      ? 'Repeat'
                      : m == LoopMode.one
                      ? 'Repeat one'
                      : 'Repeat all',
                  t,
                  m != LoopMode.off)),
              _link('Queue', x.openQueue, false),
            ]),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 3. LYRICS
//    Lyrics are the screen. The artwork button swaps to the cover.
// ════════════════════════════════════════════════════════════════════

class _LyricsFirst extends StatelessWidget {
  const _LyricsFirst(this.x);
  final PlayerCtx x;

  static const _ink = Color(0xFFF1F1F2);

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(
        const Color(0xFF101112), x.tint ?? const Color(0xFF2A2D34), 0.4)!;
    final dim = _ink.withValues(alpha: 0.65);
    final art = x.showLyrics && x.hasLyrics;
    return _Stage(
      w: 400,
      h: 780,
      back: ColoredBox(color: bg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _ink),
            const SizedBox(width: 4),
            SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8), child: x.art(8)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(x.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(16, _ink, w: FontWeight.w700)),
                  Text(x.song.artist ?? x.song.album ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(13, dim, w: FontWeight.w500)),
                ],
              ),
            ),
            _moreBtn(x, _ink),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (c, b) => _media(
                x,
                Size(b.maxWidth, b.maxHeight),
                bg: Colors.transparent,
                invert: true,
                art: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox.square(
                      dimension: 300,
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: x.art(18)),
                    ),
                    if (!x.hasLyrics) ...[
                      const SizedBox(height: 16),
                      Text('No lyrics for this song',
                          style: _s(14, dim, w: FontWeight.w500)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _bar(_ink, Colors.white24, h: 24),
          _times(_s(12, dim, w: FontWeight.w500, tab: true)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shufBtn(_ink),
            _ibtn(_Ic.prev, x.prev, 'Previous', size: 32, c: _ink),
            _playBtn(size: 64, bg: _ink, fg: bg),
            _ibtn(_Ic.next, x.next, 'Next', size: 32, c: _ink),
            _repBtn(_ink),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _favBtn(x, dim, _ink),
            _ibtn(_Ic.photo, x.hasLyrics ? x.toggleLyrics : null,
                art ? 'Show lyrics' : 'Show artwork',
                c: _ink, size: 22, on: art, mark: art),
            _ibtn(_Ic.quality, x.openQuality, 'Audio quality',
                c: _ink, size: 22),
            _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _ink, size: 22),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 4. POLAROID
// ════════════════════════════════════════════════════════════════════

class _Polaroid extends StatelessWidget {
  const _Polaroid(this.x);
  final PlayerCtx x;

  static const _bg = Color(0xFF384047);
  static const _paper = Color(0xFFF7F7F5);
  static const _ink = Color(0xFF222222);
  static const _red = Color(0xFFC8372D);
  static const _light = Color(0xFFF1F1EE);

  @override
  Widget build(BuildContext context) {
    return _Stage(
      w: 400,
      h: 780,
      back: const ColoredBox(color: _bg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _light),
            Expanded(
              child: Center(
                child: _Tap(
                  onTap: x.openQuality,
                  tip: 'Audio quality',
                  child: Text(x.quality,
                      style: _s(13, _light.withValues(alpha: 0.75),
                          w: FontWeight.w500)),
                ),
              ),
            ),
            _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _light),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: 340,
            height: 414,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Transform.rotate(
                  angle: 0.05,
                  child: Container(
                    width: 312,
                    height: 388,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCDAD5),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 14,
                            offset: Offset(0, 6))
                      ],
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: -0.025,
                  child: Container(
                    width: 318,
                    height: 392,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    decoration: BoxDecoration(
                      color: _paper,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 20,
                            offset: Offset(0, 10))
                      ],
                    ),
                    child: Column(children: [
                      _media(x, const Size(290, 290),
                          bg: const Color(0xFF111111), art: x.swipeArt),
                      Expanded(
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(x.song.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _s(20, _ink, w: FontWeight.w700)),
                                Text(x.song.artist ?? x.song.album ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: _s(14, _ink.withValues(alpha: 0.6),
                                        w: FontWeight.w500)),
                              ],
                            ),
                          ),
                          _favBtn(x, _ink.withValues(alpha: 0.5), _red,
                              size: 26),
                        ]),
                      ),
                    ]),
                  ),
                ),
                Positioned(
                  top: -4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.06,
                      child: Container(
                        width: 92,
                        height: 26,
                        color: const Color(0xCCD8D1B8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _bar(_light, Colors.white24),
          _times(_s(12, _light.withValues(alpha: 0.7),
              w: FontWeight.w500, tab: true)),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shufBtn(_light),
            _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _light),
            _playBtn(size: 72, bg: _paper, fg: _ink),
            _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _light),
            _repBtn(_light),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _lyrBtn(x, _light),
            const SizedBox(width: 28),
            _moreBtn(x, _light),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 5. TABLETOP RADIO
//    Dial = seek bar (drag or tap). Left knob = volume, right knob =
//    playback speed. Drag a knob up/down or scroll over it; double-tap
//    resets. The grille area turns into the lyrics panel.
// ════════════════════════════════════════════════════════════════════

class _Radio extends StatelessWidget {
  const _Radio(this.x);
  final PlayerCtx x;

  static const _body = Color(0xFFD7D9D6);
  static const _ink = Color(0xFF212223);
  static const _red = Color(0xFFC8372D);
  static const _win = Color(0xFF151617);
  static const _light = Color(0xFFE9E9E5);
  static const _key = Color(0xFF3A3C3E);

  /// Small rubber key with an indicator bar.
  Widget _k(IconData i, VoidCallback? t, String tip,
      {bool on = false, double w = 48}) =>
      Opacity(
        opacity: t == null ? 0.4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: Container(
            width: w,
            height: 38,
            decoration: BoxDecoration(
              color: _key,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Stack(alignment: Alignment.center, children: [
              Icon(i, size: 20, color: _light),
              Positioned(
                top: 5,
                child: Container(
                    width: 14, height: 2.5, color: on ? _red : Colors.transparent),
              ),
            ]),
          ),
        ),
      );

  Widget _t(Widget child, VoidCallback t, String tip, {bool lit = false}) =>
      _Tap(
        onTap: t,
        tip: tip,
        child: Container(
          width: double.infinity,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: _key,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Stack(alignment: Alignment.center, children: [
            child,
            Positioned(
              top: 7,
              child: Container(
                width: 18,
                height: 3,
                decoration: BoxDecoration(
                  color: lit ? _red : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _volumeKnob() => StreamBuilder<double>(
    stream: _mp.player.volumeStream,
    initialData: _mp.player.volume,
    builder: (_, s) {
      final v = (s.data ?? 1.0).clamp(0.0, 1.0).toDouble();
      return _Knob(
        v: v,
        label: 'Volume',
        readout: '${(v * 100).round()}%',
        onChanged: (n) => _mp.player.setVolume(n),
        onReset: () => _mp.player.setVolume(1),
      );
    },
  );

  Widget _speedKnob() => StreamBuilder<double>(
    stream: _mp.player.speedStream,
    initialData: _mp.player.speed,
    builder: (_, s) {
      final sp = (s.data ?? 1.0).clamp(0.5, 2.0).toDouble();
      return _Knob(
        v: (sp - 0.5) / 1.5,
        label: 'Speed',
        readout: '${(sp * 100).round() / 100}×',
        onChanged: (n) =>
            _mp.player.setSpeed(((0.5 + n * 1.5) * 20).round() / 20),
        onReset: () => _mp.player.setSpeed(1),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return _Stage(
      w: 400,
      h: 780,
      back: const ColoredBox(color: Color(0xFF2B2D2F)),
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _body,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
                color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))
          ],
        ),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _ink),
            Expanded(
              child: Center(
                child: _Tap(
                  onTap: x.openQuality,
                  tip: 'Audio quality',
                  child: Text(x.quality,
                      style: _s(13, _ink.withValues(alpha: 0.7),
                          w: FontWeight.w500)),
                ),
              ),
            ),
            _moreBtn(x, _ink),
          ]),
          const SizedBox(height: 8),
          Container(
            height: 92,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _win,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              SizedBox(
                width: 68,
                height: 68,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(6), child: x.art(6)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _s(16, _light, w: FontWeight.w600)),
                    Text(x.song.artist ?? x.song.album ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _s(13, _light.withValues(alpha: 0.6),
                            w: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _progress((f, p, t, pl, s) => Text(_fmt(p),
                  style: _s(22, _light, w: FontWeight.w600, tab: true))),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            height: 88,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _light,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF9A9C98)),
            ),
            child: _progress((f, p, tot, pl, seek) => _Seeker(
              f: f,
              onSeek: seek,
              height: 88,
              paint: (v) => _DialPainter(v, tot, _ink, _red),
            )),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _volumeKnob(),
            Column(mainAxisSize: MainAxisSize.min, children: [
              _fav(
                x.song,
                    (l, t) => _k(l ? _Ic.heartFill : _Ic.heart, t,
                    l ? 'Remove from favourites' : 'Add to favourites',
                    on: l),
              ),
              const SizedBox(height: 10),
              _k(_Ic.lyrics, x.hasLyrics ? x.toggleLyrics : null,
                  x.showLyrics ? 'Hide lyrics' : 'Show lyrics',
                  on: x.showLyrics && x.hasLyrics),
            ]),
            _speedKnob(),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _t(Icon(_Ic.prev, size: 26, color: _light), x.prev,
                  'Previous'),
            ),
            Expanded(
              child: _playing((s) => _t(
                s == ButtonState.loading
                    ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: _light))
                    : Icon(
                    s == ButtonState.playing ? _Ic.pause : _Ic.play,
                    size: 28,
                    color: _light),
                _toggle,
                s == ButtonState.playing ? 'Pause' : 'Play',
                lit: s == ButtonState.playing,
              )),
            ),
            Expanded(
              child: _t(Icon(_Ic.next, size: 26, color: _light), x.next, 'Next'),
            ),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shuffle((on, t) =>
                _k(_Ic.shuffle, t, on ? 'Shuffle: on' : 'Shuffle: off',
                    on: on, w: 100)),
            _repeat((m, t) => _k(
                m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
                t,
                m == LoopMode.off
                    ? 'Repeat: off'
                    : m == LoopMode.one
                    ? 'Repeat: one'
                    : 'Repeat: all',
                on: m != LoopMode.off,
                w: 100)),
            _k(_Ic.queue, x.openQueue, 'Queue', w: 100),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (c, b) => _media(
                x,
                Size(b.maxWidth, b.maxHeight),
                bg: _win,
                radius: 10,
                art: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: const Color(0xFFCDD0CC),
                    child: CustomPaint(
                        painter: const _Grille(), size: Size.infinite),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({
    required this.v,
    required this.onChanged,
    required this.label,
    required this.readout,
    this.onReset,
  });
  final double v;
  final ValueChanged<double> onChanged;
  final String label, readout;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF212223);
    return Column(children: [
      Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            onChanged((v - e.scrollDelta.dy / 600).clamp(0.0, 1.0).toDouble());
          }
        },
        child: GestureDetector(
          onPanUpdate: (d) => onChanged(
              (v - (d.delta.dy - d.delta.dx) / 170).clamp(0.0, 1.0).toDouble()),
          onDoubleTap: onReset,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeUpDown,
            child: SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(painter: _KnobPainter(v)),
            ),
          ),
        ),
      ),
      Text(label, style: _s(12, ink, w: FontWeight.w700)),
      Text(readout,
          style: _s(12, ink.withValues(alpha: 0.65),
              w: FontWeight.w500, tab: true)),
    ]);
  }
}

class _KnobPainter extends CustomPainter {
  const _KnobPainter(this.v);
  final double v;

  Offset _dir(double t) => Offset(math.sin(t), -math.cos(t));

  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero);
    final mark = Paint()
      ..color = const Color(0x88212223)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 10; i++) {
      final d = _dir(-2.356 + 4.712 * i / 10);
      c.drawLine(o + d * 36, o + d * 40, mark);
    }
    c.drawCircle(
        o + const Offset(0, 2), 31, Paint()..color = const Color(0x40000000));
    c.drawCircle(o, 31, Paint()..color = const Color(0xFF3B3D3F));
    final ridge = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..strokeWidth = 1.2;
    for (var k = 0; k < 36; k++) {
      final d = _dir(k * 2 * math.pi / 36);
      c.drawLine(o + d * 28, o + d * 31, ridge);
    }
    c.drawCircle(o, 25, Paint()..color = const Color(0xFF45484B));
    final d = _dir(-2.356 + 4.712 * v);
    c.drawLine(
        o + d * 9,
        o + d * 23,
        Paint()
          ..color = const Color(0xFFE9E9E5)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_KnobPainter o) => o.v != v;
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.f, this.total, this.ink, this.red);
  final double f;
  final Duration total;
  final Color ink, red;

  @override
  void paint(Canvas c, Size s) {
    final base = s.height - 12;
    final tick = Paint()
      ..color = ink.withValues(alpha: 0.75)
      ..strokeWidth = 1.2;
    for (var i = 0; i <= 60; i++) {
      final x = s.width * i / 60;
      final h = i % 10 == 0 ? 22.0 : (i % 5 == 0 ? 15.0 : 9.0);
      c.drawLine(Offset(x, base), Offset(x, base - h), tick);
    }
    c.drawLine(Offset(0, base), Offset(s.width, base),
        Paint()..color = ink..strokeWidth = 1.4);
    for (final i in const [0, 15, 30, 45, 60]) {
      final label = _fmt(Duration(
          milliseconds: (total.inMilliseconds * i / 60).round()));
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                fontSize: 11,
                color: ink,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = s.width * i / 60;
      final dx = i == 0 ? 0.0 : (i == 60 ? -tp.width : -tp.width / 2);
      tp.paint(c, Offset(x + dx, 6));
    }
    final nx = f * s.width;
    c.drawLine(Offset(nx, 24), Offset(nx, s.height - 4),
        Paint()..color = red..strokeWidth = 2);
    c.drawPath(
        Path()
          ..moveTo(nx - 5, 20)
          ..lineTo(nx + 5, 20)
          ..lineTo(nx, 28)
          ..close(),
        Paint()..color = red);
  }

  @override
  bool shouldRepaint(_DialPainter o) => true;
}

class _Grille extends CustomPainter {
  const _Grille();

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x4D212223);
    var r = 0;
    for (double y = 9; y < s.height; y += 10, r++) {
      for (double x = r.isEven ? 8 : 13; x < s.width; x += 10) {
        c.drawCircle(Offset(x, y), 1.8, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Grille o) => false;
}

// ════════════════════════════════════════════════════════════════════
// 6. STUDIO
//    Fader seek bar, transport keys, volume fader and speed presets.
// ════════════════════════════════════════════════════════════════════

class _Studio extends StatelessWidget {
  const _Studio(this.x);
  final PlayerCtx x;

  static const _bg = Color(0xFF1D1F22);
  static const _panel = Color(0xFF272A2E);
  static const _line = Color(0xFF3A3E43);
  static const _ink = Color(0xFFE7E8EA);
  static const _dim = Color(0xFF8C9096);
  static const _acc = Color(0xFF9DB8D6);

  Widget _key(Widget child, VoidCallback? t, String tip,
      {bool hot = false, double h = 52}) =>
      Opacity(
        opacity: t == null ? 0.4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: Container(
            height: h,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hot ? _acc : _line,
              borderRadius: BorderRadius.circular(10),
            ),
            child: child,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _Stage(
      w: 400,
      h: 780,
      back: const ColoredBox(color: _bg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _ink),
            Expanded(
              child: Center(
                child: Text(x.song.album ?? 'Queue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _s(13, _dim, w: FontWeight.w500)),
              ),
            ),
            _moreBtn(x, _ink),
          ]),
          const SizedBox(height: 6),
          _media(x, const Size(300, 300),
              radius: 10,
              bg: _panel,
              art: ClipRRect(
                  borderRadius: BorderRadius.circular(10), child: x.swipeArt)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(x.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(22, _ink, w: FontWeight.w700)),
                  Text(x.song.artist ?? x.song.album ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _s(15, _dim, w: FontWeight.w500)),
                ],
              ),
            ),
            _favBtn(x, _dim, _acc),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              _progress((f, p, tot, pl, s) => Row(children: [
                Text(_fmt(p),
                    style: _s(26, _ink, w: FontWeight.w600, tab: true)),
                const Spacer(),
                Text('-${_fmt(tot > p ? tot - p : Duration.zero)}',
                    style: _s(16, _dim, w: FontWeight.w500, tab: true)),
              ])),
              const SizedBox(height: 2),
              _bar(_acc, _line, h: 30, t: 6, th: _Thumb.cap, thumb: _ink),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(width: 40, child: Center(child: _shufBtn(_ink, size: 20))),
                Expanded(
                  child: _key(Icon(_Ic.prev, size: 24, color: _ink), x.prev,
                      'Previous'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _playing((s) => _key(
                    s == ButtonState.loading
                        ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: _bg))
                        : Icon(
                        s == ButtonState.playing ? _Ic.pause : _Ic.play,
                        size: 28,
                        color: _bg),
                    _toggle,
                    s == ButtonState.playing ? 'Pause' : 'Play',
                    hot: true,
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _key(
                      Icon(_Ic.next, size: 24, color: _ink), x.next, 'Next'),
                ),
                SizedBox(width: 40, child: Center(child: _repBtn(_ink, size: 20))),
              ]),
              const SizedBox(height: 12),
              StreamBuilder<double>(
                stream: _mp.player.volumeStream,
                initialData: _mp.player.volume,
                builder: (_, s) {
                  final v = (s.data ?? 1.0).clamp(0.0, 1.0).toDouble();
                  return Row(children: [
                    Icon(_Ic.volume, size: 20, color: _dim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Seeker(
                        f: v,
                        live: true,
                        height: 28,
                        onSeek: (n) => _mp.player.setVolume(n),
                        paint: (n) =>
                            _LinePainter(n, _ink, _line, 4, _Thumb.dot, _ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 40,
                      child: Text('${(v * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: _s(13, _dim, w: FontWeight.w500, tab: true)),
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 10),
              StreamBuilder<double>(
                stream: _mp.player.speedStream,
                initialData: _mp.player.speed,
                builder: (_, s) {
                  final cur = s.data ?? 1.0;
                  return Row(children: [
                    for (final sp in const [0.75, 1.0, 1.25, 1.5])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _key(
                            Text(sp == 1.0 ? '1×' : '$sp×',
                                style: _s(13, (cur - sp).abs() < 0.01 ? _bg : _ink,
                                    w: FontWeight.w700)),
                                () => _mp.player.setSpeed(sp),
                            'Playback speed',
                            hot: (cur - sp).abs() < 0.01,
                            h: 34,
                          ),
                        ),
                      ),
                  ]);
                },
              ),
            ]),
          ),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _lyrBtn(x, _ink),
            _ibtn(_Ic.quality, x.openQuality, 'Audio quality',
                c: _ink, size: 22),
            _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _ink, size: 22),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 7. RING
//    Drag around the ring to seek. Tap the artwork = play/pause,
//    double-tap = favourite, swipe = previous/next.
// ════════════════════════════════════════════════════════════════════

class _Ring extends StatelessWidget {
  const _Ring(this.x);
  final PlayerCtx x;

  static const _ink = Color(0xFFF1F1F2);

  Widget _ring() => _progress((f, p, tot, pl, seek) => _RingSeek(
    f: f,
    onSeek: seek,
    center: _fav(
      x.song,
          (l, t) => _swipe(x, x.art(0), onTap: _toggle, onDouble: t),
    ),
  ));

  @override
  Widget build(BuildContext context) {
    final bg = Color.lerp(
        const Color(0xFF0F1114), x.tint ?? const Color(0xFF2A2F3A), 0.3)!;
    final dim = _ink.withValues(alpha: 0.65);
    final lyricsOn = x.showLyrics && x.hasLyrics;
    return _Stage(
      w: 400,
      h: 780,
      back: ColoredBox(color: bg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(children: [
          Row(children: [
            _ibtn(_Ic.down, x.close, 'Close', c: _ink),
            Expanded(
              child: Center(
                child: _Tap(
                  onTap: x.openQuality,
                  tip: 'Audio quality',
                  child: Text(x.quality, style: _s(13, dim, w: FontWeight.w500)),
                ),
              ),
            ),
            _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _ink),
          ]),
          const SizedBox(height: 10),
          _media(x, const Size(340, 340),
              bg: Colors.black26, radius: 28, art: _ring()),
          SizedBox(
            height: 24,
            child: lyricsOn ? _bar(_ink, Colors.white24, h: 24) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _times(_s(13, dim, w: FontWeight.w500, tab: true),
                remaining: true),
          ),
          const SizedBox(height: 10),
          Text(x.song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _s(26, _ink, w: FontWeight.w700, ls: -0.3)),
          Text(x.song.artist ?? x.song.album ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _s(16, dim, w: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _favBtn(x, dim, _ink),
            const SizedBox(width: 20),
            _lyrBtn(x, _ink),
            const SizedBox(width: 20),
            _moreBtn(x, _ink),
          ]),
          const Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shufBtn(_ink),
            _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _ink),
            _playBtn(size: 76, bg: _ink, fg: bg),
            _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _ink),
            _repBtn(_ink),
          ]),
        ]),
      ),
    );
  }
}

class _RingSeek extends StatefulWidget {
  const _RingSeek(
      {required this.f, required this.onSeek, required this.center});
  final double f;
  final ValueChanged<double> onSeek;
  final Widget center;

  @override
  State<_RingSeek> createState() => _RingSeekState();
}

class _RingSeekState extends State<_RingSeek> {
  static const _size = 340.0;
  double? _d;
  bool _drag = false, _band = false;

  bool _inBand(Offset o) {
    final d = (o - const Offset(_size / 2, _size / 2)).distance;
    return d > 132 && d < 172;
  }

  double _at(Offset o) {
    final dx = o.dx - _size / 2, dy = o.dy - _size / 2;
    var a = math.atan2(dy, dx) + math.pi / 2;
    if (a < 0) a += 2 * math.pi;
    return (a / (2 * math.pi)).clamp(0.0, 1.0).toDouble();
  }

  void _commit(double v) {
    widget.onSeek(v);
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_drag) setState(() => _d = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: GestureDetector(
        onTapUp: (d) {
          if (_inBand(d.localPosition)) {
            final v = _at(d.localPosition);
            setState(() => _d = v);
            _commit(v);
          }
        },
        onPanStart: (d) {
          _band = _inBand(d.localPosition);
          if (_band) {
            setState(() {
              _drag = true;
              _d = _at(d.localPosition);
            });
          }
        },
        onPanUpdate: (d) {
          if (_band) setState(() => _d = _at(d.localPosition));
        },
        onPanEnd: (_) {
          if (_band) {
            _drag = false;
            final v = _d;
            if (v != null) _commit(v);
          }
          _band = false;
        },
        onPanCancel: () => setState(() {
          _drag = false;
          _band = false;
          _d = null;
        }),
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(painter: _RingPainter(_d ?? widget.f)),
          ),
          Center(
            child: ClipOval(
              child: SizedBox(width: 252, height: 252, child: widget.center),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.f);
  final double f;

  @override
  void paint(Canvas c, Size s) {
    final o = s.center(Offset.zero);
    const r = 150.0;
    final rect = Rect.fromCircle(center: o, radius: r);
    c.drawCircle(
        o,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..color = const Color(0x29FFFFFF));
    c.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFF1F1F2));
    final a = -math.pi / 2 + 2 * math.pi * f;
    final t = o + Offset(math.cos(a), math.sin(a)) * r;
    c.drawCircle(t + const Offset(0, 1.5), 10,
        Paint()..color = const Color(0x55000000));
    c.drawCircle(t, 9, Paint()..color = const Color(0xFFF1F1F2));
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.f != f;
}

// ════════════════════════════════════════════════════════════════════
// SETTINGS PICKER PAGE  (opened with Navigator.push from Settings)
// ════════════════════════════════════════════════════════════════════

class PlayerSkinPage extends StatelessWidget {
  const PlayerSkinPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Player screen')),
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