// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/lossless/lossless_quality.dart';

class LosslessQualityPage extends StatefulWidget {
  const LosslessQualityPage({super.key});

  @override
  State<LosslessQualityPage> createState() => _LosslessQualityPageState();
}

class _LosslessQualityPageState extends State<LosslessQualityPage> {
  @override
  void initState() {
    super.initState();
    LosslessPrefs.index.addListener(_onChanged);
  }

  @override
  void dispose() {
    LosslessPrefs.index.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = LosslessPrefs.current;

    return Scaffold(
      appBar: AppBar(title: const Text('Song quality')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Streaming quality for YouTube Music and JioSaavn '
                            'songs.',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'YouTube videos and downloaded songs keep their '
                            'original audio. When a song is not available in '
                            'the selected tier, the next best tier plays '
                            'automatically. Songs that have no lossless '
                            'version anywhere follow the switch below.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: <Widget>[
                    for (final tier in LosslessQuality.values)
                      ListTile(
                        title: Text(
                          tier.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(tier.detail),
                        trailing: tier == selected
                            ? Icon(Icons.check_circle,
                            color: scheme.primary)
                            : Icon(Icons.radio_button_unchecked,
                            color: scheme.onSurfaceVariant),
                        onTap: () => LosslessPrefs.set(tier),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text(
                    'Lossless only',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(LosslessPrefs.strict
                      ? 'Songs with no lossless version are skipped - '
                          'nothing is ever played at normal quality.'
                      : 'Songs with no lossless version play at normal '
                          'quality instead of being skipped.'),
                  value: LosslessPrefs.strict,
                  onChanged: (v) async {
                    await LosslessPrefs.setStrict(v);
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Applies from the next song you play.',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
