// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../services/lyrics_service.dart';

class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.positionStream,
    this.initialPosition = Duration.zero,
    this.loading = false,
    this.onSeek,
    this.accentColor,
    this.inactiveColor,
    this.loadingText = 'Looking for lyrics…',
    this.notFoundText = 'No lyrics available for this track',
    this.textScale = 1.0,
  });

  final LyricsData? lyrics;
  final Stream<Duration>? positionStream;
  final Duration initialPosition;
  final bool loading;
  final Future<void> Function(Duration position)? onSeek;
  final Color? accentColor;
  final Color? inactiveColor;
  final String loadingText;
  final String notFoundText;
  final double textScale;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView>
    with TickerProviderStateMixin {
  static const Duration _lead = Duration(milliseconds: 220);
  static const int _interludeMinMs = 6000;
  static const int _interludeAfterMs = 1800;
  static const int _extrapolationCapMs = 600;

  static const List<double> _fallAlpha = [1, 0.50, 0.40, 0.30, 0.22];
  static const List<double> _fallBlur = [0, 0.8, 1.4, 2.0, 2.6];
  // Depth-of-field blur is the priciest effect. Set false for low-end phones.
  static const bool _depthOfField = true;

  static const Curve _ease = Cubic(0.41, 0.0, 0.12, 0.99);
  static const double _focusY = 0.22; // active row sits at 22 % of viewport
  static const double _baseSize = 26;
  static const int _trailMs = 1200;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  List<GlobalKey> _keys = <GlobalKey>[];

  StreamSubscription<Duration>? _sub;
  int _active = -1;
  bool _interlude = false;
  bool _everFollowed = false;
  bool _dragging = false;
  DateTime _manualUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Elastic trail + onset pulse (one controller each, shared by all rows).
  late final AnimationController _trail = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _trailMs),
    value: 1,
  );
  late final AnimationController _onset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    value: 1,
  );

  // Karaoke driver
  late final Ticker _ticker = createTicker(_onTick);
  final Stopwatch _clock = Stopwatch()..start();
  final ValueNotifier<int> _posNotifier = ValueNotifier<int>(0);
  int _anchorMs = 0;
  int _anchorAt = 0;
  double _smooth = 0;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _listen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluate(widget.initialPosition.inMilliseconds);
    });
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView old) {
    super.didUpdateWidget(old);
    if (widget.positionStream != old.positionStream) {
      _sub?.cancel();
      _sub = null;
      _listen();
    }
    if (widget.lyrics != old.lyrics) {
      if (_ticker.isActive) _ticker.stop();
      setState(() {
        _active = -1;
        _interlude = false;
        _everFollowed = false;
      });
      _anchorMs = widget.initialPosition.inMilliseconds;
      _anchorAt = _clock.elapsedMilliseconds;
      _smooth = _anchorMs.toDouble();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _evaluate(widget.initialPosition.inMilliseconds);
      });
    }
  }

  void _listen() {
    final s = widget.positionStream;
    if (s == null) return;
    _sub = s.listen((d) {
      if (!mounted) return;
      _evaluate(d.inMilliseconds);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _trail.dispose();
    _onset.dispose();
    _posNotifier.dispose();
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }


  int get _lines => widget.lyrics?.synced?.length ?? 0;

  bool get _activeHasWords {
    final l = widget.lyrics?.synced;
    if (l == null || _active < 0 || _active >= l.length) return false;
    return l[_active].hasWords;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    final since = _clock.elapsedMilliseconds - _anchorAt;
    final target =
        _anchorMs + (since > _extrapolationCapMs ? _extrapolationCapMs : since);
    final diff = target - _smooth;
    if (diff.abs() > 400) {
      _smooth = target.toDouble();
    } else {
      _smooth += diff * (1 - math.exp(-dt / 60));
    }
    _posNotifier.value = _smooth.round();
  }

  void _syncTicker() {
    if (_activeHasWords) {
      if (!_ticker.isActive) {
        _lastTick = Duration.zero;
        _smooth = _anchorMs.toDouble();
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _evaluate(int posMs) {
    if (!mounted || _lines == 0) return;
    final lyrics = widget.lyrics!.synced!;
    _anchorMs = posMs;
    _anchorAt = _clock.elapsedMilliseconds;
    final target = posMs + _lead.inMilliseconds;

    var idx = -1;
    for (var i = 0; i < lyrics.length; i++) {
      if (lyrics[i].timeMs <= target) {
        idx = i;
      } else {
        break;
      }
    }

    var interlude = false;
    if (idx >= 0 && idx + 1 < lyrics.length) {
      final gap = lyrics[idx + 1].timeMs - lyrics[idx].timeMs;
      interlude = gap > _interludeMinMs &&
          posMs > lyrics[idx].timeMs + _interludeAfterMs;
    }

    if (idx != _active || interlude != _interlude) {
      final prev = _active;
      final changed = idx != _active;
      setState(() {
        _active = idx;
        _interlude = interlude;
      });
      if (changed) {
        _onset.forward(from: 0);
        // Ripple only for natural advances, not for seeks.
        if (_everFollowed && idx > 0 && (idx - prev).abs() <= 2) {
          _trail.forward(from: 0);
        }
      }
      _follow(instant: !_everFollowed);
      _syncTicker();
    }
  }

  /// Glide the active row to [_focusY] of the viewport. The first call per
  /// lyrics jumps; every later call animates (350–500 ms, [_ease]).
  void _follow({bool instant = false, int retries = 0}) {
    if (_active < 0 || _active >= _keys.length) return;
    if (!instant && DateTime.now().isBefore(_manualUntil)) return;

    final ctx = _keys[_active].currentContext;
    final vp = _listKey.currentContext?.findRenderObject();
    if (ctx == null || vp is! RenderBox || !vp.hasSize || !_scroll.hasClients) {
      if (retries < 4) {
        if (ctx == null && _scroll.hasClients && instant && retries == 0) {
          // Row not built yet (far down): estimate so it gets built.
          final p = _scroll.position;
          _scroll.jumpTo((p.maxScrollExtent * _active / _keys.length)
              .clamp(p.minScrollExtent, p.maxScrollExtent)
              .toDouble());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow(instant: instant, retries: retries + 1);
        });
      }
      return;
    }
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached) return;

    final y = box.localToGlobal(Offset.zero, ancestor: vp).dy;
    final delta = y - vp.size.height * _focusY;
    final pos = _scroll.position;
    final target = (pos.pixels + delta)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    _everFollowed = true;
    if ((target - pos.pixels).abs() < 0.5) return;
    if (instant) {
      _scroll.jumpTo(target);
      return;
    }
    final ms = (350 + delta.abs() * 0.35).clamp(350.0, 500.0).round();
    _scroll.animateTo(
      target,
      duration: Duration(milliseconds: ms),
      curve: _ease,
    );
  }


  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return _center(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 14),
            Text(
              widget.loadingText,
              textAlign: TextAlign.center,
              style: _base(context).copyWith(
                  color: _inactive(context, 0.6), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    final lyrics = widget.lyrics;
    if (lyrics == null) {
      return _center(
        Text(
          widget.notFoundText,
          textAlign: TextAlign.center,
          style: _base(context).copyWith(
              color: _inactive(context, 0.6), fontWeight: FontWeight.w500),
        ),
      );
    }

    if (lyrics.instrumental) {
      return _center(_Breath(color: _accent(context), scale: widget.textScale));
    }

    if (lyrics.hasSynced) return _syncedList(context, lyrics.synced!);

    final plain = lyrics.plain;
    if (plain != null && plain.trim().isNotEmpty) {
      return Center(
        child: ScrollConfiguration(
          behavior:
          ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Text(
              plain.trim(),
              textAlign: TextAlign.center,
              style: _base(context).copyWith(
                fontSize: 17 * widget.textScale,
                height: 1.7,
                fontWeight: FontWeight.w500,
                color: _activeColor(context),
              ),
            ),
          ),
        ),
      );
    }

    return _center(
      Text(
        widget.notFoundText,
        style: _base(context).copyWith(color: _inactive(context, 0.6)),
      ),
    );
  }

  Widget _syncedList(BuildContext context, List<LyricLine> lines) {
    if (_keys.length != lines.length) {
      _keys = List<GlobalKey>.generate(lines.length, (_) => GlobalKey());
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth != 0) return false;
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _dragging = true;
          _manualUntil = DateTime.now().add(const Duration(seconds: 2));
          setState(() {}); // blur snaps off while browsing
        } else if (n is ScrollEndNotification && _dragging) {
          _dragging = false;
          _manualUntil = DateTime.now().add(const Duration(milliseconds: 1500));
          setState(() {});
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: LayoutBuilder(
          builder: (context, c) {
            return ListView.builder(
              key: _listKey,
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 900,
              padding: EdgeInsets.fromLTRB(
                20,
                40,
                20,
                c.maxHeight.isFinite ? c.maxHeight * 0.7 : 300,
              ),
              itemCount: lines.length,
              itemBuilder: (context, i) => _item(context, lines, i),
            );
          },
        ),
      ),
    );
  }


  TextStyle _lineStyle(BuildContext context) => _base(context).copyWith(
    fontSize: _baseSize * widget.textScale,
    fontWeight: FontWeight.w800,
    height: 1.3,
    letterSpacing: -0.2,
  );

  bool _isStanzaBreak(List<LyricLine> l, int i) {
    if (i == 0) return false;
    return l[i - 1].text.trim().isEmpty ||
        l[i].text.trim().isEmpty ||
        l[i].timeMs - l[i - 1].timeMs >= 3800;
  }

  Widget _item(BuildContext context, List<LyricLine> lines, int i) {
    final line = lines[i];
    final isActive = i == _active;
    final isPast = _active >= 0 && i < _active;
    final dist = _active < 0 ? 0 : (i - _active).abs();
    final k = math.min(dist, _fallAlpha.length - 1);

    final target = _Fx(
      scale: isActive ? 1.0 : 0.98,
      alpha: _fallAlpha[k],
      blur: (!_depthOfField || isActive || _dragging || _active < 0)
          ? 0
          : _fallBlur[k],
      dy: isActive ? -3.5 : (isPast ? -1.5 : 3.5),
    );

    final style = _lineStyle(context);
    final accent = _accent(context);

    final fxRow = TweenAnimationBuilder<_Fx>(
      tween: _FxTween(begin: target, end: target),
      duration: const Duration(milliseconds: 420),
      curve: _ease,
      builder: (context, fx, _) {
        Widget body = _body(context, line, isActive, style, accent, fx.alpha);
        if (fx.blur > 0.05) {
          body = ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: fx.blur,
              sigmaY: fx.blur,
              tileMode: TileMode.decal,
            ),
            child: body,
          );
        }
        Widget scaled = Transform(
          alignment: Alignment.centerLeft,
          transform: Matrix4.translationValues(0, fx.dy, 0)
            ..scale(fx.scale, fx.scale, 1.0),
          child: body,
        );
        if (isActive) {
          scaled = AnimatedBuilder(
            animation: _onset,
            child: scaled,
            builder: (context, c) => Transform.scale(
              scale: 1 + 0.02 * math.sin(math.pi * _onset.value),
              alignment: Alignment.centerLeft,
              child: c,
            ),
          );
        }
        return scaled;
      },
    );

    final tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onSeek == null
          ? null
          : () => widget.onSeek!(Duration(milliseconds: line.timeMs)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: RepaintBoundary(child: fxRow),
      ),
    );

    // Elastic trail: rows lag behind the scroll, then spring in, staggered.
    final trailed = AnimatedBuilder(
      animation: _trail,
      child: tappable,
      builder: (context, c) {
        final dy = _trail.value >= 1 ? 0.0 : _trailDy(i);
        return dy == 0 ? c! : Transform.translate(offset: Offset(0, dy), child: c);
      },
    );

    return Column(
      key: _keys[i],
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isStanzaBreak(lines, i)) const SizedBox(height: 22),
        trailed,
        if (isActive && _interlude)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6, left: 4),
            child: _Breath(color: accent, scale: widget.textScale),
          ),
      ],
    );
  }

  Widget _body(BuildContext context, LyricLine line, bool isActive,
      TextStyle style, Color accent, double alpha) {
    final text = line.text.trim().isEmpty ? '♪' : line.text;

    if (isActive && line.hasWords) {
      return _KaraokeLine(
        line: line,
        pos: _posNotifier,
        style: style,
        accent: accent,
        dim: _inactive(context, 0.40),
      );
    }

    if (isActive) {
      final active = style.copyWith(color: accent);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _Glow(text: text, style: style.copyWith(color: accent)),
          ),
          Text(text, style: active, textAlign: TextAlign.left),
        ],
      );
    }

    return Text(
      text,
      textAlign: TextAlign.left,
      style: style.copyWith(color: _inactive(context, 0.44 * alpha)),
    );
  }

  /// Spring response (damping .72, stiffness 180) of the trail offset.
  double _trailDy(int i) {
    if (_active < 0) return 0;
    final rel = i - _active;
    double start;
    double delayMs;
    if (rel >= 0 && rel <= 6) {
      start = 7.0 + rel * 3.0;
      delayMs = rel * 38.0;
    } else if (rel < 0 && rel >= -3) {
      start = 3.0; // upper lines move a little too
      delayMs = -rel * 38.0;
    } else {
      return 0;
    }
    final t = (_trail.value * _trailMs - delayMs) / 1000.0;
    return start * _spring(t);
  }

  static double _spring(double t) {
    if (t <= 0) return 1;
    const w = 13.4164; // sqrt(180)
    const z = 0.72;
    final wd = w * math.sqrt(1 - z * z);
    return math.exp(-z * w * t) *
        (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
  }

  Widget _center(Widget child) =>
      Center(child: Padding(padding: const EdgeInsets.all(28), child: child));

  TextStyle _base(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge ??
          const TextStyle(fontSize: 16, inherit: false);

  Color _accent(BuildContext context) =>
      widget.accentColor ?? Theme.of(context).colorScheme.primary;

  Color _activeColor(BuildContext context) =>
      widget.accentColor ??
          Theme.of(context).colorScheme.onSurface.withOpacity(0.9);

  Color _inactive(BuildContext context, double alpha) =>
      (widget.inactiveColor ?? Theme.of(context).colorScheme.onSurface)
          .withOpacity(alpha.clamp(0.0, 1.0));
}


class _Fx {
  const _Fx(
      {required this.scale,
        required this.alpha,
        required this.blur,
        required this.dy});
  final double scale;
  final double alpha;
  final double blur;
  final double dy;

  static _Fx lerp(_Fx a, _Fx b, double t) => _Fx(
    scale: ui.lerpDouble(a.scale, b.scale, t)!,
    alpha: ui.lerpDouble(a.alpha, b.alpha, t)!,
    blur: ui.lerpDouble(a.blur, b.blur, t)!,
    dy: ui.lerpDouble(a.dy, b.dy, t)!,
  );

  @override
  bool operator ==(Object o) =>
      o is _Fx &&
          o.scale == scale &&
          o.alpha == alpha &&
          o.blur == blur &&
          o.dy == dy;

  @override
  int get hashCode => Object.hash(scale, alpha, blur, dy);
}

class _FxTween extends Tween<_Fx> {
  _FxTween({super.begin, super.end});
  @override
  _Fx lerp(double t) => _Fx.lerp(begin!, end!, t);
}


class _Glow extends StatelessWidget {
  const _Glow({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ImageFiltered(
        imageFilter:
        ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.decal),
        child: Text(
          text,
          textAlign: TextAlign.left,
          style: style.copyWith(color: (style.color ?? Colors.white).withOpacity(0.5)),
        ),
      ),
    );
  }
}


