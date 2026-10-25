// ZenMusic Desktop — full-screen player layouts ("skins").
//
// Classic is the app's default player page (this file draws nothing for it).
// Each skin below is a COMPLETE, separate screen modelled on a real player.
// Every skin has its own phone layout and its own wide (desktop) layout:
//
//   appleMusic  Apple Music — drag handle, art shrinks on pause, thick bar,
//               volume. Desktop: the player centred on the blurred colour.
//   lastWave    LastWave (github.com/Clash-Projects/LastWave-Native) —
//               Material 3 Expressive "liquid glass": frosted glass panels
//               floating on a colourful artwork-tinted backdrop, wavy
//               progress bar, big morphing expressive play button.
//   bitChord    BitChord (github.com/kushagrasinghx/BitChord) — Apple-style
//               layout with a breathing album canvas, dynamic artwork
//               theming and a floating frosted-glass control bar.
//   echo        Echo Music (github.com/EchoMusicApp/Echo-Music) — clean
//               Material 3 player: tonal squircle buttons, FAB-style play,
//               dot slider, pill actions, dynamic colour from the artwork.
//   archiveTune ArchiveTune (github.com/rukamori/ArchiveTune) — Material You
//               "cute": extra-rounded cards, thick big-thumb slider, tonal
//               chips, saturated dynamic accents.
//
// All buttons drive the real engine (MediaPlayer via GetIt) and PlayerCtx.

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
  appleMusic('Apple Music style',
      'Artwork shrinks on pause, thick bar, volume slider',
      Icons.queue_music),
  lastWave('LastWave style',
      'Liquid glass panels, wavy progress, expressive play button',
      Icons.water_drop_outlined),
  bitChord('BitChord style',
      'Breathing artwork, dynamic theming, frosted glass bar',
      Icons.piano_outlined),
  echo('Echo Music style',
      'Material 3 tonal cards, FAB play, pill actions',
      Icons.surround_sound_outlined),
  archiveTune('ArchiveTune style',
      'Material You: extra-rounded cards, big-thumb slider',
      Icons.library_music_outlined);

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
    PlayerSkin.appleMusic => _Apple(ctx),
    PlayerSkin.lastWave => _LastWave(ctx),
    PlayerSkin.bitChord => _BitChord(ctx),
    PlayerSkin.echo => _Echo(ctx),
    PlayerSkin.archiveTune => _ArchiveTune(ctx),
    PlayerSkin.classic => const SizedBox.shrink(),
  };
}

// ════════════════════════════════════════════════════════════════════
// SHARED: icons + engine hooks
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

// ════════════════════════════════════════════════════════════════════
// SHARED: layout + colour helpers
// ════════════════════════════════════════════════════════════════════

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

/// Frosted "liquid glass" panel (LastWave / BitChord): blurs whatever is
/// behind it and lays a translucent wash + hairline border on top.
Widget _glass(Widget child,
    {double r = 24, double blur = 22, Color? bg, Color? border}) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg ?? Colors.white.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
                color: border ?? Colors.white.withValues(alpha: .16)),
          ),
          child: child,
        ),
      ),
    );

/// Circular glass icon button (LastWave / BitChord).
Widget _gbtn(IconData i, VoidCallback? t, String tip,
    {double size = 20, Color c = Colors.white}) =>
    Opacity(
      opacity: t == null ? .4 : 1,
      child: _Tap(
        onTap: t,
        tip: tip,
        child: _glass(
          Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Icon(i, size: size, color: c)),
          r: 22,
          blur: 16,
        ),
      ),
    );

/// Material tonal squircle button (Echo / ArchiveTune).
Widget _tonal(Widget child, VoidCallback? t, String tip, Color bg,
    {double w = 52, double h = 52, double r = 18}) =>
    Opacity(
      opacity: t == null ? .4 : 1,
      child: _Tap(
        onTap: t,
        tip: tip,
        child: Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(r)),
          child: child,
        ),
      ),
    );

/// Lyrics panel that fills its parent.
Widget _lyr(PlayerCtx x,
    {double r = 24, Color bg = const Color(0x14FFFFFF)}) =>
    ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: ColoredBox(
        color: bg,
        child: LayoutBuilder(
            builder: (_, b) => x.lyrics(Size(b.maxWidth, b.maxHeight))),
      ),
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

