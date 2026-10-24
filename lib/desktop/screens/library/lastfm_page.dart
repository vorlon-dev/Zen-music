// ZenMusic — Last.fm scrobbling setup page (GPL-3.0).
//
// SP-25 — opened from the "Last.fm" card on the Saved page.
// Shows the connection state, starts the browser login, and offers the
// manual token paste as a fallback when the automatic return to the app
// did not happen (busy port, strict browser, etc.).

import 'package:flutter/material.dart';

import 'package:zenmusic/desktop/services/lastfm_service.dart';

class LastfmPage extends StatefulWidget {
  const LastfmPage({super.key});

  @override
  State<LastfmPage> createState() => _LastfmPageState();
}

class _LastfmPageState extends State<LastfmPage> {
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _busy = false;
  String _status = '';

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _status = 'Contacting Last.fm…';
    });
    final String msg = await LastfmService.instance.startLogin();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = msg;
    });
  }

  Future<void> _completeWithToken() async {
    setState(() {
      _busy = true;
      _status = 'Finishing login…';
    });
    final String msg =
        await LastfmService.instance.completeLoginWithToken(_tokenCtrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = msg;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await LastfmService.instance.logout();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Disconnected.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Last.fm scrobbling')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Connection card ──
          ValueListenableBuilder<String?>(
            valueListenable: LastfmService.instance.user,
            builder: (context, user, _) {
              final bool connected = user != null;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.graphic_eq,
                      size: 40,
                      color: connected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).hintColor,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            connected ? 'Connected as $user' : 'Not connected',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            connected
                                ? 'Your plays are scrobbled to Last.fm'
                                : 'Scrobble your plays to your Last.fm library',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _busy
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : connected
                            ? OutlinedButton(
                                onPressed: _disconnect,
                                child: const Text('Disconnect'),
                              )
                            : FilledButton(
                                onPressed: _connect,
                                child: const Text('Connect Last.fm'),
                              ),
                  ],
                ),
              );
            },
          ),

          // ── Login status / manual token fallback ──
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(fontSize: 13)),
          ],
          ValueListenableBuilder<String?>(
            valueListenable: LastfmService.instance.user,
            builder: (context, user, _) {
              if (user != null || _busy) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tokenCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Paste token (only if the automatic return '
                          'did not work)',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _completeWithToken,
                      child: const Text('Complete login'),
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),
          Text('How scrobbling works',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '• The moment a track starts, "now playing" appears on your '
            'Last.fm profile.\n'
            '• A play is scrobbled once you have heard at least half of it '
            '(or 4 minutes for long tracks) and the track is longer than 30 '
            'seconds.\n'
            '• Skipping early does not scrobble.\n'
            '• Offline plays are queued and sent automatically when the '
            'internet is back.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          Text('First time here?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Scrobbling needs two free strings from a Last.fm API account: '
            'create one at last.fm/api/account/create, then paste its Key '
            'and Shared secret into kLastfmApiKey / kLastfmApiSecret at the '
            'top of lib/desktop/services/lastfm_service.dart.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
