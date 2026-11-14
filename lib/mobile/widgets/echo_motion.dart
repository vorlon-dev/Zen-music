// ZenMusic · vorlon-dev
//
// Motion ported from echo-nightly (Android animated-vectors / sheet offsets)
// to plain Flutter. No packages, no blur, no saveLayer: only Transform and
// opacity on small widgets, so it stays smooth on low-end phones.
//
//  * EchoLikeButton  – heart: the filled heart grows 0 -> 1 (500 ms,
//                      fast_out_slow_in) while the outline pulses 1 -> 1.05 -> 1.
//  * EchoSkipButton  – next / previous: the glyph squeezes (scale .75) and
//                      slides away 300 ms while the next glyph pops in 0 -> 1,
//                      with a 1 px settle. Mirror for previous.
//  * EchoRise        – list items rise from below with a fade, staggered.
//  * EchoSheetMotion – expanded controls slide down 2x and fade as the sheet
//                      collapses (echo: translationY = h * offset * 2,
//                      alpha = 1 - min(1, offset * 3)).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

const Curve _kEchoCurve = Curves.fastOutSlowIn;

// ── Like button ─────────────────────────────────────────────────────────────

class EchoLikeButton extends StatefulWidget {
  const EchoLikeButton({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 26,
    this.pad = 22,
    this.likedColor = const Color(0xFFFF4D6D),
    this.idleColor = Colors.white70,
    this.outline = Icons.favorite_border_rounded,
    this.filled = Icons.favorite_rounded,
  });

  final bool liked;
  final VoidCallback onTap;
  final double size;
  final double pad;
  final Color likedColor;
  final Color idleColor;
  final IconData outline;
  final IconData filled;

  @override
  State<EchoLikeButton> createState() => _EchoLikeButtonState();
}

