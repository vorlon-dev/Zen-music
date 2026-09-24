import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/listen_together_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

/// Listen Together: create a room (host — your playback broadcasts to
/// everyone) or join by code (guest — playback follows the host).
/// The body switches purely on the service phase: entry form while
/// disconnected/connecting, room view the moment the user is in.
class ListenTogetherScreen extends StatefulWidget {
  const ListenTogetherScreen({super.key});

  @override
  State<ListenTogetherScreen> createState() => _ListenTogetherScreenState();
}

class _ListenTogetherScreenState extends State<ListenTogetherScreen> {
  final _service = ListenTogetherService.instance;
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  StreamSubscription<LtEvent>? _eventSub;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _eventSub = _service.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onEvent(LtEvent event) {
    if (!mounted) return;
    switch (event) {
      case LtJoinRequestEvent(:final userId, :final username):
        _showJoinRequest(userId, username);
      case LtErrorEvent(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
        );
      case LtKickedEvent(:final reason):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('You were removed: $reason'),
              duration: const Duration(seconds: 3)),
        );
      default:
        break;
    }
    // Every event may have mutated room state — repaint unconditionally.
    setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _createRoom() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('Enter your name first');
      return;
    }
    setState(() => _busy = true);
    final code = await _service.createRoom(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code == null) {
      _toast('Could not create the room — try again');
      return;
    }
    // Phase is inRoom now — build() switches to the room view.
    setState(() {});
  }

  Future<void> _joinRoom() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim();
    if (name.isEmpty) {
      _toast('Enter your name first');
      return;
    }
    if (code.isEmpty) {
      _toast('Enter the room code');
      return;
    }
    setState(() => _busy = true);
    final ok = await _service.joinRoom(code, name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _toast('Join failed — check the code or wait for approval');
      return;
    }
    // Approved — phase is inRoom; build() switches to the room view.
    setState(() {});
  }

  void _showJoinRequest(String userId, String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Join request',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text('$username wants to join your room.',
            style: const TextStyle(
                color: SpotifyColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () {
              _service.rejectJoin(userId, reason: 'Declined');
              Navigator.pop(ctx);
            },
            child: const Text('Reject'),
          ),
          TextButton(
            onPressed: () {
              _service.approveJoin(userId);
              Navigator.pop(ctx);
            },
            child: const Text('Allow',
                style: TextStyle(color: SpotifyColors.green)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_service.phaseNotifier, _service.roomNotifier]),
      builder: (context, _) {
        // Pure phase switch: inRoom = room view, anything else = entry.
        if (_service.isInRoom) return _buildRoom();
        return _buildEntry(_service.phase);
      },
    );
  }

  // ── Entry: create or join ──

  Widget _buildEntry(LtPhase phase) {
    final busy = _busy || phase == LtPhase.connecting;
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Listen Together',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Icon(Icons.headphones_rounded,
              size: 56, color: SpotifyColors.green),
          const SizedBox(height: 12),
          const Text(
            'Listen together in sync',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'One person controls the music — everyone hears the same '
                'song at the same moment.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: SpotifyColors.textSecondary.withOpacity(0.85),
                fontSize: 13.5),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _nameController,
            maxLength: 50,
            style: const TextStyle(
                color: SpotifyColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: const TextStyle(color: SpotifyColors.textTertiary),
              filled: true,
              fillColor: SpotifyColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Material(
            color: SpotifyColors.green,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: busy ? null : _createRoom,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        color:
                        busy ? SpotifyColors.textTertiary : Colors.black,
                        size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Create a room',
                      style: TextStyle(
                        color: busy
                            ? SpotifyColors.textTertiary
                            : Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                  child: Divider(color: SpotifyColors.surfaceLight)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or join',
                    style: TextStyle(
                        color: SpotifyColors.textTertiary, fontSize: 12)),
              ),
              const Expanded(
                  child: Divider(color: SpotifyColors.surfaceLight)),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            maxLength: 10,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 18,
                letterSpacing: 4,
                fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: 'ROOM CODE',
              hintStyle: const TextStyle(
                  color: SpotifyColors.textTertiary, letterSpacing: 4),
              counterText: '',
              filled: true,
              fillColor: SpotifyColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: busy ? null : _joinRoom,
            style: OutlinedButton.styleFrom(
              foregroundColor: SpotifyColors.textPrimary,
              side: BorderSide(
                  color: SpotifyColors.textTertiary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Join a room',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── In-room ──

  Widget _buildRoom() {
    final room = _service.room;
    final isHost = _service.isHost;
    final current = audioHandler.currentSong;

    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room ${room?.roomCode ?? ''}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: SpotifyColors.textPrimary)),
            Text(isHost ? 'You control the music' : 'Following the host',
                style: TextStyle(
                    fontSize: 11,
                    color: isHost
                        ? SpotifyColors.green
                        : SpotifyColors.textSecondary)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Room code',
            icon: const Icon(FluentIcons.share_24_regular,
                color: SpotifyColors.textSecondary),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: SpotifyColors.surface,
                  title: const Text('Room code',
                      style: TextStyle(color: SpotifyColors.textPrimary)),
                  content: Text(
                    room?.roomCode ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: SpotifyColors.green,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close')),
                  ],
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Leave room',
            icon: const Icon(Icons.logout_rounded,
                color: SpotifyColors.textSecondary),
            onPressed: () {
              _service.leaveRoom();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (current != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SpotifyColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  YoutubeThumbnail(
                    videoId: current.id,
                    imageUrl: current.thumbnail,
                    width: 56,
                    height: 56,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Synced for everyone',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: SpotifyColors.green)),
                        const SizedBox(height: 2),
                        Text(current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: SpotifyColors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600)),
                        Text(current.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: SpotifyColors.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open player',
                    icon: const Icon(Icons.play_circle_outline_rounded,
                        color: SpotifyColors.textPrimary),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PlayerScreen()),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          if (isHost)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SpotifyColors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: SpotifyColors.green),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Use the player normally — play, pause, seek and '
                            'skip are mirrored to everyone here.',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: SpotifyColors.textSecondary
                                .withOpacity(0.9)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text('In the room · ${room?.users.length ?? 0}',
              style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final user in room?.users ?? const <LtUser>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: SpotifyColors.surfaceLight,
                child: Text(
                  user.username.isNotEmpty
                      ? user.username[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(
                user.username +
                    (user.userId == _service.room?.hostId ? ' · host' : ''),
                style: const TextStyle(
                    color: SpotifyColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              trailing: user.isConnected
                  ? const Icon(Icons.circle,
                  size: 10, color: SpotifyColors.green)
                  : Icon(Icons.circle,
                  size: 10,
                  color: SpotifyColors.textTertiary.withOpacity(0.5)),
              subtitle: !user.isConnected
                  ? const Text('reconnecting…',
                  style: TextStyle(
                      color: SpotifyColors.textTertiary, fontSize: 11))
                  : null,
            ),
          if (isHost && (room?.users.length ?? 0) > 1) ...[
            const SizedBox(height: 12),
            const Text('Manage',
                style: TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            for (final user in room!.users)
              if (user.userId != room.hostId)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_remove_rounded,
                      size: 20, color: SpotifyColors.textTertiary),
                  title: Text('Remove ${user.username}',
                      style: const TextStyle(
                          color: SpotifyColors.textSecondary, fontSize: 13)),
                  onTap: () =>
                      _service.kickUser(user.userId, reason: 'Removed by host'),
                ),
          ],
        ],
      ),
    );
  }
}