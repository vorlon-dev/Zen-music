import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../main.dart';
import '../models/song.dart';

/// Listen Together client for the metroserver protocol.
/// Wire format pinned to the deployed server source:
///   binary WS frames = protobuf Envelope{1:type str, 2:payload bytes, 3:compressed bool}
///   payloads = raw protobuf, gzip when compressed=true
///   handshake: connect → client_capabilities → server_capabilities
/// Outgoing payloads are hand-encoded against pinned field numbers;
/// incoming payloads are hand-decoded with a minimal proto wire reader.
/// No generated protobuf code.
class ListenTogetherService {
  ListenTogetherService._();
  static final ListenTogetherService instance = ListenTogetherService._();

  static const _wsUrl = 'wss://zen-listen-together.antideploy.com/ws';
  static const _clientVersion = 'ZenMusic/1.0';
  static const _pingInterval = Duration(seconds: 25);
  static const _pongTimeout = Duration(seconds: 75);
  static const _maxReconnectAttempts = 5;
  static const _driftToleranceMs = 1500;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Song?>? _songSub;
  StreamSubscription<Duration>? _posSub;

  bool _userDisconnect = false;
  bool _handshaken = false;
  int _reconnectAttempts = 0;
  int _pingSeq = 0;
  int _lastPongAt = 0;
  int _serverOffsetMs = 0;
  int _applyingRemote = 0;
  bool _lastPlaying = false;
  String? _lastBroadcastSongId;
  int _lastPositionMs = 0;

  // Guest-side apply chain: remote actions run strictly one after
  // another, so a 'play' can never race ahead of its 'change_track' load.
  Future<void> _applyChain = Future<void>.value();

  String? _userId;
  String? _sessionToken;
  String? _roomCode;
  bool _isHost = false;
  String _username = 'User';

  Completer<String?>? _pendingCreate;
  Completer<bool>? _pendingJoin;

  LtPhase _phase = LtPhase.disconnected;
  LtRoomSnapshot? _room;

  final ValueNotifier<LtPhase> phaseNotifier =
  ValueNotifier<LtPhase>(LtPhase.disconnected);
  final ValueNotifier<LtRoomSnapshot?> roomNotifier =
  ValueNotifier<LtRoomSnapshot?>(null);
  final _events = StreamController<LtEvent>.broadcast();

  Stream<LtEvent> get events => _events.stream;
  LtPhase get phase => _phase;
  LtRoomSnapshot? get room => _room;
  bool get isHost => _isHost;
  bool get isInRoom => _roomCode != null;
  String? get roomCode => _roomCode;

  // ═══════════════════════════════════════════
  // CONNECTION
  // ═══════════════════════════════════════════