Widget _hdr(PlayerCtx x, Color ink, {Widget? mid, Widget? right}) =>
    Row(children: [
      _ibtn(_Ic.down, x.close, 'Close', c: ink),
      Expanded(child: Center(child: mid ?? const SizedBox.shrink())),
      right ?? _moreBtn(x, ink),
    ]);

Widget _caption(String a, String b, Color dim, Color ink) =>
    Column(mainAxisSize: MainAxisSize.min, children: [
      Text(a, style: _s(10, dim, w: FontWeight.w700, ls: 1.6)),
      Text(b,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _s(13, ink, w: FontWeight.w700)),
    ]);

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

/// `00:00 ━━━━●━━━ 03:37` in one row.
Widget _seekRow(Color ink, Color on, Color off,
    {double h = 20,
      double t = 3,
      _Thumb th = _Thumb.dot,
      double fs = 11}) =>
    _progress((f, p, tot, pl, seek) {
      final st = _s(fs, ink, w: FontWeight.w500, tab: true);
      return Row(children: [
        Text(_fmt(p), style: st),
        const SizedBox(width: 10),
        Expanded(
          child: _Seeker(
            f: f,
            onSeek: seek,
            height: h,
            paint: (v) => _LinePainter(v, on, off, t, th),
          ),
        ),
        const SizedBox(width: 10),
        Text(_fmt(tot), style: st),
      ]);
    });

// ════════════════════════════════════════════════════════════════════
// SHARED: small widgets
// ════════════════════════════════════════════════════════════════════

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

Widget _favBtn(PlayerCtx x, Color c, Color onC, {double size = 24}) => _fav(
  x.song,
      (l, t) => _ibtn(l ? _Ic.heartFill : _Ic.heart, t,
      l ? 'Remove from favourites' : 'Add to favourites',
      size: size, c: l ? onC : c),
);

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

Widget _moreBtn(PlayerCtx x, Color c) => Builder(
  builder: (ctx) =>
      _ibtn(_Ic.more, () => _more(ctx, x.song), 'More', c: c),
);

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

