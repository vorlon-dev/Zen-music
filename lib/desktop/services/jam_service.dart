// ZenMusic · vorlon-dev

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:zenmusic/desktop/services/jam_playback_sync.dart';
import 'package:zenmusic/desktop/services/media_player.dart';


/// Hosted Jam server (same one the reference clients talk to).
const String jamDefaultServer = 'wss://jam.clashprojects.qd.je/ws';

const String jamModeCollaborative = 'collaborative';
const String jamModeHostOnly = 'host_only';

/// Always-active stations. The server provisions these and never closes them.
const List<JamStation> jamStations = <JamStation>[
  JamStation(code: 'INDIA', title: 'India', blurb: 'Always-on room for India'),
  JamStation(
      code: 'WORLD',
      title: 'International',
      blurb: 'Always-on room for everyone else'),
];

class JamStation {
  final String code;
  final String title;
  final String blurb;
  const JamStation({
    required this.code,
    required this.title,
    required this.blurb,
  });
}

class JamPerson {
  final String userId;
  final String name;

  /// True for the main host and the co-host.
  final bool isHost;
  final bool isCoHost;
  const JamPerson({
    required this.userId,
    required this.name,
    this.isHost = false,
    this.isCoHost = false,
  });
}

/// Snapshot of the message a chat line replies to.
class JamReply {
  final String id;
  final String userName;
  final String text;
  const JamReply({
    required this.id,
    required this.userName,
    required this.text,
  });
}

class JamChatLine {
  final String id;
  final String userId;
  final String userName;
  final bool isHost;
  final String text;
  final int timestamp;
  final JamReply? replyTo;
  const JamChatLine({
    required this.id,
    required this.userId,
    required this.userName,
    required this.text,
    this.isHost = false,
    this.timestamp = 0,
    this.replyTo,
  });
}

class JamTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final int? durationMs;
  const JamTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artwork_url': artworkUrl,
        'duration_ms': durationMs,
      };

  factory JamTrack.fromJson(Map<String, dynamic> json) => JamTrack(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        artist: json['artist']?.toString() ?? '',
        album: json['album']?.toString(),
        artworkUrl: json['artwork_url']?.toString(),
        durationMs: json['duration_ms'] is num
            ? (json['duration_ms'] as num).toInt()
            : int.tryParse('${json['duration_ms'] ?? ''}'),
      );
}


sealed class JamRemote {
  const JamRemote();
}

class JamRemotePlay extends JamRemote {
  final int positionMs;
  final int serverTimeMs;
  final String? fromUserId;
  const JamRemotePlay(this.positionMs, this.serverTimeMs, this.fromUserId);
}

class JamRemotePause extends JamRemote {
  final int positionMs;
  final String? fromUserId;
  const JamRemotePause(this.positionMs, this.fromUserId);
}

class JamRemoteSeek extends JamRemote {
  final int positionMs;
  final String? fromUserId;
  const JamRemoteSeek(this.positionMs, this.fromUserId);
}

class JamRemoteTrack extends JamRemote {
  final JamTrack track;
  final bool isPlaying;
  final int positionMs;
  final String? fromUserId;
  const JamRemoteTrack(
    this.track,
    this.isPlaying,
    this.positionMs,
    this.fromUserId,
  );
}

class JamRemoteFull extends JamRemote {
  final JamTrack? track;
  final bool isPlaying;
  final int positionMs;
  final int serverTimeMs;
  const JamRemoteFull({
    required this.track,
    required this.isPlaying,
    required this.positionMs,
    required this.serverTimeMs,
  });
}


enum JamPhase { disconnected, connecting, active, error }

class JamSnapshot {
  final JamPhase phase;
  final String error;
  final String roomCode;
  final String userId;
  final String displayName;
  final bool isHost;
  final String hostId;
  final String coHostId;
  final bool permanent;
  final String roomMode;
  final List<JamPerson> people;
  final List<JamChatLine> chat;
  final JamTrack? track;
  final bool isPlaying;