  Future<void> connect() async {
    if (_channel != null) return;
    _userDisconnect = false;
    _setPhase(LtPhase.connecting);

    final channel = IOWebSocketChannel.connect(
      Uri.parse(_wsUrl),
      headers: const {'User-Agent': _clientVersion},
    );
    _channel = channel;
    _wsSub = channel.stream.listen(
      _onData,
      onDone: _onSocketDone,
      onError: (_) => _onSocketDone(),
    );

    // Capabilities must be the first message (server enforces this).
    _send('client_capabilities', {
      'supports_protobuf': true,
      'supports_compression': true,
      'client_version': _clientVersion,
    });

    _startPing();
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    if (isInRoom && _channel != null) {
      _send('leave_room', null);
      await Future.delayed(const Duration(milliseconds: 150));
    }
    _teardown();
    _setPhase(LtPhase.disconnected);
  }

  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _playingSub?.cancel();
    _playingSub = null;
    _songSub?.cancel();
    _songSub = null;
    _posSub?.cancel();
    _posSub = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _handshaken = false;
    _userId = null;
    _sessionToken = null;
    _roomCode = null;
    _isHost = false;
    _room = null;
    roomNotifier.value = null;
    _lastBroadcastSongId = null;
    _pendingCreate = null;
    _pendingJoin = null;
  }

  // ═══════════════════════════════════════════
  // ROOM OPERATIONS
  // ═══════════════════════════════════════════

  Future<String?> createRoom(String username) async {
    await connect();
    _username = username;
    final completer = Completer<String?>();
    _pendingCreate = completer;
    _send('create_room', {'username': username});
    return completer.future.timeout(const Duration(seconds: 15),
        onTimeout: () => null);
  }

  Future<bool> joinRoom(String roomCode, String username) async {
    await connect();
    _username = username;
    final completer = Completer<bool>();
    _pendingJoin = completer;
    _send('join_room', {
      'room_code': roomCode.trim().toUpperCase(),
      'username': username,
    });
    return completer.future.timeout(const Duration(seconds: 30),
        onTimeout: () => false);
  }

  void approveJoin(String userId) =>
      _send('approve_join', {'user_id': userId});

  void rejectJoin(String userId, {String? reason}) =>
      _send('reject_join', {'user_id': userId, 'reason': reason ?? ''});

  void kickUser(String userId, {String? reason}) =>
      _send('kick_user', {'user_id': userId, 'reason': reason ?? ''});

  void transferHost(String newHostId) =>
      _send('transfer_host', {'new_host_id': newHostId});

  void leaveRoom() => disconnect();

  // ═══════════════════════════════════════════
  // HOST API
  // ═══════════════════════════════════════════

  void hostSeek(int positionMs) =>
      _sendAction('seek', positionMs: positionMs);

  void suggestTrack(Song song) =>
      _send('suggest_track', {'track_info': _trackMap(song)});

  void approveSuggestion(String suggestionId) =>
      _send('approve_suggestion', {'suggestion_id': suggestionId});

  void rejectSuggestion(String suggestionId, {String? reason}) =>
      _send('reject_suggestion',
          {'suggestion_id': suggestionId, 'reason': reason ?? ''});

  // ═══════════════════════════════════════════
  // SEND — envelope + hand-encoded payloads
  // ═══════════════════════════════════════════

  void _send(String type, Map<String, dynamic>? payloadJson) {
    final channel = _channel;
    if (channel == null) return;

    final Uint8List payloadBytes;
    switch (type) {
      case 'client_capabilities':
        final w = PbWriter();
        w.boolField(1, true);
        w.boolField(2, true);
        w.stringField(3, _clientVersion);
        payloadBytes = w.toBytes();
        break;
      case 'create_room':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['username'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'join_room':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['room_code'] ?? ''}');
        w.stringField(2, '${payloadJson?['username'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'approve_join':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'reject_join':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'kick_user':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'transfer_host':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['new_host_id'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'suggest_track':
        final w = PbWriter();
        w.messageField(1,
            _encodeTrackInfo((payloadJson?['track_info'] ?? const {}) as Map));
        payloadBytes = w.toBytes();
        break;
      case 'approve_suggestion':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['suggestion_id'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'reject_suggestion':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['suggestion_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'buffer_ready':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['track_id'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'ping':
        final w = PbWriter();
        w.int64Field(1, DateTime.now().millisecondsSinceEpoch);
        w.int64Field(2, ++_pingSeq);
        payloadBytes = w.toBytes();
        break;
      case 'reconnect':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['session_token'] ?? ''}');
        payloadBytes = w.toBytes();
        break;
      case 'request_sync':
        payloadBytes = Uint8List(0); // no payload
        break;
      case 'leave_room':
        payloadBytes = Uint8List(0);
        break;
      case 'playback_action':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['action'] ?? ''}');
        final trackId = payloadJson?['track_id'] as String?;
        if (trackId != null && trackId.isNotEmpty) {
          w.stringField(2, trackId);
        }
        final pos = (payloadJson?['position'] as int?) ?? 0;
        if (pos > 0) w.int64Field(3, pos);
        final track = payloadJson?['track'] as Map?;
        if (track != null) {
          w.messageField(4, _encodeTrackInfo(track));
        }
        if ((payloadJson?['insert_next'] as bool?) == true) {
          w.boolField(5, true);
        }
        final queue = payloadJson?['queue'] as List?;
        if (queue != null) {
          for (final t in queue) {
            if (t is Map) w.messageField(6, _encodeTrackInfo(t));
          }
        }
        final queueTitle = payloadJson?['queue_title'] as String?;
        if (queueTitle != null && queueTitle.isNotEmpty) {
          w.stringField(7, queueTitle);
        }
        w.floatField(8, 1.0);
        final serverTime = (payloadJson?['server_time'] as int?) ?? 0;
        if (serverTime > 0) w.int64Field(9, serverTime);
        final captured = (payloadJson?['captured_at_server_time'] as int?) ?? 0;
        if (captured > 0) w.int64Field(11, captured);
        payloadBytes = w.toBytes();
        break;
      default:
        payloadBytes = Uint8List(0);
        break;
    }

    channel.sink.add(PbCodec.encodeEnvelope(type, payloadBytes));
  }

  void _sendAction(String action,
      {String? trackId,
        int positionMs = 0,
        Song? track,
        List<Song>? queue,
        bool insertNext = false,
        String? queueTitle}) {
    _send('playback_action', {
      'action': action,
      if (trackId != null) 'track_id': trackId,
      'position': positionMs,
      if (track != null)
        'track': {
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'thumbnail': track.thumbnail,
          'duration': track.duration.inMilliseconds,
        },
      if (insertNext) 'insert_next': true,
      if (queue != null)
        'queue': [
          for (final s in queue)
            {
              'id': s.id,
              'title': s.title,
              'artist': s.artist,
              'thumbnail': s.thumbnail,
              'duration': s.duration.inMilliseconds,
            },
        ],
      if (queueTitle != null) 'queue_title': queueTitle,
      'server_time': _serverNow(),
      'captured_at_server_time': _serverNow(),
    });
  }

  Map<String, dynamic> _trackMap(Song s) => {
    'id': s.id,
    'title': s.title,
    'artist': s.artist,
    'thumbnail': s.thumbnail,
    'duration': s.duration.inMilliseconds,
  };

  // TrackInfo: 1 id 2 title 3 artist 4 album 5 duration 6 thumbnail 7 suggested_by
  Uint8List _encodeTrackInfo(Map t) {
    final w = PbWriter();
    w.stringField(1, '${t['id'] ?? ''}');
    w.stringField(2, '${t['title'] ?? ''}');
    w.stringField(3, '${t['artist'] ?? ''}');
    w.stringField(4, '${t['album'] ?? ''}');
    final dur = (t['duration'] as num?)?.toInt() ?? 0;
    if (dur > 0) w.int64Field(5, dur);
    w.stringField(6, '${t['thumbnail'] ?? ''}');
    w.stringField(7, '${t['suggested_by'] ?? ''}');
    return w.toBytes();
  }

  int _serverNow() =>
      DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  // ═══════════════════════════════════════════
  // INCOMING — per-message isolation
  // ═══════════════════════════════════════════

  void _onData(dynamic data) {
    Uint8List bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else {
      return; // text frames are not part of the protocol
    }

    final env = PbCodec.decodeEnvelope(bytes);
    var payload = env.payload;
    if (env.compressed && payload.isNotEmpty) {
      try {
        payload = Uint8List.fromList(gzip.decode(payload));
      } catch (e) {
        print('🎧 LT: gzip decode failed for ${env.type} '
            '(${payload.length}B): $e');
        return;
      }
    }

    // Per-message isolation: a malformed frame must never kill the
    // socket or strand the UI mid-join.
    try {
      _dispatch(env.type, payload);
    } catch (e) {
      final hex = payload
          .take(32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print('🎧 LT: failed to parse "${env.type}" (${payload.length}B) '
          'hex[$hex]: $e');

      // Room-entry fallbacks: the envelope type itself is reliable even
      // when payload parsing desyncs. Enter the room; the server will
      // re-deliver state via sync_state / sync_playback.
      switch (env.type) {
        case 'room_created':
          var code = '';
          try {
            final r = PbReader(payload);
            if (r.hasNext()) {
              final t = r.readTag();
              if (t.$1 == 1 && t.$2 == 2) {
                code = utf8.decode(r.readBytesRaw());
              }
            }
          } catch (_) {}
          _sessionToken ??= '';
          _roomCode = code;
          _isHost = true;
          _room = LtRoomSnapshot(
            roomCode: code,
            hostId: _userId ?? '',
            users: [
              LtUser(
                  userId: _userId ?? '',
                  username: _username,
                  isHost: true,
                  isConnected: true)
            ],
            isPlaying: false,
            positionMs: 0,
            queue: const [],
          );
          roomNotifier.value = _room;
          _setPhase(LtPhase.inRoom);
          _rebindHostBroadcast();
          _pendingCreate?.complete(code.isNotEmpty ? code : 'unknown');
          _pendingCreate = null;
          break;
        case 'join_approved':
          _isHost = false;
          _setPhase(LtPhase.inRoom);
          _pendingJoin?.complete(true);
          _pendingJoin = null;
          // Ask the server for the current state — it answers with
          // sync_state, which re-establishes queue + position.
          _send('request_sync', null);
          break;
        default:
          break;
      }
    }
  }

  void _dispatch(String type, Uint8List payload) {
    switch (type) {
      case 'server_capabilities':
        _handshaken = true;
        _setPhase(LtPhase.connected);
        break;
      case 'room_created':
        final r = PbReader(payload);
        final roomCode = r.readString(1);
        final userId = r.readString(2);
        final token = r.readString(3);
        _userId = userId;
        _sessionToken = token;
        _roomCode = roomCode;
        _isHost = true;
        _room = LtRoomSnapshot(
          roomCode: roomCode,
          hostId: userId,
          users: [
            LtUser(
                userId: userId,
                username: _username,
                isHost: true,
                isConnected: true)
          ],
          isPlaying: false,
          positionMs: 0,
          queue: const [],
        );
        roomNotifier.value = _room;
        _setPhase(LtPhase.inRoom);
        _rebindHostBroadcast();
        _pendingCreate?.complete(roomCode);
        _pendingCreate = null;
        break;
      case 'join_approved':
        final r = PbReader(payload);
        final roomCode = r.readString(1);
        final userId = r.readString(2);
        final token = r.readString(3);
        final stateBytes = r.readBytes(4);
        _userId = userId;
        _sessionToken = token;
        _roomCode = roomCode;
        _isHost = false;
        final state = parseRoomState(stateBytes);
        if (state != null) {
          _applyRoomState(state);
          // Load the room's track right away — a guest joining mid-song
          // hears it immediately, no waiting for sync_state.
          unawaited(_adoptRoomState(state));
        }
        _setPhase(LtPhase.inRoom);
        // Pull authoritative state — re-aligns position/play state.
        _send('request_sync', null);
        _pendingJoin?.complete(true);
        _pendingJoin = null;
        break;
      case 'join_rejected':
        final r = PbReader(payload);
        final reason = r.readString(1);
        _pendingJoin?.complete(false);
        _pendingJoin = null;
        _events.add(LtErrorEvent('join_rejected', reason));
        break;
      case 'join_request':
        final r = PbReader(payload);
        final uid = r.readString(1);
        final uname = r.readString(2);
        if (_isHost) _events.add(LtJoinRequestEvent(uid, uname));
        break;
      case 'user_joined':
        final p = readUserIdName(payload);
        _patchUser(p.$1, p.$2, isHost: false, connected: true);
        _events.add(LtUserEvent(p.$1, p.$2, LtUserEventKind.joined));
        break;
      case 'user_left':
        final p = readUserIdName(payload);
        _removeUser(p.$1);
        _events.add(LtUserEvent(p.$1, p.$2, LtUserEventKind.left));
        break;
      case 'user_disconnected':
        final p = readUserIdName(payload);
        _patchConnected(p.$1, false);
        break;
      case 'user_reconnected':
        final p = readUserIdName(payload);
        _patchConnected(p.$1, true);
        break;
      case 'sync_playback':
        if (_isHost) break;
        final action = parsePlaybackAction(payload);
        print('🎧 LT: sync_playback ${action.action} track=${action.trackId}');
        _enqueueApply(() => _applyPlaybackAction(action));
        break;
      case 'sync_state':
        if (_isHost) break;
        final st = parseSyncState(payload);
        print('🎧 LT: sync_state track=${st.track?['id']} playing=${st.isPlaying}');
        _enqueueApply(() => _applySyncState(st));
        break;
      case 'buffer_wait':
        final r = PbReader(payload);
        final trackId = r.readString(1);
        if (audioHandler.currentSong?.id == trackId) {
          _send('buffer_ready', {'track_id': trackId});
        }
        break;
      case 'buffer_complete':
        break;
      case 'host_changed':
        final r = PbReader(payload);
        final hostId = r.readString(1);
        final hostName = r.readString(2);
        _isHost = hostId == _userId;
        _patchHost(hostId);
        _events.add(LtHostChangedEvent(hostId, hostName));
        _rebindHostBroadcast();
        break;
      case 'kicked':
        final r = PbReader(payload);
        final reason = r.readString(1);
        _events.add(LtKickedEvent(reason));
        _teardown();
        _setPhase(LtPhase.disconnected);
        break;
      case 'pong':
        final r = PbReader(payload);
        final clientTime = r.readInt(1);
        final recvTime = r.readInt(2);
        final sendTime = r.readInt(3);
        final now = DateTime.now().millisecondsSinceEpoch;
        final rtt = now - clientTime;
        if (rtt >= 0 && clientTime > 0) {
          _serverOffsetMs =
              ((recvTime - (clientTime + rtt ~/ 2)) + (sendTime - now)) ~/
                  2;
        }
        _lastPongAt = now;
        break;
      case 'error':
        final r = PbReader(payload);
        final code = r.readString(1);
        final message = r.readString(2);
        if (code == 'join_rejected') {
          _pendingJoin?.complete(false);
          _pendingJoin = null;
        }
        _events.add(LtErrorEvent(code, message));
        break;
      case 'suggestion_received':
        final r = PbReader(payload);
        final sid = r.readString(1);
        r.readString(2); // from_user_id
        final fromName = r.readString(3);
        final trackBytes = r.readBytes(4);
        if (_isHost && trackBytes.isNotEmpty) {
          final t = parseTrackInfo(trackBytes);
          _events.add(LtSuggestionEvent(sid, fromName, mapToSong(t)));
        }
        break;
      case 'suggestion_approved':
        final r = PbReader(payload);
        final sid = r.readString(1);
        final trackBytes = r.readBytes(2);
        if (trackBytes.isNotEmpty) {
          final t = parseTrackInfo(trackBytes);
          _events.add(LtSuggestionApprovedEvent(sid, mapToSong(t)));
        }
        break;
      case 'reconnected':
        final r = PbReader(payload);
        final roomCode = r.readString(1);
        final userId = r.readString(2);
        final stateBytes = r.readBytes(3);
        final isHost = r.readInt(4) != 0;
        _roomCode = roomCode;
        _userId = userId;
        _isHost = isHost;
        final state = parseRoomState(stateBytes);
        if (state != null) _applyRoomState(state);
        _setPhase(LtPhase.inRoom);
        _rebindHostBroadcast();
        break;
      default:
        break;
    }
  }

  void _enqueueApply(Future<void> Function() task) {
    _applyChain = _applyChain.then((_) async {
      try {
        await task();
      } catch (e) {
        print('🎧 ListenTogether apply failed: $e');
      }
    });
  }

  // ═══════════════════════════════════════════
  // GUEST APPLICATION
  // ═══════════════════════════════════════════

  Future<void> _adoptRoomState(LtRoomSnapshot state) async {
    final track = state.currentTrack;
    if (track == null || track.id.isEmpty) return;
    if (audioHandler.currentSong?.id == track.id) return;
    _applyingRemote++;
    try {
      var queue = state.queue;
      var index = queue.indexWhere((s) => s.id == track.id);
      if (index < 0) {
        queue = [track, ...queue];
        index = 0;
      }
      print('🎧 LT: adopting room track ${track.id} "${track.title}"');
      await audioHandler.setQueue(queue, startIndex: index);
      if (!state.isPlaying) await audioHandler.pause();
      _send('buffer_ready', {'track_id': track.id});
    } catch (e) {
      print('🎧 LT: adopt room state failed: $e');
    } finally {
      _applyingRemote--;
    }
  }

  Future<void> _applyPlaybackAction(LtPlaybackAction p) async {
    _applyingRemote++;
    try {
      switch (p.action) {
        case 'play':
          await _ensureTrack(p);
          final target =
          effectivePosition(p.positionMs, p.capturedAtServerTime, true);
          await _seekIfNeeded(target);
          await audioHandler.play();
          break;
        case 'pause':
          await _ensureTrack(p);
          final target =
          effectivePosition(p.positionMs, p.capturedAtServerTime, false);
          await _seekIfNeeded(target);
          await audioHandler.pause();
          break;
        case 'seek':
          await _ensureTrack(p);
          await audioHandler.seek(Duration(milliseconds: p.positionMs));
          break;
        case 'change_track':
          await _applyTrackChange(p, autoplay: true);
          break;
        case 'skip_next':
        case 'skip_prev':
          break; // the follow-up change_track carries the real track
        case 'sync_queue':
        case 'queue_add':
        case 'queue_remove':
        case 'queue_clear':
          await _applyQueue(p.queue);
          break;
        default:
          break;
      }
    } catch (e) {
      print('🎧 ListenTogether apply failed: $e');
      // Never leave the server's buffer gate waiting on a failed apply.
      if (p.trackId.isNotEmpty) {
        _send('buffer_ready', {'track_id': p.trackId});
      }
    } finally {
      _applyingRemote--;
    }
  }

  Future<void> _applySyncState(LtSyncState p) async {
    _applyingRemote++;
    try {
      final trackId = p.track?['id']?.toString() ?? '';
      final currentId = audioHandler.currentSong?.id ?? '';
      if (trackId.isNotEmpty && currentId != trackId) {
        final song = mapToSong(p.track!);
        final queue = [for (final t in p.queue) mapToSong(t)];
        var index = queue.indexWhere((s) => s.id == trackId);
        if (index < 0) {
          queue.insert(0, song);
          index = 0;
        }
        print('🎧 LT: loading track ${song.id} "${song.title}"');
        await audioHandler.setQueue(queue, startIndex: index);
        if (!p.isPlaying) await audioHandler.pause();
        _patchCurrentTrack(song);
        _send('buffer_ready', {'track_id': trackId});
      }
      final target = effectivePosition(p.positionMs, p.lastUpdate, p.isPlaying);
      await _seekIfNeeded(target);
      if (p.isPlaying) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
    } catch (e) {
      print('🎧 ListenTogether sync failed: $e');
    } finally {
      _applyingRemote--;
    }
  }

  Future<void> _applyTrackChange(LtPlaybackAction p,
      {required bool autoplay}) async {
    final track = p.track;
    if (track == null) return;
    final song = mapToSong(track);
    if (audioHandler.currentSong?.id == song.id) {
      // Already on this track — never restart it; just align play state.
      if (autoplay) {
        await audioHandler.play();
      } else {
        await audioHandler.pause();
      }
      _patchCurrentTrack(song);
      _send('buffer_ready', {'track_id': song.id});
      return;
    }
    var queue = [for (final t in p.queue) mapToSong(t)];
    var index = queue.indexWhere((s) => s.id == song.id);
    if (index < 0) {
      queue = [song, ...queue];
      index = 0;
    }
    print('🎧 LT: loading track ${song.id} "${song.title}"');
    await audioHandler.setQueue(queue, startIndex: index);
    // The host switched songs — mirror its play state explicitly.
    // setQueue alone must not be relied on to start playback.
    if (autoplay) {
      await audioHandler.play();
    } else {
      await audioHandler.pause();
    }
    _patchCurrentTrack(song);
    _send('buffer_ready', {'track_id': song.id});
  }

  Future<void> _applyQueue(List<Map<String, dynamic>> protoQueue) async {
    final queue = [for (final t in protoQueue) mapToSong(t)];
    if (queue.isEmpty) return;
    final currentId = audioHandler.currentSong?.id;
    var index = queue.indexWhere((s) => s.id == currentId);
    if (index < 0) index = 0;
    await audioHandler.setQueue(queue, startIndex: index);
  }

  Future<void> _ensureTrack(LtPlaybackAction p) async {
    final trackId = p.trackId;
    if (trackId.isEmpty) return;
    if (audioHandler.currentSong?.id == trackId) return;
    await _applyTrackChange(p, autoplay: false);
  }

  Future<void> _seekIfNeeded(int targetMs) async {
    if (targetMs <= 0) return;
    final current = _lastPositionMs;
    if ((current - targetMs).abs() > _driftToleranceMs) {
      await audioHandler.seek(Duration(milliseconds: targetMs));
    }
  }

  int effectivePosition(int position, int capturedAt, bool playing) {
    if (position <= 0 || !playing) return position;
    if (capturedAt <= 0) return position;
    final elapsed = _serverNow() - capturedAt;
    if (elapsed < 0 || elapsed > 60000) return position;
    return position + elapsed;
  }

  // ═══════════════════════════════════════════
  // HOST AUTO-BROADCAST
  // ═══════════════════════════════════════════

  void _rebindHostBroadcast() {
    _playingSub?.cancel();
    _songSub?.cancel();
    _posSub?.cancel();
    // Guests track position too, so drift correction compares real values.
    _posSub = audioHandler.positionStream.listen((p) {
      _lastPositionMs = p.inMilliseconds;
    });
    if (!_isHost || !isInRoom) return;

    _lastPlaying = audioHandler.playbackState.value.playing;

    _playingSub = audioHandler.playingStream.listen((playing) {
      if (!_isHost || _applyingRemote > 0) return;
      if (playing == _lastPlaying) return;
      _lastPlaying = playing;
      _sendAction(
        playing ? 'play' : 'pause',
        trackId: audioHandler.currentSong?.id,
        positionMs: _lastPositionMs,
      );
    });

    _songSub = audioHandler.currentSongStream.listen((song) {
      if (!_isHost || _applyingRemote > 0 || song == null) return;
      if (song.id == _lastBroadcastSongId) return;
      _lastBroadcastSongId = song.id;
      _sendAction(
        'change_track',
        trackId: song.id,
        track: song,
        queue: audioHandler.queueSongs,
        queueTitle: 'Listen Together',
      );
      _patchCurrentTrack(song);
      // The playing-state listener dedups unchanged values, so a track
      // change while already playing would never send 'play' on its own —
      // always follow the track change with the host's actual state.
      final playing = audioHandler.playbackState.value.playing;
      _lastPlaying = playing;
      _sendAction(
        playing ? 'play' : 'pause',
        trackId: song.id,
        positionMs: _lastPositionMs,
      );
    });

    // If the host already had a song loaded before the room existed, the
    // current-song stream may never fire again — push it once now.
    final current = audioHandler.currentSong;
    if (current != null && current.id != _lastBroadcastSongId) {
      _lastBroadcastSongId = current.id;
      _sendAction(
        'change_track',
        trackId: current.id,
        track: current,
        queue: audioHandler.queueSongs,
        queueTitle: 'Listen Together',
      );
      _patchCurrentTrack(current);
      final playing = audioHandler.playbackState.value.playing;
      _lastPlaying = playing;
      _sendAction(
        playing ? 'play' : 'pause',
        trackId: current.id,
        positionMs: _lastPositionMs,
      );
    }
  }

  // ═══════════════════════════════════════════
  // ROOM STATE HELPERS
  // ═══════════════════════════════════════════

  void _patchCurrentTrack(Song song) {
    final r = _room;
    if (r == null) return;
    if (r.currentTrack?.id == song.id) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: r.hostId,
      users: r.users,
      currentTrack: song,
      isPlaying: r.isPlaying,
      positionMs: r.positionMs,
      lastUpdateMs: r.lastUpdateMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

  void _patchUser(String userId, String username,
      {required bool isHost, required bool connected}) {
    final r = _room;
    if (r == null) return;
    if (r.users.any((u) => u.userId == userId)) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: r.hostId,
      users: [
        ...r.users,
        LtUser(
            userId: userId,
            username: username,
            isHost: isHost,
            isConnected: connected),
      ],
      currentTrack: r.currentTrack,
      isPlaying: r.isPlaying,
      positionMs: r.positionMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

  void _patchConnected(String userId, bool connected) {
    final r = _room;
    if (r == null) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: r.hostId,
      users: r.users
          .map((u) => u.userId == userId
          ? LtUser(
          userId: u.userId,
          username: u.username,
          isHost: u.isHost,
          isConnected: connected)
          : u)
          .toList(),
      currentTrack: r.currentTrack,
      isPlaying: r.isPlaying,
      positionMs: r.positionMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

  void _removeUser(String userId) {
    final r = _room;
    if (r == null) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: r.hostId,
      users: r.users.where((u) => u.userId != userId).toList(),
      currentTrack: r.currentTrack,
      isPlaying: r.isPlaying,
      positionMs: r.positionMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

  void _patchHost(String hostId) {
    final r = _room;
    if (r == null) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: hostId,
      users: r.users
          .map((u) => LtUser(
        userId: u.userId,
        username: u.username,
        isHost: u.userId == hostId,
        isConnected: u.isConnected,
      ))
          .toList(),
      currentTrack: r.currentTrack,
      isPlaying: r.isPlaying,
      positionMs: r.positionMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

  void _applyRoomState(LtRoomSnapshot? state) {
    if (state == null) return;
    _room = state;
    roomNotifier.value = state;
  }

  // ═══════════════════════════════════════════
  // KEEPALIVE + RECONNECT
  // ═══════════════════════════════════════════

  void _startPing() {
    _pingTimer?.cancel();
    _lastPongAt = DateTime.now().millisecondsSinceEpoch;
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_channel == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastPongAt > _pongTimeout.inMilliseconds) {
        print('🎧 ListenTogether: pong timeout — reconnecting');
        _reconnectAfterDrop();
        return;
      }
      _send('ping', null);
    });
  }

  void _onSocketDone() {
    if (_userDisconnect) return;
    _reconnectAfterDrop();
  }

  void _reconnectAfterDrop() {
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _handshaken = false;

    if (_userDisconnect) return;
    if (_sessionToken == null || _reconnectAttempts >= _maxReconnectAttempts) {
      _events.add(LtErrorEvent('disconnected', 'Connection lost'));
      _teardown();
      _setPhase(LtPhase.disconnected);
      return;
    }
    _reconnectAttempts++;
    _setPhase(LtPhase.reconnecting);
    _reconnectTimer = Timer(Duration(seconds: 2 * _reconnectAttempts), () async {
      await connect();
      if (_sessionToken != null && _handshaken) {
        _send('reconnect', {'session_token': _sessionToken});
      }
    });
  }

  void _setPhase(LtPhase p) {
    if (_phase == p) return;
    _phase = p;
    phaseNotifier.value = p;
    if (p == LtPhase.inRoom) {
      _reconnectAttempts = 0;
    }
  }
}

// ═══════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════

enum LtPhase { disconnected, connecting, connected, inRoom, reconnecting }

class LtUser {
  LtUser({
    required this.userId,
    required this.username,
    required this.isHost,
    required this.isConnected,
  });

  final String userId;
  final String username;
  final bool isHost;
  final bool isConnected;
}

class LtRoomSnapshot {
  LtRoomSnapshot({
    required this.roomCode,
    required this.hostId,
    required this.users,
    this.currentTrack,
    required this.isPlaying,
    required this.positionMs,
    this.lastUpdateMs = 0,
    required this.queue,
    this.revision = 0,
  });

  final String roomCode;
  final String hostId;
  final List<LtUser> users;
  final Song? currentTrack;
  final bool isPlaying;
  final int positionMs;
  final int lastUpdateMs;
  final List<Song> queue;
  final int revision;
}

class LtPlaybackAction {
  String action = '';
  String trackId = '';
  int positionMs = 0;
  Map<String, dynamic>? track;
  final List<Map<String, dynamic>> queue = [];
  int serverTime = 0;
  int capturedAtServerTime = 0;
}

class LtSyncState {
  Map<String, dynamic>? track;
  bool isPlaying = false;
  int positionMs = 0;
  int lastUpdate = 0;
  final List<Map<String, dynamic>> queue = [];
}

sealed class LtEvent {
  const LtEvent();
}

class LtJoinRequestEvent extends LtEvent {
  LtJoinRequestEvent(this.userId, this.username);
  final String userId;
  final String username;
}

class LtUserEvent extends LtEvent {
  LtUserEvent(this.userId, this.username, this.kind);
  final String userId;
  final String username;
  final LtUserEventKind kind;
}

enum LtUserEventKind { joined, left }

class LtHostChangedEvent extends LtEvent {
  LtHostChangedEvent(this.newHostId, this.newHostName);
  final String newHostId;
  final String newHostName;
}

class LtKickedEvent extends LtEvent {
  LtKickedEvent(this.reason);
  final String reason;
}

class LtErrorEvent extends LtEvent {
  LtErrorEvent(this.code, this.message);
  final String code;
  final String message;
}

class LtSuggestionEvent extends LtEvent {
  LtSuggestionEvent(this.suggestionId, this.fromUsername, this.song);
  final String suggestionId;
  final String fromUsername;
  final Song song;
}

class LtSuggestionApprovedEvent extends LtEvent {
  LtSuggestionApprovedEvent(this.suggestionId, this.song);
  final String suggestionId;
  final Song song;
}

// ═══════════════════════════════════════════
// PROTO WIRE — writer + reader + envelope codec
// (hand-rolled against the pinned field numbers; no generated code)
// ═══════════════════════════════════════════

class PbWriter {
  final _data = BytesBuilder(copy: false);

  void _tag(int field, int wireType) => _varint((field << 3) | wireType);

  void _varint(int value) {
    var v = value & 0xFFFFFFFFFFFFFFFF;
    while (v > 0x7F) {
      _data.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    _data.addByte(v);
  }

  void _bytes(List<int> bytes) {
    _varint(bytes.length);
    _data.add(bytes);
  }

  void stringField(int field, String value) {
    if (value.isEmpty) return;
    _tag(field, 2);
    _bytes(utf8.encode(value));
  }

  void boolField(int field, bool value) {
    if (!value) return; // proto3 default — omitted
    _tag(field, 0);
    _varint(1);
  }

  void int64Field(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _varint(value);
  }

  void floatField(int field, double value) {
    _tag(field, 5);
    // fixed32 = 4 raw little-endian bytes, NO length prefix
    final b = ByteData(4)..setFloat32(0, value, Endian.little);
    _data.add(b.buffer.asUint8List());
  }

  void messageField(int field, List<int> inner) {
    _tag(field, 2);
    _bytes(inner);
  }

  Uint8List toBytes() => _data.takeBytes();
}

class PbCodec {
  // Envelope: 1 type(str) 2 payload(bytes) 3 compressed(bool)
  static Uint8List encodeEnvelope(String type, Uint8List payload) {
    final w = PbWriter();
    w.stringField(1, type);
    if (payload.isNotEmpty) w.messageField(2, payload);
    return w.toBytes();
  }

  static ({String type, Uint8List payload, bool compressed}) decodeEnvelope(
      Uint8List data) {
    final r = PbReader(data);
    var type = '';
    var payload = Uint8List(0);
    var compressed = false;
    while (r.hasNext()) {
      final t = r.readTag();
      switch (t.$1) {
        case 1:
          type = utf8.decode(r.readBytesRaw());
        case 2:
          payload = r.readBytesRaw();
        case 3:
          compressed = r.readIntField() != 0;
        default:
          r.skip(t.$2);
      }
    }
    return (type: type, payload: payload, compressed: compressed);
  }
}

class PbReader {
  PbReader(this._data);
  final Uint8List _data;
  int _pos = 0;

  bool hasNext() => _pos < _data.length;

  (int, int) readTag() {
    final key = _varint();
    return (key >> 3, key & 7);
  }

  int _varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _data.length) {
        throw const FormatException('proto varint overrun');
      }
      final b = _data[_pos++];
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) throw const FormatException('proto varint too long');
    }
    return result;
  }

  Uint8List readBytesRaw() {
    final len = _varint();
    if (len < 0 || _pos + len > _data.length) {
      throw const FormatException('proto length overrun');
    }
    final out = Uint8List.fromList(_data.sublist(_pos, _pos + len));
    _pos += len;
    return out;
  }

  String readString(int field) {
    final saved = _pos;
    while (hasNext()) {
      final t = readTag();
      if (t.$1 == field) {
        if (t.$2 != 2) throw const FormatException('wire mismatch');
        return utf8.decode(readBytesRaw());
      }
      skip(t.$2);
    }
    _pos = saved;
    return '';
  }

  int readInt(int field) {
    final saved = _pos;
    while (hasNext()) {
      final t = readTag();
      if (t.$1 == field) {
        if (t.$2 != 0) throw const FormatException('wire mismatch');
        return _varint();
      }
      skip(t.$2);
    }
    _pos = saved;
    return 0;
  }

  Uint8List readBytes(int field) {
    final saved = _pos;
    while (hasNext()) {
      final t = readTag();
      if (t.$1 == field) {
        if (t.$2 != 2) throw const FormatException('wire mismatch');
        return readBytesRaw();
      }
      skip(t.$2);
    }
    _pos = saved;
    return Uint8List(0);
  }

  bool readBool(int field) => readInt(field) != 0;

  int readIntField() => _varint();

  int readRawVarint() => _varint();

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        _varint();
      case 1:
        _pos += 8;
      case 2:
        final len = _varint();
        _pos += len;
      case 5:
        _pos += 4;
      default:
        throw FormatException('unsupported wire type $wireType');
    }
  }
}

