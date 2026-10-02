import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Connected Bluetooth audio output, pushed live from native
/// (zen/audio_device EventChannel — BroadcastReceiver +
/// AudioDeviceCallback in MainActivity). [deviceName] is null when no
/// Bluetooth output is active.
///
/// The buds/speaker heuristics are direct ports of the reference
/// echomusic helpers (keyword matching on the product name).
class AudioDeviceService {
  AudioDeviceService._();

  static final AudioDeviceService instance = AudioDeviceService._();

  static const _channel = EventChannel('zen/audio_device');

  /// Connected Bluetooth device name (null = none).
  final deviceName = ValueNotifier<String?>(null);

  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  /// Starts the native event stream. Safe to call repeatedly; the
  /// listener stays registered for the app's lifetime (one receiver,
  /// negligible cost) so the row is always current when the player
  /// opens.
  void start() {
    if (_started) return;
    _started = true;
    _sub = _channel.receiveBroadcastStream().listen(
          (v) {
        deviceName.value = v is String ? v : null;
      },
      onError: (_) {
        // Channel errors (e.g., activity teardown) must never crash.
      },
    );
  }

  // ── Product-name heuristics (verbatim port) ──

  static bool isBuds(String? name) {
    if (name == null) return false;
    final lowerName = name.toLowerCase();
    return lowerName.contains('buds') ||
        lowerName.contains('airpods') ||
        lowerName.contains('earpods') ||
        lowerName.contains('earphone') ||
        lowerName.contains('freebuds') ||
        lowerName.contains('pods');
  }

  static bool isSpeaker(String? name) {
    if (name == null) return false;
    final lowerName = name.toLowerCase();
    return lowerName.contains('speaker') ||
        lowerName.contains('soundbar') ||
        lowerName.contains('homepod') ||
        lowerName.contains('echo') ||
        lowerName.contains('boombox') ||
        lowerName.contains('audio system') ||
        lowerName.contains('sound') ||
        lowerName.contains('audio') ||
        lowerName.contains('stereo') ||
        lowerName.contains('music') ||
        lowerName.contains('box') ||
        lowerName.contains('party') ||
        lowerName.contains('waves');
  }
}