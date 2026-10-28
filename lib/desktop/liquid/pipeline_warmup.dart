// SP-56: Liquid Glass — Android compositor pipeline warm-up.
//
// THE BUG THIS FIXES
//   First time the user flips Liquid Glass ON (app already running), the
//   glass nav bar + mini player mount the session's FIRST platform views
//   mid-frame, mid-session, while the whole app is simultaneously
//   re-theming. On real devices that 0 → N platform-view compositor
//   transition is fragile (the same plane-drop family SP-54.3 removed the
//   fullscreen backdrop PV for): the aurora and the glass bar composite,
//   but every PAGE plane is dropped — blank pages until the app restarts.
//   Restarting with glass ON works because the platform views are then
//   born during the boot frames, where the compositor switches modes
//   cleanly (the user's "close and reopen = perfect" screenshot).
//
// THE FIX
//   Prime the pipeline at BOOT instead: a 1×1 logical-px glass-surface
//   platform view (the same proven "zen_liquid_glass" kind:"surface" view,
//   LiquidGlassSurfaceView) is mounted underneath the app root the moment
//   the device tier resolves to mid/high — regardless of the liquid glass
//   flag. It lives at the very bottom of the root Stack, is fully covered
//   by the opaque backdrop above it, ignores every pointer, and the
//   Kotlin view is a STATIC gradient painter (no animator), so the
//   running cost is one ~3×3 real-pixel view that only repaints on theme
//   revision bumps — effectively zero.
//
//   With the pipeline primed, the later toggle adds platform views AFTER
//   one already exists (1 → 3), which is the routine case in production
//   apps (ads, video, maps) — no mode switch, no plane drop.
//
//   On low-tier devices nothing mounts at all: the frost fallback never
//   creates platform views either, so there is no 0 → N transition to
//   protect against.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid_backdrop.dart' show kZenGlassViewType;
import 'liquid_bridge.dart';

// SP-56: prime the Android platform-view pipeline at boot (see header).
class ZenGlassPipelineWarmup extends StatefulWidget {
  const ZenGlassPipelineWarmup({super.key});

  @override
  State<ZenGlassPipelineWarmup> createState() =>
      _ZenGlassPipelineWarmupState();
}

class _ZenGlassPipelineWarmupState extends State<ZenGlassPipelineWarmup> {
  bool _primed = false;

  @override
  void initState() {
    super.initState();
    // Idempotent: ZenDesktopApp.build already kicks warmUp() off; this is
    // the same singleton call, so it completes instantly if the tier is
    // already known and otherwise rides the same round-trip. Either way
    // the 1×1 platform view lands within the first frames of boot.
    LiquidGlassBridge.instance.warmUp().then((_) {
      if (!mounted) return;
      final tier = LiquidGlassBridge.instance.tier;
      if (tier == ZenGlassTier.mid || tier == ZenGlassTier.high) {
        setState(() => _primed = true);
      }
      // low tier: never prime — that path has no platform views at all.
    });
  }

  @override
  Widget build(BuildContext context) {
    // Belt and braces: the call site already only mounts this on Android.
    if (!Platform.isAndroid || !_primed) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      // 1×1 logical px — sized by the Positioned in ZenDesktopApp's builder.
      // 'kind': 'surface' + radius 0 → LiquidGlassSurfaceView paints its
      // static gradient into one pixel, hidden under the opaque backdrop.
      child: AndroidView(
        viewType: kZenGlassViewType,
        creationParams: <String, dynamic>{
          'kind': 'surface',
          'radius': 0.0,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
