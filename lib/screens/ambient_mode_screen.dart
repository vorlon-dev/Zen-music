import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
// VOLUME: requires `flutter pub add volume_controller`.
// Delete these 3 marked spots to make the vertical drag inert.
import 'package:volume_controller/volume_controller.dart';
// WAKELOCK: requires `flutter pub add wakelock_plus`.
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../services/appearance_prefs.dart';
import '../widgets/lyrics_view.dart';

/// Ambient Mode — Echo Nightly port. Landscape, immersive, palette-
/// extracted animated glow background. Left: album art (double-tap
/// toggles playback) with optional title/artist. Right: lyrics.
/// Horizontal swipe skips, vertical drag adjusts volume.
class AmbientModeScreen extends StatefulWidget {
  const AmbientModeScreen({super.key});

  @override
  State<AmbientModeScreen> createState() => _AmbientModeScreenState();
}

class _AmbientModeScreenState extends State<AmbientModeScreen> {
  // VOLUME
  final _volumeController = VolumeController.instance;

  @override
  void initState() {
    super.initState();
    AppearancePrefs.load();
    // Landscape + immersive + keep screen on for the session.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    // Restore the app's normal portrait / edge-to-edge state.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    super.dispose();
  }

  void _togglePlayPause() {
    final playing = audioHandler.playbackState.value.playing;
    playing ? audioHandler.pause() : audioHandler.play();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final dx = d.delta.dx;
    final dy = d.delta.dy;

    // Vertical drag → volume (Echo's AudioManager logic).
    if (dy.abs() > 10 && dy.abs() > dx.abs()) {
      // VOLUME
      _stepVolume(dy < 0);
    }
  }

  // VOLUME
  Future<void> _stepVolume(bool up) async {
    try {
      final v = await _volumeController.getVolume() ?? 0.5;
      final next = (v + (up ? 0.05 : -0.05)).clamp(0.0, 1.0);
      await _volumeController.setVolume(next);
    } catch (_) {}
  }

