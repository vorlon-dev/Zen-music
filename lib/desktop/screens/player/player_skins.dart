// ZenMusic Desktop — full-screen player layouts ("skins").
//
// Classic is the app's default player page (this file draws nothing for it).
// Each skin below is a COMPLETE, separate screen modelled on a popular app.
// Every skin has its own phone layout and its own wide (desktop) layout:
//
//   spotify     Colour fade, white play button. Desktop: art + lyrics on top,
//               the classic bottom player bar underneath.
//   appleMusic  Drag handle, art shrinks on pause, thick bar, volume.
//               Desktop: the same player centred on the blurred colour.
//   ytMusic     Song/Lyrics switch, pill actions, tab strip. Desktop: seek
//               line on the top edge of the bottom bar, tabs on the right.
//   amazon      Centred titles, ring play button, Like/Lyrics/Queue pills.
//               Desktop: artwork on the RIGHT, text + lyrics on the left.
//   tidal       Edge-to-edge artwork, thin line, bare icons.
//               Desktop: artwork flush left, full height.
//   deezer      Rounded art, purple accent, lyrics drawer at the bottom.
//               Desktop: lyrics on the LEFT, player on the right.
//   soundcloud  Waveform seek bar, orange play. Desktop: banner on top.
//   pandora     Blue, bar under the art, five-button row, bottom tab strip.
//               Desktop: now-playing card with lyrics underneath.
//   material    Android Material-You: wavy progress, squircle buttons.
//               Desktop: art card + lyrics card + control card.
//   winamp      Classic Winamp windows with a green LCD.
//
// All buttons drive the real engine (MediaPlayer via GetIt) and PlayerCtx.

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

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
  spotify('Spotify style', 'Colour fade, white play button, bottom bar on desktop',
      Icons.graphic_eq),
  appleMusic('Apple Music style',
      'Artwork shrinks on pause, thick bar, volume slider',
      Icons.queue_music),
  ytMusic('YouTube Music style', 'Song / Lyrics switch, pills and tabs',
      Icons.smart_display_outlined),
  amazon('Amazon Music style', 'Centred titles, ring play button, pills',
      Icons.headphones_outlined),
  tidal('Tidal style', 'Edge-to-edge artwork, thin line, black',
      Icons.waves),
  deezer('Deezer style', 'Rounded artwork, purple, lyrics drawer',
      Icons.equalizer),
  soundcloud('SoundCloud style', 'Waveform seek bar, orange play button',
      Icons.cloud_outlined),
  pandora('Pandora style', 'Blue, bar under the artwork, tab strip',
      Icons.radio_outlined),
  material('Material You style', 'Wavy progress, squircle buttons',
      Icons.bubble_chart_outlined),
  winamp('Winamp style', 'Retro windows with a green LCD',
      Icons.settings_input_component);

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
    PlayerSkin.spotify => _Spotify(ctx),
    PlayerSkin.appleMusic => _Apple(ctx),
    PlayerSkin.ytMusic => _Yt(ctx),
    PlayerSkin.amazon => _Amazon(ctx),
    PlayerSkin.tidal => _Tidal(ctx),
    PlayerSkin.deezer => _Deezer(ctx),
    PlayerSkin.soundcloud => _Sc(ctx),
    PlayerSkin.pandora => _Pandora(ctx),
    PlayerSkin.material => _Material(ctx),
    PlayerSkin.winamp => _Winamp(ctx),
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

/// Play/pause drawn as a bare icon (Apple Music, Tidal).
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

/// Play/pause drawn as an outlined ring (Amazon).
Widget _ringPlay(Color c, double size) => _playing((s) => _Tap(
  onTap: _toggle,
  tip: s == ButtonState.playing ? 'Pause' : 'Play',
  child: Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: c, width: 2.5),
    ),
    child: s == ButtonState.loading
        ? Padding(
      padding: EdgeInsets.all(size * 0.3),
      child: CircularProgressIndicator(strokeWidth: 3, color: c),
    )
        : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
        size: size * 0.48, color: c),
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

Widget _favPill(PlayerCtx x, Color ink, Color onC) => _fav(
  x.song,
      (l, t) => _pill(l ? _Ic.heartFill : _Ic.heart, l ? 'Liked' : 'Like', t,
      ink, on: l, onC: onC),
);

Widget _tab(String label, VoidCallback? t, bool on, Color ink, Color dim,
    Color accent) =>
    Opacity(
      opacity: t == null ? .4 : 1,
      child: _Tap(
        onTap: t,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style:
                _s(13, on ? ink : dim, w: FontWeight.w700, ls: 1.2)),
            const SizedBox(height: 4),
            Container(
                width: 28,
                height: 2,
                color: on ? accent : Colors.transparent),
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

/// SoundCloud-style waveform (deterministic from the song id).
List<double> _waveFor(String seed) {
  final r = math.Random(seed.hashCode);
  var v = .55;
  return List.generate(72, (i) {
    v = (v + (r.nextDouble() - .5) * .9).clamp(.2, 1.0).toDouble();
    return v;
  });
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.f, this.bars, this.on, this.off);
  final double f;
  final List<double> bars;
  final Color on, off;

  @override
  void paint(Canvas c, Size s) {
    final n = bars.length, w = s.width / n;
    for (var i = 0; i < n; i++) {
      final h = math.max(4.0, bars[i] * s.height);
      c.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(w * i + w / 2, s.height / 2),
                  width: w * 0.62,
                  height: h),
              const Radius.circular(2)),
          Paint()..color = (i + .5) / n <= f ? on : off);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => true;
}

