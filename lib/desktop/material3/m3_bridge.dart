// ZenMusic · vorlon-dev

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
