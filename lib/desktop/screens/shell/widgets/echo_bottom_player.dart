// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show DragUpdateDetails, DragEndDetails;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:text_scroll/text_scroll.dart';

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/progress_ring.dart';
import 'package:zenmusic/desktop/utils/song_thumbnail.dart';

/// SP-76: vertical-drag sink for the mobile shell's Echo Nightly player
/// sheet. When the shell provides one, dragging the mini pill UP feeds the
/// shell's sheet offset every frame (1:1 finger tracking, like the
/// reference) instead of firing the old threshold-open spring. Tap still
/// opens through [EchoBottomPlayer.onOpen]; horizontal swipe-to-switch is
/// untouched. Null (desktop / standalone) keeps the old behaviour.
class EchoSheetDragSink {
  const EchoSheetDragSink({
    required this.update,
    required this.end,
    required this.cancel,
  });

  final void Function(DragUpdateDetails d) update;
  final void Function(DragEndDetails d) end;
  final VoidCallback cancel;
}

class EchoBottomPlayer extends StatefulWidget {
  const EchoBottomPlayer({super.key, this.onOpen, this.sheetDrag});

  final VoidCallback? onOpen;

  /// SP-76: when set, dragging the pill up/down drives the shell's player
  /// sheet directly (Echo Nightly finger-following) instead of the
  /// threshold-open spring.
  final EchoSheetDragSink? sheetDrag;

  @override
  State<EchoBottomPlayer> createState() => _EchoBottomPlayerState();
}

class _EchoBottomPlayerState extends State<EchoBottomPlayer> {
  Color? backgroundColor;