  /// The admin's upcoming queue, shared read-only with the room.
  final List<JamTrack> queue;

  /// Friendly title of an always-on room ("India"); empty otherwise.
  final String roomName;

  /// Wall-clock ms until which pause/skip are locked for you; 0 when free.
  final int cooldownUntilMs;

  /// Transient message from the server (rate limit, host rules).
  final String notice;

  /// Wall-clock ms when the playback cooldown ends; 0 when none.
  final int retryAtMs;

  /// True only for the main host, who may give and remove co-hosts.
  bool get isMainHost => userId.isNotEmpty && userId == hostId;

  /// Hosts and collaborative-mode guests may control playback.
  bool get canControl => isHost || roomMode == jamModeCollaborative;

  const JamSnapshot({
    this.phase = JamPhase.disconnected,
    this.error = '',
    this.roomCode = '',
    this.userId = '',
    this.displayName = '',
    this.isHost = false,
    this.hostId = '',
    this.coHostId = '',
    this.permanent = false,
    this.roomMode = jamModeCollaborative,
    this.people = const [],
    this.chat = const [],
    this.track,
    this.isPlaying = false,
    this.queue = const [],
    this.roomName = '',
    this.cooldownUntilMs = 0,
    this.notice = '',
    this.retryAtMs = 0,
  });

  JamSnapshot copyWith({
    JamPhase? phase,
    String? error,
    String? roomCode,
    String? userId,
    String? displayName,
    bool? isHost,
    String? hostId,
    String? coHostId,
    bool? permanent,
    String? roomMode,
    List<JamPerson>? people,
    List<JamChatLine>? chat,
    JamTrack? track,
    bool clearTrack = false,
    bool? isPlaying,
    List<JamTrack>? queue,
    String? roomName,
    int? cooldownUntilMs,
    String? notice,
    int? retryAtMs,
  }) =>
      JamSnapshot(
        phase: phase ?? this.phase,
        error: error ?? this.error,
        roomCode: roomCode ?? this.roomCode,
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        isHost: isHost ?? this.isHost,
        hostId: hostId ?? this.hostId,
        coHostId: coHostId ?? this.coHostId,
        permanent: permanent ?? this.permanent,
        roomMode: roomMode ?? this.roomMode,
        people: people ?? this.people,
        chat: chat ?? this.chat,
        track: clearTrack ? null : (track ?? this.track),
        isPlaying: isPlaying ?? this.isPlaying,
        queue: queue ?? this.queue,
        roomName: roomName ?? this.roomName,
        cooldownUntilMs: cooldownUntilMs ?? this.cooldownUntilMs,
        notice: notice ?? this.notice,
        retryAtMs: retryAtMs ?? this.retryAtMs,
      );
}

bool _isDefaultName(String name) => const {
      '',
      'listener',
      'host',
      'guest',
      'user',
      'anonymous',
    }.contains(name.trim().toLowerCase());

/// "3:42:10 PM" for a wall-clock millisecond timestamp (cooldown clock).
String jamClock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(t.minute)}:${two(t.second)} ${t.hour < 12 ? 'AM' : 'PM'}';
}


/// WebSocket client for the hosted Jam server (reference wire format).
///
/// A failed connection sets [JamPhase.error] and does not touch playback.
class JamController extends ChangeNotifier {
  WebSocketChannel? _socket;
  Timer? _ping;
  final _remote = StreamController<JamRemote>.broadcast();
  int _generation = 0;
  Timer? _cooldownTimer;

  JamSnapshot _state = const JamSnapshot();
  JamSnapshot get state => _state;

  /// Remote playback events other people caused (already echo-filtered at
  /// the transport level only by from_user_id — the sync bridge re-checks).
  Stream<JamRemote> get remote => _remote.stream;

  bool get isActive => _state.phase == JamPhase.active;

