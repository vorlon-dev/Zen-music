// SP-54: Liquid Glass — adaptive glass surface (ZenGlassPanel).
//
// ONE widget, three rendering paths, chosen per platform + device tier:
//
//   Windows (liquid_glass_widgets ^1.15.1)
//     → GlassContainer.card from the package: real shader-based blur,
//       specular highlights, refraction. `adaptiveQuality` (set app-wide
//       in ZenDesktopApp) auto-degrades on weak GPUs / thermal throttle.
//       SP-54.4: the card runs with useOwnLayer + explicit settings (in
//       grouped mode per-widget settings are IGNORED — we silently got the
//       theme defaults: blur 4 + 8% white tint = a dark slab over a dark
//       aurora), our own corner radius, and zero inner padding.
//
//   Android — SP-57: ZERO platform views. Dart frosted glass on mid/high
//     tier (a real BackdropFilter blur over the aurora + the same tint
//     family the Windows shader glass uses), static frost on low tier.
//     The Kotlin platform-view path is kept verbatim below behind
//     kUseNativeGlassAndroid (= false) but is NOT used. Why: the SP-56
//     field logcat showed the 1×1 boot warm-up view itself being torn
//     down at the exact moment the toggle created the first glass panel
//     view — i.e. real devices churn the platform-view set mid-session
//     even with the pipeline primed, and still drop every page plane
//     (blank pages until restart). With no platform view anywhere in the
//     glass path, a Liquid Glass toggle changes NOTHING in the Android
//     compositor, so that bug is structurally impossible.
//
//   Fallback / low tier / liquid widgets disabled
//     → plain translucent frost (one alpha fill + hairline). Zero shaders.
//
// The panel only draws the SURFACE; the caller's `child` is stacked above
// it and keeps every gesture.

import 'dart:io';
import 'dart:ui' show ImageFilter; // SP-57: frosted glass blur

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:zenmusic/desktop/services/settings_manager.dart';

import 'liquid_backdrop.dart' show kZenGlassViewType;
import 'liquid_bridge.dart';

/// SP-54 kill-switch: set false to fall back to the static frost surface if
/// a future liquid_glass_widgets version drifts its API and breaks builds.
const bool kUsePackageGlass = true;

/// SP-57: Android NATIVE (Kotlin platform-view) glass kill-switch.
///
/// false (default) = glass panels render entirely in Dart (frosted glass
/// on mid/high tier, static frost on low tier) and the Android glass path
/// creates ZERO platform views — the Liquid Glass toggle becomes
/// compositor-inert, which kills the "first toggle blanks every page"
/// bug class for good (SP-54.3 backdrop, SP-56 warm-up, SP-57 panels).
///
/// true = resurrect the Kotlin "zen_liquid_glass" surface views below.
/// Only flip this on a future Flutter whose Android platform-view
/// pipeline tolerates mid-session set changes on real devices — and pair
/// it with the SP-56 boot warm-up (see pipeline_warmup.dart history).
const bool kUseNativeGlassAndroid = false;

/// SP-54.4: surface settings matching the package demo look.
///
/// Glass reads as "liquid" only when (a) the blurred backdrop is colourful
/// (see LiquidBackdrop) and (b) the glass BODY is a readable material —
/// tint + rim light. The package's own dark-theme defaults (blur 4, 8%
/// white) are tuned for small chrome over bright content; floating big
/// panels over our dark aurora with them produced the flat dark slab.
LiquidGlassSettings _zenGlassSettings({required bool dark}) {
  return LiquidGlassSettings(
    blur: dark ? 14 : 12,
    glassColor: dark
        ? const Color.fromRGBO(255, 255, 255, 0.10)
        : const Color.fromRGBO(255, 255, 255, 0.24),
    thickness: dark ? 12 : 14,
    lightIntensity: dark ? 1.1 : 0.9,
    ambientStrength: dark ? 0.0 : 0.15,
    lightAngle: 2.356, // 0.75π — upper-left key light (iOS 26 standard)
    refractiveIndex: 1.2,
    saturation: 1.2,
  );
}

