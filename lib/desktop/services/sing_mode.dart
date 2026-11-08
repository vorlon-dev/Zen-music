// ZenMusic · Sing mode (Android): vocal removal with an adjustable voice level.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class SingMode {
  SingMode._();
  static final SingMode instance = SingMode._();
  static const MethodChannel _ch = MethodChannel('zen/lossless');

  final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// How much of the singer's voice stays: 0 = none, 1 = all.
  final ValueNotifier<double> voiceLevel = ValueNotifier(0.0);

  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> restore() async {
    final b = Hive.box('SETTINGS');
    enabled.value = b.get('SING_ENABLED', defaultValue: false) as bool;
    voiceLevel.value = (b.get('SING_VOICE', defaultValue: 0.0) as num).toDouble();
    await _apply();
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    await Hive.box('SETTINGS').put('SING_ENABLED', v);
    await _apply();
  }

  Future<void> setVoiceLevel(double v) async {
    voiceLevel.value = v.clamp(0.0, 1.0);
    await Hive.box('SETTINGS').put('SING_VOICE', voiceLevel.value);
    await _apply();
  }

  Future<void> _apply() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod('setVocalRemoval',
          {'amount': enabled.value ? 1.0 - voiceLevel.value : 0.0});
    } catch (_) {}
  }
}

/// Mic button: tap toggles Sing mode, long-press opens the voice-level slider.
/// Put it next to the lyrics controls.
class SingButton extends StatelessWidget {
  const SingButton({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = SingMode.instance;
    if (!s.supported) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: s.enabled,
      builder: (context, on, _) => GestureDetector(
        onLongPress: () => _sheet(context),
        child: IconButton(
          tooltip: 'Sing (hold for voice level)',
          iconSize: size,
          icon: Icon(on ? Icons.mic : Icons.mic_none,
              color: on ? (color ?? Theme.of(context).colorScheme.primary) : Colors.white54),
          onPressed: () => s.setEnabled(!on),
        ),
      ),
    );
  }

  void _sheet(BuildContext context) {
    final s = SingMode.instance;
    showModalBottomSheet(
      context: context,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: s.voiceLevel,
        builder: (context, v, _) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Voice in the song: ${(v * 100).round()}%'),
            Slider(
              value: v,
              onChanged: (x) {
                if (!s.enabled.value) s.setEnabled(true);
                s.setVoiceLevel(x);
              },
            ),
            const Text('0% = voice removed (karaoke)',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      ),
    );
  }
}
