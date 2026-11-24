// ZenMusic · vorlon-dev
//
// Equalizer UI: on/off switch, preset chips and 15 vertical band sliders.
// Layout idea and presets follow LastWave
// (https://github.com/Clash-Projects/LastWave-Native, GPL-3.0).

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:zenmusic/desktop/services/native_equalizer.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final power = ZenCard(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _enabled ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.equalizer_rounded,
                color: _enabled ? cs.onPrimary : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Equalizer'.tr,
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(_enabled ? 'On · $_preset' : 'Off',
                    style: tt.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Switch.adaptive(value: _enabled, onChanged: _setEnabled),
        ]),
      );

      final curve = ZenCard(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: SizedBox(
          height: 150,
          child: CustomPaint(
            painter: _CurvePainter(
              gains: List<double>.of(_gains),
              maxDb: NativeEqualizer.maxGainDb,
              color: _enabled ? cs.primary : cs.onSurfaceVariant,
              grid: cs.outlineVariant.withValues(alpha: 0.6),
              text: cs.onSurfaceVariant,
            ),
            size: Size.infinite,
          ),
        ),
      );

      final presets = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
            child: Text('Presets'.tr,
                style: tt.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in NativeEqualizer.presets)
                ChoiceChip(
                  label: Text(preset.name),
                  selected: _preset == preset.name,
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  onSelected: (_) => _applyPreset(preset),
                ),
            ],
          ),
        ],
      );

      final bands = ZenCard(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
            child: Row(children: [
              Text('Bands'.tr,
                  style: tt.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text('Reset'.tr),
              ),
            ]),
          ),
          SizedBox(
            height: wide ? 300 : 270,
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
        ]),
      );

      final note = Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          'Boost or cut each frequency by up to 8 dB. Changes apply to '
              'ZenMusic playback right away.',
          textAlign: TextAlign.center,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );

      final body = wide
          ? Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(children: [
              power,
              const SizedBox(height: 12),
              curve,
              const SizedBox(height: 16),
              presets,
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(child: Column(children: [bands, note])),
        ],
      )
          : Column(children: [
        power,
        const SizedBox(height: 12),
        curve,
        const SizedBox(height: 16),
        presets,
        const SizedBox(height: 16),
        bands,
        note,
      ]);

      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [body],
          ),
        ),
      );
    });
  }
}

/// Smooth frequency-response curve through the band gains.
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.gains,
    required this.maxDb,
    required this.color,
    required this.grid,
    required this.text,
  });
  final List<double> gains;
  final double maxDb;
  final Color color;
  final Color grid;
  final Color text;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    final w = size.width - left;
    final h = size.height;
    double y(double db) => h / 2 - (db / maxDb) * (h / 2 - 8);

    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final db in [maxDb, maxDb / 2, 0.0, -maxDb / 2, -maxDb]) {
      canvas.drawLine(Offset(left, y(db)), Offset(size.width, y(db)),
          gp..strokeWidth = db == 0 ? 1.5 : 1);
      final tp = TextPainter(
        text: TextSpan(
            text: '${db > 0 ? '+' : ''}${db.round()}',
            style: TextStyle(fontSize: 10, color: text)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 6, y(db) - tp.height / 2));
    }
    if (gains.length < 2) return;

    final pts = <Offset>[
      for (var i = 0; i < gains.length; i++)
        Offset(left + w * i / (gains.length - 1), y(gains[i])),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, y(0))
      ..lineTo(pts.first.dx, y(0))
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter o) =>
      o.gains != gains || o.color != color || o.maxDb != maxDb;
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
                trackHeight: 6,
                trackShape: const RoundedRectSliderTrackShape(),
                thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 9),
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