class ZenGlassPanel extends StatefulWidget {
  const ZenGlassPanel({
    super.key,
    required this.child,
    this.radius = 20,
    this.margin,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<ZenGlassPanel> createState() => _ZenGlassPanelState();
}

class _ZenGlassPanelState extends State<ZenGlassPanel> {
  ZenGlassTier _tier = ZenGlassTier.unknown;

  @override
  void initState() {
    super.initState();
    _tier = LiquidGlassBridge.instance.tier;
    LiquidGlassBridge.instance.warmUp().then((_) {
      if (mounted && LiquidGlassBridge.instance.tier != _tier) {
        setState(() => _tier = LiquidGlassBridge.instance.tier);
      }
    });
  }

  bool _isDark(BuildContext context) {
    final settings = GetIt.I<SettingsManager>();
    switch (settings.themeMode) {
      case ThemeMode.dark:
        return true;
      case ThemeMode.light:
        return false;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _surface(context);
    if (widget.margin != null) {
      return Padding(padding: widget.margin!, child: body);
    }
    return body;
  }

  Widget _surface(BuildContext context) {
    final dark = _isDark(context);

    // ── Windows: liquid_glass_widgets shader glass ──
    if (Platform.isWindows && kUsePackageGlass) {
      // SP-54.4: useOwnLayer is REQUIRED for `settings` to apply — grouped
      // mode (the default) ignores per-widget settings entirely. Zero card
      // padding (panels manage their own insets) and OUR corner radius
      // (the card preset silently used a 12px superellipse).
      return GlassContainer.card(
        quality: GlassQuality.standard,
        useOwnLayer: true,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: widget.radius),
        settings: _zenGlassSettings(dark: dark),
        child: widget.child,
      );
    }

    // ── Android: Kotlin-rendered glass — RETIRED by SP-57 ──
    // Dead behind kUseNativeGlassAndroid = false; kept verbatim so the
    // native surface can be resurrected with a one-line flip.
    if (Platform.isAndroid &&
        kUseNativeGlassAndroid &&
        (_tier == ZenGlassTier.mid || _tier == ZenGlassTier.high)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Native glass surface (LiquidGlassSurfaceView).
            IgnorePointer(
              child: AndroidView(
                viewType: kZenGlassViewType,
                creationParams: <String, dynamic>{
                  'kind': 'surface',
                  'radius': widget.radius, // SP-54.4: match the Flutter clip
                },
                creationParamsCodec: const StandardMessageCodec(),
              ),
            ),
            // Content keeps every gesture; the glass is decoration below.
            widget.child,
          ],
        ),
      );
    }

    // ── Android mid/high: Dart frosted glass (SP-57 — zero platform views) ──
    if (Platform.isAndroid &&
        (_tier == ZenGlassTier.mid || _tier == ZenGlassTier.high)) {
      // SP-57: pure-Dart glass — a real BackdropFilter blur over the
      // animated aurora, the same tint family as the Windows shader glass
      // (_zenGlassSettings glassColor) and a hairline rim light. Two small
      // panels per screen; the aurora behind repaints at ≤40 fps on mid
      // tier, which is exactly the load the old Kotlin surface view
      // handled. No platform view → no compositor transition → the first
      // Liquid Glass toggle cannot blank the pages any more.
      final double blur = dark ? 14.0 : 12.0; // = _zenGlassSettings blur
      final Color tintTop = dark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.34);
      final Color tintBottom = dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.20);
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tintTop, tintBottom],
              ),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.55),
              ),
            ),
            child: widget.child,
          ),
        ),
      );
    }

    // ── Fallback: static frost (low-tier Android, other platforms) ──
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        color: dark
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.42),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: widget.child,
      ),
    );
  }
}
