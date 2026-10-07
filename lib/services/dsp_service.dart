import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Bridge to the dsp-core Kotlin module (pure-JVM library).
///
/// Channel contract (zen/dsp, LIVE):
/// - available           → bool
/// - parsePresetText     {text} → {preamp, bands, metadata} | null
/// - validatePreset      {preamp, bands} → [String errors]
/// - magnitudeResponseDb {bands, preamp, points, minHz, maxHz}
///     → [double dB] over the log grid
///       f(i) = minHz * (maxHz/minHz)^(i / (points - 1))
/// - responseAtFrequencies {bands, preamp, frequencies} → [double dB]
///
/// AUDIO NOTE: this service computes NUMBERS (parse, validate,
/// curves). It does not filter playback. Applying a profile to the
/// system equalizer (approximation) lives in the equalizer screen;
/// true per-sample parametric filtering is the audio-pipeline round.
class DspService {
  DspService._();
  static final DspService instance = DspService._();

  static const _channel = MethodChannel('zen/dsp');

  /// Native handler registered in MainActivity (Round A2).
  bool get _isNativeWired => true;

  Future<bool> get available async {
    if (!_isNativeWired) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// AutoEq-style text → preset. Null when the text fails to parse.
  Future<DspPreset?> parsePresetText(String text) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('parsePresetText', {
        'text': text,
      });
      if (raw == null) return null;
      return DspPreset.fromMap(Map<String, dynamic>.from(raw));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Range violations (preamp, band count, per-band limits). Empty
  /// list = valid.
  Future<List<String>> validatePreset(DspPreset preset) async {
    try {
      final raw = await _channel
          .invokeMethod<List<dynamic>>('validatePreset', preset.toMap());
      return raw?.map((e) => e.toString()).toList() ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Magnitude response in dB over the log-spaced grid (see contract).
  Future<List<double>?> magnitudeResponseDb({
    required List<DspBand> bands,
    required double preamp,
    int points = 128,
    double minHz = 20,
    double maxHz = 20000,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'magnitudeResponseDb', {
        'bands': [for (final b in bands) b.toMap()],
        'preamp': preamp,
        'points': points,
        'minHz': minHz,
        'maxHz': maxHz,
      });
      return raw?.map((e) => (e as num).toDouble()).toList();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Response in dB at exact frequencies — used to project a
  /// parametric profile onto the system equalizer's band centers.
  Future<List<double>?> responseAtFrequencies({
    required List<DspBand> bands,
    required double preamp,
    required List<double> frequencies,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'responseAtFrequencies', {
        'bands': [for (final b in bands) b.toMap()],
        'preamp': preamp,
        'frequencies': frequencies,
      });
      return raw?.map((e) => (e as num).toDouble()).toList();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// The log-spaced frequency grid Dart plots against — MUST mirror
  /// the native grid exactly (f(i) = minHz · (max/min)^(i/(n-1))).
  /// Real math.pow: fractional exponents are the entire point of a
  /// log grid (a hand-rolled integer loop was wrong here once).
  static List<double> frequencyGrid(int points, double minHz, double maxHz) {
    if (points < 2) return [minHz];
    final ratio = maxHz / minHz;
    return List<double>.generate(points, (i) {
      final t = i / (points - 1);
      return (minHz * math.pow(ratio, t)).toDouble();
    });
  }
}

class DspBand {
  const DspBand({
    required this.filterType,
    required this.frequency,
    required this.gain,
    required this.q,
    this.enabled = true,
  });

  final String filterType; // PK | LSC | HSC | LPQ | HPQ
  final double frequency;
  final double gain;
  final double q;
  final bool enabled;

  Map<String, dynamic> toMap() => {
    'filterType': filterType,
    'frequency': frequency,
    'gain': gain,
    'q': q,
    'enabled': enabled,
  };

  static DspBand fromMap(Map<String, dynamic> m) => DspBand(
    filterType: (m['filterType'] ?? 'PK').toString(),
    frequency: (m['frequency'] as num?)?.toDouble() ?? 0,
    gain: (m['gain'] as num?)?.toDouble() ?? 0,
    q: (m['q'] as num?)?.toDouble() ?? 1.41,
    enabled: (m['enabled'] as bool?) ?? true,
  );
}

class DspPreset {
  const DspPreset({
    required this.preamp,
    required this.bands,
    this.metadata = const {},
  });

  final double preamp;
  final List<DspBand> bands;
  final Map<String, String> metadata;

  Map<String, dynamic> toMap() => {
    'preamp': preamp,
    'bands': [for (final b in bands) b.toMap()],
    'metadata': metadata,
  };

  static DspPreset fromMap(Map<String, dynamic> m) => DspPreset(
    preamp: (m['preamp'] as num?)?.toDouble() ?? 0,
    bands: ((m['bands'] as List?) ?? const [])
        .map((e) => DspBand.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    metadata: Map<String, String>.from((m['metadata'] as Map?) ?? const {}),
  );
}

/// A saved parametric EQ profile (Dart-persisted mirror of the
/// module's SavedEQProfile). Storage lives in storage_service under
/// the 'eq_profiles' box.
class EqProfile {
  const EqProfile({
    required this.id,
    required this.name,
    required this.preamp,
    required this.bands,
    this.isCustom = true,
    this.isActive = false,
    this.addedTimestamp = 0,
  });

  final String id;
  final String name;
  final double preamp;
  final List<DspBand> bands;
  final bool isCustom;
  final bool isActive;
  final int addedTimestamp;

  DspPreset get preset => DspPreset(preamp: preamp, bands: bands);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'preamp': preamp,
    'bands': [for (final b in bands) b.toMap()],
    'isCustom': isCustom,
    'isActive': isActive,
    'addedTimestamp': addedTimestamp,
  };

  factory EqProfile.fromJson(Map<String, dynamic> m, {String? fallbackId}) =>
      EqProfile(
        id: (m['id'] ?? fallbackId ?? '').toString(),
        name: (m['name'] ?? 'Preset').toString(),
        preamp: (m['preamp'] as num?)?.toDouble() ?? 0,
        bands: ((m['bands'] as List?) ?? const [])
            .map((e) => DspBand.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        isCustom: (m['isCustom'] as bool?) ?? true,
        isActive: (m['isActive'] as bool?) ?? false,
        addedTimestamp: (m['addedTimestamp'] as num?)?.toInt() ?? 0,
      );

  static String newId() => 'eqp_${DateTime.now().millisecondsSinceEpoch}';
}