  void _onPanEnd(DragEndDetails d, double dx, double dy) {
    // Horizontal swipe → skip (Echo: >150px and predominantly horizontal).
    if (dx.abs() > 150 && dx.abs() > dy.abs()) {
      if (dx > 0) {
        audioHandler.skipToPrevious();
      } else {
        audioHandler.skipToNext();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = audioHandler.currentSong;
    final artScale = AppearancePrefs.ambientArtScale.value;
    final showTitle = AppearancePrefs.ambientShowTitle.value;
    final showArtist = AppearancePrefs.ambientShowArtist.value;
    final showLyrics = AppearancePrefs.ambientShowLyrics.value;

    final double dragX = 0;
    final double dragY = 0;

    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (d) =>
            _onPanEnd(d, dragX, dragY), // accumulators handled below
        child: Stack(
          fit: StackFit.expand,
          children: [
            AmbientGlowBackground(
              key: ValueKey(song?.id ?? 'none'),
              imageUrl: song?.thumbnail ?? '',
            ),
            Row(
              children: [
                // ── Left: album art + optional text ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FractionallySizedBox(
                            widthFactor: artScale,
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: GestureDetector(
                                onDoubleTap: _togglePlayPause,
                                child: ClipRRect(
                                  borderRadius:
                                  BorderRadius.circular(16),
                                  child: song != null &&
                                      song.thumbnail.isNotEmpty
                                      ? Image.network(
                                    song.thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                    const ColoredBox(
                                        color: Color(0xFF151617)),
                                  )
                                      : const ColoredBox(
                                    color: Color(0xFF151617),
                                    child: Icon(
                                        Icons.music_note_rounded,
                                        size: 64,
                                        color: Colors.white24),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showTitle || showArtist) ...[
                            const SizedBox(height: 16),
                            if (showTitle)
                              Text(song?.title ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            if (showArtist)
                              Text(song?.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 15,
                                      color:
                                      Colors.white.withOpacity(0.7))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // ── Right: lyrics ──
                if (showLyrics && song != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                          16, 32, 32, 32),
                      child: LyricsView(
                        songId: song.id,
                        title: song.title,
                        artist: song.artist,
                        imageUrl: song.thumbnail,
                        duration: song.duration,
                        positionStream: audioHandler.positionStream,
                      ),
                    ),
                  ),
              ],
            ),
            // ── Back button overlay ──
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// AMBIENT GLOW BACKGROUND — Echo AmbientGlowBackground port.
// Palette colors extracted from the artwork (vibrant / light /
// dark vibrant / muted variants), six radial glows whose centers,
// radii and hues oscillate over a 20s loop. Crossfades on song
// change.
// ═════════════════════════════════════════════

class AmbientGlowBackground extends StatefulWidget {
  final String imageUrl;
  const AmbientGlowBackground({
    super.key,
    required this.imageUrl,
  });

  @override
  State<AmbientGlowBackground> createState() => _AmbientGlowBackgroundState();
}

class _AmbientGlowBackgroundState extends State<AmbientGlowBackground>
    with SingleTickerProviderStateMixin {
  List<Color> _colors = const [];
  bool _loading = false;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20), // Echo's 20s loop
  )..repeat();

  @override
  void didUpdateWidget(covariant AmbientGlowBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _extract();
    }
  }

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    final url = widget.imageUrl;
    if (url.isEmpty) {
      if (mounted) setState(() => _colors = const []);
      return;
    }
    setState(() => _loading = true);
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(100, 100),
        maximumColorCount: 8,
      );
      const fallback = Color(0xFF444444);
      final colors = <Color>[];
      for (final c in [
        palette.vibrantColor?.color,
        palette.lightVibrantColor?.color,
        palette.darkVibrantColor?.color,
        palette.mutedColor?.color,
        palette.lightMutedColor?.color,
        palette.darkMutedColor?.color,
      ]) {
        if (c != null && !colors.contains(c)) colors.add(c);
      }
      if (!mounted) return;
      setState(() {
        _colors = colors.isEmpty ? const [fallback] : colors;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _colors = const [Color(0xFF444444)];
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Echo: 1200ms crossfade when the palette changes (song switch).
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 1200),
      child: _colors.isEmpty
          ? const ColoredBox(color: Color(0xFF050505))
          : AnimatedBuilder(
        key: ValueKey(_colors.hashCode),
        animation: _progress,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _GlowPainter(
            colors: _colors,
            progress: _progress.value,
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  final List<Color> colors;
  final double progress; // 0..1 over the 20s loop

  _GlowPainter({required this.colors, required this.progress});

  // Echo's rotatedColorAt: continuous hue rotation across the palette.
  Color _rotatedAt(int index) {
    final size = colors.length;
    final idx = index + progress * size;
    final a = idx.floor() % size;
    final b = (a + 1) % size;
    final frac = idx - idx.floor();
    return Color.lerp(colors[a], colors[b], frac) ?? colors[a];
  }

  // Echo's oscillate: smooth min↔max sweep driven by the loop phase.
  double _oscillate(double min, double max, double phase) {
    final v = math.sin(2 * math.pi * (progress + phase));
    return min + (max - min) * ((v + 1) / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Echo's exact phase table for the six glows.
    final c = [
      _rotatedAt(0), _rotatedAt(1), _rotatedAt(2),
      _rotatedAt(3), _rotatedAt(4), _rotatedAt(5),
    ];
    final alphas = [0.85, 0.80, 0.75, 0.70, 0.65, 0.60];
    final ox = [
      _oscillate(0.0, 1.0, 0.00),
      _oscillate(1.0, 0.0, 0.20),
      _oscillate(0.2, 0.8, 0.33),
      _oscillate(0.3, 0.7, 0.44),
      _oscillate(0.4, 0.6, 0.55),
      _oscillate(0.0, 1.0, 0.66),
    ];
    final oy = [
      _oscillate(0.0, 0.5, 0.07),
      _oscillate(0.5, 1.0, 0.25),
      _oscillate(0.8, 0.2, 0.36),
      _oscillate(0.2, 0.8, 0.41),
      _oscillate(0.0, 1.0, 0.51),
      _oscillate(0.5, 0.7, 0.62),
    ];
    final rr = [
      _oscillate(0.8, 1.6, 0.12),
      _oscillate(0.7, 1.5, 0.18),
      _oscillate(0.6, 1.4, 0.29),
      _oscillate(0.9, 1.7, 0.47),
      _oscillate(0.7, 1.5, 0.58),
      _oscillate(0.8, 1.8, 0.69),
    ];

    // Base near-black, like Echo's Color(0xFF050505).
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050505));

    for (var i = 0; i < 6; i++) {
      final color = c[i];
      final brush = Paint()
        ..shader = uiGrad(
            color, alphas[i], Offset(w * ox[i], h * oy[i]), w * rr[i]);
      canvas.drawRect(Offset.zero & size, brush);
    }
  }

  Shader uiGrad(Color color, double alpha, Offset center, double radius) {
    return RadialGradient(
      colors: [
        color.withOpacity(alpha),
        color.withOpacity(alpha * 0.6),
        color.withOpacity(0.0),
      ],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.progress != progress || old.colors != colors;
}