// ZenMusic — LastWave Jam room screen. ZenMusic remains GPL-3.0.
//
// Material port of the LastWave-Desktop Jam page (Clash Projects, GPL-3.0):
// entry cards (display name, always-on rooms with live listener counts,
// create room with the collaborative/host-only toggle, join by code or
// pasted invite link) and the room view (code tile + copy invite, now
// playing, shared "up next" queue, listeners with host controls, chat with
// replies, cooldown notice). Local playback keeps running if the server
// cannot be reached; the error is shown here — same as the reference.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/services/jam_service.dart';

/// Collaborative listening room ("Listen Together"), LastWave-style.
class JamPage extends StatefulWidget {
  final String? initialCode;
  const JamPage({super.key, this.initialCode});

  @override
  State<JamPage> createState() => _JamPageState();
}

class _JamPageState extends State<JamPage> {
  final _jam = JamService.instance.controller;
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _chat = TextEditingController();
  final _chatFocus = FocusNode();
  final _chatScroll = ScrollController();
  bool _collaborative = true;
  bool _copied = false;
  JamChatLine? _replyTo;
  Timer? _noticeTimer;
  Timer? _countsTimer;
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _name.text = _jam.savedDisplayName();
    _code.text = widget.initialCode ?? '';
    _loadCounts();
    _countsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_jam.state.phase != JamPhase.active) _loadCounts();
    });
  }

  @override
  void didUpdateWidget(JamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final code = widget.initialCode;
    if (code != null && code != oldWidget.initialCode) _code.text = code;
  }

  Future<void> _loadCounts() async {
    final counts = await _jam.fetchRoomCounts();
    if (mounted && counts.isNotEmpty) setState(() => _counts = counts);
  }

  void _remember() => _jam.rememberDisplayName(_name.text);

  void _send() {
    _jam.sendChat(_chat.text, replyToId: _replyTo?.id);
    _chat.clear();
    if (_replyTo != null) setState(() => _replyTo = null);
    // Drop and re-take focus so the keyboard reliably comes back after a
    // submit (same trick as the reference page).
    _chatFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chatFocus.requestFocus();
    });
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: _jam.inviteLink(code)));
    if (!mounted) return;
    setState(() => _copied = true);
    BottomMessage.showText(context, 'Invite link copied');
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  void _reply(JamChatLine line) {
    setState(() => _replyTo = line);
    _chatFocus.requestFocus();
  }

  /// Clears the server notice once the cooldown has passed (or after a few
  /// seconds for plain messages).
  void _scheduleNoticeClear(JamSnapshot jam) {
    _noticeTimer?.cancel();
    if (jam.notice.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ms = jam.retryAtMs > now ? jam.retryAtMs - now + 500 : 6000;
    _noticeTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) _jam.clearNotice();
    });
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _countsTimer?.cancel();
    _name.dispose();
    _code.dispose();
    _chat.dispose();
    _chatFocus.dispose();
    _chatScroll.dispose();
    // The controller is app-scoped (JamService): navigating away must NOT
    // kill the room — sync keeps running in the background, same as the
    // reference's provider scope.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary =
        theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75) ??
            Colors.grey;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jam'),
        actions: [
          if (_jam.state.phase == JamPhase.active)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: _LivePill()),
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _jam,
        builder: (context, _) {
          final jam = _jam.state;
          final noticeKey = _lastNoticeKey(jam);
          if (noticeKey != _seenNoticeKey) {
            _seenNoticeKey = noticeKey;
            if (jam.notice.isNotEmpty) _scheduleNoticeClear(jam);
          }
          if (jam.phase == JamPhase.active) {
            final prevChatLen = _lastChatLen;
            if (jam.chat.length != prevChatLen) {
              _lastChatLen = jam.chat.length;
              _scrollChatToEnd();
            }
          }
          final active = jam.phase == JamPhase.active;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  active
                      ? 'Playback stays in sync with everyone in the room.'
                      : 'Listen together. Rooms run on a hosted server; if it '
                          'is unreachable, playback on this device keeps going.',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                ),
              ),
              Expanded(
                child: active
                    ? _room(context, jam)
                    : _entry(context, jam),
              ),
            ],
          );
        },
      ),
    );
  }

  String _lastNoticeKey(JamSnapshot jam) => '${jam.notice}|${jam.retryAtMs}';
  String _seenNoticeKey = '|0';
  int _lastChatLen = 0;

  // ── Not in a room ───────────────────────────────────────────────────

  Widget _entry(BuildContext context, JamSnapshot jam) {
    final busy = jam.phase == JamPhase.connecting;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (jam.phase == JamPhase.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _NoticeBanner(
                    text: jam.error.isEmpty
                        ? 'Connection failed'
                        : jam.error,
                    tone: _NoticeTone.warning,
                  ),
                ),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('Your name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        hintText: 'Listener',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Always-on rooms',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Open all day. The first person in is the admin.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    for (final station in jamStations)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(station.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    _counts[station.code] == null
                                        ? '${station.blurb} · ${station.code}'
                                        : '${_counts[station.code]} listening · ${station.code}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      _remember();
                                      _jam.joinRoom(station.code, _name.text);
                                    },
                              child: const Text('Join'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Start a room',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'You get a code to share with friends.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _collaborative,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _collaborative = v),
                      title: Text(
                        _collaborative
                            ? 'Everyone controls playback'
                            : 'Only the host controls playback',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: busy
                            ? null
                            : () {
                                _remember();
                                _jam.createRoom(_name.text,
                                    collaborative: _collaborative);
                              },
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text(
                            busy ? 'Connecting…' : 'Create room'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Join a room',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the code a friend sent you (links work too).',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            decoration: const InputDecoration(
                              hintText: 'ABC123',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            onSubmitted: busy
                                ? null
                                : (_) {
                                    _remember();
                                    _jam.joinRoom(_code.text, _name.text);
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () {
                                  _remember();
                                  _jam.joinRoom(_code.text, _name.text);
                                },
                          child: const Text('Join'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── In a room ───────────────────────────────────────────────────────

  Widget _room(BuildContext context, JamSnapshot jam) {
    final info = _roomColumn(context, jam);
    final chat = _chatCard(context, jam);
    Widget body;
    if (MediaQuery.of(context).size.width < 860) {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            info,
            const SizedBox(height: 14),
            SizedBox(height: 420, child: chat),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
                width: 340, child: SingleChildScrollView(child: info)),
            const SizedBox(width: 16),
            Expanded(child: chat),
          ],
        ),
      );
    }
    if (jam.notice.isEmpty) return body;
    final limited = jam.retryAtMs > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _NoticeBanner(
            text: limited
                ? 'One pause or change per minute. '
                    'Try again at ${jamClock(jam.retryAtMs)}.'
                : jam.notice,
            tone: _NoticeTone.warning,
            onClose: _jam.clearNotice,
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _roomColumn(BuildContext context, JamSnapshot jam) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final secondary = theme.textTheme.bodySmall?.color ?? Colors.grey;
    final track = jam.track;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(jam.roomName.isEmpty
                  ? 'Room code'
                  : 'Room · ${jam.roomCode}'),
              const SizedBox(height: 8),
              // The code sits in its own tinted tile so it reads at a glance.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.28),
                    width: 0.8,
                  ),
                ),
                child: SelectableText(
                  jam.roomName.isEmpty ? jam.roomCode : jam.roomName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: jam.roomName.isEmpty ? 8 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Pill(
                    label: jam.isMainHost
                        ? 'Host'
                        : jam.isHost
                            ? 'Co-host'
                            : 'Guest',
                  ),
                  if (jam.permanent) const _Pill(label: 'Always on'),
                  _Pill(
                    label: jam.roomMode == jamModeHostOnly
                        ? 'Host controls playback'
                        : 'Everyone controls playback',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _copyInvite(jam.roomCode),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: Text(_copied ? 'Copied' : 'Copy invite'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      _jam.leave();
                      if (context.canPop()) context.pop();
                    },
                    child: const Text('Leave'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Now playing'),
              const SizedBox(height: 10),
              if (track == null)
                Text(
                  'Nothing yet. Play a song and it plays for everyone.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: secondary.withValues(alpha: 0.8)),
                )
              else
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: track.artworkUrl?.isNotEmpty == true
                          ? Image.network(
                              track.artworkUrl!,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 64,
                                height: 64,
                                child: ColoredBox(
                                  color: Color(0x22888888),
                                  child: Icon(Icons.music_note),
                                ),
                              ),
                            )
                          : const SizedBox(
                              width: 64,
                              height: 64,
                              child: ColoredBox(
                                color: Color(0x22888888),
                                child: Icon(Icons.music_note),
                              ),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: secondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label(jam.isMainHost
                  ? 'Up next · your queue is shared'
                  : 'Up next · admin queue'),
              const SizedBox(height: 10),
              if (jam.queue.isEmpty)
                Text(
                  'Nothing queued.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: secondary.withValues(alpha: 0.8)),
                )
              else ...[
                for (var i = 0; i < jam.queue.length && i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text('${i + 1}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: secondary)),
                        ),
                        Expanded(
                          child: Text(
                            jam.queue[i].artist.isEmpty
                                ? jam.queue[i].title
                                : '${jam.queue[i].title} · ${jam.queue[i].artist}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (jam.queue.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+${jam.queue.length - 5} more',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondary)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('Listeners · ${jam.people.length}'),
              const SizedBox(height: 10),
              for (final person in jam.people)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      _Avatar(name: person.name),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          person.userId == jam.userId
                              ? '${person.name} (you)'
                              : person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (person.isHost)
                        _Pill(label: person.isCoHost ? 'Co-host' : 'Host'),
                      if (jam.isMainHost && person.userId != jam.userId) ...[
                        const SizedBox(width: 8),
                        if (person.isCoHost)
                          OutlinedButton(
                            onPressed: () => _jam.revokeHost(person.userId),
                            child: const Text('Remove host'),
                          )
                        else if (jam.coHostId.isEmpty)
                          OutlinedButton(
                            onPressed: () => _jam.grantHost(person.userId),
                            child: const Text('Make host'),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chatCard(BuildContext context, JamSnapshot jam) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: _Label('Chat'),
          ),
          Container(height: 1, color: theme.dividerColor),
          Expanded(
            child: jam.chat.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet. Say hi.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: jam.chat.length,
                    itemBuilder: (context, i) {
                      final line = jam.chat[i];
                      final prev = i > 0 ? jam.chat[i - 1] : null;
                      return _Bubble(
                        line: line,
                        mine: line.userId == jam.userId,
                        showName: prev == null || prev.userId != line.userId,
                        onReply: () => _reply(line),
                      );
                    },
                  ),
          ),
          Container(height: 1, color: theme.dividerColor),
          if (_replyTo != null)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Replying to ${_replyTo!.userName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _replyTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _replyTo = null),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chat,
                    focusNode: _chatFocus,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    // onEditingComplete (not onSubmitted) so Enter does not
                    // run the default "unfocus after submit".
                    onEditingComplete: _send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send',
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Small shared pieces ─────────────────────────────────────────────

enum _NoticeTone { warning }

class _NoticeBanner extends StatelessWidget {
  final String text;
  final _NoticeTone tone;
  final VoidCallback? onClose;
  const _NoticeBanner({required this.text, this.tone = _NoticeTone.warning,
      this.onClose});

  @override
  Widget build(BuildContext context) {
    // Only the warning tone exists today; kept for parity with the
    // reference's InfoBar severities.
    final color = tone == _NoticeTone.warning
        ? Colors.amber.shade800
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final base = theme.cardColor;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              (dark ? Colors.white : Colors.black)
                  .withValues(alpha: dark ? 0.025 : 0.015),
              base,
            ),
            base,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor, width: 0.8),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
            .copyWith(
          color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withValues(alpha: 0.6) ??
              Colors.grey,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color? color;
  final bool dot;
  const _Pill({required this.label, this.color, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final tone = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    final green = Colors.greenAccent.shade400;
    return _Pill(label: 'Live', color: green, dot: true);
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  static const size = 30.0;
  const _Avatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
      ),
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final JamChatLine line;
  final bool mine;
  final bool showName;
  final VoidCallback onReply;
  const _Bubble({
    required this.line,
    required this.mine,
    required this.showName,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).cardColor;
    return Padding(
      padding: EdgeInsets.only(top: showName ? 10 : 3),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showName && !mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                line.isHost ? '${line.userName} · host' : line.userName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mine) _replyButton(),
              Flexible(child: _bubble(context, accent, surface)),
              if (!mine) _replyButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _replyButton() => IconButton(
        tooltip: 'Reply',
        icon: const Icon(Icons.reply_rounded, size: 14),
        onPressed: onReply,
        visualDensity: VisualDensity.compact,
      );

  Widget _bubble(BuildContext context, Color accent, Color surface) {
    final reply = line.replyTo;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? accent.withValues(alpha: 0.18) : surface,
          // Chat-bubble shape: the corner facing the speaker is tight.
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reply != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.12),
                  border: Border(left: BorderSide(color: accent, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reply.userName,
                      style: TextStyle(
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      reply.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            SelectableText(line.text),
          ],
        ),
      ),
    );
  }
}
