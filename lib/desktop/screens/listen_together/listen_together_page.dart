// ZenMusic Desktop — FRESH screen (not ported): minimal Listen Together UI
// driving ListenTogetherService — create/join a room, see users + current
// track, host approvals (remove / transfer host), leave. Playback itself is
// controlled by whatever the host/device plays; the service auto-broadcasts.
//
// SP-43: added the live sync-health row (Room view) — the service already
// publishes LtSyncStats once per second (rtt, clock offset, drift, heartbeat
// age); the old page ignored it, so a half-working room looked identical to
// a healthy one ("listen together not working" had no on-screen signal).
// NOTE: the reported mute came from the crossfade fade-in bug in
// media_player.dart (SP-43 fix) — every guest load goes through playAll,
// which the old crossfade code muted. One root cause, both symptoms.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/services/listen_together_service.dart';

class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key});

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final _service = ListenTogetherService.instance;
  final _usernameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  StreamSubscription<LtEvent>? _eventsSub;
  bool _joinDialogOpen = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _usernameCtrl.text =
        Hive.box('SETTINGS').get('LT_USERNAME', defaultValue: '');
    _eventsSub = _service.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _usernameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _onEvent(LtEvent e) {
    if (!mounted) return;
    if (e is LtJoinRequestEvent) {
      _showJoinRequest(e.userId, e.username);
    } else if (e is LtUserEvent) {
      BottomMessage.showText(
        context,
        e.kind == LtUserEventKind.joined
            ? '${e.username} joined the room'
            : '${e.username} left the room',
      );
    } else if (e is LtHostChangedEvent) {
      BottomMessage.showText(context, '${e.newHostName} is now the host');
    } else if (e is LtKickedEvent) {
      BottomMessage.showText(context, 'You were removed from the room');
      if (mounted) context.pop();
    } else if (e is LtErrorEvent) {
      BottomMessage.showText(context, e.message);
    }
  }

  Future<void> _showJoinRequest(String userId, String username) async {
    if (_joinDialogOpen || !mounted) return;
    _joinDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join request'),
        content: Text('$username wants to join this room.'),
        actions: [
          TextButton(
            onPressed: () {
              _service.rejectJoin(userId);
              Navigator.pop(dialogContext);
            },
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () {
              _service.approveJoin(userId);
              Navigator.pop(dialogContext);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    _joinDialogOpen = false;
  }

  String get _username =>
      _usernameCtrl.text.trim().isEmpty
          ? 'User'
          : _usernameCtrl.text.trim();

  Future<void> _create() async {
    await Hive.box('SETTINGS').put('LT_USERNAME', _username);
    setState(() => _busy = true);
    final code = await _service.createRoom(_username);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code == null) {
      BottomMessage.showText(context, 'Could not create the room');
    } else {
      BottomMessage.showText(context, 'Room created — share the code');
    }
  }

  Future<void> _join() async {
    if (_codeCtrl.text.trim().length < 4) {
      BottomMessage.showText(context, 'Enter the room code');
      return;
    }
    await Hive.box('SETTINGS').put('LT_USERNAME', _username);
    setState(() => _busy = true);
    final ok = await _service.joinRoom(_codeCtrl.text, _username);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) BottomMessage.showText(context, 'Could not join the room');
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    BottomMessage.showText(context, 'Room code copied');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listen Together'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ValueListenableBuilder<LtRoomSnapshot?>(
            valueListenable: _service.roomNotifier,
            builder: (context, room, _) {
              if (room != null) return _RoomView(room: room);
              return ValueListenableBuilder<LtPhase>(
                valueListenable: _service.phaseNotifier,
                builder: (context, phase, _) {
                  if (phase == LtPhase.connecting ||
                      (phase == LtPhase.connected && _busy)) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _EntryForms(
                    usernameCtrl: _usernameCtrl,
                    codeCtrl: _codeCtrl,
                    busy: _busy,
                    onCreate: _create,
                    onJoin: _join,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Entry (disconnected) ──

class _EntryForms extends StatelessWidget {
  const _EntryForms({
    required this.usernameCtrl,
    required this.codeCtrl,
    required this.busy,
    required this.onCreate,
    required this.onJoin,
  });

  final TextEditingController usernameCtrl;
  final TextEditingController codeCtrl;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.groups_rounded, size: 56),
          const SizedBox(height: 8),
          Text(
            'Listen together in sync — one host, everyone follows.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_rounded),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Create a room'),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          TextField(
            controller: codeCtrl,
            decoration: const InputDecoration(
              labelText: 'Room code',
              prefixIcon: Icon(Icons.vpn_key_rounded),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onJoin(),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onJoin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Join a room'),
          ),
        ],
      ),
    );
  }
}

// ── In-room ──

class _RoomView extends StatelessWidget {
  const _RoomView({required this.room});

  final LtRoomSnapshot room;

  @override
  Widget build(BuildContext context) {
    final iAmHost = ListenTogetherService.instance.isHost;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          // Room code card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Room code',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: room.roomCode));
                      BottomMessage.showText(context, 'Room code copied');
                    },
                    child: Text(
                      room.roomCode,
                      style: Theme.of(context)
                          .textTheme
                          .headlineLarge
                          ?.copyWith(
                          letterSpacing: 6,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Tap to copy — share it with friends',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // SP-43: live sync health — the service refreshes this every
          // second while in a room; a stalled/degraded link is now visible
          // instead of a silent "not working".
          ValueListenableBuilder<LtSyncStats>(
            valueListenable: ListenTogetherService.instance.syncStats,
            builder: (context, st, _) {
              final String text;
              if (st.isHost) {
                text = 'Hosting — your playback is the room clock';
              } else if (st.heartbeatAgeMs < 0) {
                text = 'Waiting for the host…';
              } else {
                text = 'Synced · drift ${st.driftMs} ms · '
                    'ping ${st.rttMs} ms';
              }
              return Card(
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        st.isHost || st.inSync
                            ? Icons.check_circle_rounded
                            : Icons.sync_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(text,
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Now playing
          Card(
            child: ListTile(
              leading: room.currentTrack?.thumbnail.isNotEmpty == true
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  room.currentTrack!.thumbnail,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.music_note),
                ),
              )
                  : const Icon(Icons.music_note, size: 40),
              title: Text(room.currentTrack?.title ?? 'Nothing playing',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                room.isPlaying ? 'Playing in sync' : 'Paused',
                style: TextStyle(
                  color: room.isPlaying ? Colors.greenAccent : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Users
          Card(
            child: Column(
              children: [
                for (final u in room.users)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      u.isHost
                          ? Icons.star_rounded
                          : Icons.person_rounded,
                      color: u.isHost ? Colors.amber : null,
                    ),
                    title: Text(u.username),
                    trailing: u.isHost
                        ? const Text('Host', style: TextStyle(fontSize: 12))
                        : (iAmHost
                        ? PopupMenuButton<String>(
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'kick',
                            child: Text('Remove')),
                        PopupMenuItem(
                            value: 'host',
                            child: Text('Make host')),
                      ],
                      onSelected: (v) {
                        if (v == 'kick') {
                          ListenTogetherService.instance
                              .kickUser(u.userId);
                        } else {
                          ListenTogetherService.instance
                              .transferHost(u.userId);
                        }
                      },
                    )
                        : null),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Leave
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                ListenTogetherService.instance.leaveRoom();
                context.pop();
              },
              icon: const Icon(Icons.logout_rounded),
              label: Text(iAmHost ? 'Close room' : 'Leave room'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            iAmHost
                ? 'Everything you play is synced to the room.'
                : 'Playback follows the host.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
