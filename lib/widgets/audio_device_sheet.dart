import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../services/audio_device_service.dart';
import '../services/audio_output_service.dart';
import '../theme/spotify_theme.dart';
import 'wave_spinner.dart';

/// Echo-style audio device sheet: active output card (scallop icon
/// plate, Connected pill, volume %, wavy battery ring), custom-fill
/// volume row, Done. Output switching is not included (just_audio has
/// no preferred-device API — Android auto-routes).
void showAudioDeviceSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: SpotifyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    isScrollControlled: false,
    builder: (_) => const _AudioDeviceSheet(),
  );
}

class _AudioDeviceSheet extends StatefulWidget {
  const _AudioDeviceSheet();

  @override
  State<_AudioDeviceSheet> createState() => _AudioDeviceSheetState();
}

class _AudioDeviceSheetState extends State<_AudioDeviceSheet> {
  final _out = AudioOutputService.instance;

  List<AudioOutputDevice> _devices = [];
  AudioOutputDevice? _active;
  bool _loading = true;

  // Reconnect race guard: retries while a BT device registers.
  Timer? _retryTimer;
  int _retriesLeft = 0;

  static const _prio = {
    'bluetooth': 0,
    'wired': 1,
    'usb': 2,
    'hdmi': 3,
    'speaker': 4,
  };

  @override
  void initState() {
    super.initState();
    _out.startVolumeEvents();
    _refresh();
    AudioDeviceService.instance.deviceName.addListener(_refresh);
  }

  @override
  void dispose() {
    AudioDeviceService.instance.deviceName.removeListener(_refresh);
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    var devices = await _out.listDevices();
    if (!mounted) return;

    final btNoBattery =
    devices.any((d) => d.type == 'bluetooth' && d.battery == null);
    if (btNoBattery && !_out.batteryPermissionRequested) {
      _out.batteryPermissionRequested = true;
      final granted = await _out.requestBluetoothPermission();
      if (granted) {
        devices = await _out.listDevices();
        if (!mounted) return;
      }
    }

    devices.sort((a, b) {
      final pa = _prio[a.type] ?? 9;
      final pb = _prio[b.type] ?? 9;
      if (pa != pb) return pa.compareTo(pb);
      return a.name.compareTo(b.name);
    });
    final seen = <String>{};
    devices = devices.where((d) => seen.add('${d.type}|${d.name}')).toList();

    AudioOutputDevice? active;
    for (final t in const ['bluetooth', 'wired', 'usb', 'hdmi', 'speaker']) {
      active = devices.where((d) => d.type == t).firstOrNull;
      if (active != null) break;
    }

    setState(() {
      _devices = devices;
      _active = active;
      _loading = false;
    });

    _scheduleReconnectRetry(active);
  }

