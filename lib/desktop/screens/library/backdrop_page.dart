import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/backdrop/windows_backdrop_service.dart';

class BackdropPage extends StatefulWidget {
  const BackdropPage({super.key});

  @override
  State<BackdropPage> createState() => _BackdropPageState();
}

class _BackdropPageState extends State<BackdropPage> {
  bool _enabled = true;
  bool _supported = true;

  @override
  void initState() {
    super.initState();
    final WindowsBackdropService service = WindowsBackdropService.instance;
    _enabled = service.isEnabled;
    _supported = service.isSupported;
  }

  Future<void> _apply(bool value) async {
    setState(() => _enabled = value);
    await WindowsBackdropService.instance.setEnabled(value);
  }

  String _statusLabel(WindowsBackdropState state, bool enabled) {
    switch (state) {
      case WindowsBackdropState.active:
        return 'Playing behind the player';
      case WindowsBackdropState.resolving:
        return 'Looking for the video…';
      case WindowsBackdropState.hidden:
        return enabled
            ? 'No video found for this track'
            : 'Off — will show for the next track';
      case WindowsBackdropState.off:
        return 'Off';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video backdrop')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (!_supported) ...<Widget>[
                const Text(
                  'Windows only — this feature does nothing on this '
                      'platform.',
                  style: TextStyle(color: Colors.redAccent),
                ),
                const SizedBox(height: 8),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Video backdrop',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: const Text(
                          'Play the song video, blurred, behind the player '
                              'screen (Windows only)',
                        ),
                        value: _enabled,
                        onChanged: _supported
                            ? (bool v) => _apply(v)
                            : null,
                      ),
                      ValueListenableBuilder<WindowsBackdropState>(
                        valueListenable:
                        WindowsBackdropService.instance.state,
                        builder: (BuildContext context,
                            WindowsBackdropState state, Widget? _) {
                          final bool good =
                              state == WindowsBackdropState.active;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  good
                                      ? Icons.check_circle
                                      : Icons.info_outline,
                                  size: 15,
                                  color: good
                                      ? Colors.greenAccent.shade400
                                      : Theme.of(context).hintColor,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _statusLabel(state, _enabled),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: good
                                          ? Colors.greenAccent.shade400
                                          : Theme.of(context).hintColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
                        'When a YouTube song is playing, its video is '
                            'fetched separately and played muted behind the '
                            'player screen — scaled to 16:9, covered edge to '
                            'edge and softened with a light blur layer plus a '
                            'dark gradient, so the controls stay readable and '
                            'the whole screen feels alive. The audio you hear '
                            'is completely unchanged; the video layer is '
                            'silent, loops automatically when it is shorter '
                            'than the song and realigns whenever you seek.',
                        style: TextStyle(height: 1.5),
                      ),
                      SizedBox(height: 12),
                      Text('Good to know',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        '• Windows only — other platforms keep the plain '
                            'look.\n'
                            '• Uses one extra muted ~360p video stream while a '
                            'song plays; turning it off saves that bandwidth '
                            'and GPU work.\n'
                            '• Spotify-engine tracks, local files and '
                            'unavailable/restricted videos simply show no '
                            'backdrop — everything keeps working.\n'
                            '• If a video cannot be fetched right now, it '
                            'quietly retries once after ~20 s and again on the '
                            'next track.',
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