class _KaraokeLine extends StatefulWidget {
  const _KaraokeLine({
    required this.line,
    required this.pos,
    required this.style,
    required this.accent,
    required this.dim,
  });

  final LyricLine line;
  final ValueListenable<int> pos;
  final TextStyle style;
  final Color accent;
  final Color dim;

  @override
  State<_KaraokeLine> createState() => _KaraokeLineState();
}

class _KaraokeLineState extends State<_KaraokeLine> {
  double? _w;
  Object? _lineKey;
  TextStyle? _style;
  Color? _accent;
  Color? _dim;

  late String _full;
  late List<int> _t0;
  late List<int> _dur;
  late List<(int, int)> _ranges;
  late List<Rect?> _rects;
  TextPainter? _dimTp;
  TextPainter? _brightTp;

  TextPainter _tp(String s, Color c, TextScaler scaler, double w) {
    return TextPainter(
      text: TextSpan(text: s, style: widget.style.copyWith(color: c)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      textScaler: scaler,
    )..layout(maxWidth: w);
  }

  void _ensure(BuildContext context, double w) {
    if (_w == w &&
        identical(_lineKey, widget.line) &&
        _style == widget.style &&
        _accent == widget.accent &&
        _dim == widget.dim) {
      return;
    }
    _w = w;
    _lineKey = widget.line;
    _style = widget.style;
    _accent = widget.accent;
    _dim = widget.dim;

    final words = widget.line.words;
    final sb = StringBuffer();
    _t0 = <int>[];
    _dur = <int>[];
    _ranges = <(int, int)>[];
    for (final wd in words) {
      final s = sb.length;
      sb.write(wd.text);
      _ranges.add((s, sb.length));
      _t0.add(wd.timeMs);
      _dur.add(wd.durationMs);
    }
    _full = sb.toString();

    final scaler = MediaQuery.textScalerOf(context);
    _dimTp = _tp(_full, widget.dim, scaler, w);
    _brightTp = _tp(_full, widget.accent, scaler, w);

    _rects = <Rect?>[];
    for (final r in _ranges) {
      if (r.$2 <= r.$1) {
        _rects.add(null);
        continue;
      }
      final boxes = _brightTp!.getBoxesForSelection(
        TextSelection(baseOffset: r.$1, extentOffset: r.$2),
      );
      if (boxes.isEmpty) {
        _rects.add(null);
        continue;
      }
      final top = boxes.first.top;
      final bottom = boxes.first.bottom;
      final sameLine =
      boxes.every((b) => (b.top - top).abs() < 1 && (b.bottom - bottom).abs() < 1);
      if (!sameLine) {
        _rects.add(null); // wraps across visual lines → no lift
        continue;
      }
      var rect = boxes.first.toRect();
      for (final b in boxes.skip(1)) {
        rect = rect.expandToInclude(b.toRect());
      }
      _rects.add(rect);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 600.0;
        _ensure(context, w);
        final h = _brightTp!.height;
        return SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: w,
                child: _Glow(
                  text: _full,
                  style: widget.style.copyWith(color: widget.accent),
                ),
              ),
              CustomPaint(
                size: Size(w, h),
                painter: _KaraokePainter(
                  dim: _dimTp!,
                  bright: _brightTp!,
                  t0: _t0,
                  dur: _dur,
                  ranges: _ranges,
                  rects: _rects,
                  textLength: _full.length,
                  pos: widget.pos,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({
    required this.dim,
    required this.bright,
    required this.t0,
    required this.dur,
    required this.ranges,
    required this.rects,
    required this.textLength,
    required this.pos,
  }) : super(repaint: pos);

  final TextPainter dim;
  final TextPainter bright;
  final List<int> t0;
  final List<int> dur;
  final List<(int, int)> ranges;
  final List<Rect?> rects;
  final int textLength;
  final ValueListenable<int> pos;

  static const double _lift = 3.0;

  final Paint _clear = Paint()..blendMode = BlendMode.clear;
  final Paint _mask = Paint()..blendMode = BlendMode.dstIn;

  static double _liftOf(int t0, int d, int p) {
    if (p < t0) return 0;
    final dd = math.max(d, 1);
    final rise = ((p - t0) / dd.clamp(140, 420).toDouble()).clamp(0.0, 1.0);
    final riseInv = 1 - rise;
    final riseE = 1 - riseInv * riseInv * riseInv;
    final after = p - (t0 + dd);
    final settle = after <= 0 ? 1.0 : (1 - after / 520).clamp(0.0, 1.0);
    final settleE = settle * settle * (3 - 2 * settle);
    return riseE * settleE;
  }

  /// Text with each currently-lifting syllable translated up by <= _lift px.
  void _paintLifted(Canvas canvas, TextPainter tp, int p) {
    List<(Rect, double)>? lifts;
    for (var i = 0; i < t0.length; i++) {
      final r = rects[i];
      if (r == null) continue;
      final l = _liftOf(t0[i], dur[i], p);
      if (l <= 0.001) continue;
      (lifts ??= <(Rect, double)>[]).add((r, -l * _lift));
    }
    if (lifts == null) {
      tp.paint(canvas, Offset.zero);
      return;
    }
    canvas.save();
    for (final e in lifts) {
      canvas.clipRect(e.$1, clipOp: ui.ClipOp.difference);
    }
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    for (final e in lifts) {
      canvas.save();
      canvas.translate(0, e.$2);
      canvas.clipRect(e.$1);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = pos.value;
    _paintLifted(canvas, dim, p);
    if (textLength == 0) return;

    // Which syllable is being sung, and how far along (mild ease-out).
    double fill = 0;
    var idx = -1;
    double sylP = 0;
    for (var i = 0; i < t0.length; i++) {
      if (p < t0[i]) break;
      final linear = dur[i] <= 0
          ? 1.0
          : ((p - t0[i]) / dur[i]).clamp(0.0, 1.0).toDouble();
      final e = 1 - math.pow(1 - linear, 1.4).toDouble();
      fill = ranges[i].$1 + (ranges[i].$2 - ranges[i].$1) * e;
      idx = i;
      sylP = e;
      if (e < 1) break;
    }
    if (fill <= 0 || idx < 0) return;

    if (fill >= textLength) {
      _paintLifted(canvas, bright, p);
      return;
    }

    // Pixel extent of the syllable (not per char: complex scripts).
    final (cs, ce) = ranges[idx];
    double x;
    double top;
    double bottom;
    var feather = 12.0;
    final r = rects[idx];
    if (r != null) {
      x = r.left + (r.right - r.left) * sylP;
      top = r.top;
      bottom = r.bottom;
      feather = ((r.right - r.left).abs() * 0.3).clamp(5.0, 18.0).toDouble();
    } else {
      final ci = fill.floor().clamp(0, textLength - 1);
      final frac = fill - ci;
      final boxes = bright.getBoxesForSelection(
        TextSelection(baseOffset: ci, extentOffset: math.min(ci + 1, textLength)),
      );
      if (boxes.isEmpty) return;
      final b = boxes.first;
      x = b.left + (b.right - b.left) * frac;
      top = b.top;
      bottom = b.bottom;
    }
    // Lifted glyphs rise above the row; widen the mask upward.
    top -= _lift * 1.5;

    canvas.saveLayer(Offset.zero & size, Paint());
    _paintLifted(canvas, bright, p);

    final xStart = math.max(0.0, x - feather);
    final xEnd = math.min(size.width, x + feather);
    if (xEnd < size.width) {
      canvas.drawRect(Rect.fromLTRB(xEnd, top, size.width, bottom), _clear);
    }
    if (xEnd > xStart) {
      _mask.shader = ui.Gradient.linear(
        Offset(xStart, 0),
        Offset(xEnd, 0),
        const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
      );
      canvas.drawRect(Rect.fromLTRB(xStart, top, xEnd, bottom), _mask);
    }
    if (bottom < size.height) {
      canvas.drawRect(
          Rect.fromLTRB(0, bottom, size.width, size.height), _clear);
    }
    canvas.restore();
    // cs/ce kept for clarity of the syllable range used above.
    assert(cs <= ce);
  }

  @override
  bool shouldRepaint(covariant _KaraokePainter old) =>
      old.dim != dim || old.bright != bright || old.rects != rects;
}


class _Breath extends StatefulWidget {
  const _Breath({required this.color, this.scale = 1.0});

  final Color color;
  final double scale;

  @override
  State<_Breath> createState() => _BreathState();
}

class _BreathState extends State<_Breath> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return FadeTransition(
      opacity: Tween<double>(begin: 0.30, end: 0.85).animate(curved),
      child: Text(
        '♪   ♪   ♪',
        style: TextStyle(
          fontSize: 22 * widget.scale,
          color: widget.color,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
