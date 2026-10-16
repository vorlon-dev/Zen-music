// ZenMusic Desktop — FRESH equalizer screen (not ported): device-band EQ
// via the MediaPlayer's Android session EQ. Windows/other platforms show
// an honest notice (desktop EQ = mpv arc, later). Gains persist in Hive
// (EQ_ENABLED / EQ_BANDS) and restore on every launch.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/desktop/services/eq_models.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  final _player = GetIt.I<MediaPlayer>();

  EqParams? _params;
  bool _enabled = false;
  List<double> _gains = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final params = await _player.getEqParameters();
    if (!mounted) return;
    if (params == null) {
      setState(() {
        _loading = false;
        _error = 'Equalizer is not available on this device.';
      });
      return;
    }
    final enabled = await _player.getEqEnabled();
    final stored = Hive.box('SETTINGS').get('EQ_BANDS');
    final storedGains = stored is List
        ? List<double>.from(
        stored.map((e) => (e as num?)?.toDouble() ?? 0.0))
        : <double>[];
    setState(() {
      _params = params;
      _enabled = enabled;
      _gains = storedGains.length == params.bands.length
          ? storedGains
          : List<double>.filled(params.bands.length, 0);
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final params = await _player.getEqParameters();
    if (!mounted || params == null) return;
    final enabled = await _player.getEqEnabled();
    setState(() {
      _params = params;
      _enabled = enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      )
          : _Body(
        params: _params!,
        enabled: _enabled,
        gains: _gains,
        onEnabled: (v) async {
          await _player.setEqEnabled(v);
          if (mounted) setState(() => _enabled = v);
        },
        onGain: (i, g) async {
          if (mounted) {
            setState(() {
              _gains[i] = g;
            });
          }
          await _player.setEqBandGain(i, g);
        },
        onReset: () async {
          await _player.resetEq();
          await _reload();
          if (mounted) {
            setState(() {
              _gains = List.filled(_params!.bands.length, 0);
            });
          }
        },
      ),
    );
  }
}

// ignore: unused_element
bool _await0(Future<bool> f) => false;

class _Body extends StatelessWidget {
  const _Body({
    required this.params,
    required this.enabled,
    required this.gains,
    required this.onEnabled,
    required this.onGain,
    required this.onReset,
  });

  final EqParams params;
  final bool enabled;
  final List<double> gains;
  final ValueChanged<bool> onEnabled;
  final void Function(int index, double gain) onGain;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        SwitchListTile(
          title: const Text('Enable Equalizer'),
          secondary: const Icon(Icons.equalizer_rounded),
          value: enabled,
          onChanged: onEnabled,
        ),
        const Divider(),
        for (var i = 0; i < params.bands.length; i++)
          ListTile(
            dense: true,
            title: Text(
              '${(params.bands[i].centerHz / 100).round() / 10} kHz',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Slider(
              value: gains.length > i
                  ? gains[i].clamp(params.minDb, params.maxDb)
                  : 0.0,
              min: params.minDb,
              max: params.maxDb,
              divisions:
              ((params.maxDb - params.minDb) * 2).round().clamp(4, 60),
              label: gains.length > i
                  ? '${gains[i].toStringAsFixed(1)} dB'
                  : '0.0 dB',
              onChanged: enabled ? (v) => onGain(i, v) : null,
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: enabled ? onReset : null,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset all bands'),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Bands are the device equalizer — applies system-wide to '
                'ZenMusic playback while enabled.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}