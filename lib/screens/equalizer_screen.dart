import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../audio/zen_audio_handler.dart';
import '../main.dart';
import '../services/dsp_service.dart';
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

  // ── Parametric (AutoEq) state ──
  List<EqProfile> _profiles = [];
  String? _selectedProfileId;
  String? _activeParametricId;
  List<double>? _curveDb;
  bool _curveLoading = false;

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
    final profiles = storage.getEqProfiles();
    final active = storage.getActiveEqProfile();
    setState(() {
      _params = params;
      _gains = params?.bands.map((b) => b.gain).toList() ?? [];
      _profiles = profiles;
      _activeParametricId = active?.id;
      _isLoading = false;
    });
    if (active != null) {
      unawaitedPreview(active);
    }
  }

  /// Loads the response curve for [profile] into the preview card.
  Future<void> unawaitedPreview(EqProfile profile) async {
    setState(() {
      _selectedProfileId = profile.id;
      _curveLoading = true;
    });
    final db = await DspService.instance.magnitudeResponseDb(
      bands: profile.bands,
      preamp: profile.preamp,
      points: 128,
    );
    if (!mounted) return;
    setState(() {
      _curveDb = db;
      _curveLoading = false;
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

  // ── Parametric: import ──

  Future<void> _importPreset() async {
    final nameCtrl = TextEditingController();
    final textCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Import parametric preset',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: SpotifyColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Preset name',
                hintStyle: TextStyle(color: SpotifyColors.textTertiary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textCtrl,
              maxLines: 6,
              style: const TextStyle(
                  color: SpotifyColors.textPrimary, fontSize: 12.5),
              decoration: const InputDecoration(
                hintText: 'Paste AutoEq text — Preamp / Filter lines',
                hintStyle: TextStyle(color: SpotifyColors.textTertiary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: SpotifyColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import',
                  style: TextStyle(
                      color: SpotifyColors.green,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final text = textCtrl.text;
    nameCtrl.dispose();
    textCtrl.dispose();

    if (saved != true || text.trim().isEmpty) return;

    final preset = await DspService.instance.parsePresetText(text);
    if (!mounted) return;
    if (preset == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not read that preset — check the text')));
      return;
    }

    final errors = await DspService.instance.validatePreset(preset);
    if (!mounted) return;
    if (errors.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: SpotifyColors.surface,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Preset has problems',
              style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in errors.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(e,
                      style: const TextStyle(
                          color: SpotifyColors.textSecondary,
                          fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK',
                    style: TextStyle(color: SpotifyColors.green))),
          ],
        ),
      );
      return;
    }

    final profile = EqProfile(
      id: EqProfile.newId(),
      name: name.isEmpty ? _defaultName(preset) : name,
      preamp: preset.preamp,
      bands: preset.bands,
      addedTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await storage.saveEqProfile(profile);
    if (!mounted) return;
    setState(() => _profiles = storage.getEqProfiles());
    unawaitedPreview(profile);
  }

  String _defaultName(DspPreset preset) {
    final notes = preset.metadata['Notes'] ??
        preset.metadata.values.firstWhere((v) => v.isNotEmpty,
            orElse: () => '');
    if (notes.isNotEmpty) {
      final words = notes.split(RegExp(r'\s+')).take(4).join(' ');
      if (words.isNotEmpty) return words;
    }
    return 'Imported preset';
  }

  // ── Parametric: delete ──

  Future<void> _deleteProfile(EqProfile profile) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: const Text('Delete preset?'),
        content: Text(profile.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await storage.deleteEqProfile(profile.id);
    if (profile.id == _activeParametricId) {
      await storage.setActiveEqProfile(null);
      _activeParametricId = null;
    }
    if (!mounted) return;
    setState(() {
      _profiles = storage.getEqProfiles();
      if (_selectedProfileId == profile.id) {
        _selectedProfileId = null;
        _curveDb = null;
      }
    });
  }

  // ── Parametric: apply to playback (system-EQ approximation) ──

  Future<void> _applyToPlayback(EqProfile profile) async {
    if (_params == null) return;
    final freqs = _params!.bands
        .map((b) => b.centerFrequency.toDouble())
        .toList();
    final db = await DspService.instance.responseAtFrequencies(
      bands: profile.bands,
      preamp: profile.preamp,
      frequencies: freqs,
    );
    if (!mounted || db == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not compute the EQ response')));
      }
      return;
    }
    final min = _params!.minDecibels;
    final max = _params!.maxDecibels;
    for (var i = 0; i < _params!.bands.length && i < db.length; i++) {
      final g = db[i].clamp(min, max).toDouble();
      await audioHandler.setEqualizerBandGain(i, g);
    }
    await audioHandler.setEqualizerEnabled(true);
    await storage.setActiveEqProfile(profile.id);
    if (!mounted) return;
    setState(() {
      _gains =
          db.map((d) => d.clamp(min, max).toDouble()).toList();
      _activePreset = profile.name;
      _enabled = true;
      _activeParametricId = profile.id;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Applied "${profile.name}" to the system equalizer')));
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
              await storage.setActiveEqProfile(null);
              if (!mounted || _params == null) return;
              setState(() {
                _gains = List<double>.filled(_params!.bands.length, 0);
                _activePreset = null;
                _activeParametricId = null;
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

          // ── Parametric (AutoEq) section ──
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Parametric EQ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _importPreset,
                icon: const Icon(Icons.upload_file_rounded,
                    size: 16,
                    color: SpotifyColors.green),
                label: const Text('Import',
                    style: TextStyle(
                        fontSize: 13,
                        color: SpotifyColors.green)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_profiles.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No parametric presets yet. Import an AutoEq-style '
                    'text (Preamp + Filter lines) to add one.',
                style: TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 13,
                    height: 1.4),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _profiles)
                  GestureDetector(
                    onLongPress: () => _deleteProfile(p),
                    child: ChoiceChip(
                      label: Text(p.name),
                      selected: _selectedProfileId == p.id,
                      onSelected: (_) => unawaitedPreview(p),
                      selectedColor: SpotifyColors.green,
                      labelStyle: TextStyle(
                        color: _selectedProfileId == p.id
                            ? Colors.black
                            : SpotifyColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: SpotifyColors.surface,
                      side: BorderSide(
                        color: p.id == _activeParametricId
                            ? SpotifyColors.green
                            : SpotifyColors.textTertiary
                            .withOpacity(0.25),
                        width: p.id == _activeParametricId ? 1.6 : 1,
                      ),
                    ),
                  ),
              ],
            ),
          if (_selectedProfileId != null) ...[
            const SizedBox(height: 12),
            _curveCard(),
          ],
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
            style: TextStyle(
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

  /// Response-curve preview card for the selected profile, with the
  /// apply button (system-EQ approximation — the caption says so).
  Widget _curveCard() {
    final profile = _profiles.firstWhere(
            (p) => p.id == _selectedProfileId,
        orElse: () => _profiles.first);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${profile.name} · ${profile.bands.length} bands · '
                      'preamp ${profile.preamp.toStringAsFixed(1)} dB',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: SpotifyColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: _curveLoading
                ? const Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SpotifyColors.green)))
                : (_curveDb == null
                ? const Center(
                child: Text('Curve unavailable',
                    style: TextStyle(
                        color: SpotifyColors.textTertiary,
                        fontSize: 12)))
                : CustomPaint(
                painter: _EqCurvePainter(_curveDb!))),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => _applyToPlayback(profile),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: SpotifyColors.green,
                shape: const StadiumBorder(),
              ),
              child: Text(
                  profile.id == _activeParametricId
                      ? 'Re-apply to playback'
                      : 'Apply to playback',
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5)),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Projected onto the system equalizer — an approximation. '
                'Full parametric filtering arrives with the native audio '
                'pipeline.',
            style: TextStyle(
                color: SpotifyColors.textTertiary,
                fontSize: 11.5,
                height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Draws the magnitude response over the log-frequency grid. The x
/// mapping mirrors DspService.frequencyGrid exactly: linear in
/// log10(f) between 20 Hz and 20 kHz.
/// Draws the magnitude response over the log-frequency grid. The x
/// mapping mirrors DspService.frequencyGrid exactly: linear in
/// log10(f) between 20 Hz and 20 kHz.
class _EqCurvePainter extends CustomPainter {
  final List<double> db;
  _EqCurvePainter(this.db);

  static const _minHz = 20.0;
  static const _maxHz = 20000.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (db.length < 2) return;

    var lo = -12.0;
    var hi = 12.0;
    for (final d in db) {
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    lo = (lo - 1).floorToDouble();
    hi = (hi + 1).ceilToDouble();
    final span = (hi - lo).abs().clamp(1.0, 999.0);

    // 0 dB reference line.
    final zeroY = size.height * (1 - (0 - lo) / span);
    if (zeroY >= 0 && zeroY <= size.height) {
      final zeroPaint = Paint()
        ..color = SpotifyColors.textTertiary.withOpacity(0.3)
        ..strokeWidth = 1;
      canvas.drawLine(
          Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);
    }

    final grid = DspService.frequencyGrid(db.length, _minHz, _maxHz);
    final logLo = _log(_minHz);
    final logSpan = _log(_maxHz) - logLo;

    final path = Path();
    for (var i = 0; i < db.length && i < grid.length; i++) {
      final x = size.width * (_log(grid[i]) - logLo) / logSpan;
      final y = size.height * (1 - (db[i] - lo) / span);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = SpotifyColors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static double _log(double v) => v <= 0 ? 0.0 : math.log(v);

  @override
  bool shouldRepaint(_EqCurvePainter old) => old.db.length != db.length;
}