// ════════════════════════════════════════════════════════════════════
// 1. SPOTIFY
// ════════════════════════════════════════════════════════════════════

class _Spotify extends StatelessWidget {
  const _Spotify(this.x);
  final PlayerCtx x;

  static const _g = Color(0xFF1ED760);
  static const _dim = Color(0xFFB3B3B3);
  static const _w = Colors.white;

  Widget _ctl(double play, double side) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: _g),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: side, c: _w),
        _playBtn(size: play, bg: _w, fg: Colors.black),
        _ibtn(_Ic.next, x.next, 'Next', size: side, c: _w),
        _repBtn(_w, onC: _g),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return _shell(
      _grad([_dark(t, .75), const Color(0xFF121212)], const [0, .65]),
      LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(t) : _mobile()),
    );
  }

  Widget _mobile() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
    child: Column(children: [
      _hdr(x, _w,
          mid: _caption('PLAYING FROM ALBUM', x.song.album ?? 'Now playing',
              Colors.white70, _w)),
      const SizedBox(height: 10),
      Expanded(child: _art(x, r: 8)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: _titles(x, _w, _dim, size: 22)),
        _favBtn(x, _dim, _g, size: 28),
      ]),
      const SizedBox(height: 4),
      _bar(_w, Colors.white24, h: 22, t: 3),
      _times(_dim, fs: 11),
      const SizedBox(height: 6),
      _ctl(72, 36),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _dim),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _lyrBtn(x, _dim, onC: _g),
          _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _dim),
        ]),
      ]),
    ]),
  );

  Widget _wide(Color t) => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _hdr(x, _w,
          mid: Text('PLAYING FROM ALBUM · ${x.song.album ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _s(11, Colors.white70, ls: 1.4)),
          right: _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w)),
    ),
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Column(children: [
              Expanded(child: _art(x, r: 8, swap: false)),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: _titles(x, _w, _dim, size: 28),
              ),
            ]),
          ),
          const SizedBox(width: 32),
          Expanded(flex: 6, child: _lyr(x, r: 16, bg: _dark(t, .9))),
        ]),
      ),
    ),
    Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      color: Colors.black.withValues(alpha: .4),
      child: Row(children: [
        SizedBox(
          width: 280,
          child: Row(children: [
            _mini(x, 56, 4),
            const SizedBox(width: 12),
            Expanded(child: _titles(x, _w, _dim, size: 15)),
            _favBtn(x, _dim, _g),
          ]),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _shufBtn(_w, onC: _g),
                  _ibtn(_Ic.prev, x.prev, 'Previous', size: 26, c: _w),
                  _playBtn(size: 42, bg: _w, fg: Colors.black),
                  _ibtn(_Ic.next, x.next, 'Next', size: 26, c: _w),
                  _repBtn(_w, onC: _g),
                ]),
                _seekRow(_dim, _w, Colors.white24, h: 14, t: 3),
              ]),
            ),
          ),
        ),
        SizedBox(
          width: 280,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _dim),
            _moreBtn(x, _dim),
            SizedBox(width: 130, child: _vol(_w, Colors.white24)),
          ]),
        ),
      ]),
    ),
  ]);
}

// ════════════════════════════════════════════════════════════════════
// 2. APPLE MUSIC
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
// 3. YOUTUBE MUSIC
// ════════════════════════════════════════════════════════════════════

class _Yt extends StatelessWidget {
  const _Yt(this.x);
  final PlayerCtx x;

  static const _red = Color(0xFFFF2D4B);
  static const _dim = Color(0xFFAAAAAA);
  static const _w = Colors.white;