  /// RECONNECT RACE: the BT name push can land before the device
  /// appears in getDevices(). If a BT device should exist but isn't
  /// enumerated yet, retry a couple of times on a delay.
  void _scheduleReconnectRetry(AudioOutputDevice? active) {
    final btName = AudioDeviceService.instance.deviceName.value;
    final btMissing = btName != null &&
        !_devices.any((d) => d.type == 'bluetooth');
    if (btMissing && _retriesLeft > 0) {
      _retriesLeft--;
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 700), _refresh);
    } else if (!btMissing) {
      _retriesLeft = 2;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: _loading
            ? const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: WaveSpinner(size: 30)),
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audio output',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            if (_active != null)
              _DeviceCard(device: _active!, volume: _out.volume)
            else
              const Text(
                'No audio devices found',
                style: TextStyle(
                  fontSize: 13,
                  color: SpotifyColors.textSecondary,
                ),
              ),
            const SizedBox(height: 16),
            _VolumeRow(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: SpotifyColors.green,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DEVICE CARD
// ═════════════════════════════════════════════

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.volume});

  final AudioOutputDevice device;
  final ValueNotifier<({int volume, int max})?> volume;

  IconData get _icon {
    switch (device.type) {
      case 'bluetooth':
        return AudioDeviceService.isSpeaker(device.name)
            ? Icons.speaker_rounded
            : (AudioDeviceService.isBuds(device.name)
            ? Icons.earbuds_rounded
            : Icons.headset_rounded);
      case 'wired':
        return Icons.headphones_rounded;
      case 'usb':
        return Icons.usb_rounded;
      case 'hdmi':
        return Icons.tv_rounded;
      default:
        return Icons.phone_android_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = device.type == 'speaker' ? 'This phone' : device.name;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpotifyColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(46, 46),
                  painter: _ScallopPainter(
                    color: SpotifyColors.green.withOpacity(0.18),
                  ),
                ),
                Icon(_icon, size: 24, color: SpotifyColors.textPrimary),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'Connected',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Battery ring (BT only, when the system reports a level).
          // When absent, the volume % shows here instead — it is the
          // MEDIA volume, not the battery.
          if (device.type == 'bluetooth' && device.battery != null)
            _BatteryRing(level: device.battery!)
          else
            ValueListenableBuilder<({int volume, int max})?>(
              valueListenable: volume,
              builder: (context, v, _) {
                if (v == null || v.max <= 0) return const SizedBox.shrink();
                final pct = ((v.volume / v.max) * 100).round();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 14, color: SpotifyColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SpotifyColors.textSecondary,
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _BatteryRing extends StatelessWidget {
  const _BatteryRing({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(46, 46),
            painter: WaveRingPainter(
              phase: 0,
              startAngle: -math.pi / 2,
              sweepAngle: 2 * math.pi * (level / 100).clamp(0.0, 1.0),
              color: SpotifyColors.green,
              backgroundColor: Colors.white.withOpacity(0.15),
              strokeWidth: 3,
              amplitude: 1.2,
            ),
          ),
          Text(
            '$level%',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScallopPainter extends CustomPainter {
  _ScallopPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    const indent = 0.10;
    const sides = 8;

    const steps = 120;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final angle = i * math.pi * 2 / steps;
      final r = 1 - indent + indent * math.cos(sides * angle);
      final x = cx + (size.width / 2) * r * math.cos(angle);
      final y = cy + (size.height / 2) * r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScallopPainter old) => old.color != color;
}

// ═════════════════════════════════════════════
// VOLUME ROW — the fill is a vertically CENTERED inset bar (rounded
// both ends), not a full-height block.
// ═════════════════════════════════════════════

class _VolumeRow extends StatefulWidget {
  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  final _out = AudioOutputService.instance;
  double? _dragValue;
  ({int volume, int max})? _local;

  @override
  void initState() {
    super.initState();
    _out.startVolumeEvents();
    _out.getVolume().then((v) {
      if (mounted && v != null && _out.volume.value == null) {
        setState(() => _local = v);
      }
    });
  }

  void _applyFraction(double fraction, int max) {
    final target = (fraction.clamp(0.0, 1.0) * max).round();
    _out.setVolume(target);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<({int volume, int max})?>(
      valueListenable: _out.volume,
      builder: (context, event, _) {
        final state = _dragValue != null ? null : (event ?? _local);
        final max = state?.max ?? 15;
        final current = _dragValue ?? (state?.volume.toDouble() ?? 0);
        final fraction = (current / max).clamp(0.0, 1.0);

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            // Inset bar geometry: 12dp side padding, 26dp tall,
            // vertically centered in the 72dp row.
            const inset = 12.0;
            const barH = 26.0;
            final inner = width - inset * 2;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _applyFraction(
                  ((d.localPosition.dx - inset) / inner), max),
              onHorizontalDragStart: (d) => setState(() => _dragValue =
                  (((d.localPosition.dx - inset) / inner) * max)
                      .clamp(0.0, max.toDouble())),
              onHorizontalDragUpdate: (d) => setState(() =>
              _dragValue = (((d.localPosition.dx - inset) / inner) * max)
                  .clamp(0.0, max.toDouble())),
              onHorizontalDragEnd: (_) {
                final v = _dragValue;
                if (v != null) _out.setVolume(v.round());
                setState(() => _dragValue = null);
              },
              onHorizontalDragCancel: () => setState(() => _dragValue = null),
              child: Container(
                height: 72,
                decoration: BoxDecoration(
                  color: SpotifyColors.surfaceLight,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Stack(
                  children: [
                    // Track (dim, full inset width).
                    Positioned(
                      left: inset,
                      right: inset,
                      top: (72 - barH) / 2,
                      height: barH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(barH / 2),
                        ),
                      ),
                    ),
                    // Fill (centered inset bar, rounded both ends).
                    Positioned(
                      left: inset,
                      top: (72 - barH) / 2,
                      height: barH,
                      width: (inner * fraction)
                          .clamp(0.0, inner)
                          .toDouble(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: SpotifyColors.green.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(barH / 2),
                        ),
                      ),
                    ),
                    // Icon + label + end dot.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(
                            current > 0
                                ? Icons.volume_up_rounded
                                : Icons.volume_off_rounded,
                            size: 24,
                            color: SpotifyColors.textPrimary,
                          ),
                          const SizedBox(width: 14),
                          const Text(
                            'Volume',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: SpotifyColors.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: fraction >= 0.95
                                  ? SpotifyColors.textPrimary
                                  : SpotifyColors.textSecondary
                                  .withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}