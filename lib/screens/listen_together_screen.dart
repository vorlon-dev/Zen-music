import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/listen_together_service.dart';
import '../theme/spotify_theme.dart';

/// Listen Together — ported from the Echo Nightly screen to the
/// ZenMusic design system. Hosts approve joins, manage participants,
/// review suggestions; guests follow and cannot control playback.
class ListenTogetherScreen extends StatefulWidget {
  const ListenTogetherScreen({super.key});

  @override
  State<ListenTogetherScreen> createState() => _ListenTogetherScreenState();
}

class _ListenTogetherScreenState extends State<ListenTogetherScreen> {
  final _service = ListenTogetherService.instance;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  StreamSubscription<LtEvent>? _eventsSub;
  bool _tabJoin = false;
  bool _busy = false;
  bool _waitingApproval = false;
  String? _joinError;
  final _pendingJoins = <({String userId, String username})>[];
  final _pendingSuggestions = <LtSuggestionEvent>[];

  static const _usernameKey = 'lt_username';

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _eventsSub = _service.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_usernameKey) ?? '';
    if (saved.isNotEmpty && mounted) {
      setState(() => _nameCtrl.text = saved);
    }
  }

  Future<void> _saveUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, name);
  }

  void _onEvent(LtEvent event) {
    if (!mounted) return;
    if (event is LtJoinRequestEvent) {
      final exists = _pendingJoins.any((j) => j.userId == event.userId);
      if (!exists) {
        setState(() =>
            _pendingJoins.add((userId: event.userId, username: event.username)));
      }
    } else if (event is LtUserEvent && event.kind == LtUserEventKind.joined) {
      setState(() =>
          _pendingJoins.removeWhere((j) => j.userId == event.userId));
    } else if (event is LtErrorEvent) {
      if (event.code == 'join_rejected') {
        setState(() {
          _joinError = event.message.isEmpty
              ? 'Join was rejected by the host'
              : event.message;
          _waitingApproval = false;
        });
      } else {
        _snack('${event.code}: ${event.message}');
      }
    } else if (event is LtKickedEvent) {
      _snack(event.reason.isEmpty
          ? 'You were removed from the room'
          : 'Removed from room: ${event.reason}');
    } else if (event is LtSuggestionEvent) {
      final exists = _pendingSuggestions
          .any((s) => s.suggestionId == event.suggestionId);
      if (!exists) {
        setState(() => _pendingSuggestions.add(event));
      }
    } else if (event is LtSuggestionApprovedEvent) {
      setState(() => _pendingSuggestions
          .removeWhere((s) => s.suggestionId == event.suggestionId));
      _snack('Playing suggestion: ${event.song.title}');
    } else if (event is LtHostChangedEvent) {
      _snack('${event.newHostName} is now the host');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: SpotifyColors.surfaceLight,
        content: Text(message,
            style: const TextStyle(color: SpotifyColors.textPrimary)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _createRoom() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Enter a username first');
      return;
    }
    await _saveUsername(name);
    setState(() {
      _busy = true;
      _joinError = null;
    });
    final code = await _service.createRoom(name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (code == null) {
      setState(() => _joinError = 'Could not create the room — try again.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    _snack('Room $code created — code copied');
  }

  Future<void> _joinRoom() async {
    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) {
      _snack('Enter a username first');
      return;
    }
    if (code.length != 8) {
      _snack('Enter the 8-character room code');
      return;
    }
    await _saveUsername(name);
    setState(() {
      _busy = true;
      _waitingApproval = true;
      _joinError = null;
    });
    final ok = await _service.joinRoom(code, name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _waitingApproval = false;
      if (!ok && _joinError == null) {
        _joinError = 'Join was not approved. Check the code and try again.';
      }
    });
  }

  Future<void> _confirmAction({
    required String title,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: SpotifyColors.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel,
                  style: const TextStyle(
                      color: SpotifyColors.green,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: SpotifyColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
        title: const Text(
          'Listen Together',
          style: TextStyle(
            color: SpotifyColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          ValueListenableBuilder<LtPhase>(
            valueListenable: _service.phaseNotifier,
            builder: (context, phase, _) {
              final color = switch (phase) {
                LtPhase.connected || LtPhase.inRoom => SpotifyColors.green,
                LtPhase.connecting || LtPhase.reconnecting =>
                Colors.orangeAccent,
                _ => SpotifyColors.textTertiary,
              };
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<LtRoomSnapshot?>(
          valueListenable: _service.roomNotifier,
          builder: (context, room, _) {
            if (_service.isInRoom && room != null) {
              return _buildRoom(room);
            }
            return _buildEntry();
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ROOM VIEW
  // ═══════════════════════════════════════════

  Widget _buildRoom(LtRoomSnapshot room) {
    final isHost = _service.isHost;
    final connected = room.users.where((u) => u.isConnected).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _roomCard(room, isHost),
        const SizedBox(height: 12),
        _nowPlayingCard(room),
        const SizedBox(height: 16),
        if (isHost && _pendingJoins.isNotEmpty) ...[
          _pendingJoinsSection(),
          const SizedBox(height: 16),
        ],
        _participantsSection(connected, isHost),
        const SizedBox(height: 16),
        if (isHost && _pendingSuggestions.isNotEmpty) ...[
          _suggestionsSection(),
          const SizedBox(height: 16),
        ],
        _hintCard(isHost),
        const SizedBox(height: 20),
        _leaveButton(),
      ],
    );
  }

  Widget _roomCard(LtRoomSnapshot room, bool isHost) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Text(
            'ROOM CODE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: SpotifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: room.roomCode));
              _snack('Room code copied');
            },
            child: Text(
              room.roomCode,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: SpotifyColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isHost ? 'You control the music' : 'Following the host',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: SpotifyColors.green,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: room.roomCode));
                _snack('Room code copied');
              },
              icon: const Icon(Icons.content_copy_rounded,
                  size: 15, color: SpotifyColors.textSecondary),
              label: const Text(
                'Copy code',
                style: TextStyle(
                    fontSize: 12.5, color: SpotifyColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nowPlayingCard(LtRoomSnapshot room) {
    final song = room.currentTrack;
    if (song == null) {
      return _panel(
        child: const Row(
          children: [
            Icon(Icons.music_note_rounded,
                size: 20, color: SpotifyColors.textTertiary),
            SizedBox(width: 10),
            Expanded(
              child: Text('Nothing playing yet — the host can start a song.',
                  style: TextStyle(
                      fontSize: 13, color: SpotifyColors.textSecondary)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: song.thumbnail.isNotEmpty
                ? Image.network(
              song.thumbnail,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 52,
                height: 52,
                color: SpotifyColors.surfaceLight,
                child: const Icon(Icons.music_note_rounded,
                    color: SpotifyColors.textTertiary),
              ),
            )
                : Container(
              width: 52,
              height: 52,
              color: SpotifyColors.surfaceLight,
              child: const Icon(Icons.music_note_rounded,
                  color: SpotifyColors.textTertiary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOW PLAYING · ${room.isPlaying ? "PLAYING" : "PAUSED"}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: SpotifyColors.green,
                  ),
                ),
                const SizedBox(height: 3),
                Text(song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: SpotifyColors.textPrimary)),
                Text(song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: SpotifyColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingJoinsSection() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Join requests',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary),
          ),
          const SizedBox(height: 10),
          for (final req in _pendingJoins)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(req.username, 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(req.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: SpotifyColors.textPrimary)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _service.approveJoin(req.userId);
                      setState(() => _pendingJoins
                          .removeWhere((j) => j.userId == req.userId));
                    },
                    icon: const Icon(Icons.check_rounded,
                        color: SpotifyColors.green, size: 24),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _service.rejectJoin(req.userId,
                          reason: 'Rejected by host');
                      setState(() => _pendingJoins
                          .removeWhere((j) => j.userId == req.userId));
                    },
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.redAccent, size: 24),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _participantsSection(List<LtUser> users, bool isHost) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'In the room · ${users.length}',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary),
          ),
          const SizedBox(height: 8),
          // The host can tap any non-host participant to manage them.
          for (final user in users)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: (isHost && !user.isHost)
                  ? () => _showUserActions(user)
                  : null,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    _avatar(user.username, 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: user.username,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: SpotifyColors.textPrimary),
                          children: [
                            if (user.isHost)
                              const TextSpan(
                                text: '  ·  host',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: SpotifyColors.green),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: user.isConnected
                            ? SpotifyColors.green
                            : SpotifyColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showUserActions(LtUser user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Make host',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(
                  title: 'Make ${user.username} the host?',
                  confirmLabel: 'Make host',
                  onConfirm: () => _service.transferHost(user.userId),
                );
              },
            ),
            ListTile(
              leading:
              const Icon(Icons.person_remove_rounded, color: Colors.redAccent),
              title: const Text('Remove from room',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmAction(
                  title: 'Remove ${user.username}?',
                  confirmLabel: 'Remove',
                  onConfirm: () =>
                      _service.kickUser(user.userId, reason: 'Removed by host'),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _suggestionsSection() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suggested songs',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary),
          ),
          const SizedBox(height: 10),
          for (final s in _pendingSuggestions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.queue_music_rounded,
                      size: 22, color: SpotifyColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: SpotifyColors.textPrimary)),
                        Text('by ${s.fromUsername}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: SpotifyColors.textSecondary)),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _service.approveSuggestion(s.suggestionId);
                      setState(() => _pendingSuggestions.removeWhere(
                              (x) => x.suggestionId == s.suggestionId));
                    },
                    icon: const Icon(Icons.check_rounded,
                        color: SpotifyColors.green, size: 24),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _service.rejectSuggestion(s.suggestionId,
                          reason: 'Rejected by host');
                      setState(() => _pendingSuggestions.removeWhere(
                              (x) => x.suggestionId == s.suggestionId));
                    },
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.redAccent, size: 24),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _hintCard(bool isHost) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 20, color: SpotifyColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isHost
                  ? 'You control playback for everyone — play, pause, seek and skips are mirrored to the room.'
                  : 'Playback is controlled by the host. Your player follows along automatically.',
              style: const TextStyle(
                  fontSize: 13, color: SpotifyColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: Colors.redAccent.withOpacity(0.12),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        ),
        onPressed: () => _service.leaveRoom(),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Leave room',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.redAccent)),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _avatar(String username, double size) {
    final letter =
    username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: SpotifyColors.surfaceLight,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: SpotifyColors.textPrimary),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ENTRY VIEW (create / join)
  // ═══════════════════════════════════════════

  Widget _buildEntry() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _tabToggle(),
        const SizedBox(height: 16),
        _entryCard(),
        const SizedBox(height: 20),
        _howItWorks(),
      ],
    );
  }

  Widget _tabToggle() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(23),
      ),
      child: Row(
        children: [
          _tabPill('Create a room', Icons.add_rounded, !_tabJoin, () {
            setState(() => _tabJoin = false);
          }),
          const SizedBox(width: 4),
          _tabPill('Join a room', Icons.login_rounded, _tabJoin, () {
            setState(() => _tabJoin = true);
          }),
        ],
      ),
    );
  }

  Widget _tabPill(String label, IconData icon, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? SpotifyColors.green : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.black : SpotifyColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.black : SpotifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard() {
    final hasName = _nameCtrl.text.trim().isNotEmpty;
    final hasCode = _codeCtrl.text.trim().length == 8;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _textField(
            controller: _nameCtrl,
            hint: 'Your name',
            icon: Icons.person_outline_rounded,
            maxLength: 24,
            onChanged: (_) => setState(() {}),
          ),
          if (_tabJoin) ...[
            const SizedBox(height: 12),
            _textField(
              controller: _codeCtrl,
              hint: 'Room code (8 characters)',
              icon: Icons.group_outlined,
              maxLength: 8,
              uppercase: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (_waitingApproval) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SpotifyColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: SpotifyColors.green),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Waiting for the host to approve…',
                        style: TextStyle(
                            fontSize: 13, color: SpotifyColors.textPrimary)),
                  ),
                ],
              ),
            ),
          ],
          if (_joinError != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_joinError!,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.redAccent)),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: hasName && !_busy
                    ? SpotifyColors.green
                    : SpotifyColors.surfaceLight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: (!_busy && hasName && (_tabJoin ? hasCode : true))
                  ? () => _tabJoin ? _joinRoom() : _createRoom()
                  : null,
              child: _busy
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.black),
              )
                  : Text(
                _tabJoin ? 'Join a room' : 'Create a room',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: hasName && !_busy
                      ? Colors.black
                      : SpotifyColors.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required int maxLength,
    bool uppercase = false,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      onChanged: (v) => onChanged(uppercase ? v.toUpperCase() : v),
      style: const TextStyle(
          color: SpotifyColors.textPrimary, fontSize: 15),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: SpotifyColors.textTertiary),
        prefixIcon:
        Icon(icon, size: 20, color: SpotifyColors.textSecondary),
        filled: true,
        fillColor: SpotifyColors.surfaceLight,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
          const BorderSide(color: SpotifyColors.green, width: 1.4),
        ),
      ),
    );
  }

  Widget _howItWorks() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How it works',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
          SizedBox(height: 14),
          _Step('1. Create a room',
              'Start a session and share the room code with friends.'),
          _Step('2. Join a friend',
              'Enter their room code to join their session instantly.'),
          _Step('3. Listen in sync',
              'The host controls the music — everyone hears the same song at the same moment.'),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.title, this.description);
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: SpotifyColors.textPrimary)),
          const SizedBox(height: 3),
          Text(description,
              style: const TextStyle(
                  fontSize: 13, color: SpotifyColors.textSecondary)),
        ],
      ),
    );
  }
}