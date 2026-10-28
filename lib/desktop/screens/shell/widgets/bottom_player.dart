// ZenMusic Desktop — ported from Echo Music (GPL-3.0). ZenMusic remains GPL-3.0.
// PORT DEVIATIONS: unused imports dropped (dart:ui, bottom_modals, listtile);
// MINI PLAYER REDESIGN: layout/behaviour ported from the old mobile
// MiniPlayer (72px card, 20px radius, 52px rounded artwork, marquee title,
// wavy progress ring around play/pause, next button, slide-on-track-change
// animation, swipe left/right = next/previous, swipe up / tap = open
// player, press-scale). audioHandler streams -> MediaPlayer (GetIt);
// spotify theme colours -> artwork palette colour.
// SP-5b: song source is MediaPlayer.currentSongNotifier (works for both
// just_audio and the Spotify desktop engine); transport routes through
// MediaPlayer.togglePlayPause/skipNext/skipPrevious.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:text_scroll/text_scroll.dart';

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/material3/m3_tokens.dart'; // SP-58
import 'package:zenmusic/desktop/material3/m3_wavy_slider.dart'; // SP-58
import 'package:zenmusic/desktop/services/settings_manager.dart'; // SP-54
import 'package:zenmusic/desktop/utils/adaptive_widgets/buttons.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/progress_ring.dart';
import 'package:zenmusic/desktop/utils/song_thumbnail.dart';

class BottomPlayer extends StatefulWidget {
  const BottomPlayer({super.key});

  @override
  State<BottomPlayer> createState() => _BottomPlayerState();
}