// ── shared payload parsers (used by the service above) ──

LtPlaybackAction parsePlaybackAction(Uint8List payload) {
  final r = PbReader(payload);
  final p = LtPlaybackAction();
  while (r.hasNext()) {
    final t = r.readTag();
    switch (t.$1) {
      case 1:
        p.action = utf8.decode(r.readBytesRaw());
      case 2:
        p.trackId = utf8.decode(r.readBytesRaw());
      case 3:
        p.positionMs = r.readRawVarint();
      case 4:
        p.track = parseTrackInfo(r.readBytesRaw());
      case 6:
        p.queue.add(parseTrackInfo(r.readBytesRaw()));
      case 9:
        p.serverTime = r.readRawVarint();
      case 11:
        p.capturedAtServerTime = r.readRawVarint();
      default:
        r.skip(t.$2);
    }
  }
  return p;
}

LtSyncState parseSyncState(Uint8List payload) {
  final r = PbReader(payload);
  final p = LtSyncState();
  while (r.hasNext()) {
    final t = r.readTag();
    switch (t.$1) {
      case 1:
        p.track = parseTrackInfo(r.readBytesRaw());
      case 2:
        p.isPlaying = r.readRawVarint() != 0;
      case 3:
        p.positionMs = r.readRawVarint();
      case 4:
        p.lastUpdate = r.readRawVarint();
      case 5:
        p.queue.add(parseTrackInfo(r.readBytesRaw()));
      default:
        r.skip(t.$2);
    }
  }
  return p;
}