/// Pill button with an icon and a label.
Widget _pill(IconData i, String label, VoidCallback? t, Color ink,
    {bool on = false, double h = 44, Color? onC, Color? bg}) =>
    Opacity(
      opacity: t == null ? .4 : 1,
      child: _Tap(
        onTap: t,
        child: Container(
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg ?? ink.withValues(alpha: on ? .2 : .1),
            borderRadius: BorderRadius.circular(h / 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 18, color: on ? (onC ?? ink) : ink),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _s(13, ink, w: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );

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

Widget _vol(Color a, Color i) => StreamBuilder<double>(
  stream: _mp.player.volumeStream,
  initialData: _mp.player.volume,
  builder: (_, s) {
    final v = (s.data ?? 1.0).clamp(0.0, 1.0).toDouble();
    return Row(children: [
      Icon(_Ic.volume, size: 16, color: a.withValues(alpha: 0.7)),
      const SizedBox(width: 8),
      Expanded(
        child: _Seeker(
          f: v,
          live: true,
          height: 24,
          onSeek: (n) => _mp.player.setVolume(n),
          paint: (n) => _LinePainter(n, a, i, 4, _Thumb.none),
        ),
      ),
      const SizedBox(width: 8),
      Icon(_Ic.volume, size: 22, color: a.withValues(alpha: 0.7)),
    ]);
  },
);

/// Material 3 Expressive wavy progress (LastWave). The wave undulates
/// continuously — [anim] supplies both the phase and the repaint signal.
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

/// Owns the repeating ticker that keeps the LastWave wave moving —
/// the phase loops every 1.6 s so the bar truly undulates.
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

/// Dynamic Material palette derived from the artwork tint
/// (LastWave / Echo / ArchiveTune).
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

// ════════════════════════════════════════════════════════════════════
// 1. APPLE MUSIC
// ════════════════════════════════════════════════════════════════════

class _Apple extends StatelessWidget {
  const _Apple(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;

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

  Widget _col() {
    final dim = Colors.white.withValues(alpha: .6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 14),
      child: Column(children: [
        _Tap(
          onTap: x.close,
          tip: 'Close',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.white38,
                  borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
        Expanded(
          child: _playing((s) => AnimatedScale(
            scale: s == ButtonState.playing ? 1 : 0.86,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            child: _art(x, r: 14),
          )),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _titles(x, _w, dim, size: 22, w: FontWeight.w700)),
          _fav(
            x.song,
                (l, t) => _rb(
                Icon(l ? _Ic.heartFill : _Ic.heart, size: 17, color: _w),
                t,
                'Favourite'),
          ),
          const SizedBox(width: 10),
          Builder(
            builder: (c) => _rb(Icon(_Ic.more, size: 17, color: _w),
                    () => _more(c, x.song), 'More'),
          ),
        ]),
        const SizedBox(height: 12),
        _bar(_w, Colors.white24, h: 18, t: 7, th: _Thumb.none),
        _times(
          dim,
          rem: true,
          mid: _Tap(
            onTap: x.openQuality,
            tip: 'Audio quality',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(x.quality,
                  style: _s(10, dim, w: FontWeight.w700, ls: .5)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _ibtn(_Ic.prev, x.prev, 'Previous', size: 46, c: _w),
          _bare(_w, 70),
          _ibtn(_Ic.next, x.next, 'Next', size: 46, c: _w),
        ]),
        const SizedBox(height: 4),
        _vol(_w, Colors.white24),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _shufBtn(_w),
          _lyrBtn(x, _w),
          _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _w),
          _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w),
          _repBtn(_w),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return _shell(
      _grad([_dark(t, .9), _dark(t, .55), _dark(t, .3)]),
      LayoutBuilder(
        builder: (_, c) => _isWide(c)
            ? Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: _col()))
            : _col(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 2. LASTWAVE — Liquid Glass + Material 3 Expressive
//    Modelled on github.com/Clash-Projects/LastWave-Native
// ════════════════════════════════════════════════════════════════════

class _LastWave extends StatelessWidget {
  const _LastWave(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;

  /// Colourful glass backdrop: artwork tint + soft light blobs.
  Widget _bg(Color t) => Stack(fit: StackFit.expand, children: [
    _grad([_dark(t, .8), _dark(t, .42), _dark(t, .18)]),
    Align(
      alignment: const Alignment(-.85, -.75),
      child: Container(
        width: 340,
        height: 340,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              colors: [t.withValues(alpha: .38), Colors.transparent]),
        ),
      ),
    ),
    Align(
      alignment: const Alignment(.9, .85),
      child: Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
              colors: [_w.withValues(alpha: .09), Colors.transparent]),
        ),
      ),
    ),
  ]);

  /// M3 Expressive wavy seek bar — animated, full-width wave.
  Widget _wavy(_Pal p) => _WavyBar(p.prim, _w.withValues(alpha: .18));

  /// Big expressive play button — pill that tightens while playing.
  Widget _play(_Pal p) => _playing((s) => _Tap(
    onTap: _toggle,
    tip: s == ButtonState.playing ? 'Pause' : 'Play',
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: 104,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.prim,
        borderRadius:
        BorderRadius.circular(s == ButtonState.playing ? 26 : 36),
        boxShadow: _shadow(26, 10, .4),
      ),
      child: s == ButtonState.loading
          ? SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: p.onPrim))
          : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
          size: 36, color: p.onPrim),
    ),
  ));

  Widget _ctl(_Pal p) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: p.prim),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 36, c: _w),
        _play(p),
        _ibtn(_Ic.next, x.next, 'Next', size: 36, c: _w),
        _repBtn(_w, onC: p.prim),
      ]);

  Widget _glassBar(_Pal p) => _glass(
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _lyrBtn(x, _w, onC: p.prim),
        _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w),
        _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _w),
      ]),
    ),
    r: 26,
  );

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return _shell(
      _bg(t),
      LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(_Pal.of(t)) : _mobile(_Pal.of(t))),
    );
  }

  Widget _mobile(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(children: [
      Row(children: [
        _gbtn(_Ic.down, x.close, 'Close'),
        const Spacer(),
        _caption('LASTWAVE', x.song.album ?? 'Liquid player',
            Colors.white60, _w),
        const Spacer(),
        Builder(
          builder: (c) =>
              _gbtn(_Ic.more, () => _more(c, x.song), 'More'),
        ),
      ]),
      const SizedBox(height: 10),
      Expanded(child: _art(x, r: 30)),
      const SizedBox(height: 18),
      _titles(x, _w, Colors.white70, size: 24, center: true),
      const SizedBox(height: 14),
      _wavy(p),
      _times(Colors.white70, fs: 12),
      const SizedBox(height: 8),
      _ctl(p),
      const SizedBox(height: 16),
      _glassBar(p),
    ]),
  );

  Widget _wide(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
    child: Column(children: [
      Row(children: [
        _gbtn(_Ic.down, x.close, 'Close'),
        const Spacer(),
        _caption('LASTWAVE', x.song.album ?? 'Liquid player',
            Colors.white60, _w),
        const Spacer(),
        _gbtn(_Ic.queue, x.openQueue, 'Queue'),
      ]),
      const SizedBox(height: 14),
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: _glass(
              Padding(
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  Expanded(child: _art(x, r: 26, swap: false)),
                  const SizedBox(height: 16),
                  _titles(x, _w, Colors.white70, size: 26, center: true),
                  const SizedBox(height: 14),
                  _wavy(p),
                  _times(Colors.white70),
                  const SizedBox(height: 10),
                  _ctl(p),
                  const SizedBox(height: 12),
                  SizedBox(
                      height: 24,
                      child: _vol(_w, _w.withValues(alpha: .18))),
                ]),
              ),
              r: 34,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: _glass(
                _lyr(x, r: 34, bg: Colors.transparent), r: 34),
          ),
        ]),
      ),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