  Widget _seg() {
    final ly = x.showLyrics && x.hasLyrics;
    Widget o(String l, bool on, VoidCallback? t) => Opacity(
      opacity: t == null && !on ? .4 : 1,
      child: _Tap(
        onTap: t,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: on ? Colors.white24 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(l, style: _s(14, on ? _w : _dim, w: FontWeight.w700)),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(22)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        o('Song', !ly, ly ? x.toggleLyrics : null),
        o('Lyrics', ly, !ly && x.hasLyrics ? x.toggleLyrics : null),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t(x);
    return _shell(
      _grad([_dark(t, .22), const Color(0xFF030303)], const [0, .7]),
      LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide() : _mobile()),
    );
  }

  Widget _mobile() => Column(children: [
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(children: [
          _hdr(x, _w, mid: _seg()),
          const SizedBox(height: 8),
          Expanded(child: _art(x, r: 8)),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _titles(x, _w, _dim, size: 21),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _favPill(x, _w, _red)),
            const SizedBox(width: 8),
            Expanded(
                child: _pill(_Ic.queue, 'Queue', x.openQueue, _w)),
            const SizedBox(width: 8),
            Expanded(
                child: _pill(_Ic.quality, 'Quality', x.openQuality, _w)),
          ]),
          const SizedBox(height: 6),
          _bar(_red, Colors.white24, h: 22, t: 3),
          _times(_dim, fs: 11),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _shufBtn(_w, onC: _red),
            _ibtn(_Ic.prev, x.prev, 'Previous', size: 36, c: _w),
            _playBtn(size: 66, bg: _w, fg: Colors.black),
            _ibtn(_Ic.next, x.next, 'Next', size: 36, c: _w),
            _repBtn(_w, onC: _red),
          ]),
          const SizedBox(height: 4),
        ]),
      ),
    ),
    Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _tab('UP NEXT', x.openQueue, false, _w, _dim, _w),
        _tab('LYRICS', x.hasLyrics ? x.toggleLyrics : null,
            x.showLyrics && x.hasLyrics, _w, _dim, _w),
        _tab('QUALITY', x.openQuality, false, _w, _dim, _w),
      ]),
    ),
  ]);

  Widget _wide() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: _hdr(x, _w, mid: _seg(), right: _moreBtn(x, _w)),
    ),
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 16),
        child: Row(children: [
          Expanded(flex: 6, child: _art(x, r: 8, swap: false)),
          const SizedBox(width: 40),
          Expanded(
            flex: 5,
            child: Column(children: [
              Row(children: [
                _tab('UP NEXT', x.openQueue, false, _w, _dim, _w),
                _tab('LYRICS', null, true, _w, _dim, _w),
              ]),
              Container(height: 1, color: Colors.white12),
              const SizedBox(height: 10),
              Expanded(child: _lyr(x, r: 8, bg: Colors.white10)),
            ]),
          ),
        ]),
      ),
    ),
    Container(
      color: const Color(0xFF111111),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _bar(_red, Colors.white24, h: 12, t: 3, th: _Thumb.none),
        SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              SizedBox(
                width: 300,
                child: Row(children: [
                  _mini(x, 50, 4),
                  const SizedBox(width: 12),
                  Expanded(child: _titles(x, _w, _dim, size: 15)),
                ]),
              ),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _shufBtn(_w, onC: _red),
                  _ibtn(_Ic.prev, x.prev, 'Previous', size: 28, c: _w),
                  _playBtn(size: 46, bg: _w, fg: Colors.black),
                  _ibtn(_Ic.next, x.next, 'Next', size: 28, c: _w),
                  _repBtn(_w, onC: _red),
                  const SizedBox(width: 12),
                  _progress((f, p, tot, pl, s) => Text(
                      '${_fmt(p)} / ${_fmt(tot)}',
                      style: _s(12, _dim, w: FontWeight.w500, tab: true))),
                ]),
              ),
              SizedBox(
                width: 300,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  _favBtn(x, _dim, _red),
                  _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _dim),
                  SizedBox(width: 110, child: _vol(_w, Colors.white24)),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    ),
  ]);
}

// ════════════════════════════════════════════════════════════════════
// 4. AMAZON MUSIC
// ════════════════════════════════════════════════════════════════════

class _Amazon extends StatelessWidget {
  const _Amazon(this.x);
  final PlayerCtx x;

  static const _c = Color(0xFF25D1DA);
  static const _dim = Color(0xFF9AA7B8);
  static const _w = Colors.white;