  void updateBackgroundColor(ImageProvider image) async {
    final palette = await PaletteGenerator.fromImageProvider(
      image,
      maximumColorCount: 20,
    );
    if (mounted) {
      if (palette.dominantColor != null &&
          backgroundColor != palette.dominantColor!.color) {
        setState(() {
          backgroundColor = palette.dominantColor!.color;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaPlayer = GetIt.I<MediaPlayer>();
    // SP-5b: source song from currentSongNotifier so this works for both
    // just_audio and the engine (just_audio's sequence is empty when the
    // engine owns playback).
    return ValueListenableBuilder<MediaItem?>(
      valueListenable: mediaPlayer.currentSongNotifier,
      builder: (context, currentSong, _) {
        if (currentSong == null) {
          return const SizedBox();
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EchoMiniBody(
              song: currentSong,
              color: backgroundColor,
              onImageReady: updateBackgroundColor,
              onOpen: widget.onOpen, // SP-81b: forward the sheet opener
              sheetDrag: widget.sheetDrag, // SP-76: finger-following sheet
            ),
          ),
        );
      },
    );
  }
}


class _EchoMiniBody extends StatefulWidget {
  const _EchoMiniBody({
    required this.song,
    required this.color,
    required this.onImageReady,
    this.onOpen, // SP-81b
    this.sheetDrag, // SP-76
  });

  final MediaItem song;
  final Color? color;
  final void Function(ImageProvider image) onImageReady;

  final VoidCallback? onOpen;

  /// SP-76: vertical drags go to the shell's sheet when provided.
  final EchoSheetDragSink? sheetDrag;

  @override
  State<_EchoMiniBody> createState() => _EchoMiniBodyState();
}

class _EchoMiniBodyState extends State<_EchoMiniBody>
    with TickerProviderStateMixin {
  // Echo Music pill: 64 dp tall, fully rounded, 40 dp round art inside a
  // 48 dp progress ring, 32 dp skip buttons around a 48 dp cookie play button.
  static const double _height = 64;
  static const double _ring = 48;
  static const double _art = 40;
  static const double _dragThreshold = 10;

  late final AnimationController _spin; // cookie rotation (8 s / turn)
  late final AnimationController _indent; // cookie bloom (300 ms)
  late final AnimationController _drag; // swipe offset, spring back
  double _dx = 0;
  double _dragDist = 0;
  DateTime _dragStart = DateTime.now();

  late final AnimationController _press;
  late final Animation<double> _scale;

  // Track-change slide state: direction follows the user's intent
  // (swipe / next button), so the new track slides in from the right place.
  bool _slideForward = true;
  bool? _pendingSlideForward;
  DateTime _slideIntentAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSlideSongId;

  MediaPlayer get _mp => GetIt.I<MediaPlayer>();

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _spin = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 8000));
    _indent = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _drag = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() => _dx = _drag.value));
    _applyPlaying(_mp.buttonState.value == ButtonState.playing);
    _mp.buttonState.addListener(_onButton);
    _scale = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _mp.buttonState.removeListener(_onButton);
    _spin.dispose();
    _indent.dispose();
    _drag.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onButton() =>
      _applyPlaying(_mp.buttonState.value == ButtonState.playing);

  void _applyPlaying(bool playing) {
    if (playing) {
      _indent.forward();
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _indent.reverse();
      _spin.stop();
    }
  }

  void _springBack([double velocity = 0]) {
    _drag.value = _dx;
    _drag.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 200, damping: 28),
      _dx,
      0,
      velocity,
    ));
  }

  void _dragEnd(DragEndDetails d) {
    final ms = DateTime.now().difference(_dragStart).inMilliseconds;
    final v = ms > 0 ? _dragDist / ms : 0.0; // px per ms, like Echo
    final far = _dx.abs() > 50 && v > 0.9;
    final farther = _dx.abs() > 150;
    if (far || farther) {
      if (_dx < 0 && _mp.player.hasNext) {
        _next();
      } else if (_dx > 0 && _mp.player.hasPrevious) {
        _previous();
      }
    }
    _springBack(d.primaryVelocity ?? 0);
  }

  void _noteSlideIntent(bool forward) {
    _pendingSlideForward = forward;
    _slideIntentAt = DateTime.now();
  }

  void _consumeSlideIntentIfNeeded() {
    final id = widget.song.id;
    if (id == _lastSlideSongId) return;
    final pending = _pendingSlideForward;
    if (pending != null &&
        DateTime.now().difference(_slideIntentAt) <
            const Duration(milliseconds: 3000)) {
      _slideForward = pending;
    }
    _pendingSlideForward = null;
    _lastSlideSongId = id;
  }

  static bool _opening = false;

  void _open() {
    if (_opening) return;
    _opening = true;
    final opener = widget.onOpen;
    if (opener != null) {
      Timer(const Duration(milliseconds: 600), () => _opening = false);
      opener();
      return;
    }
    context.push('/player').whenComplete(() => _opening = false);
  }

  void _next() {
    _noteSlideIntent(true);
    _mp.skipNext(); // SP-5b
  }

  void _previous() {
    _noteSlideIntent(false);
    _mp.skipPrevious(); // SP-5b
  }

  Widget _slideOnChange({required String slideKey, required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.hardEdge,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == ValueKey<String>(slideKey);
        final Offset slideFrom = incoming
            ? Offset(_slideForward ? 0.35 : -0.35, 0)
            : Offset(_slideForward ? -0.35 : 0.35, 0);
        return IgnorePointer(
          ignoring: !incoming,
          child: FadeTransition(
            opacity: incoming
                ? Tween<double>(begin: 0.35, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut))
                : Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeIn)),
            child: SlideTransition(
              position: Tween<Offset>(begin: slideFrom, end: Offset.zero)
                  .animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey<String>(slideKey), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    _consumeSlideIntentIfNeeded();
    final song = widget.song;
    final settings = GetIt.I<SettingsManager>();
    final liquid = settings.liquidGlass;
    final m3 = settings.isMaterial3;
    final cs = Theme.of(context).colorScheme;
    final base = widget.color ?? const Color(0xFF202020);
    final dark = Color.lerp(base, Colors.black, 0.45)!;
    final subtitle = '${song.artist ?? song.extras?['subtitle'] ?? ''}';
    // Echo: surfaceContainerHigh pill with a 1 dp outline at 30 %.
    final themed = m3;
    final fg = themed ? cs.onSurface : Colors.white;
    final fg2 = fg.withValues(alpha: 0.7);
    final outline =
        (themed ? cs.outline : Colors.white).withValues(alpha: 0.3);
    final shape = BorderRadius.circular(_height / 2);

    return ListenableBuilder(
      listenable: _scale,
      builder: (context, _) => Transform.scale(
        scale: _scale.value,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press.forward(),
          onTapUp: (_) => _press.reverse(),
          onTapCancel: () => _press.reverse(),
          onTap: _open,
          // SP-76: with a sheet sink the pill IS the collapsed sheet — drag
          // it and the sheet follows the finger 1:1 (Echo Nightly). Without
          // one, keep the old upward-threshold open.
          onVerticalDragUpdate: widget.sheetDrag != null
              ? (d) => widget.sheetDrag!.update(d)
              : (d) {
                  if ((d.primaryDelta ?? 0) < -_dragThreshold) _open();
                },
          onVerticalDragEnd:
              widget.sheetDrag != null ? widget.sheetDrag!.end : null,
          onVerticalDragCancel:
              widget.sheetDrag != null ? widget.sheetDrag!.cancel : null,
          onHorizontalDragStart: (_) {
            _drag.stop();
            _dragStart = DateTime.now();
            _dragDist = 0;
          },
          onHorizontalDragUpdate: (d) {
            final dx = d.primaryDelta ?? 0;
            final hasNext = _mp.player.hasNext;
            final hasPrev = _mp.player.hasPrevious;
            final ok = (dx < 0 && hasNext) ||
                (dx > 0 && hasPrev) ||
                (dx > 0 && _dx < 0) ||
                (dx < 0 && _dx > 0);
            if (!ok) return;
            _dragDist += dx.abs();
            setState(() => _dx += dx);
          },
          onHorizontalDragCancel: () => _springBack(),
          onHorizontalDragEnd: _dragEnd,
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                color: themed
                    ? cs.surfaceContainerHigh
                    : liquid
                        ? Colors.white.withValues(alpha: 0.05)
                        : null,
                gradient: (liquid || themed)
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [base, dark],
                      ),
                borderRadius: shape,
                border: Border.all(color: outline, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: themed ? 0.14 : (liquid ? 0.18 : 0.3)),
                    blurRadius: themed ? 10 : (liquid ? 18 : 20),
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: shape,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      _thumb(song, themed ? cs.primary : Colors.white, outline),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _slideOnChange(
                          slideKey: 'meta-${song.id}',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextScroll(
                                song.title,
                                mode: TextScrollMode.bouncing,
                                velocity: const Velocity(
                                    pixelsPerSecond: Offset(30, 0)),
                                delayBefore: const Duration(seconds: 3),
                                pauseBetween: const Duration(seconds: 2),
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: fg2,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _buildControls(fg, themed ? cs.primary : Colors.white,
                          themed ? cs.surface : Colors.black),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 40 dp round art inside a 48 dp, 3 dp round-capped progress ring.
  Widget _thumb(MediaItem song, Color ring, Color outline) {
    return SizedBox(
      width: _ring,
      height: _ring,
      child: ValueListenableBuilder<ProgressBarState>(
        valueListenable: _mp.progressBarState,
        builder: (context, value, child) {
          final total = value.total.inMilliseconds;
          final p = total <= 0
              ? 0.0
              : (value.current.inMilliseconds / total).clamp(0.0, 1.0);
          return CustomPaint(
            foregroundPainter: _EchoThumbRingPainter(
              progress: p,
              color: ring,
              track: outline.withValues(alpha: 0.2),
            ),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: _art,
            height: _art,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: outline, width: 1),
            ),
            child: ClipOval(
              child: _slideOnChange(
                slideKey: song.id,
                child: SongThumbnail(
                  song: song.extras!,
                  dp: MediaQuery.of(context).devicePixelRatio,
                  height: _art,
                  width: _art,
                  fit: BoxFit.cover,
                  onImageReady: widget.onImageReady,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(Color fg, Color playBg, Color playFg) {
    final mp = _mp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder(
          stream: mp.player.sequenceStateStream,
          builder: (context, _) => _skipBtn(
            Icons.skip_previous_rounded,
            fg,
            mp.player.hasPrevious ? _previous : null,
          ),
        ),
        const SizedBox(width: 12),
        ValueListenableBuilder<ButtonState>(
          valueListenable: mp.buttonState,
          builder: (context, state, _) {
            final loading = state == ButtonState.loading;
            final playing = state == ButtonState.playing;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: loading ? null : () => mp.togglePlayPause(),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: Listenable.merge([_spin, _indent]),
                      builder: (context, _) => Transform.rotate(
                        angle: _spin.value * 2 * math.pi,
                        child: CustomPaint(
                          size: const Size(48, 48),
                          painter: _EchoCookiePainter(
                            color: playBg,
                            indent: 0.08 * _indent.value,
                          ),
                        ),
                      ),
                    ),
                    if (loading)
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: AdaptiveProgressRing(),
                      )
                    else
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(playing),
                          color: playFg,
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        StreamBuilder(
          stream: mp.player.sequenceStateStream,
          builder: (context, _) => _skipBtn(
            Icons.skip_next_rounded,
            fg,
            mp.player.hasNext ? _next : null,
          ),
        ),
      ],
    );
  }

  Widget _skipBtn(IconData icon, Color fg, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          size: 24,
          color: onTap == null ? fg.withValues(alpha: 0.35) : fg,
        ),
      ),
    );
  }
}

class _EchoThumbRingPainter extends CustomPainter {
  _EchoThumbRingPainter(
      {required this.progress, required this.color, required this.track});
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const w = 3.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(w / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawArc(r, 0, 2 * math.pi, false, paint..color = track);
    if (progress > 0) {
      canvas.drawArc(
          r, -math.pi / 2, 2 * math.pi * progress, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_EchoThumbRingPainter o) =>
      o.progress != progress || o.color != color || o.track != track;
}

/// 9-lobed cookie; [indent] 0 is a circle, 0.08 matches Echo's playing state.
class _EchoCookiePainter extends CustomPainter {
  _EchoCookiePainter({required this.color, required this.indent});
  final Color color;
  final double indent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final R = size.width / 2;
    final path = Path();
    const n = 180;
    for (var i = 0; i <= n; i++) {
      final a = 2 * math.pi * i / n;
      final r = R * (1 - indent * 1.8 * (0.5 + 0.5 * math.cos(9 * a)));
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_EchoCookiePainter o) =>
      o.color != color || o.indent != indent;
}
