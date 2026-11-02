// ZenMusic · vorlon-dev

import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:zenmusic/desktop/services/settings_manager.dart';

import 'liquid_backdrop.dart' show kZenGlassViewType;
import 'liquid_bridge.dart';

const bool kUsePackageGlass = true;

const bool kUseNativeGlassAndroid = false;

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

    if (Platform.isWindows && kUsePackageGlass) {
      return GlassContainer.card(
        quality: GlassQuality.standard,
        useOwnLayer: true,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: widget.radius),
        settings: _zenGlassSettings(dark: dark),
        child: widget.child,
      );
    }

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
                  'radius': widget.radius,
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

    if (Platform.isAndroid &&
        (_tier == ZenGlassTier.mid || _tier == ZenGlassTier.high)) {
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