  Widget _ctl() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: _c),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _w),
        _ringPlay(_c, 72),
        _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _w),
        _repBtn(_w, onC: _c),
      ]);

  Widget _quality() => _Tap(
    onTap: x.openQuality,
    tip: 'Audio quality',
    child: Text(x.quality, style: _s(12, _dim, w: FontWeight.w600)),
  );

  @override
  Widget build(BuildContext context) => _shell(
    _grad(const [Color(0xFF14243A), Color(0xFF070B12)]),
    LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide() : _mobile()),
  );

  Widget _mobile() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
    child: Column(children: [
      _hdr(x, _w, mid: _quality()),
      const SizedBox(height: 8),
      Expanded(child: _art(x, r: 6)),
      const SizedBox(height: 18),
      Text(x.song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: _s(23, _w, w: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(x.song.artist ?? x.song.album ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _s(16, _c, w: FontWeight.w600)),
      const SizedBox(height: 10),
      _bar(_c, Colors.white24, h: 22, t: 5, th: _Thumb.none),
      _times(_dim, fs: 12),
      const SizedBox(height: 6),
      _ctl(),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _favPill(x, _w, _c)),
        const SizedBox(width: 8),
        Expanded(
            child: _pill(_Ic.lyrics, 'Lyrics',
                x.hasLyrics ? x.toggleLyrics : null, _w,
                on: x.showLyrics && x.hasLyrics, onC: _c)),
        const SizedBox(width: 8),
        Expanded(child: _pill(_Ic.queue, 'Queue', x.openQueue, _w)),
      ]),
    ]),
  );

  Widget _wide() => Padding(
    padding: const EdgeInsets.fromLTRB(36, 8, 36, 24),
    child: Row(children: [
      Expanded(
        flex: 6,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _hdr(x, _w, mid: _quality()),
          const SizedBox(height: 4),
          Text(x.song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _s(36, _w, w: FontWeight.w800, h: 1.1)),
          const SizedBox(height: 4),
          Text(x.song.artist ?? x.song.album ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _s(20, _c, w: FontWeight.w600)),
          const SizedBox(height: 14),
          Expanded(child: _lyr(x, r: 14, bg: Colors.white.withValues(alpha: .06))),
          const SizedBox(height: 14),
          _bar(_c, Colors.white24, h: 22, t: 5, th: _Thumb.none),
          _times(_dim),
          const SizedBox(height: 6),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480), child: _ctl()),
          const SizedBox(height: 12),
          Row(children: [
            _favPill(x, _w, _c),
            const SizedBox(width: 8),
            _pill(_Ic.queue, 'Queue', x.openQueue, _w),
            const SizedBox(width: 8),
            _pill(_Ic.more, 'More', null, _w),
          ]),
        ]),
      ),
      const SizedBox(width: 40),
      Expanded(flex: 4, child: _art(x, r: 6, swap: false)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
// 5. TIDAL
// ════════════════════════════════════════════════════════════════════

class _Tidal extends StatelessWidget {
  const _Tidal(this.x);
  final PlayerCtx x;

  static const _c = Color(0xFF00FFFF);
  static const _dim = Color(0xFF8E8E93);
  static const _w = Colors.white;

  Widget _q() => _Tap(
    onTap: x.openQuality,
    tip: 'Audio quality',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          border: Border.all(color: _c), borderRadius: BorderRadius.circular(4)),
      child: Text(x.quality.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _s(10, _c, w: FontWeight.w800, ls: 1)),
    ),
  );

  Widget _ctl() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: _c),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 38, c: _w),
        _bare(_w, 66),
        _ibtn(_Ic.next, x.next, 'Next', size: 38, c: _w),
        _repBtn(_w, onC: _c),
      ]);

  @override
  Widget build(BuildContext context) => _shell(
    const ColoredBox(color: Colors.black),
    LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(c) : _mobile()),
  );

  Widget _mobile() => Column(children: [
    Expanded(
      child: Stack(children: [
        Positioned.fill(
            child: _art(x,
                r: 0, shadow: false, al: Alignment.topCenter, lbg: Colors.black)),
        IgnorePointer(
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: .6), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(top: 4, left: 8, right: 8, child: _hdr(x, _w)),
      ]),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(x.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _s(21, _w, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(x.song.artist ?? x.song.album ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _s(15, _c, w: FontWeight.w600)),
            const SizedBox(height: 8),
            _q(),
          ]),
        ),
        _favBtn(x, _w, _c, size: 28),
      ]),
    ),
    const SizedBox(height: 6),
    _bar(_c, Colors.white24, h: 16, t: 2, th: _Thumb.none),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        _times(_dim, fs: 11),
        const SizedBox(height: 2),
        _ctl(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _lyrBtn(x, _dim, onC: _c),
          _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _dim),
        ]),
        const SizedBox(height: 6),
      ]),
    ),
  ]);

  Widget _wide(BoxConstraints c) {
    final side = math.min(c.maxHeight, c.maxWidth * .46);
    return Row(children: [
      SizedBox(width: side, height: side, child: x.swipeArt),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 8, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _hdr(x, _w, right: _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w)),
            const SizedBox(height: 8),
            Text(x.song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _s(36, _w, w: FontWeight.w800, h: 1.08)),
            const SizedBox(height: 4),
            Text(x.song.artist ?? x.song.album ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _s(20, _c, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(children: [_q(), const Spacer(), _favBtn(x, _w, _c, size: 28)]),
            const SizedBox(height: 12),
            Expanded(child: _lyr(x, r: 0, bg: Colors.transparent)),
            _seekRow(_dim, _c, Colors.white24, h: 18, t: 2, th: _Thumb.none),
            _ctl(),
          ]),
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════
// 6. DEEZER
// ════════════════════════════════════════════════════════════════════

class _Deezer extends StatelessWidget {
  const _Deezer(this.x);
  final PlayerCtx x;

  static const _p = Color(0xFFA238FF);
  static const _w = Colors.white;

  Widget _main(bool wide) {
    final dim = Colors.white70;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            _hdr(x, _w,
                mid: _caption('PLAYING FROM', x.song.album ?? 'Now playing',
                    dim, _w)),
            const SizedBox(height: 6),
            Expanded(child: _art(x, r: 24, swap: !wide)),
            const SizedBox(height: 16),
            _titles(x, _w, dim, size: 23, center: true),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _favBtn(x, dim, _p, size: 26),
              const SizedBox(width: 12),
              _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: dim),
            ]),
            _bar(_p, Colors.white24, h: 22, t: 4),
            _times(dim),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _shufBtn(_w, onC: _p),
              _ibtn(_Ic.prev, x.prev, 'Previous', size: 36, c: _w),
              _playBtn(size: 72, bg: _p, fg: _w),
              _ibtn(_Ic.next, x.next, 'Next', size: 36, c: _w),
              _repBtn(_w, onC: _p),
            ]),
            const SizedBox(height: 14),
          ]),
        ),
      ),
      if (!wide)
        _Tap(
          onTap: x.hasLyrics ? x.toggleLyrics : null,
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(children: [
              Icon(_Ic.lyrics, size: 20, color: _w),
              const SizedBox(width: 10),
              Text(x.showLyrics && x.hasLyrics ? 'Hide lyrics' : 'Lyrics',
                  style: _s(15, _w, w: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(
                  x.showLyrics && x.hasLyrics
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  size: 22,
                  color: dim),
              const Spacer(),
              _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t(x, const Color(0xFF6A2BC0));
    return _shell(
      _grad([_dark(t, .5), const Color(0xFF0E0E14)], const [0, .8]),
      LayoutBuilder(
        builder: (_, c) => _isWide(c)
            ? Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
          child: Row(children: [
            Expanded(
                flex: 6,
                child: _lyr(x, r: 28, bg: Colors.white.withValues(alpha: .08))),
            const SizedBox(width: 24),
            Expanded(
              flex: 5,
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _main(true))),
            ),
          ]),
        )
            : _main(false),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 7. SOUNDCLOUD
// ════════════════════════════════════════════════════════════════════

class _Sc extends StatelessWidget {
  const _Sc(this.x);
  final PlayerCtx x;

  static const _or = Color(0xFFFF5500);
  static const _dim = Color(0xFF999999);
  static const _w = Colors.white;

  Widget _wave({double h = 64}) => _progress((f, p, t, pl, seek) {
    final bars = _waveFor(x.song.id);
    return _Seeker(
      f: f,
      onSeek: seek,
      height: h,
      paint: (v) => _WavePainter(v, bars, _or, Colors.white30),
    );
  });

  Widget _chip(String s, double fs, FontWeight w) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    color: Colors.black.withValues(alpha: .85),
    child: Text(s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _s(fs, _w, w: w)),
  );

  Widget _ctl(double play) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shufBtn(_w, onC: _or),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _w),
        _playBtn(size: play, bg: _or, fg: _w),
        _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _w),
        _repBtn(_w, onC: _or),
      ]);

  @override
  Widget build(BuildContext context) => _shell(
    const ColoredBox(color: Color(0xFF121212)),
    LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide() : _mobile()),
  );

  Widget _mobile() => Column(children: [
    Expanded(
      child: Stack(children: [
        Positioned.fill(
            child: _art(x,
                r: 0, shadow: false, al: Alignment.topCenter, lbg: Colors.black)),
        IgnorePointer(
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: .6), Colors.transparent],
              ),
            ),
          ),
        ),
        Positioned(top: 4, left: 8, right: 8, child: _hdr(x, _w)),
      ]),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.song.artist ?? x.song.album ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _s(13, _dim, w: FontWeight.w500)),
              Text(x.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _s(20, _w, w: FontWeight.w700)),
            ]),
          ),
          _favBtn(x, _dim, _or, size: 26),
        ]),
        const SizedBox(height: 6),
        _wave(),
        _times(_or, fs: 11),
        const SizedBox(height: 6),
        _ctl(66),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _lyrBtn(x, _dim, onC: _or),
          _ibtn(_Ic.quality, x.openQuality, 'Audio quality', c: _dim),
          _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _dim),
        ]),
      ]),
    ),
  ]);

  Widget _wide() {
    final t = _t(x);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: _hdr(x, _w, right: _moreBtn(x, _w)),
      ),
      SizedBox(
        height: 300,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_dark(t, .85), _dark(t, .35)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    _playBtn(size: 72, bg: _or, fg: _w),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _chip(x.song.artist ?? x.song.album ?? '', 14,
                              FontWeight.w500),
                          const SizedBox(height: 6),
                          _chip(x.song.title, 26, FontWeight.w700),
                        ],
                      ),
                    ),
                  ]),
                  const Spacer(),
                  _wave(h: 72),
                  _times(_w, fs: 11),
                ]),
              ),
              const SizedBox(width: 20),
              SizedBox.square(dimension: 260, child: x.swipeArt),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(children: [
          _shufBtn(_w, onC: _or),
          _ibtn(_Ic.prev, x.prev, 'Previous', c: _w),
          _ibtn(_Ic.next, x.next, 'Next', c: _w),
          _repBtn(_w, onC: _or),
          const Spacer(),
          _favPill(x, _w, _or),
          const SizedBox(width: 8),
          _pill(_Ic.queue, 'Queue', x.openQueue, _w),
          const SizedBox(width: 8),
          _pill(_Ic.quality, 'Quality', x.openQuality, _w),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: _lyr(x, r: 6, bg: Colors.white.withValues(alpha: .05)),
        ),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════
// 8. PANDORA
// ════════════════════════════════════════════════════════════════════

class _Pandora extends StatelessWidget {
  const _Pandora(this.x);
  final PlayerCtx x;

  static const _blue = Color(0xFF2C4BD9);
  static const _w = Colors.white;
  static const _dim = Color(0xCCFFFFFF);

  Widget _ctl() =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _repBtn(_w),
        _ibtn(_Ic.prev, x.prev, 'Previous', size: 34, c: _w),
        _playBtn(size: 78, bg: _w, fg: _blue),
        _ibtn(_Ic.next, x.next, 'Next', size: 34, c: _w),
        _favBtn(x, _w, _w, size: 28),
      ]);

  Widget _lab(IconData i, String l, VoidCallback? t, {bool on = false}) =>
      Opacity(
        opacity: t == null ? .4 : 1,
        child: _Tap(
          onTap: t,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 22, color: on ? _w : _dim),
              const SizedBox(height: 3),
              Text(l, style: _s(11, on ? _w : _dim, w: FontWeight.w700)),
            ]),
          ),
        ),
      );

  Widget _pillCap() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(14)),
    child: Text('NOW PLAYING', style: _s(11, _w, w: FontWeight.w800, ls: 1.4)),
  );

  @override
  Widget build(BuildContext context) => _shell(
    _grad(const [Color(0xFF3A5BFF), Color(0xFF14226E)]),
    LayoutBuilder(builder: (_, c) => _isWide(c) ? _wide(c) : _mobile()),
  );

  Widget _mobile() => Column(children: [
    Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(children: [
          _hdr(x, _w, mid: _pillCap()),
          const SizedBox(height: 6),
          Expanded(child: _art(x, r: 4)),
          const SizedBox(height: 8),
          _bar(_w, Colors.white30, h: 16, t: 3, th: _Thumb.none),
          _times(_dim, fs: 11),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _titles(x, _w, _dim, size: 22),
          ),
          const SizedBox(height: 12),
          _ctl(),
          const SizedBox(height: 10),
        ]),
      ),
    ),
    Container(
      color: Colors.black.withValues(alpha: .25),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _lab(_Ic.lyrics, 'Lyrics', x.hasLyrics ? x.toggleLyrics : null,
            on: x.showLyrics && x.hasLyrics),
        _lab(_Ic.queue, 'Queue', x.openQueue),
        _lab(_Ic.quality, 'Quality', x.openQuality),
      ]),
    ),
  ]);

  Widget _wide(BoxConstraints c) {
    final side = math.min(c.maxHeight * .5, 360.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 4, 32, 24),
      child: Column(children: [
        _hdr(x, _w, mid: _pillCap(), right: _ibtn(_Ic.queue, x.openQueue, 'Queue', c: _w)),
        const SizedBox(height: 8),
        SizedBox(
          height: side,
          child: Row(children: [
            SizedBox.square(
              dimension: side,
              child: DecoratedBox(
                decoration: BoxDecoration(boxShadow: _shadow(30, 14, .4)),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: x.swipeArt),
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _titles(x, _w, _dim, size: 32),
                  const SizedBox(height: 18),
                  _bar(_w, Colors.white30, h: 18, t: 4, th: _Thumb.none),
                  _times(_dim),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _ctl()),
                  const SizedBox(height: 8),
                  Row(children: [
                    _lab(_Ic.quality, 'Quality', x.openQuality),
                    _lab(_Ic.more, 'More', null),
                  ]),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Expanded(child: _lyr(x, r: 12, bg: Colors.black.withValues(alpha: .22))),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// 9. MATERIAL YOU
// ════════════════════════════════════════════════════════════════════

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

class _WavyPainter extends CustomPainter {
  const _WavyPainter(this.f, this.on, this.off);
  final double f;
  final Color on, off;

  @override
  void paint(Canvas c, Size s) {
    final y = s.height / 2, x = f * s.width;
    c.drawLine(
        Offset(x, y),
        Offset(s.width, y),
        Paint()
          ..color = off
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    final path = Path()..moveTo(0, y);
    for (double i = 0; i <= x; i += 2) {
      path.lineTo(i, y + 3.5 * math.sin(i / 6.5));
    }
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = on
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(x, y), width: 5, height: 24),
            const Radius.circular(3)),
        Paint()..color = on);
  }

  @override
  bool shouldRepaint(_WavyPainter o) => true;
}

class _Material extends StatelessWidget {
  const _Material(this.x);
  final PlayerCtx x;

  static const _w = Colors.white;

  Widget _tb(Widget child, VoidCallback? t, String tip, _Pal p,
      {double w = 48, double h = 48, double r = 24}) =>
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
                color: p.tonal, borderRadius: BorderRadius.circular(r)),
            child: child,
          ),
        ),
      );

  Widget _wavy(_Pal p) => _progress((f, pos, tot, pl, seek) => _Seeker(
    f: f,
    onSeek: seek,
    height: 30,
    paint: (v) => _WavyPainter(v, p.prim, Colors.white24),
  ));

  Widget _ctl(_Pal p) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _tb(Icon(_Ic.prev, size: 30, color: _w), x.prev, 'Previous', p,
            w: 76, h: 66, r: 26),
        _playing((s) => _Tap(
          onTap: _toggle,
          tip: s == ButtonState.playing ? 'Pause' : 'Play',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 108,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.prim,
              borderRadius:
              BorderRadius.circular(s == ButtonState.playing ? 24 : 38),
            ),
            child: s == ButtonState.loading
                ? SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: p.onPrim))
                : Icon(s == ButtonState.playing ? _Ic.pause : _Ic.play,
                size: 38, color: p.onPrim),
          ),
        )),
        _tb(Icon(_Ic.next, size: 30, color: _w), x.next, 'Next', p,
            w: 76, h: 66, r: 26),
      ]);

  Widget _chips(_Pal p, bool wide) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _shuffle((on, t) => _tb(
            Icon(_Ic.shuffle, size: 20, color: on ? p.prim : _w), t,
            on ? 'Shuffle: on' : 'Shuffle: off', p)),
        _repeat((m, t) => _tb(
            Icon(m == LoopMode.one ? _Ic.repeatOne : _Ic.repeat,
                size: 20, color: m == LoopMode.off ? _w : p.prim),
            t,
            m == LoopMode.off
                ? 'Repeat: off'
                : m == LoopMode.one
                ? 'Repeat: one'
                : 'Repeat: all',
            p)),
        if (!wide)
          _tb(
              Icon(_Ic.lyrics,
                  size: 20,
                  color: x.showLyrics && x.hasLyrics ? p.prim : _w),
              x.hasLyrics ? x.toggleLyrics : null,
              'Lyrics',
              p),
        _tb(Icon(_Ic.quality, size: 20, color: _w), x.openQuality,
            'Audio quality', p),
      ]);

  Widget _heart(_Pal p) => _fav(
    x.song,
        (l, t) => _tb(
        Icon(l ? _Ic.heartFill : _Ic.heart,
            size: 22, color: l ? p.prim : _w),
        t,
        'Favourite',
        p),
  );

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
        _tb(Icon(_Ic.down, size: 24, color: _w), x.close, 'Close', p),
        const Spacer(),
        _tb(Icon(_Ic.queue, size: 22, color: _w), x.openQueue, 'Queue', p),
        const SizedBox(width: 8),
        Builder(
          builder: (c) => _tb(Icon(_Ic.more, size: 22, color: _w),
                  () => _more(c, x.song), 'More', p),
        ),
      ]),
      const SizedBox(height: 12),
      Expanded(child: _art(x, r: 36, shadow: false)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: _titles(x, _w, Colors.white70, size: 27, w: FontWeight.w600)),
        _heart(p),
      ]),
      const SizedBox(height: 8),
      _wavy(p),
      _times(Colors.white70, fs: 12),
      const SizedBox(height: 10),
      _ctl(p),
      const SizedBox(height: 14),
      _chips(p, false),
    ]),
  );

  Widget _wide(_Pal p) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
    child: Column(children: [
      Row(children: [
        _tb(Icon(_Ic.down, size: 24, color: _w), x.close, 'Close', p),
        const Spacer(),
        _tb(Icon(_Ic.queue, size: 22, color: _w), x.openQueue, 'Queue', p),
        const SizedBox(width: 8),
        Builder(
          builder: (c) => _tb(Icon(_Ic.more, size: 22, color: _w),
                  () => _more(c, x.song), 'More', p),
        ),
      ]),
      const SizedBox(height: 14),
      Expanded(
        child: Row(children: [
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: p.tonal, borderRadius: BorderRadius.circular(40)),
              child: Column(children: [
                Expanded(child: _art(x, r: 28, swap: false, shadow: false)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: _titles(x, _w, Colors.white70,
                          size: 24, w: FontWeight.w600)),
                  _heart(p),
                ]),
              ]),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: Column(children: [
              Expanded(child: _lyr(x, r: 32, bg: p.tonal)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                decoration: BoxDecoration(
                    color: p.tonal, borderRadius: BorderRadius.circular(32)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _wavy(p),
                  _times(Colors.white70),
                  const SizedBox(height: 8),
                  _ctl(p),
                  const SizedBox(height: 12),
                  _chips(p, true),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════
// 10. WINAMP
// ════════════════════════════════════════════════════════════════════

class _WinSlider extends CustomPainter {
  const _WinSlider(this.f);
  final double f;

  @override
  void paint(Canvas c, Size s) {
    final g = Rect.fromLTWH(0, s.height / 2 - 4, s.width, 8);
    c.drawRect(g, Paint()..color = const Color(0xFF050507));
    c.drawRect(
        g,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF55555F));
    c.drawRect(Rect.fromLTWH(1, g.top + 1, math.max(0, f * s.width - 1), 6),
        Paint()..color = const Color(0xFF1FA838));
    final tx = (f * (s.width - 14)).clamp(0.0, s.width - 14).toDouble();
    final th = Rect.fromLTWH(tx, 0, 14, s.height);
    c.drawRect(
        th,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFA0A0AC), Color(0xFF4A4A55)],
          ).createShader(th));
    c.drawRect(
        th,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF14141A));
  }

  @override
  bool shouldRepaint(_WinSlider o) => true;
}

class _Winamp extends StatelessWidget {
  const _Winamp(this.x);
  final PlayerCtx x;

  static const _panel = Color(0xFF2B2B33);
  static const _hi = Color(0xFF55555F);
  static const _lo = Color(0xFF14141A);
  static const _green = Color(0xFF3DFF5A);

  TextStyle _m(double sz, {Color c = _green}) => TextStyle(
    fontFamily: 'monospace',
    fontSize: sz,
    color: c,
    fontWeight: FontWeight.w700,
    height: 1.1,
    decoration: TextDecoration.none,
  );

  Widget _win(String title, Widget body,
      {bool fill = false, VoidCallback? onClose}) =>
      Container(
        decoration: BoxDecoration(
          color: _panel,
          border: Border.all(color: _hi, width: 1.5),
          boxShadow: _shadow(16, 6, .5),
        ),
        child: Column(mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min, children: [
          Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF3B4A7A), Color(0xFF1B2440)]),
            ),
            child: Row(children: [
              Text(title, style: _s(10, Colors.white, ls: 2)),
              const Spacer(),
              if (onClose != null)
                _Tap(
                  onTap: onClose,
                  tip: 'Close',
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
            ]),
          ),
          if (fill) Expanded(child: body) else body,
        ]),
      );

  Widget _mb(Widget child, VoidCallback? t, String tip,
      {double w = 46, double h = 28, bool on = false}) =>
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
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: on
                    ? const [Color(0xFF3A5A3A), Color(0xFF1E3A1E)]
                    : const [Color(0xFF70707C), Color(0xFF3B3B45)],
              ),
              border: Border.all(color: _lo),
              borderRadius: BorderRadius.circular(3),
            ),
            child: child,
          ),
        ),
      );

  Widget _main() => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            height: 84,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.black, border: Border.all(color: _lo)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _progress((f, p, t, pl, s) => Text(_fmt(p), style: _m(34))),
              const Spacer(),
              Text(x.song.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: _m(12)),
              Text('${x.quality}  ${x.index}/${x.total}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _m(10, c: const Color(0xFF1FA838))),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(border: Border.all(color: _lo, width: 2)),
          child: x.art(0),
        ),
      ]),
      const SizedBox(height: 8),
      _progress((f, p, t, pl, seek) => _Seeker(
          f: f,
          onSeek: seek,
          height: 16,
          paint: (v) => _WinSlider(v))),
      const SizedBox(height: 6),
      Row(children: [
        Text('VOL', style: _m(10)),
        const SizedBox(width: 6),
        SizedBox(
          width: 100,
          child: StreamBuilder<double>(
            stream: _mp.player.volumeStream,
            initialData: _mp.player.volume,
            builder: (_, s) => _Seeker(
              f: (s.data ?? 1.0).clamp(0.0, 1.0).toDouble(),
              live: true,
              height: 14,
              onSeek: (n) => _mp.player.setVolume(n),
              paint: (v) => _WinSlider(v),
            ),
          ),
        ),
        const Spacer(),
        _shuffle((on, t) => _mb(
            Text('SHUF', style: _m(10, c: on ? _green : Colors.white70)), t,
            on ? 'Shuffle: on' : 'Shuffle: off',
            w: 44, h: 22, on: on)),
        const SizedBox(width: 4),
        _repeat((m, t) => _mb(
            Text(m == LoopMode.one ? 'REP1' : 'REP',
                style: _m(10,
                    c: m != LoopMode.off ? _green : Colors.white70)),
            t,
            m == LoopMode.off
                ? 'Repeat: off'
                : m == LoopMode.one
                ? 'Repeat: one'
                : 'Repeat: all',
            w: 44,
            h: 22,
            on: m != LoopMode.off)),
      ]),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        _mb(const Icon(Icons.skip_previous, size: 18, color: Colors.white),
            x.prev, 'Previous'),
        _playing((s) => _mb(
            Icon(s == ButtonState.playing ? Icons.pause : Icons.play_arrow,
                size: 20, color: _green),
            _toggle,
            s == ButtonState.playing ? 'Pause' : 'Play',
            w: 62)),
        _mb(const Icon(Icons.skip_next, size: 18, color: Colors.white),
            x.next, 'Next'),
        _fav(
          x.song,
              (l, t) => _mb(
              Icon(l ? Icons.favorite : Icons.favorite_border,
                  size: 15,
                  color: l ? const Color(0xFFFF5470) : Colors.white70),
              t,
              'Favourite',
              w: 38),
        ),
        _mb(Text('QUE', style: _m(10, c: Colors.white70)), x.openQueue,
            'Queue',
            w: 38),
        _mb(Text('QLT', style: _m(10, c: Colors.white70)), x.openQuality,
            'Audio quality',
            w: 38),
        _mb(Text('...', style: _m(12, c: Colors.white70)), null, 'More',
            w: 0, h: 0),
      ]),
    ]),
  );

  @override
  Widget build(BuildContext context) => _shell(
    _grad(const [Color(0xFF0E0E14), Color(0xFF1A1A24)]),
    LayoutBuilder(
      builder: (_, c) {
        final lyr = _win('LYRICS', _lyr(x, r: 0, bg: Colors.black), fill: true);
        return _isWide(c)
            ? Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 440,
                child: _win('WINAMP', _main(), onClose: x.close)),
            const SizedBox(width: 16),
            Expanded(child: lyr),
          ]),
        )
            : Padding(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            _win('WINAMP', _main(), onClose: x.close),
            const SizedBox(height: 8),
            Expanded(child: lyr),
          ]),
        );
      },
    ),
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