Map<String, dynamic> parseTrackInfo(Uint8List bytes) {
  final r = PbReader(bytes);
  final m = <String, dynamic>{};
  while (r.hasNext()) {
    final t = r.readTag();
    switch (t.$1) {
      case 1:
        m['id'] = utf8.decode(r.readBytesRaw());
      case 2:
        m['title'] = utf8.decode(r.readBytesRaw());
      case 3:
        m['artist'] = utf8.decode(r.readBytesRaw());
      case 4:
        m['album'] = utf8.decode(r.readBytesRaw());
      case 5:
        m['duration'] = r.readRawVarint();
      case 6:
        m['thumbnail'] = utf8.decode(r.readBytesRaw());
      case 7:
        m['suggested_by'] = utf8.decode(r.readBytesRaw());
      default:
        r.skip(t.$2);
    }
  }
  return m;
}

LtRoomSnapshot? parseRoomState(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  final r = PbReader(bytes);
  var roomCode = '';
  var hostId = '';
  var isPlaying = false;
  var positionMs = 0;
  var lastUpdate = 0;
  final users = <LtUser>[];
  Map<String, dynamic>? currentTrack;
  final queue = <Map<String, dynamic>>[];
  while (r.hasNext()) {
    final t = r.readTag();
    switch (t.$1) {
      case 1:
        roomCode = utf8.decode(r.readBytesRaw());
      case 2:
        hostId = utf8.decode(r.readBytesRaw());
      case 3:
        final u = parseUserInfo(r.readBytesRaw());
        if (u != null) users.add(u);
      case 4:
        currentTrack = parseTrackInfo(r.readBytesRaw());
      case 5:
        isPlaying = r.readRawVarint() != 0;
      case 6:
        positionMs = r.readRawVarint();
      case 7:
        lastUpdate = r.readRawVarint();
      case 9:
        queue.add(parseTrackInfo(r.readBytesRaw()));
      default:
        r.skip(t.$2);
    }
  }
  return LtRoomSnapshot(
    roomCode: roomCode,
    hostId: hostId,
    users: users,
    currentTrack: currentTrack == null ? null : mapToSong(currentTrack),
    isPlaying: isPlaying,
    positionMs: positionMs,
    lastUpdateMs: lastUpdate,
    queue: [for (final t in queue) mapToSong(t)],
  );
}

LtUser? parseUserInfo(Uint8List bytes) {
  final r = PbReader(bytes);
  var userId = '';
  var username = '';
  var isHost = false;
  var connected = true;
  while (r.hasNext()) {
    final t = r.readTag();
    switch (t.$1) {
      case 1:
        userId = utf8.decode(r.readBytesRaw());
      case 2:
        username = utf8.decode(r.readBytesRaw());
      case 3:
        isHost = r.readRawVarint() != 0;
      case 4:
        connected = r.readRawVarint() != 0;
      default:
        r.skip(t.$2);
    }
  }
  if (userId.isEmpty) return null;
  return LtUser(
      userId: userId, username: username, isHost: isHost, isConnected: connected);
}

(String, String) readUserIdName(Uint8List payload) {
  final r = PbReader(payload);
  final a = r.readString(1);
  final b = r.readString(2);
  return (a, b);
}

Song mapToSong(Map<String, dynamic> t) => Song(
  id: '${t['id'] ?? ''}',
  title: '${t['title'] ?? 'Unknown'}',
  artist: '${t['artist'] ?? 'Unknown'}',
  thumbnail: '${t['thumbnail'] ?? ''}',
  duration: Duration(milliseconds: ((t['duration'] as num?) ?? 0).toInt()),
);