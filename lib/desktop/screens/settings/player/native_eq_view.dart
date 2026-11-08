// ZenMusic · vorlon-dev
//
// Equalizer UI: on/off switch, preset chips and 15 vertical band sliders.
// Layout idea and presets follow LastWave
// (https://github.com/Clash-Projects/LastWave-Native, GPL-3.0).

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:zenmusic/desktop/services/native_equalizer.dart';

class NativeEqView extends StatefulWidget {
  const NativeEqView({super.key});

  @override
  State<NativeEqView> createState() => _NativeEqViewState();
}

class _NativeEqViewState extends State<NativeEqView> {
  final NativeEqualizer _eq = NativeEqualizer.instance;

  late bool _enabled = _eq.enabled;
  late String _preset = _eq.presetName;
  late List<double> _gains = _eq.gains;

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await _eq.setEnabled(value);
  }

  Future<void> _applyPreset(EqPreset preset) async {
    setState(() {
      _preset = preset.name;
      _gains = List<double>.of(preset.gains);
      _enabled = true;
    });
    await _eq.applyPreset(preset);
  }

  void _onBandChanged(int index, double value) {
    setState(() {
      _gains[index] = value;
      _preset = NativeEqualizer.customName;
      _enabled = true;
    });
    _eq.setBandGain(index, value, persist: false);
  }

  void _onBandChangeEnd(int index, double value) {
    _eq.setBandGain(index, value);
  }

  Future<void> _reset() async {
    setState(() {
      _preset = NativeEqualizer.flat.name;
      _gains = List<double>.of(NativeEqualizer.flat.gains);
    });
    await _eq.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Equalizer'.tr),
          subtitle: Text(_enabled ? 'On · $_preset' : 'Off'),
          secondary: const Icon(Icons.equalizer_rounded),
          value: _enabled,
          onChanged: _setEnabled,
        ),
        const SizedBox(height: 8),
        Text('Presets'.tr, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in NativeEqualizer.presets)
              ChoiceChip(
                label: Text(preset.name),
                selected: _preset == preset.name,
                onSelected: (_) => _applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Bands'.tr, style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text('Reset'.tr),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 270,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < NativeEqualizer.bandCount; i++)
                Expanded(
                  child: _BandSlider(
                    label: NativeEqualizer.bandLabel(
                        NativeEqualizer.bandFreqsHz[i]),
                    value: _gains[i],
                    active: _enabled,
                    onChanged: (v) => _onBandChanged(i, v),
                    onChangeEnd: (v) => _onBandChangeEnd(i, v),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Boost or cut each frequency by up to 8 dB. Changes apply to '
          'ZenMusic playback right away.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.label,
    required this.value,
    required this.active,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double value;
  final bool active;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      fontSize: 9,
      color: active
          ? theme.colorScheme.onSurface
          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
    );
    final text = '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';
    return Column(
      children: [
        Text(text, style: style, maxLines: 1),
        const SizedBox(height: 4),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: value,
                min: -NativeEqualizer.maxGainDb,
                max: NativeEqualizer.maxGainDb,
                divisions: 32,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: style, maxLines: 1),
      ],
    );
  }
}