  /// Optional server override from the SETTINGS box ('' = default).
  String get serverUrl {
    String raw = '';
    try {
      raw = Hive.box('SETTINGS').get('JAM_SERVER', defaultValue: '') as String;
    } catch (_) {}
    final trimmed = raw.trim();
    return trimmed.isEmpty ? jamDefaultServer : trimmed;
  }

  String savedDisplayName() {
    try {
      return Hive.box('SETTINGS').get('JAM_USERNAME', defaultValue: '')
          as String;
    } catch (_) {
      return '';
    }
  }

  void rememberDisplayName(String name) {
    try {
      Hive.box('SETTINGS').put('JAM_USERNAME', name.trim());
    } catch (_) {}
  }

  String inviteLink(String code) {
    final u = Uri.parse(serverUrl);
    final base = Uri(
      scheme: u.scheme == 'wss' ? 'https' : 'http',
      host: u.host,
      port: u.hasPort ? u.port : null,
    );
    return '$base/?code=$code';
  }

  /// Accepts a bare code or a pasted invite link (`...?code=ABC123`).
  static String parseCode(String raw) {
    final text = raw.trim();
    final at = text.toLowerCase().indexOf('code=');
    final tail = at >= 0 ? text.substring(at + 5) : text;
    return tail.split(RegExp(r'[&#\s]')).first.trim().toUpperCase();
  }

  void createRoom(String displayName, {required bool collaborative}) {
    final name = displayName.trim().isEmpty ? 'Listener' : displayName.trim();
    _connect(() {
      _send('create_room', {
        'name': name,
        'room_mode': collaborative ? jamModeCollaborative : jamModeHostOnly,
      });
    });
  }

  void joinRoom(String roomCode, String displayName) {
    final code = parseCode(roomCode);
    final name = displayName.trim().isEmpty ? 'Listener' : displayName.trim();
    if (code.isEmpty) {
      _state = _state.copyWith(
        phase: JamPhase.error,
        error: 'Room code is required',
      );
      notifyListeners();
      return;
    }
    if (jamStations.any((s) => s.code == code) && _isDefaultName(displayName)) {
      _state = _state.copyWith(
        phase: JamPhase.error,
        error: 'Pick your own display name to join this public room',
      );
      notifyListeners();
      return;
    }
    _connect(() {
      _send('join_room', {'room_code': code, 'name': name});
    }, code: code);
  }

  /// Leaves the room and closes the socket. Awaitable so callers (page,
  /// tests) get an orderly shutdown before asserting the state.
  Future<void> leave() {
    _send('leave_room', null);
    return _close(clear: true);
  }

  void sendChat(String text, {String? replyToId}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _send('send_chat', {
      'text': trimmed,
      if (replyToId != null && replyToId.isNotEmpty) 'reply_to_id': replyToId,
    });
  }

  /// Main host only: make [userId] a co-host (a room has at most two hosts).
  void grantHost(String userId) => _send('grant_host', {'user_id': userId});

  /// Main host only: remove [userId]'s co-host role.
  void revokeHost(String userId) => _send('revoke_host', {'user_id': userId});

  /// Main host only: publish the upcoming queue so listeners can see it.
  void broadcastQueue(List<JamTrack> queue) {
    if (!isActive) return;
    _send('queue_update', {
      'queue': [for (final t in queue.take(5)) t.toJson()],
    });
  }