// 3. BITCHORD — Apple-style layout, breathing album canvas, frosted bar
//    Modelled on github.com/kushagrasinghx/BitChord
// ════════════════════════════════════════════════════════════════════

class _BitChord extends StatelessWidget {
  const _BitChord(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;
  static const _heart = Color(0xFFFF6B81);

  /// Animated album canvas — artwork breathes while paused/playing
  /// (BitChord's motion artwork).
  Widget _canvas() => _playing((s) => AnimatedScale(
    scale: s == ButtonState.playing ? 1 : .92,
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    child: _art(x, r: 24),
  ));

  Widget _gCircle(Widget child, VoidCallback? t, String tip) => Opacity(
    opacity: t == null ? .4 : 1,
    child: _Tap(
      onTap: t,
      tip: tip,
      child: _glass(
        Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: child),
        r: 20,
        blur: 16,
      ),
    ),
  );

  Widget _ctl() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 44, c: _w),
        _playBtn(size: 70, bg: _w, fg: Colors.black),
        _ibtn(_Ic.next, x.next, 'Next', size: 44, c: _w),
      ]);

  /// Floating frosted-glass bar (Haze-style): pills row on phones,
  /// full transport bar with seek line + volume on desktop.
  Widget _frost(_Pal p, {bool wide = false}) => _glass(
    Padding(
      padding: EdgeInsets.symmetric(
          horizontal: wide ? 18 : 6, vertical: wide ? 10 : 4),
      child: wide
          ? Column(mainAxisSize: MainAxisSize.min, children: [
        _seekRow(Colors.white60, _w, _w.withValues(alpha: .2),
            h: 14, t: 3),
        const SizedBox(height: 4),
        Row(children: [
          _mini(x, 52, 12),
          const SizedBox(width: 12),
          Expanded(
              child: _titles(x, _w, Colors.white70, size: 15)),
          _shufBtn(_w, onC: p.prim),
          _ibtn(_Ic.prev, x.prev, 'Previous', size: 26, c: _w),
          _playBtn(size: 44, bg: _w, fg: Colors.black),
          _ibtn(_Ic.next, x.next, 'Next', size: 26, c: _w),
          _repBtn(_w, onC: p.prim),
          const SizedBox(width: 8),
          _favBtn(x, Colors.white70, p.prim),
          _lyrBtn(x, _w, onC: p.prim),
          _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _w),
          const SizedBox(width: 8),
          SizedBox(
              width: 110,
              child: _vol(_w, _w.withValues(alpha: .2))),
        ]),
      ])
          : Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _shufBtn(_w, onC: p.prim),
        _lyrBtn(x, _w, onC: p.prim),
        _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w),
        _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _w),
        _repBtn(_w, onC: p.prim),
      ]),
    ),
    r: 30,
  );

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return _shell(
      _grad([_dark(t, .95), _dark(t, .5), _dark(t, .28)]),
      LayoutBuilder(
        builder: (_, c) => _isWide(c) ? _wide(_Pal.of(t)) : _mobile(_Pal.of(t)),
      ),
    );
  }

  Widget _mobile(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    child: Column(children: [
      _Tap(
        onTap: x.close,
        tip: 'Close',
        child: Padding(
          padding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
          child: Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(3)),
          ),
        ),
      ),
      Expanded(child: _canvas()),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: _titles(x, _w, Colors.white70,
                size: 22, w: FontWeight.w700)),
        _fav(
          x.song,
              (l, t2) => _gCircle(
              Icon(l ? _Ic.heartFill : _Ic.heart,
                  size: 18, color: l ? _heart : _w),
              t2,
              'Favourite'),
        ),
        const SizedBox(width: 10),
        Builder(
          builder: (c) => _gCircle(Icon(_Ic.more, size: 18, color: _w),
              () => _more(c, x.song), 'More'),
        ),
      ]),
      const SizedBox(height: 12),
      _bar(_w, _w.withValues(alpha: .22), h: 16, t: 5, th: _Thumb.none),
      _times(Colors.white60, rem: true, fs: 11),
      const SizedBox(height: 10),
      _ctl(),
      const SizedBox(height: 12),
      _frost(p),
    ]),
  );

  Widget _wide(_Pal p) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(children: [
        _gCircle(Icon(_Ic.down, size: 20, color: _w), x.close, 'Close'),
        const Spacer(),
        Text('BITCHORD · ${x.song.album ?? 'Now playing'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _s(11, Colors.white60, ls: 1.6)),
        const Spacer(),
        _gCircle(Icon(_Ic.queue, size: 20, color: _w), x.openQueue,
            'Queue'),
      ]),
    ),
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 10, 32, 16),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              Expanded(child: _canvas()),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: _titles(x, _w, Colors.white70,
                    size: 28, w: FontWeight.w700),
              ),
            ]),
          ),
          const SizedBox(width: 28),
          Expanded(
            flex: 6,
            child: _glass(
                _lyr(x, r: 28, bg: Colors.transparent), r: 28),
          ),
        ]),
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: _frost(p, wide: true),
    ),
  ]);
}

