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
