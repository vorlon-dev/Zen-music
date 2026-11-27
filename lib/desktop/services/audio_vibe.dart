// ZenMusic · Sound vibes (Android): "Slowed + Reverb" and "Nightcore" one-tap presets.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:zenmusic/desktop/services/media_player.dart';

class AudioVibe {
  AudioVibe._();
  static final AudioVibe instance = AudioVibe._();
  static const MethodChannel _ch = MethodChannel('zen/lossless');

  static const none = 0;
  static const slowed = 1;
  static const nightcore = 2;

  /// 0 = off, 1 = Slowed + Reverb, 2 = Nightcore.
  final ValueNotifier<int> preset = ValueNotifier(none);

  /// Playback speed (pitch follows it, tape-style). 1.0 when off.
  final ValueNotifier<double> speed = ValueNotifier(1.0);

  bool get supported => !kIsWeb && Platform.isAndroid;

  static double defaultSpeed(int p) =>
      p == slowed ? 0.85 : (p == nightcore ? 1.25 : 1.0);
  static (double, double) rangeFor(int p) =>
      p == slowed ? (0.65, 0.95) : (1.05, 1.5);

  Future<void> restore() async {
    final b = Hive.box('SETTINGS');
    final p = (b.get('VIBE_PRESET', defaultValue: 0) as num).toInt();
    preset.value = (p == slowed || p == nightcore) ? p : none;
    speed.value = preset.value == none
        ? 1.0
        : (b.get('VIBE_SPEED', defaultValue: defaultSpeed(preset.value)) as num)
            .toDouble();
    if (preset.value != none) await _apply(retries: 6);
  }

  Future<void> setPreset(int p) async {
    preset.value = (p == slowed || p == nightcore) ? p : none;
    speed.value = defaultSpeed(preset.value);
    final b = Hive.box('SETTINGS');
    await b.put('VIBE_PRESET', preset.value);
    await b.put('VIBE_SPEED', speed.value);
    await _apply();
  }

  Future<void> setSpeed(double v) async {
    if (preset.value == none) return;
    final r = rangeFor(preset.value);
    speed.value = v.clamp(r.$1, r.$2);
    await Hive.box('SETTINGS').put('VIBE_SPEED', speed.value);
    await _apply();
  }

  Future<void> _apply({int retries = 0}) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod(
          'setRoomAmount', {'amount': preset.value == slowed ? 1.0 : 0.0});
    } catch (_) {}
    if (!GetIt.I.isRegistered<MediaPlayer>()) {
      if (retries > 0) {
        Timer(const Duration(seconds: 2), () => _apply(retries: retries - 1));
      }
      return;
    }
    try {
      final p = GetIt.I<MediaPlayer>().player;
      await p.setSpeed(speed.value);
      await p.setPitch(speed.value);
    } catch (_) {}
  }
}
