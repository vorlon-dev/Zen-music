import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One audio output device (from the native enumerator).
class AudioOutputDevice {
  const AudioOutputDevice({
    required this.name,
    required this.type,
    this.battery,
    this.id,
  });

  final String name;
  // bluetooth | wired | usb | hdmi | speaker
  final String type;
  final int? battery;
  final int? id;

  static AudioOutputDevice fromMap(Map<Object?, Object?> m) =>
      AudioOutputDevice(
        name: m['name']?.toString() ?? 'Audio device',
        type: m['type']?.toString() ?? 'speaker',
        battery: m['battery'] is int ? m['battery'] as int : null,
        id: m['id'] is int ? m['id'] as int : null,
      );
}

/// Audio output enumeration + system volume control, backed by the
/// native `zen/audio` MethodChannel and the `zen/volume_events`
/// EventChannel (VOLUME_CHANGED_ACTION).
///
/// NOTE: output SWITCHING is deliberately absent — just_audio exposes
/// no preferred-device API (Echo uses Media3's setPreferredAudioDevice);
/// Android auto-routes. The sheet lists and monitors devices only.
class AudioOutputService {
  AudioOutputService._();

  static final AudioOutputService instance = AudioOutputService._();

  static const _channel = MethodChannel('zen/audio');
  static const _volumeEvents = EventChannel('zen/volume_events');

  /// Live media volume, pushed by native on change + subscribe.
  final volume = ValueNotifier<({int volume, int max})?>(null);

  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  /// Whether the BLUETOOTH_CONNECT permission request was already made
  /// this session (never nag more than once).
  bool batteryPermissionRequested = false;

  /// Starts the volume event stream. Idempotent; app-lifetime.
  void startVolumeEvents() {
    if (_started) return;
    _started = true;
    _sub = _volumeEvents.receiveBroadcastStream().listen(
          (v) {
        if (v is Map) {
          final vol = v['volume'];
          final max = v['max'];
          if (vol is int && max is int) {
            volume.value = (volume: vol, max: max);
          }
        }
      },
      onError: (_) {},
    );
  }

  Future<List<AudioOutputDevice>> listDevices() async {
    try {
      final raw = await _channel.invokeMethod('listDevices');
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map(AudioOutputDevice.fromMap)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<({int volume, int max})?> getVolume() async {
    try {
      final raw = await _channel.invokeMethod('getVolume');
      if (raw is! Map) return null;
      final v = raw['volume'];
      final m = raw['max'];
      if (v is int && m is int) return (volume: v, max: m);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setVolume(int value) async {
    try {
      await _channel.invokeMethod('setVolume', value);
    } catch (_) {}
  }

  /// Asks for BLUETOOTH_CONNECT (API 31+) — needed to read bonded
  /// devices for battery levels. Returns whether it is granted.
  Future<bool> requestBluetoothPermission() async {
    try {
      final r = await _channel.invokeMethod('requestBluetoothPermission');
      return r == true;
    } catch (_) {
      return false;
    }
  }
}