class _EchoLikeButtonState extends State<EchoLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant EchoLikeButton old) {
    super.didUpdateWidget(old);
    if (old.liked != widget.liked) {
      if (MediaQuery.of(context).disableAnimations) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: SizedBox(
        width: s + widget.pad,
        height: s + widget.pad,
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              if (widget.liked) {
                // outline pulses 1 -> 1.05 -> 1 between 300 and 500 ms
                final pulse = t < 0.6
                    ? 1.0
                    : 1.0 +
                    0.05 *
                        (t < 0.8
                            ? _kEchoCurve.transform((t - 0.6) / 0.2)
                            : 1 - _kEchoCurve.transform((t - 0.8) / 0.2));
                final grow = _kEchoCurve.transform(t);
                return Transform.scale(
                  scale: pulse,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(widget.filled,
                          size: s, color: widget.likedColor.withValues(alpha: 0.28)),
                      Transform.scale(
                        scale: grow,
                        child: Icon(widget.filled,
                            size: s, color: widget.likedColor),
                      ),
                    ],
                  ),
                );
              }
              // un-like: filled shrinks away quickly, outline fades in
              final out = _kEchoCurve.transform(t);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: (1 - out).clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 1 - out * 0.4,
                      child: Icon(widget.filled,
                          size: s, color: widget.likedColor),
                    ),
                  ),
                  Opacity(
                    opacity: out.clamp(0.0, 1.0),
                    child: Icon(widget.outline,
                        size: s, color: widget.idleColor),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Next / previous ─────────────────────────────────────────────────────────

/// Bump [next] / [previous] whenever a skip happens (button, swipe, media
/// key, notification): every EchoSkipButton of that direction animates.
class EchoSkipPulse {
  EchoSkipPulse._();
  static final ValueNotifier<int> next = ValueNotifier<int>(0);
  static final ValueNotifier<int> previous = ValueNotifier<int>(0);
}

class EchoSkipButton extends StatefulWidget {
  const EchoSkipButton({
    super.key,
    required this.onTap,
    this.next = true,
    this.size = 32,
    this.box = 52,
    this.color = Colors.white,
    this.tooltip,
  });

  final VoidCallback onTap;
  final bool next; // false = previous
  final double size;
  final double box;
  final Color color;
  final String? tooltip;

  @override
  State<EchoSkipButton> createState() => _EchoSkipButtonState();
}

class _EchoSkipButtonState extends State<EchoSkipButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  ValueNotifier<int> get _pulse =>
      widget.next ? EchoSkipPulse.next : EchoSkipPulse.previous;

  @override
  void initState() {
    super.initState();
    _pulse.addListener(_play);
  }

  @override
  void didUpdateWidget(covariant EchoSkipButton old) {
    super.didUpdateWidget(old);
    if (old.next != widget.next) {
      (old.next ? EchoSkipPulse.next : EchoSkipPulse.previous)
          .removeListener(_play);
      _pulse.addListener(_play);
    }
  }

  @override
  void dispose() {
    _pulse.removeListener(_play);
    _c.dispose();
    super.dispose();
  }

  void _play() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) return;
    _c.forward(from: 0);
  }

  void _tap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final dir = widget.next ? 1.0 : -1.0;
    final icon = widget.next
        ? Icons.skip_next_rounded
        : Icons.skip_previous_rounded;
    final s = widget.size;

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: SizedBox(
        width: widget.box,
        height: widget.box,
        child: ClipRect(
          child: Center(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _kEchoCurve.transform(_c.value);
                // outgoing glyph: slides ~half its width and squeezes to .75
                final outShift = -dir * (s * 0.48) * t;
                final outScale = 1 - 0.25 * t;
                // incoming glyph: pops 0 -> 1 from the opposite side
                final inScale = t;
                final inShift = dir * (s * 0.48) * (1 - t);
                final settle = (_c.value > 0.33 && _c.value < 0.66)
                    ? dir * -1.0 * (1 - (_c.value - 0.33) / 0.33).clamp(0, 1)
                    : 0.0;
                if (_c.value >= 1) {
                  return Icon(icon, size: s, color: widget.color);
                }
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(outShift, 0),
                        child: Transform.scale(
                          scale: outScale,
                          child: Icon(icon, size: s, color: widget.color),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(inShift + settle, 0),
                      child: Transform.scale(
                        scale: inScale,
                        child: Icon(icon, size: s, color: widget.color),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

// ── Slide-up for list rows ──────────────────────────────────────────────────

/// Wrap a list row / card: it rises ~28 px and fades in the first time it is
/// built. Give each row its [index] for a light stagger (capped at 8 rows so
/// long lists never feel slow).
class EchoRise extends StatefulWidget {
  const EchoRise({
    super.key,
    required this.child,
    this.index = 0,
    this.distance = 28,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget child;
  final int index;
  final double distance;
  final Duration duration;

  @override
  State<EchoRise> createState() => _EchoRiseState();
}

class _EchoRiseState extends State<EchoRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 38 * widget.index.clamp(0, 8).toInt());
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.distance),
            child: child,
          ),
        );
      },
    );
  }
}

// ── Player sheet: controls follow the sheet offset ──────────────────────────

/// [offset] 0 = sheet fully expanded, 1 = collapsed. Same maths as echo:
/// the controls slide down 2x their height and fade out three times faster
/// than the sheet collapses.
class EchoSheetMotion extends StatelessWidget {
  const EchoSheetMotion({
    super.key,
    required this.offset,
    required this.height,
    required this.child,
  });

  final double offset;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = offset.clamp(0.0, 1.0);
    final alpha = 1 - (o * 3).clamp(0.0, 1.0);
    if (alpha <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: alpha,
      child: Transform.translate(
        offset: Offset(0, height * o * 2),
        child: child,
      ),
    );
  }
}

/// Mini-player counterpart: fades/slides in as the sheet collapses
/// (echo: alpha = collapsedOffset * 2, translationY = -h * (1 - offset) * 2).
class EchoCollapsedMotion extends StatelessWidget {
  const EchoCollapsedMotion({
    super.key,
    required this.offset,
    required this.height,
    required this.child,
  });

  final double offset;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = offset.clamp(0.0, 1.0);
    return Opacity(
      opacity: (o * 2).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -height * (1 - o) * 2),
        child: child,
      ),
    );
  }
}

// ── 1. Play / pause morph ───────────────────────────────────────────────────

/// Play <-> pause morph (Flutter's built-in AnimatedIcons), 300 ms.
class EchoPlayPauseIcon extends StatefulWidget {
  const EchoPlayPauseIcon({
    super.key,
    required this.playing,
    this.size = 34,
    this.color = Colors.black,
  });

