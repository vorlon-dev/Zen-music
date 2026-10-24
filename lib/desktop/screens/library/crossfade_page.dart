// ZenMusic Desktop — SP-27: Crossfade setup page.
//
// Control surface for the volume-fade transition implemented in
// media_player.dart (SP-27 block): the last N seconds of the current track
// fade out and the next track fades in over its first N seconds. 0 = off.
// The setting persists in Hive ('CROSSFADE_SECS') and applies from the next
// track boundary onward.
//
// Same page style as lastfm_page.dart: plain Material widgets only, no new
// dependencies. MediaPlayer is accessed the same way the rest of the app
// does it (GetIt.I<MediaPlayer>()).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/services/media_player.dart';

class CrossfadePage extends StatefulWidget {
  const CrossfadePage({super.key});

  @override
  State<CrossfadePage> createState() => _CrossfadePageState();
}

class _CrossfadePageState extends State<CrossfadePage> {
  int _seconds = 0;
  bool _playerAvailable = true;

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
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      Text('How it works',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        'The current track fades out over its last seconds '
                        'and the next track fades in over its first seconds. '
                        'Works on every source — YouTube, JioSaavn and '
                        'offline files — and on automatic advances, skips '
                        'and the end of the queue alike. The volume always '
                        'restores itself if you pause, seek or stop '
                        'mid-fade.',
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
                        '• A single track on loop-one replays without a fade '
                        '(v1).',
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
