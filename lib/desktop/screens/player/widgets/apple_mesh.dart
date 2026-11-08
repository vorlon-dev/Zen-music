// ZenMusic · pieces of the "Apple Music · Mesh" player skin:
//  - AppleMeshBackdrop: a drifting colour mesh taken from the artwork
//  - AppleLyricStrip:   the line being sung, lit word by word, above the bar
//  - HeldCrossfade:     fades a layer in/out but keeps it mounted
//  - NowLyricsFeed:     lets any skin see the current song's lyrics
import 'package:zenmusic/desktop/services/lyrics_romanizer.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:zenmusic/desktop/services/lyrics_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

/// Published by LyricsBox whenever lyrics for the current song are loaded.
class NowLyricsFeed {
  NowLyricsFeed._();
  static final NowLyricsFeed instance = NowLyricsFeed._();
  final ValueNotifier<LyricsData?> data = ValueNotifier(null);
  String? songId;

  void set(String id, LyricsData? d) {
    songId = id;
    data.value = d;
  }
}

// ---------------------------------------------------------------------------
// Mesh backdrop
// ---------------------------------------------------------------------------
class AppleMeshBackdrop extends StatefulWidget {
  const AppleMeshBackdrop({
    super.key,
    required this.artKey,
    required this.provider,
    required this.fallback,
  });
  final String? artKey;
  final ImageProvider? provider;
  final Color fallback;

  @override
  State<AppleMeshBackdrop> createState() => _AppleMeshBackdropState();
}

class _AppleMeshBackdropState extends State<AppleMeshBackdrop>
    with TickerProviderStateMixin {
  static final Map<String, List<Color>> _cache = {};

  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 26))..repeat();
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..value = 1;
  List<Color> _from = const [];
  List<Color> _to = const [];

  @override
  void initState() {
    super.initState();
    _to = _fallbackSet(widget.fallback);
    _from = _to;
    _load();
  }

  @override
  void didUpdateWidget(covariant AppleMeshBackdrop old) {
    super.didUpdateWidget(old);
    if (old.artKey != widget.artKey || old.fallback != widget.fallback) _load();
  }

  @override
  void dispose() {
    _drift.dispose();
    _fade.dispose();
    super.dispose();
  }

  static Color _tone(Color c) {
    final h = HSLColor.fromColor(c);
    return h
        .withSaturation(h.saturation.clamp(0.4, 0.95).toDouble())
        .withLightness(h.lightness.clamp(0.26, 0.55).toDouble())
        .toColor();
  }

  static List<Color> _fallbackSet(Color c) {
    final h = HSLColor.fromColor(c);
    return [
      _tone(c),
      _tone(h.withHue((h.hue + 35) % 360).toColor()),
      _tone(h.withHue((h.hue + 320) % 360).toColor()),
      _tone(h.withLightness(0.2).toColor()),
    ];
  }

  Color _current(int i) =>
      Color.lerp(_from[i % _from.length], _to[i % _to.length], _fade.value)!;

  void _apply(List<Color> cs) {
    final now = [for (var i = 0; i < 4; i++) _current(i)];
    _from = now;
    _to = cs;
    _fade.forward(from: 0);
  }

  Future<void> _load() async {
    final key = widget.artKey;
    if (key != null && _cache.containsKey(key)) {
      _apply(_cache[key]!);
      return;
    }
    final prov = widget.provider;
    if (key == null || prov == null) {
      _apply(_fallbackSet(widget.fallback));
      return;
    }
    try {
      final p = await PaletteGenerator.fromImageProvider(
        ResizeImage(prov, width: 48, height: 48),
        maximumColorCount: 10,
      );
      final raw = <Color?>[
        p.darkVibrantColor?.color,
        p.vibrantColor?.color,
        p.mutedColor?.color,
        p.lightVibrantColor?.color,
        p.dominantColor?.color,
      ].whereType<Color>().map(_tone).toList();
      final fb = _fallbackSet(widget.fallback);
      final out = <Color>[...raw, ...fb].take(4).toList();
      _cache[key] = out;
      if (mounted && widget.artKey == key) _apply(out);
    } catch (_) {
      if (mounted) _apply(_fallbackSet(widget.fallback));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_drift, _fade]),
        builder: (context, _) {
          final t = _drift.value * 2 * math.pi;
          final cs = [for (var i = 0; i < 4; i++) _current(i)];
          Alignment a(double ph, double cx, double cy) => Alignment(
                cx + 0.55 * math.sin(t + ph),
                cy + 0.45 * math.cos(t * 0.8 + ph),
              );
          Widget blob(Color c, Alignment al, double r) => Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: al,
                      radius: r,
                      colors: [c.withValues(alpha: 0.92), c.withValues(alpha: 0)],
                    ),
                  ),
                ),
              );
          return Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Color.lerp(const Color(0xFF0B0B0D), cs[0], 0.35)!),
            blob(cs[0], a(0, -0.6, -0.6), 1.15),
            blob(cs[1], a(2.1, 0.7, -0.2), 1.0),
            blob(cs[2], a(4.2, -0.5, 0.7), 1.1),
            blob(cs[3], a(1.0, 0.6, 0.8), 0.9),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x73000000)],
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lyric strip
// ---------------------------------------------------------------------------
class AppleLyricStrip extends StatelessWidget {
  const AppleLyricStrip({
    super.key,
    this.onTap,
    this.bright = Colors.white,
    this.fontSize = 18,
  });
  final VoidCallback? onTap;
  final Color bright;
  final double fontSize;