  /// Live listener counts for the always-on rooms ({code: count}).
  /// Empty on any failure; the join screen then just omits the counts.
  Future<Map<String, int>> fetchRoomCounts() async {
    try {
      final uri = Uri.parse(serverUrl);
      final http = Uri(
        scheme: uri.scheme == 'wss' ? 'https' : 'http',
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/rooms',
      );
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.getUrl(http);
        final response =
            await request.close().timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) return const {};
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        final rooms = decoded is Map ? decoded['rooms'] : null;
        if (rooms is! List) return const {};
        return {
          for (final r in rooms)
            if (r is Map) r['code'].toString(): _int(r['participants']),
        };
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      return const {};
    }
  }

  void clearNotice() {
    if (_state.notice.isEmpty && _state.retryAtMs == 0) return;
    _state = _state.copyWith(notice: '', retryAtMs: 0);
    notifyListeners();
  }

  void broadcastPlay(int positionMs) => _action({
        'action': 'play',
        'position_ms': positionMs,
        'client_time_ms': DateTime.now().millisecondsSinceEpoch,
        'is_playing': true,
      });

  void broadcastPause(int positionMs) => _action({
        'action': 'pause',
        'position_ms': positionMs,
        'client_time_ms': DateTime.now().millisecondsSinceEpoch,
        'is_playing': false,
      });

  void broadcastSeek(int positionMs) => _action({
        'action': 'seek',
        'position_ms': positionMs,
        'client_time_ms': DateTime.now().millisecondsSinceEpoch,
      });

  void broadcastTrack(JamTrack track,
      {required int positionMs, required bool isPlaying}) {
    _action({
      'action': 'change_track',
      'track': track.toJson(),
      'position_ms': positionMs,
      'client_time_ms': DateTime.now().millisecondsSinceEpoch,
      'is_playing': isPlaying,
    });
  }

  void _action(Map<String, dynamic> payload) {
    if (!isActive) return;
    _send('playback_action', payload);
  }

  Future<void> _connect(void Function() onOpen, {String? code}) async {
    final generation = ++_generation;
    await _close(clear: false);
    _state = JamSnapshot(
      phase: JamPhase.connecting,
      roomCode: code ?? '',
    );
    notifyListeners();
    final url = serverUrl;
    try {
      final socket = await WebSocket.connect(url).timeout(
        const Duration(seconds: 12),
      );
      if (generation != _generation) {
        try {
          await socket.close();
        } catch (_) {}
        return;
      }
      _socket = IOWebSocketChannel(socket);
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        _send('ping', null);
      });
      _socket!.stream.listen(
        (data) {
          if (data is String) _onMessage(data);
        },
        onError: (Object error) {
          if (generation != _generation) return;
          _state = _state.copyWith(
            phase: JamPhase.error,
            error: error.toString(),
          );
          notifyListeners();
        },
        onDone: () {
          if (generation != _generation) return;
          if (_state.phase != JamPhase.error) {
            _state = const JamSnapshot();
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
      onOpen();
    } catch (error) {
      if (generation != _generation) return;
      _state = JamSnapshot(
        phase: JamPhase.error,
        error: error.toString(),
      );
      notifyListeners();
    }
  }

  void _onMessage(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final type = decoded['type']?.toString() ?? '';
      final payload = decoded['payload'];
      final map = payload is Map
          ? payload.map((k, v) => MapEntry(k.toString(), v))
          : const <String, dynamic>{};
      switch (type) {
        case 'room_created':
          final userId = map['user_id']?.toString() ?? '';
          final name = (map['name']?.toString() ?? '').isEmpty
              ? 'Host'
              : map['name'].toString();
          _state = JamSnapshot(
            phase: JamPhase.active,
            roomCode: map['room_code']?.toString() ?? '',
            userId: userId,
            displayName: name,
            isHost: true,
            hostId: userId,
            roomMode: map['room_mode']?.toString() ?? jamModeCollaborative,
            people: [JamPerson(userId: userId, name: name, isHost: true)],
          );
        case 'sync_state':
          final playback = map['playback'] is Map
              ? (map['playback'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v))
              : const <String, dynamic>{};
          final trackRaw = playback['current_track'];
          final track = trackRaw is Map
              ? JamTrack.fromJson(
                  trackRaw.map((k, v) => MapEntry(k.toString(), v)))
              : null;
          final people = _people(map['participants']);
          final chat = _chat(map['chat_history']);
          _state = JamSnapshot(
            phase: JamPhase.active,
            roomCode: map['room_code']?.toString() ?? '',
            userId: map['user_id']?.toString() ?? '',
            displayName: map['name']?.toString() ?? '',
            isHost: map['is_host'] == true,
            hostId: map['host_id']?.toString() ?? '',
            coHostId: map['cohost_id']?.toString() ?? '',
            permanent: map['permanent'] == true,
            roomName: map['room_name']?.toString() ?? '',
            roomMode: map['room_mode']?.toString() ?? jamModeCollaborative,
            people: people,
            chat: chat,
            track: track,
            isPlaying: playback['is_playing'] == true,
            queue: _tracks(playback['queue']),
          );
          _remote.add(JamRemoteFull(
            track: track,
            isPlaying: playback['is_playing'] == true,
            positionMs: _int(playback['position_ms']),
            serverTimeMs: _int(playback['server_time_ms']),
          ));
        case 'user_joined':
          if (!isActive) return;
          final person = JamPerson(
            userId: map['user_id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
            isHost: map['is_host'] == true,
          );
          final next = [
            ..._state.people.where((p) => p.userId != person.userId),
            person,
          ];
          _state = _state.copyWith(people: next);
        case 'user_left':
          if (!isActive) return;
          final id = map['user_id']?.toString() ?? '';
          _state = _state.copyWith(
            people: _state.people.where((p) => p.userId != id).toList(),
          );
        case 'host_changed':
          if (!isActive) return;
          final hostId = (map['host_id']?.toString() ?? '').isNotEmpty
              ? map['host_id'].toString()
              : (map['new_host_id']?.toString() ?? '').isNotEmpty
                  ? map['new_host_id'].toString()
                  : (map['user_id']?.toString() ?? '');
          _applyRoles(hostId, map['cohost_id']?.toString() ?? '');
        case 'cooldown':
          _startCooldown(_int(map['retry_at_ms']));
        case 'queue_updated':
          if (!isActive) return;
          _state = _state.copyWith(queue: _tracks(map['queue']));
        case 'cohost_changed':
          if (!isActive) return;
          _applyRoles(
            map['host_id']?.toString() ?? _state.hostId,
            map['cohost_id']?.toString() ?? '',
          );
        case 'room_mode_changed':
          _state = _state.copyWith(
            roomMode: map['room_mode']?.toString() ?? _state.roomMode,
          );
        case 'chat_message':
          final next = [..._state.chat, _chatLine(map)];
          _state = _state.copyWith(
            chat: next.length > 50 ? next.sublist(next.length - 50) : next,
          );
        case 'sync_playback':
          _applyPlayback(map);
        case 'error':
          // A rejected request inside a room must not eject you from it;
          // show it as a notice instead (reference behaviour).
          if (_state.phase == JamPhase.active) {
            final message = map['message']?.toString() ?? '';
            if (map['code'] == 'rate_limited') {
              final retryAt = _int(map['retry_at_ms']);
              final after = _int(map['retry_after_ms']);
              final until = retryAt > 0
                  ? retryAt
                  : DateTime.now().millisecondsSinceEpoch + after;
              _state = _state.copyWith(notice: message, retryAtMs: until);
              _startCooldown(until);
            } else if (message.isNotEmpty) {
              _state = _state.copyWith(notice: message, retryAtMs: 0);
            }
            notifyListeners();
            return;
          }
          _state = _state.copyWith(
            phase: JamPhase.error,
            error: (map['message']?.toString() ?? '').isEmpty
                ? 'Unknown server error'
                : map['message'].toString(),
          );
        case 'pong':
          break;
      }
      notifyListeners();
    } catch (e) {
      print('[jam] bad frame: $e');
    }
  }

  void _applyRoles(String hostId, String coHostId) {
    _state = _state.copyWith(
      hostId: hostId,
      coHostId: coHostId,
      isHost: _state.userId == hostId || _state.userId == coHostId,
      people: [
        for (final person in _state.people)
          JamPerson(
            userId: person.userId,
            name: person.name,
            isHost: person.userId == hostId || person.userId == coHostId,
            isCoHost: coHostId.isNotEmpty && person.userId == coHostId,
          ),
      ],
    );
  }

  JamChatLine _chatLine(Map item) {
    final reply = item['reply_to'];
    return JamChatLine(
      id: item['id']?.toString() ?? '',
      userId: item['user_id']?.toString() ?? '',
      userName: item['user_name']?.toString() ?? '',
      isHost: item['is_host'] == true,
      text: item['text']?.toString() ?? '',
      timestamp: _int(item['timestamp']),
      replyTo: reply is Map
          ? JamReply(
              id: reply['id']?.toString() ?? '',
              userName: reply['user_name']?.toString() ?? '',
              text: reply['text']?.toString() ?? '',
            )
          : null,
    );
  }

  void _applyPlayback(Map<String, dynamic> action) {
    final trackRaw = action['track'];
    final track = trackRaw is Map
        ? JamTrack.fromJson(
            trackRaw.map((k, v) => MapEntry(k.toString(), v)))
        : _state.track;
    final playing = action['is_playing'] == true;
    _state = _state.copyWith(
      isPlaying: playing,
      track: track,
    );
    final from = action['from_user_id']?.toString();
    final position = _int(action['position_ms']);
    switch (action['action']?.toString()) {
      case 'play':
        _remote.add(JamRemotePlay(
          position,
          _int(action['server_time_ms']),
          from,
        ));
      case 'pause':
        _remote.add(JamRemotePause(position, from));
      case 'seek':
        _remote.add(JamRemoteSeek(position, from));
      case 'change_track':
        if (track != null && track.id.isNotEmpty) {
          _remote.add(JamRemoteTrack(track, playing, position, from));
        }
    }
  }

  List<JamPerson> _people(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          JamPerson(
            userId: item['user_id']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            isHost: item['is_host'] == true,
            isCoHost: item['is_cohost'] == true,
          ),
    ];
  }

  List<JamChatLine> _chat(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map) _chatLine(item.map((k, v) => MapEntry('$k', v))),
    ];
  }

  List<JamTrack> _tracks(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          JamTrack.fromJson(item.map((k, v) => MapEntry('$k', v))),
    ];
  }

  /// Locks pause/skip until [untilMs] and unlocks them automatically.
  void _startCooldown(int untilMs) {
    final wait = untilMs - DateTime.now().millisecondsSinceEpoch;
    if (wait <= 0) return;
    _state = _state.copyWith(cooldownUntilMs: untilMs);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(Duration(milliseconds: wait + 100), () {
      if (_state.cooldownUntilMs == untilMs) {
        _state = _state.copyWith(cooldownUntilMs: 0);
        notifyListeners();
      }
    });
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  void _send(String type, Map<String, dynamic>? payload) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.sink.add(jsonEncode({'type': type, 'payload': payload}));
    } catch (_) {}
  }

  Future<void> _close({required bool clear}) async {
    _ping?.cancel();
    _ping = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.sink.close(1000, 'Normal closure');
      } catch (_) {}
    }
    if (clear) {
      _state = const JamSnapshot();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _generation++;
    _ping?.cancel();
    try {
      _socket?.sink.close();
    } catch (_) {}
    _remote.close();
    super.dispose();
  }
}


/// App-scoped Jam holder: one controller + one sync bridge for the whole
/// app (the reference keeps both in its root provider scope, so rooms
/// survive navigation and the page being closed).
class JamService {
  JamService._();

  static final JamService instance = JamService._();

  final JamController controller = JamController();
  final JamPlaybackSync _sync = JamPlaybackSync.instance;
  bool _started = false;

  /// Called once from both entry points after MediaPlayer is registered.
  void start(MediaPlayer player) {
    if (_started) return;
    _started = true;
    _sync.start(controller: controller, player: player);
  }
}