  final bool playing;
  final double size;
  final Color color;

  @override
  State<EchoPlayPauseIcon> createState() => _EchoPlayPauseIconState();
}

class _EchoPlayPauseIconState extends State<EchoPlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant EchoPlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (old.playing != widget.playing) {
      widget.playing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedIcon(
    icon: AnimatedIcons.play_pause,
    progress: CurvedAnimation(parent: _c, curve: _kEchoCurve),
    size: widget.size,
    color: widget.color,
  );
}

// ── 2. Shuffle / repeat pop ─────────────────────────────────────────────────

/// Pops (1 -> 1.3 -> 1) and turns a quarter when [icon] or [active] changes:
/// shuffle on/off, repeat off -> all -> one.
class EchoPopIcon extends StatefulWidget {
  const EchoPopIcon({
    super.key,
    required this.icon,
    required this.active,
    this.size = 24,
    this.activeColor = Colors.white,
    this.idleColor = const Color(0x8CFFFFFF),
  });

  final IconData icon;
  final bool active;
  final double size;
  final Color activeColor;
  final Color idleColor;

  @override
  State<EchoPopIcon> createState() => _EchoPopIconState();
}

class _EchoPopIconState extends State<EchoPopIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant EchoPopIcon old) {
    super.didUpdateWidget(old);
    if (old.icon != widget.icon || old.active != widget.active) {
      if (!MediaQuery.of(context).disableAnimations) _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final pop = 1 + 0.3 * (t < 0.5 ? t * 2 : (1 - t) * 2);
        return Transform.rotate(
          angle: (1 - _kEchoCurve.transform(t)) * -0.5,
          child: Transform.scale(
            scale: pop,
            child: Icon(widget.icon,
                size: widget.size,
                color: widget.active ? widget.activeColor : widget.idleColor),
          ),
        );
      },
    );
  }
}

// ── 4. Now-playing bars ─────────────────────────────────────────────────────

/// Three bars bouncing like an equaliser. Frozen at rest when [playing] is false.
class EchoNowPlayingBars extends StatefulWidget {
  const EchoNowPlayingBars({
    super.key,
    this.playing = true,
    this.color = Colors.white,
    this.size = 20,
  });

  final bool playing;
  final Color color;
  final double size;

  @override
  State<EchoNowPlayingBars> createState() => _EchoNowPlayingBarsState();
}

class _EchoNowPlayingBarsState extends State<EchoNowPlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant EchoNowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing && _c.isAnimating) _c.stop();
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
        builder: (context, _) {
          double h(double phase) {
            final v = (_c.value + phase) % 1.0;
            final w = v < 0.5 ? v * 2 : (1 - v) * 2;
            return s * (0.25 + 0.75 * Curves.easeInOut.transform(w));
          }

          Widget bar(double phase) => Container(
            width: s * 0.2,
            height: widget.playing ? h(phase) : s * 0.3,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(s * 0.1),
            ),
          );

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [bar(0.0), bar(0.33), bar(0.66)],
          );
        },
      ),
    );
  }
}

// ── 5. Splash ───────────────────────────────────────────────────────────────

/// Logo pops in (scale .6 -> 1, fade) then the whole splash fades out over
/// [child]. Wrap the app's first screen: EchoSplash(logo: ..., child: app).
class EchoSplash extends StatefulWidget {
  const EchoSplash({
    super.key,
    required this.child,
    required this.logo,
    this.background = Colors.black,
  });

  final Widget child;
  final Widget logo;
  final Color background;

  @override
  State<EchoSplash> createState() => _EchoSplashState();
}

class _EchoSplashState extends State<EchoSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            if (v >= 1) return const SizedBox.shrink();
            final inT = Curves.easeOutBack.transform((v / 0.5).clamp(0.0, 1.0));
            final out = ((v - 0.7) / 0.3).clamp(0.0, 1.0);
            return IgnorePointer(
              child: Opacity(
                opacity: 1 - out,
                child: ColoredBox(
                  color: widget.background,
                  child: Center(
                    child: Opacity(
                      opacity: (v / 0.3).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.6 + 0.4 * inT,
                        child: widget.logo,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}