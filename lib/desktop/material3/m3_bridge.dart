// SP-58: Material 3 token bridge.
//
// On Android the M3 design tokens live NATIVELY — declared in
// android/app/src/main/res/values/material3_tokens.xml and served by
// Material3Tokens.kt over the `zen/material3_tokens` channel. Dart pulls
// them once at boot so a native-side palette tweak (XML edit + Gradle
// rebuild) re-skins the theme without touching Dart. Everything is
// failure-soft: if the channel is missing (Windows, or an APK built
// before SP-58) the Dart fallbacks in m3_palette.dart are used — they
// are the same values.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MethodChannel shared with Material3Tokens.kt.
const MethodChannel kZenM3Channel =
    MethodChannel('zen/material3_tokens');

/// Resolved native tokens (null = use the Dart defaults in m3_palette).
Map<String, int>? _nativeColors;

/// Fire-and-forget boot fetch. Never throws.
Future<void> loadM3Tokens() async {
  if (!Platform.isAndroid) return;
  try {
    final raw = await kZenM3Channel
        .invokeMethod<Map<dynamic, dynamic>>('getTokens');
    if (raw == null || raw.isEmpty) return;
    final parsed = <String, int>{};
    raw.forEach((key, value) {
      if (key is String && value is int) parsed[key] = value;
    });
    if (parsed.isNotEmpty) _nativeColors = parsed;
  } catch (_) {
    // Failure-soft: Dart palette stays authoritative.
  }
}

/// Native override for [name] (e.g. 'dark_primary') or null.
int? m3NativeColor(String name) => _nativeColors?[name];
