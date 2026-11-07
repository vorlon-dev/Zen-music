// ZenMusic · vorlon-dev

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/services/automix.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

class CrossfadePage extends StatefulWidget {
  const CrossfadePage({super.key});

  @override
  State<CrossfadePage> createState() => _CrossfadePageState();
}

class _CrossfadePageState extends State<CrossfadePage> {
  int _seconds = 0;
  bool _playerAvailable = true;
  bool _automix = AutomixPrefs.enabled;

  @override
  void initState() {
    super.initState();
    try {
      _seconds = GetIt.I<MediaPlayer>().crossfadeSeconds;
    } catch (_) {
      _playerAvailable = false;
    }
  }

  Future<void> _apply(int seconds) async {
    setState(() => _seconds = seconds);
    try {
      await GetIt.I<MediaPlayer>().setCrossfadeSeconds(seconds);
    } catch (_) {}
  }

  String get _label => _seconds == 0 ? 'Off' : '${_seconds}s';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crossfade')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (!_playerAvailable) ...<Widget>[
                const Text(
                  'Player not available right now.',
                  style: TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              'Fade duration',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          Text(
                            _label,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _seconds == 0
                                  ? Theme.of(context).hintColor
                                  : Colors.greenAccent.shade400,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _seconds.toDouble(),
                        min: 0,
                        max: 12,
                        divisions: 12,
                        label: _label,
                        onChanged: (double v) => unawaited(_apply(v.round())),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text('Off', style: TextStyle(fontSize: 11)),
                          Text('2s', style: TextStyle(fontSize: 11)),
                          Text('6s', style: TextStyle(fontSize: 11)),
                          Text('12s', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Card(
                child: SwitchListTile(
                  title: const Text('Automix',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text(
                      'DJ-style blends: looks up both tempos, stretches the '
                      'tracks toward each other and sizes the overlap to '
                      'whole bars. Needs no fade length. Tempo-matched, not '
                      'beat-phase-locked.'),
                  value: _automix,
                  onChanged: (bool v) async {
                    setState(() => _automix = v);
                    await AutomixPrefs.setEnabled(v);
                  },
                ),
              ),
              const SizedBox(height: 4),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      Text('How it works',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        'Near the end of a track a second player takes over '
                        'its tail while the next track starts, and the two '
                        'are blended with an equal-power curve, so both are '
                        'audible together. It applies to automatic '
                        'advances; a manual skip cuts straight to the next '
                        'track and the volume restores itself.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text('Good to know',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        '• Off by default — drag the slider to switch it on.\n'
                        '• Spotify tracks played by the Spotify engine keep '
                        'their own audio path and are not faded.\n'
                        '• A single track on loop-one replays without a fade.\n'
                        '• If the next track cannot be prepared in time, '
                        'playback just moves on without an overlap.',
                        style: TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
