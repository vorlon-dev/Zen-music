// ZenMusic · vorlon-dev

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid_backdrop.dart' show kZenGlassViewType;
import 'liquid_bridge.dart';

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