// ════════════════════════════════════════════════════════════════════
// 4. ECHO MUSIC — clean Material 3 player
//    Modelled on github.com/EchoMusicApp/Echo-Music
// ════════════════════════════════════════════════════════════════════

class _Echo extends StatelessWidget {
  const _Echo(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;

  Widget _favTonal(_Pal p) => _fav(
    x.song,
        (l, t) => _tonal(
        Icon(l ? _Ic.heartFill : _Ic.heart,
            size: 22, color: l ? p.prim : _w),
        t,
        'Favourite',
        p.tonal,
        r: 26),
  );

  /// M3 FAB-style play button — pill that tightens while playing.
  Widget _playFab(_Pal p) => _playing((s) => _Tap(
    onTap: _toggle,
    tip: s == ButtonState.playing ? 'Pause' : 'Play',
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 92,
      height: 66,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.prim,
        borderRadius:
        BorderRadius.circular(s == ButtonState.playing ? 22 : 33),
      ),
      child: s == ButtonState.loading
          ? SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 3, color: p.onPrim))
          : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
          size: 34, color: p.onPrim),
    ),
  ));

  Widget _ctl(_Pal p) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shuffle((on, t) => _tonal(
            Icon(_Ic.shuffle, size: 22, color: on ? p.prim : _w),
            t,
            on ? 'Shuffle: on' : 'Shuffle: off',
            p.tonal,
            r: 26)),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 40, c: _w),
        _playFab(p),
        _ibtn(_Ic.next, x.next, 'Next', size: 40, c: _w),
        _repeat((m, t) => _tonal(
            Icon(m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
                size: 22, color: m == LoopMode.off ? _w : p.prim),
            t,
            m == LoopMode.off
                ? 'Repeat: off'
                : m == LoopMode.one
                ? 'Repeat: one'
                : 'Repeat: all',
            p.tonal,
            r: 26)),
      ]);

  /// Icon-only tonal square (Echo) — pill labels truncated on phones,
  /// so the four actions below use icons with tooltips instead.
  Widget _sqr(Widget icon, VoidCallback? t, String tip, Color bg) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          tip: tip,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(24)),
            child: icon,
          ),
        ),
      );

  Widget _pills(_Pal p) => Row(children: [
    Expanded(
      child: _fav(x.song, (l, t) => _sqr(
          Icon(l ? _Ic.heartFill : _Ic.heart,
              size: 22, color: l ? p.prim : _w),
          t,
          l ? 'Remove from favourites' : 'Add to favourites',
          p.tonal)),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: _sqr(
          Icon(_Ic.lyrics,
              size: 22,
              color: x.showLyrics && x.hasLyrics ? p.prim : _w),
          x.hasLyrics ? x.toggleLyrics : null,
          'Lyrics',
          p.tonal),
    ),
    const SizedBox(width: 10),
    Expanded(
        child: _sqr(Icon(_Ic.queue, size: 22, color: _w),
            x.openQueue, 'Queue', p.tonal)),
    const SizedBox(width: 10),
    Expanded(
        child: _sqr(Icon(_Ic.quality, size: 22, color: _w),
            x.openQuality, 'Quality', p.tonal)),
  ]);

  @override
  Widget build(BuildContext context) {
    final p = _Pal.of(_t(x));
    return _shell(
      ColoredBox(color: p.surf),
      LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(p) : _mobile(p)),
    );
  }

  Widget _mobile(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(children: [
      Row(children: [
        _tonal(Icon(_Ic.down, size: 24, color: _w), x.close, 'Close',
            p.tonal,
            r: 26),
        const Spacer(),
        _caption('ECHO MUSIC', x.song.album ?? 'Now playing',
            Colors.white54, _w),
        const Spacer(),
        Builder(
          builder: (c) => _tonal(Icon(_Ic.more, size: 22, color: _w),
              () => _more(c, x.song), 'More', p.tonal,
              r: 26),
        ),
      ]),
      const SizedBox(height: 14),
      Expanded(child: _art(x, r: 26, shadow: false)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
            child: _titles(x, _w, Colors.white70,
                size: 26, w: FontWeight.w600)),
        _favTonal(p),
      ]),
      const SizedBox(height: 10),
      _bar(p.prim, _w.withValues(alpha: .22), h: 20, t: 4),
      _times(Colors.white70, fs: 12),
      const SizedBox(height: 8),
      _ctl(p),
      const SizedBox(height: 14),
      _pills(p),
    ]),
  );

  Widget _wide(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
    child: Column(children: [
      Row(children: [
        _tonal(Icon(_Ic.down, size: 24, color: _w), x.close, 'Close',
            p.tonal,
            r: 26),
        const Spacer(),
        _caption('ECHO MUSIC', x.song.album ?? 'Now playing',
            Colors.white54, _w),
        const Spacer(),
        Builder(
          builder: (c) => _tonal(Icon(_Ic.more, size: 22, color: _w),
              () => _more(c, x.song), 'More', p.tonal,
              r: 26),
        ),
      ]),
      const SizedBox(height: 16),
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              Expanded(
                  child: _art(x, r: 26, swap: false, shadow: false)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: _titles(x, _w, Colors.white70,
                        size: 26, w: FontWeight.w600)),
                _favTonal(p),
              ]),
              const SizedBox(height: 8),
              _bar(p.prim, _w.withValues(alpha: .22), h: 20, t: 4),
              _times(Colors.white70),
              const SizedBox(height: 6),
              _ctl(p),
              const SizedBox(height: 12),
              SizedBox(
                  height: 24,
                  child: _vol(_w, _w.withValues(alpha: .2))),
            ]),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 6,
            child: Column(children: [
              Expanded(child: _lyr(x, r: 28, bg: p.tonal)),
              const SizedBox(height: 14),
              _pills(p),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
// 5. ARCHIVETUNE — Material You "cute": extra rounded, colourful
//    Modelled on github.com/rukamori/ArchiveTune
// ════════════════════════════════════════════════════════════════════

class _ArchiveTune extends StatelessWidget {
  const _ArchiveTune(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;

  /// Round filled play button in the dynamic accent colour.
  Widget _play(_Pal p) => _playing((s) => _Tap(
    onTap: _toggle,
    tip: s == ButtonState.playing ? 'Pause' : 'Play',
    child: Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.prim,
          boxShadow: _shadow(22, 8, .35)),
      child: s == ButtonState.loading
          ? Padding(
          padding: const EdgeInsets.all(23),
          child: CircularProgressIndicator(
              strokeWidth: 3, color: p.onPrim))
          : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
          size: 38, color: p.onPrim),
    ),
  ));

  Widget _ctl(_Pal p) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: p.prim, size: 24),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 38, c: _w),
        _play(p),
        _ibtn(_Ic.next, x.next, 'Next', size: 38, c: _w),
        _repBtn(_w, onC: p.prim, size: 24),
      ]);

  /// Big rounded card that hugs the artwork (Material You container).
  Widget _artCard(_Pal p, {required bool swap}) => Container(
    padding: EdgeInsets.all(swap ? 12 : 16),
    decoration: BoxDecoration(
        color: p.tonal.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(48)),
    child: _art(x, r: 32, swap: swap, shadow: false),
  );

  @override
  Widget build(BuildContext context) {
    final p = _Pal.of(_t(x));
    return _shell(
      _grad([_dark(p.prim, .16), p.surf]),
      LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(p) : _mobile(p)),
    );
  }

  Widget _mobile(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
    child: Column(children: [
      _hdr(x, _w,
          mid: _caption('ARCHIVETUNE', x.song.album ?? 'Now playing',
              Colors.white60, _w)),
      const SizedBox(height: 10),
      Expanded(child: _artCard(p, swap: true)),
      const SizedBox(height: 16),
      _titles(x, _w, Colors.white70, size: 25, center: true),
      const SizedBox(height: 6),
      _favBtn(x, Colors.white70, p.prim, size: 28),
      const SizedBox(height: 8),
      _bar(p.prim, _w.withValues(alpha: .22), h: 26, t: 6),
      _times(Colors.white70, fs: 12),
      const SizedBox(height: 8),
      _ctl(p),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: _pill(_Ic.lyrics, 'Lyrics',
                x.hasLyrics ? x.toggleLyrics : null, _w,
                on: x.showLyrics && x.hasLyrics, onC: p.prim)),
        const SizedBox(width: 8),
        Expanded(child: _pill(_Ic.queue, 'Queue', x.openQueue, _w)),
        const SizedBox(width: 8),
        Expanded(child: _pill(_Ic.quality, 'Quality', x.openQuality, _w)),
      ]),
    ]),
  );

  Widget _wide(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 10, 28, 20),
    child: Column(children: [
      _hdr(x, _w,
          mid: _caption('ARCHIVETUNE', x.song.album ?? 'Now playing',
              Colors.white60, _w)),
      const SizedBox(height: 14),
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              Expanded(child: _artCard(p, swap: false)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _titles(x, _w, Colors.white70, size: 26)),
                _favBtn(x, Colors.white70, p.prim, size: 28),
              ]),
              const SizedBox(height: 8),
              _bar(p.prim, _w.withValues(alpha: .22), h: 26, t: 6),
              _times(Colors.white70),
              const SizedBox(height: 6),
              _ctl(p),
              const SizedBox(height: 10),
              SizedBox(
                  height: 24,
                  child: _vol(_w, _w.withValues(alpha: .2))),
            ]),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 6,
            child: _lyr(x, r: 36, bg: p.tonal.withValues(alpha: .6)),
          ),
        ]),
      ),
    ]),
  );
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
