// ZenMusic Desktop — SP-29: Windows video backdrop (canvas widget).
//
// Renders the muted song video (WindowsBackdropService's media_kit
// texture) as a full-bleed 16:9 canvas layer behind the player UI:
//
//   ┌──────────────────────────────────────┐
//   │  blurred song video (16:9, cover)    │
//   │  + dark scrim gradient               │  ← this file
//   │  ── your existing player UI on top ──│
//   └──────────────────────────────────────┘
//
// HOW TO PLACE IT — player_page.dart gets it at the same z-position as
// the built-in "Synchronized video backdrop" (above the palette
// gradient, below the scrim):
//
//   Stack(
//     children: [
//       AnimatedGradientBackground(...),      // existing
//       const WindowsVideoBackdrop(),         // ← SP-33: here
//       ...everything else the screen has..., // scrim, controls
//     ],
//   )
//
// SP-33 — UNIVERSAL SWITCH: Appearance → "Song backdrop" is now the
// one backdrop button for both platforms (mobile 9:16 canvas flow /
// desktop 16:9 blurred video). This widget listens to
// AppearancePrefs.canvasEnabled LIVE, so the switch hides/shows the
// video instantly. The service's own Hive toggle (Settings → Desktop →
// Video backdrop) stays the engine master switch — the video renders
// only when BOTH are on. Spotify tracks show the built-in Canvas layer
// (this service ignores spotify: ids), YouTube tracks show this layer.
//
// Canvas pipeline: video texture → 16:9 FittedBox cover (never stretched)
// → slight overscan so blur never bleeds dark edges → ImageFiltered blur
// (the "little blur layer") → dark scrim so foreground controls stay
// readable. The whole layer cross-fades in over ~0.7 s on each track.
//
// Tuning: kBackdropBlurSigma / kBackdropScrimTop / kBackdropScrimBottom
// below are the only knobs — everything else is automatic. Windows-only:
// on every other platform this widget renders nothing.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/appearance_prefs.dart';
import 'windows_backdrop_service.dart';

/// "Little blur" — the sigma of the blur layer over the video.
const double kBackdropBlurSigma = 10.0;

/// The video is scaled this slightly-past-full amount so the blur filter
/// never samples transparent pixels at the screen edges (no dark frame).
const double kBackdropOverscan = 1.08;

/// Dark scrim on top of the video so foreground UI stays readable.
const Color kBackdropScrimTop = Color(0x51000000); // ~32% black
const Color kBackdropScrimBottom = Color(0xA3000000); // ~64% black

class WindowsVideoBackdrop extends StatelessWidget {
  const WindowsVideoBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final WindowsBackdropService service = WindowsBackdropService.instance;
    if (!service.isSupported) return const SizedBox.shrink();

    // SP-33: universal switch gate (live — the appearance switch toggles
    // this layer instantly, no restart needed).
    return ValueListenableBuilder<bool>(
      valueListenable: AppearancePrefs.canvasEnabled,
      builder: (BuildContext context, bool canvasOn, Widget? _) {
        if (!canvasOn) {
          return const Positioned.fill(child: SizedBox.shrink());
        }
        return ValueListenableBuilder<WindowsBackdropState>(
          valueListenable: service.state,
          builder: (BuildContext context, WindowsBackdropState state,
              Widget? _) {
            final VideoController? controller = service.videoController;
            if (state != WindowsBackdropState.active || controller == null) {
              return const Positioned.fill(child: SizedBox.shrink());
            }

            return Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOut,
                builder: (BuildContext context, double t, Widget? child) =>
                    Opacity(opacity: t, child: child),
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      // 1. The muted video, 16:9 cover-filled, slightly
                      //    blurred ("little blur layer" — the point is a
                      //    soft living backdrop, not a watchable video).
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: kBackdropBlurSigma,
                          sigmaY: kBackdropBlurSigma,
                        ),
                        child: Transform.scale(
                          scale: kBackdropOverscan,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: 16,
                              height: 9,
                              child: Video(
                                controller: controller,
                                wakelock: false,
                                filterQuality: FilterQuality.low,
                                controls: NoVideoControls,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 2. Scrim — keeps the player UI readable on bright
                      //    video scenes.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              kBackdropScrimTop,
                              kBackdropScrimBottom,
                            ],
                          ),
                        ),
                      ),
                    ],
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
