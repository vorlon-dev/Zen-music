import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../audio/zen_audio_handler.dart';
import '../main.dart';
import '../theme/spotify_theme.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  AndroidEqualizerParameters? _params;
  List<double> _gains = [];
  bool _enabled = false;
  bool _isLoading = true;
  String? _activePreset;

  static const Map<String, List<double>> _presets = {
    'Balanced': [],
    'Bass Boost': [8.0, 3.0, -2.0],
    'Treble Boost': [-2.0, 2.0, 8.0],
    'Vocal': [2.0, 6.0, 4.0, 1.0],
    'Rock': [7.0, 2.0, 4.0, 6.0],
    'Pop': [3.0, 4.0, 2.0],
    'Electronic': [9.0, -1.0, 3.0, 7.0],
  };

  List<double> _gainsForPreset(List<double> stops, int bandCount) {
    if (stops.isEmpty) return List<double>.filled(bandCount, 0);
    return List<double>.generate(bandCount, (i) {
      final position = bandCount > 1 ? i / (bandCount - 1) : 0.0;
      final segment = (position * (stops.length - 1)).floor();
      final clamped = segment.clamp(0, stops.length - 1);
      return stops[clamped];
    });
  }

  Future<void> _applyPreset(String name) async {
    final gains = _gainsForPreset(_presets[name]!, _params!.bands.length);
    for (var i = 0; i < gains.length; i++) {
      await audioHandler.setEqualizerBandGain(i, gains[i]);
    }
    if (!mounted) return;
    setState(() {
      _gains = gains;
      _activePreset = name;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final params = await audioHandler.getEqualizerParameters();
    if (!mounted) return;
    setState(() {
      _params = params;
      _gains = params?.bands.map((b) => b.gain).toList() ?? [];
      _isLoading = false;
    });
  }

  String _formatFrequency(double hz) {
    if (hz >= 1000) {
      return hz >= 10000
          ? '${(hz / 1000).toStringAsFixed(0)} kHz'
          : '${(hz / 1000).toStringAsFixed(1)} kHz';
    }
    return '${hz.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Equalizer',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            )),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded,
                color: SpotifyColors.textPrimary),
            tooltip: 'Reset bands',
            onPressed: () async {
              await audioHandler.resetEqualizerBands();
              if (!mounted || _params == null) return;
              setState(() {
                _gains = List<double>.filled(_params!.bands.length, 0);
                _activePreset = null;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
          child:
          CircularProgressIndicator(color: SpotifyColors.green))
          : _params == null
          ? const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Equalizer is not available on this device',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: SpotifyColors.textSecondary,
              fontSize: 15,
            ),
          ),
        ),
      )
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Enable switch
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: SpotifyColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SwitchListTile.adaptive(
              value: _enabled,
              activeColor: SpotifyColors.green,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Enable equalizer',
                style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              onChanged: (value) async {
                await audioHandler.setEqualizerEnabled(value);
                if (!mounted) return;
                setState(() => _enabled = value);
              },
            ),
          ),
          const SizedBox(height: 24),

          // Presets
          const Text(
            'Presets',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.keys.map((name) {
              final isActive = _activePreset == name;
              return ChoiceChip(
                label: Text(name),
                selected: isActive,
                onSelected: (_) => _applyPreset(name),
                selectedColor: SpotifyColors.green,
                labelStyle: TextStyle(
                  color: isActive
                      ? Colors.black
                      : SpotifyColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: SpotifyColors.surface,
                side: BorderSide(
                  color: SpotifyColors.textTertiary
                      .withOpacity(0.25),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Bands
          Text(
            '${_params!.bands.length} bands',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: SpotifyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...List.generate(_params!.bands.length, (index) {
            final band = _params!.bands[index];
            final gain = _gains[index];
            final min = _params!.minDecibels;
            final max = _params!.maxDecibels;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatFrequency(band.centerFrequency),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: SpotifyColors.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SpotifyColors.green
                              .withOpacity(0.15),
                          borderRadius:
                          BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${gain.toStringAsFixed(1)} dB',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: SpotifyColors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: gain.clamp(min, max),
                    min: min,
                    max: max,
                    activeColor: SpotifyColors.green,
                    inactiveColor: SpotifyColors.textTertiary
                        .withOpacity(0.25),
                    onChanged: (value) {
                      setState(() {
                        _gains[index] = value;
                        _activePreset = null;
                      });
                    },
                    onChangeEnd: (value) => audioHandler
                        .setEqualizerBandGain(index, value),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}