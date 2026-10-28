// SP-54: Liquid Glass — Dart ⇄ Kotlin bridge.
//
// Android renders the liquid glass layer NATIVELY in Kotlin
// (com.zen.music.zenmusic.liquid). This file is the only contact point:
//   • `sync()` pushes the current theme state (on/off, dark, accent) to
//     ZenLiquidGlassEngine over the `zenmusic/liquid_glass` channel.
//   • `tier` exposes the Kotlin-computed device tier (low / mid / high)
//     so Dart-side widgets can degrade gracefully on low-end phones.
//
// On Windows/desktop everything here is a cheap no-op — the desktop glass
// path is pure Flutter (liquid_glass_widgets), no platform channel traffic.

import 'dart:io';

import 'package:flutter/services.dart';

/// Rendering tier reported by the Kotlin engine (or synthesised on desktop).
enum ZenGlassTier { unknown, low, mid, high, desktop }

class LiquidGlassBridge {
  LiquidGlassBridge._();

  static final LiquidGlassBridge instance = LiquidGlassBridge._();

  static const MethodChannel _channel = MethodChannel('zenmusic/liquid_glass');

  ZenGlassTier _tier = ZenGlassTier.unknown;
  bool _warmedUp = false;

  /// Last known device tier. `unknown` until [warmUp] completes on Android.
  ZenGlassTier get tier => _tier;

  /// True when the native (Kotlin) glass layer is available.
  bool get nativeGlassAvailable =>
      Platform.isAndroid &&
      (_tier == ZenGlassTier.mid || _tier == ZenGlassTier.high);

  /// Ask the Kotlin engine for the device profile. Safe to call anywhere:
  /// on desktop it just resolves to [ZenGlassTier.desktop] without any
  /// channel traffic. Called once from ZenDesktopApp's first build.
  Future<void> warmUp() async {
    if (_warmedUp) return;
    _warmedUp = true;
    if (!Platform.isAndroid) {
      _tier = ZenGlassTier.desktop;
      return;
    }
    try {
      final profile =
          await _channel.invokeMapMethod<String, dynamic>('getProfile');
      _tier = _tierFromName(profile?['tier'] as String?);
    } on PlatformException catch (_) {
      _tier = ZenGlassTier.low;
    } on MissingPluginException catch (_) {
      _tier = ZenGlassTier.low;
    }
  }

  /// Push the current liquid-glass state to the Kotlin engine. Idempotent
  /// and cheap; called from ZenDesktopApp's build and from the
  /// SettingsManager setter. No-op on desktop.
  Future<void> sync({
    required bool enabled,
    required bool dark,
    int? accent,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setTheme', <String, dynamic>{
        'enabled': enabled,
        'dark': dark,
        if (accent != null) 'accent': accent,
      });
    } on PlatformException catch (_) {
      // Older APK without the Kotlin module — glass falls back gracefully.
    } on MissingPluginException catch (_) {
      // Same — native side not registered (should not happen post SP-54).
    }
  }

  static ZenGlassTier _tierFromName(String? name) {
    switch (name) {
      case 'low':
        return ZenGlassTier.low;
      case 'high':
        return ZenGlassTier.high;
      case 'mid':
      case 'medium':
        return ZenGlassTier.mid;
      default:
        return ZenGlassTier.low;
    }
  }
}
