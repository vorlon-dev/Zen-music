// ZenMusic · vorlon-dev
//
// Dart side of the native 15-band equalizer (the `zen/lossless` channel).
//
// The band layout (15 ISO centre frequencies, 25 Hz to 16 kHz), the +-8 dB
// range and the preset curves below follow LastWave
// (https://github.com/Clash-Projects/LastWave-Native, GPL-3.0).

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// A named set of per-band gains in dB, index-aligned with
/// [NativeEqualizer.bandFreqsHz].
class EqPreset {
  const EqPreset(this.name, this.gains);

  final String name;
  final List<double> gains;
}

/// Controls the native equalizer and remembers its settings.
///
/// The native layer keeps the last equalizer state globally, so players that
/// are created later pick it up automatically; [restore] only has to run once
/// at startup.
class NativeEqualizer {
  NativeEqualizer._();

  static final NativeEqualizer instance = NativeEqualizer._();

  static const MethodChannel _channel = MethodChannel('zen/lossless');

  static const int bandCount = 15;
  static const double maxGainDb = 8.0;
  static const String customName = 'Custom';

  static const List<int> bandFreqsHz = <int>[
    25, 40, 63, 100, 160, 250, 400, 630, //
    1000, 1600, 2500, 4000, 6300, 10000, 16000,
  ];

  static const EqPreset flat = EqPreset(
    'Default',
    <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  );

  static const List<EqPreset> presets = <EqPreset>[
    flat,
    EqPreset('Studio Master', <double>[
      2.6, 2.8, 2.2, 0.6, -1.8, -2.6, -1.2, 0.0, //
      1.2, 2.4, 3.6, 4.0, 4.2, 4.5, 4.8,
    ]),
    EqPreset('Acoustic', <double>[
      3.0, 2.5, 2.0, 1.5, 0.5, 1.0, 1.5, 2.0, //
      2.0, 1.5, 1.0, 1.0, 1.0, 1.5, 1.5,
    ]),
    EqPreset('Vocal Clarity', <double>[
      -1.5, -1.0, -0.5, 0, 0.5, 1.0, 2.0, 3.0, //
      3.5, 3.0, 2.5, 2.0, 1.5, 1.5, 1.0,
    ]),
    EqPreset('Classical', <double>[
      3.0, 2.5, 2.0, 1.5, 0.5, 0, 0, 0, //
      0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.0,
    ]),
    EqPreset('Jazz', <double>[
      2.5, 2.0, 1.5, 1.0, 0, -0.5, 0, 0.5, //
      1.0, 1.5, 2.0, 2.0, 2.5, 2.5, 2.5,
    ]),
    EqPreset('Rock', <double>[
      4.0, 3.5, 3.0, 1.5, 0, -1.0, -1.0, -0.5, //
      0.5, 1.5, 2.5, 3.0, 3.5, 4.0, 4.0,
    ]),
    EqPreset('Pop', <double>[
      -1.0, -0.5, 0.0, 1.0, 1.5, 2.0, 2.0, 1.5, //
      1.0, 0.5, 0.5, 1.0, 1.5, 2.0, 2.5,
    ]),
    EqPreset('Treble Air', <double>[
      0, 0, 0, -0.5, -0.5, -0.5, 0, 0.5, //
      1.0, 1.5, 2.0, 3.0, 3.5, 4.5, 5.0,
    ]),
    EqPreset('Deep Bass Clean', <double>[
      5.0, 4.5, 3.5, 2.5, 1.0, 0, -0.5, -0.5, //
      0, 0, 0, 0, 0.5, 0.5, 0.5,
    ]),
    EqPreset('Electronic', <double>[
      4.5, 4.0, 3.0, 2.0, 0.5, -0.5, 0, 1.0, //
      2.0, 2.5, 2.5, 2.5, 3.0, 3.5, 4.0,
    ]),
    EqPreset('R&B', <double>[
      5.0, 4.5, 3.5, 2.0, 1.0, -0.5, -1.0, -0.5, //
      0.5, 1.5, 2.0, 2.5, 3.0, 3.0, 3.0,
    ]),
  ];

  static const String _kEnabled = 'NEQ_ENABLED';
  static const String _kPreset = 'NEQ_PRESET';
  static const String _kGains = 'NEQ_GAINS';

  /// Short label under a band slider: `63`, `1K`, `1.6K`, `16K`.
  static String bandLabel(int hz) {
    if (hz < 1000) return '$hz';
    if (hz % 1000 == 0) return '${hz ~/ 1000}K';
    return '${(hz / 1000).toStringAsFixed(1)}K';
  }

  static EqPreset? presetByName(String name) {
    for (final p in presets) {
      if (p.name == name) return p;
    }
    return null;
  }

  bool? _available;

  /// Whether the native equalizer exists on this device (Android build with
  /// the native audio library loaded).
  Future<bool> isAvailable() async {
    final cached = _available;
    if (cached != null) return cached;
    if (!Platform.isAndroid) return _available = false;
    try {
      _available = (await _channel.invokeMethod<bool>('available')) ?? false;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  Box? get _box {
    try {
      return Hive.box('SETTINGS');
    } catch (_) {
      return null;
    }
  }

  bool get enabled => _box?.get(_kEnabled, defaultValue: false) == true;

  String get presetName {
    final name = _box?.get(_kPreset);
    if (name is String && (name == customName || presetByName(name) != null)) {
      return name;
    }
    return flat.name;
  }

  /// Saved per-band gains (dB), always [bandCount] long and within range.
  List<double> get gains {
    final stored = _box?.get(_kGains);
    if (stored is List && stored.length == bandCount) {
      return <double>[
        for (final g in stored) _clamp((g as num?)?.toDouble() ?? 0.0),
      ];
    }
    final preset = presetByName(presetName) ?? flat;
    return List<double>.of(preset.gains);
  }

  static double _clamp(double v) =>
      v.isFinite ? v.clamp(-maxGainDb, maxGainDb).toDouble() : 0.0;

  Future<void> setEnabled(bool value) async {
    await _box?.put(_kEnabled, value);
    await apply();
  }

  Future<void> applyPreset(EqPreset preset) async {
    final box = _box;
    await box?.put(_kPreset, preset.name);
    await box?.put(_kGains, List<double>.of(preset.gains));
    await box?.put(_kEnabled, true);
    await apply();
  }

  /// Changes one band. Pass `persist: false` while a slider is being dragged
  /// and persist once when the drag ends.
  Future<void> setBandGain(
    int index,
    double gain, {
    bool persist = true,
  }) async {
    if (index < 0 || index >= bandCount) return;
    final next = gains;
    next[index] = _clamp(gain);
    final box = _box;
    if (persist) {
      await box?.put(_kGains, next);
      await box?.put(_kPreset, customName);
      await box?.put(_kEnabled, true);
    }
    await _send(true, next);
  }

  Future<void> reset() => applyPreset(flat);

  /// Pushes the saved state to the native engine.
  Future<void> apply() => _send(enabled, gains);

  /// Call once at startup.
  Future<void> restore() async {
    if (!await isAvailable()) return;
    await apply();
  }

  Future<void> _send(bool isEnabled, List<double> values) async {
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod<void>('setEqualizer', <String, dynamic>{
        'enabled': isEnabled,
        'gains': values,
      });
    } catch (_) {
      // The native engine may be unavailable; stay silent, audio is unchanged.
    }
  }
}