class _BottomPlayerState extends State<BottomPlayer> {
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
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MiniBody(
              song: currentSong,
              color: backgroundColor,
              onImageReady: updateBackgroundColor,
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════
// MINI PLAYER BODY
// ═════════════════════════════════════════════

class _MiniBody extends StatefulWidget {
  const _MiniBody({
    required this.song,
    required this.color,
    required this.onImageReady,
  });

  final MediaItem song;
  final Color? color;
  final void Function(ImageProvider image) onImageReady;

  @override
  State<_MiniBody> createState() => _MiniBodyState();
}

class _MiniBodyState extends State<_MiniBody>
    with SingleTickerProviderStateMixin {
  static const double _height = 72;
  static const double _radius = 20;
  static const double _artSize = 52;
  static const double _artRadius = 14;
  static const double _dragThreshold = 10;

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
    _scale = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _press, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
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

  void _open() => context.push('/player');

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
    // SP-54: Liquid Glass — in glass mode the artwork-palette gradient is
    // dropped so the surrounding ZenGlassPanel (shader glass on Windows,
    // Kotlin glass on Android) shows through; only a faint frost tint and
    // a soft shadow remain for legibility.
    // SP-58: Material 3 — PixelMusic surface treatment: solid
    // surfaceContainerHigh at 16dp radius, theme-aware text, and the
    // expressive wavy progress line pinned to the bottom edge.
    final settings = GetIt.I<SettingsManager>();
    final liquid = settings.liquidGlass;
    final m3 = settings.isMaterial3; // SP-58
    final cs = Theme.of(context).colorScheme; // SP-58
    final base = widget.color ?? const Color(0xFF202020);
    final dark = Color.lerp(base, Colors.black, 0.45)!;
    final subtitle = '${song.artist ?? song.extras?['subtitle'] ?? ''}';

    return ListenableBuilder(
      listenable: _scale,
      builder: (context, _) => Transform.scale(
        scale: _scale.value,
        child: GestureDetector(
          onTapDown: (_) => _press.forward(),
          onTapUp: (_) => _press.reverse(),
          onTapCancel: () => _press.reverse(),
          onTap: _open,
          onVerticalDragUpdate: (d) {
            if ((d.primaryDelta ?? 0) < -_dragThreshold) _open();
          },
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -300) {
              _next();
            } else if (v > 300) {
              _previous();
            }
          },
          child: Container(
            height: _height,
            decoration: BoxDecoration(
              // SP-58: Material 3 — solid M3 surface, no palette gradient.
              color: m3
                  ? cs.surfaceContainerHigh
                  : liquid
                      ? Colors.white.withValues(alpha: 0.05)
                      : null,
              gradient: (liquid || m3)
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [base, dark],
                    ),
              borderRadius: BorderRadius.circular(
                  m3 ? ZenM3MiniPlayer.radius : _radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: m3 ? 0.14 : (liquid ? 0.18 : 0.3)),
                  blurRadius: m3 ? 10 : (liquid ? 18 : 20),
                  spreadRadius: 0,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  m3 ? ZenM3MiniPlayer.radius : _radius),
              child: Stack(
                children: [
                  Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _slideOnChange(
                      slideKey: song.id,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(_artRadius),
                          child: SongThumbnail(
                            song: song.extras!,
                            dp: MediaQuery.of(context).devicePixelRatio,
                            height: _artSize,
                            width: _artSize,
                            fit: BoxFit.cover,
                            onImageReady: widget.onImageReady,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _slideOnChange(
                        slideKey: 'meta-${song.id}',
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextScroll(
                                song.title,
                                mode: TextScrollMode.bouncing,
                                velocity: const Velocity(
                                    pixelsPerSecond: Offset(30, 0)),
                                delayBefore: const Duration(seconds: 2),
                                pauseBetween: const Duration(seconds: 2),
                                style: TextStyle(
                                  color: m3
                                      ? cs.onSurface
                                      : Colors.white, // SP-58
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: m3
                                        ? cs.onSurfaceVariant
                                        : Colors.white.withValues(alpha: 0.75),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    _buildControls(),
                  ],
                ),
              ),
                  // SP-58: the expressive wavy progress line along the
                  // bottom edge (PixelMusic's collapsed-bar indicator).
                  if (m3)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ValueListenableBuilder<ProgressBarState>(
                        valueListenable: _mp.progressBarState,
                        builder: (context, value, _) {
                          final total = value.total.inMilliseconds;
                          final frac = total <= 0
                              ? 0.0
                              : (value.current.inMilliseconds / total)
                                  .clamp(0.0, 1.0);
                          final playing =
                              _mp.buttonState.value == ButtonState.playing;
                          return ExcludeSemantics(
                            child: ZenM3WavySlider(
                              value: frac,
                              playing: playing,
                              compact: true,
                              height: ZenM3MiniPlayer.progressLineHeight + 5,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final mp = _mp;
    // SP-58: Material 3 — theme-aware control icons.
    final m3 = GetIt.I<SettingsManager>().isMaterial3;
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder<ButtonState>(
          valueListenable: mp.buttonState,
          builder: (context, state, _) => _CircularPlayButton(state: state),
        ),
        StreamBuilder(
          stream: mp.player.sequenceStateStream,
          builder: (context, _) => mp.player.hasNext
              ? Padding(
            padding: const EdgeInsets.only(left: 4),
            child: AdaptiveIconButton(
              onPressed: _next,
              icon: Icon(
                Icons.skip_next_rounded,
                size: 26,
                color: m3
                    ? cs.onSurfaceVariant
                    : Colors.white.withValues(alpha: 0.85),
              ),
            ),
          )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// CIRCULAR PLAY BUTTON — wavy arc ring only: arc = progress, wave
// travels while playing, flattens when paused.
// ═════════════════════════════════════════════

class _CircularPlayButton extends StatefulWidget {
  const _CircularPlayButton({required this.state});

  final ButtonState state;

  @override
  State<_CircularPlayButton> createState() => _CircularPlayButtonState();
}

class _CircularPlayButtonState extends State<_CircularPlayButton>
    with TickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    duration: const Duration(milliseconds: 2000),
    vsync: this,
  );
  late final AnimationController _amp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
    value: 0,
  );

  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _playing = widget.state == ButtonState.playing;
    if (_playing) {
      _phase.repeat();
      _amp.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _CircularPlayButton old) {
    super.didUpdateWidget(old);
    final playing = widget.state == ButtonState.playing;
    if (playing != _playing) {
      _playing = playing;
      if (playing) {
        _phase.repeat();
        _amp.forward();
      } else {
        _amp.reverse();
        _phase.stop();
      }
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    _amp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mp = GetIt.I<MediaPlayer>();
    final isLoading = widget.state == ButtonState.loading;
    final isPlaying = widget.state == ButtonState.playing;
    // SP-58: Material 3 — ring reads the theme instead of fixed white.
    final m3 = GetIt.I<SettingsManager>().isMaterial3;
    final cs = Theme.of(context).colorScheme;
    final ringColor = m3 ? cs.primary : Colors.white;
    final ringTrack = m3
        ? cs.primary.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.18);

    return SizedBox(
      width: 48,
      height: 48,
      child: ValueListenableBuilder<ProgressBarState>(
        valueListenable: mp.progressBarState,
        builder: (context, value, _) {
          final total = value.total.inMilliseconds;
          final progress = total <= 0
              ? 0.0
              : (value.current.inMilliseconds / total).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([_phase, _amp]),
                builder: (context, _) => CustomPaint(
                  size: const Size(48, 48),
                  painter: _WaveRingPainter(
                    phase: _phase.value * 2 * math.pi,
                    sweepAngle: 2 * math.pi * progress,
                    color: ringColor, // SP-58
                    trackColor: ringTrack, // SP-58
                    strokeWidth: 3,
                    amplitude: 1.6 * _amp.value,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: AdaptiveProgressRing(),
                )
              else
                IconButton(
                  // SP-5b: MediaPlayer.togglePlayPause
                  onPressed: () => mp.togglePlayPause(),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WaveRingPainter extends CustomPainter {
  _WaveRingPainter({
    required this.phase,
    required this.sweepAngle,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
    required this.amplitude,
  });

  final double phase;
  final double sweepAngle;
  final Color color;
  final Color trackColor;
  final double strokeWidth;
  final double amplitude;

  static const _waves = 8; // humps around the full circle
  static const _start = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 5;

    // faint full track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth - 1
        ..color = trackColor,
    );

    if (sweepAngle < 0.02) return;

    final steps = math.max(12, (sweepAngle * radius / 1.5).ceil());
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final a = _start + sweepAngle * (i / steps);
      final r = radius + amplitude * math.sin(a * _waves + phase);
      final p = Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_WaveRingPainter old) =>
      old.phase != phase ||
          old.sweepAngle != sweepAngle ||
          old.amplitude != amplitude ||
          old.color != color ||
          old.trackColor != trackColor;
}