  static int _indexAt(List<LyricLine> l, int ms) {
    var lo = 0, hi = l.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (l[mid].timeMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  /// 0..1: how much of the line has been sung (by characters).
  static double _progress(LyricLine line, int ms) {
    if (!line.hasWords) return 1.0;
    var total = 0, done = 0.0;
    for (final w in line.words) {
      total += w.text.length;
    }
    if (total == 0) return 1.0;
    for (final w in line.words) {
      final end = w.timeMs + w.durationMs;
      if (ms >= end) {
        done += w.text.length;
      } else {
        if (ms > w.timeMs && w.durationMs > 0) {
          done += w.text.length * (ms - w.timeMs) / w.durationMs;
        }
        break;
      }
    }
    return (done / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final h = fontSize * 1.6;
    return ValueListenableBuilder<LyricsData?>(
      valueListenable: NowLyricsFeed.instance.data,
      builder: (context, d, _) {
        final lines = d?.synced;
        if (lines == null || lines.isEmpty) return SizedBox(height: h);
        return ValueListenableBuilder<ProgressBarState>(
          valueListenable: GetIt.I<MediaPlayer>().progressBarState,
          builder: (context, pb, _) {
            final ms = pb.current.inMilliseconds;
            final i = _indexAt(lines, ms);
            final style = TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: bright.withValues(alpha: 0.38),
            );
            Widget child;
            if (i < 0) {
              child = Text('• • •', key: const ValueKey(-1), style: style);
            } else {
              final line = LyricsRomanizer.instance.apply(lines[i]);
              final text = line.text.trim().isEmpty ? '♪' : line.text.trim();
              final p = _progress(line, ms);
              child = Stack(key: ValueKey(i), children: [
                Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => LinearGradient(
                    colors: const [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
                    stops: [0, p, math.min(1.0, p + 0.0001), 1],
                  ).createShader(r),
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: bright)),
                ),
              ]);
            }
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: SizedBox(
                height: h,
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (c, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.5), end: Offset.zero).animate(a),
                        child: c,
                      ),
                    ),
                    layoutBuilder: (cur, prev) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...prev, if (cur != null) cur],
                    ),
                    child: Align(alignment: Alignment.centerLeft, child: child),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Keep-mounted crossfade
// ---------------------------------------------------------------------------
class HeldCrossfade extends StatefulWidget {
  const HeldCrossfade({super.key, required this.on, required this.builder});
  final bool on;

  /// [shown] is true while the layer is visible or still fading out.
  final Widget Function(BuildContext context, bool shown) builder;

  @override
  State<HeldCrossfade> createState() => _HeldCrossfadeState();
}

class _HeldCrossfadeState extends State<HeldCrossfade> {
  late bool _show = widget.on;
  Timer? _t;

  @override
  void didUpdateWidget(covariant HeldCrossfade old) {
    super.didUpdateWidget(old);
    if (widget.on) {
      _t?.cancel();
      _show = true;
    } else if (old.on) {
      _t?.cancel();
      _t = Timer(const Duration(milliseconds: 320), () {
        if (mounted) setState(() => _show = false);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Offstage(
        offstage: !_show,
        child: AnimatedOpacity(
          opacity: widget.on ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(ignoring: !widget.on, child: widget.builder(context, _show)),
        ),
      );
}
