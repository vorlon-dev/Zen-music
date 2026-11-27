// ZenMusic · Spatial audio (Android): "6D" and "16D" orbiting-sound effect for headphones.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SpatialAudio {
  SpatialAudio._();
  static final SpatialAudio instance = SpatialAudio._();
  static const MethodChannel _ch = MethodChannel('zen/lossless');

  /// 0 = off, 6 / 8 / 16 / 18 = nD orbit, 100 = Surround (far-away concert hall).
  static const modes = [0, 6, 8, 16, 18, 100];
  final ValueNotifier<int> mode = ValueNotifier(0);

  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> restore() async {
    final v = (Hive.box('SETTINGS').get('SPATIAL_MODE', defaultValue: 0) as num).toInt();
    mode.value = modes.contains(v) ? v : 0;
    await _apply();
  }

  Future<void> setMode(int v) async {
    mode.value = modes.contains(v) ? v : 0;
    await Hive.box('SETTINGS').put('SPATIAL_MODE', mode.value);
    await _apply();
  }

  Future<void> _apply() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('setSpatialAudio', {'mode': mode.value});
    } catch (_) {}
  }
}
