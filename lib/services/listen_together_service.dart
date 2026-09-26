import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../main.dart';
import '../models/song.dart';

/// Listen Together client for the metroserver protocol.
/// Wire: protobuf Envelope{1:type, 2:payload, 3:compressed} from frame one.
/// Latency model:
///   - host broadcasts change_track the moment its load STARTS (mediaItem),
///     so guests buffer in parallel instead of waiting for the host;
///   - host attaches its resolved stream URL to the current TrackInfo
///     (album field, "zen1|url|||headers"); guests seed it into the
///     handler's memory cache — zero extraction, zero Hive round-trip;
///   - guest applies are CHAIN-FREE: play/pause land instantly even while
///     a load is in flight;
///   - guest drift-correction: periodic request_sync (a VALID protocol
///     message — the server rejects unknown actions like a raw 'position'
///     heartbeat); the sync_state reply re-aligns position;
///   - failed loads retry the same URL 5x in the handler, then auto
///     re-sync — never falling back to the previous track.
/// Guest lockout: all host-driven calls go through audioHandler.runRemote();
/// user-initiated transport is ignored by the handler while in a room.
class ListenTogetherService {
  ListenTogetherService._();
  static final ListenTogetherService instance = ListenTogetherService._();

  static const _wsUrl = 'wss://zen-listen-together.antideploy.com/ws';
  static const _clientVersion = 'ZenMusic/1.0';
  static const _pingInterval = Duration(seconds: 25);
  static const _pongTimeout = Duration(seconds: 75);
  static const _maxReconnectAttempts = 5;
  static const _driftToleranceMs = 1000;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _guestSyncTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<MediaItem?>? _songSub;
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

  // ── Guest desired-state machine (chain-free applies) ──
  int _loadSeq = 0; // bumps on every guest load; stale loads discarded
  bool? _desiredPlaying; // latest remote play state
  int _pendingSeekMs = 0; // position to apply after the load completes
  int _lastResyncAt = 0; // throttle for request_sync on failed loads

  // Host-side send chain: the hint lookup is async; the chain keeps
  // change_track → play ordering stable.
  Future<void> _sendChain = Future<void>.value();

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

    // Host: broadcast local seeks so guests follow scrubbing.
    audioHandler.onLocalSeek = (pos) {
      if (_isHost && isInRoom && _applyingRemote == 0) {
        _sendAction('seek',
            trackId: audioHandler.currentSong?.id,
            positionMs: pos.inMilliseconds);
      }
    };

    // Guest: a load failed (no URL yet) — ask the server for a re-sync;
    // the reply carries the host's resolved URL and triggers a retry.
    audioHandler.onRemoteLoadFailed = (songId) {
      if (!_isHost && isInRoom) _requestResync(songId);
    };

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
    final w = PbWriter();
    w.boolField(1, true);
    w.boolField(2, true);
    w.stringField(3, _clientVersion);
    _sendRaw('client_capabilities', w.toBytes());

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
    _guestSyncTimer?.cancel();
    _guestSyncTimer = null;
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
    _loadSeq++;
    _desiredPlaying = null;
    _pendingSeekMs = 0;
    audioHandler.followRemote = false;
    audioHandler.hostControlsPlayback = false;
    audioHandler.onLocalSeek = null;
    audioHandler.onRemoteLoadFailed = null;
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
  // STREAM HINTS + GUEST MODE
  // ═══════════════════════════════════════════

  /// Host: reads the handler's persistent stream cache for this song.
  /// Pure local Hive read — no network.
  Future<String?> _hintAlbumFor(String songId) async {
    try {
      final cached = storage.getCachedStream(songId);
      if (cached == null) return null;
      final url = cached.url;
      if (url.isEmpty || url.startsWith('file://')) return null;
      final h = jsonEncode(cached.headers);
      return 'zen1|$url|||$h';
    } catch (_) {
      return null;
    }
  }

  void _applyFollowRemote() {
    audioHandler.followRemote = isInRoom && !_isHost;
    // Guest lockout: user-initiated transport is ignored by the handler;
    // host-driven calls bypass the guard via runRemote().
    audioHandler.hostControlsPlayback = isInRoom && !_isHost;
    _applyGuestSyncTimer();
  }

  /// Guest drift correction: periodic request_sync (a valid protocol
  /// message) — the server answers with sync_state, which re-aligns
  /// position and play state. The server rejects unknown actions like a
  /// raw 'position' heartbeat, so this is the sanctioned path.
  void _applyGuestSyncTimer() {
    _guestSyncTimer?.cancel();
    _guestSyncTimer = null;
    if (!isInRoom || _isHost) return;
    _guestSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!isInRoom || _isHost) return;
      if (!audioHandler.playbackState.value.playing) return;
      _send('request_sync', null);
    });
  }

  /// Runs a host-driven playback mutation with the guest lockout bypassed.
  Future<T> _remote<T>(Future<T> Function() action) =>
      audioHandler.runRemote(action);

  void _requestResync(String songId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastResyncAt < 3000) return;
    _lastResyncAt = now;
    print('🎧 LT: stream missing for $songId — requesting re-sync');
    _send('request_sync', null);
  }

  // ═══════════════════════════════════════════
  // SEND
  // ═══════════════════════════════════════════

  void _sendRaw(String type, Uint8List payloadBytes) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(PbCodec.encodeEnvelope(type, payloadBytes));
    } catch (e) {
      print('🎧 LT: send failed [$type]: $e');
    }
  }

  void _send(String type, Map<String, dynamic>? payloadJson) {
    final channel = _channel;
    if (channel == null) return;

    final Uint8List payloadBytes;
    switch (type) {
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

    _sendRaw(type, payloadBytes);
  }

  /// Ordered async sender. Only the CURRENT track carries the resolved
  /// stream URL — the queue stays metadata-only, keeping the payload
  /// small and the send fast. Guests seed the URL into their memory
  /// cache so the load is instant.
  Future<void> _sendActionAsync(String action,
      {String? trackId,
        int positionMs = 0,
        Song? track,
        List<Song>? queue,
        bool insertNext = false,
        String? queueTitle}) async {
    Map<String, dynamic>? trackMap;
    if (track != null) {
      final albumHint = await _hintAlbumFor(track.id);
      trackMap = {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'thumbnail': track.thumbnail,
        'duration': track.duration.inMilliseconds,
        if (albumHint != null) 'album': albumHint,
      };
    }
    final queueMaps = queue == null
        ? null
        : [
      for (final s in queue)
        {
          'id': s.id,
          'title': s.title,
          'artist': s.artist,
          'thumbnail': s.thumbnail,
          'duration': s.duration.inMilliseconds,
        }
    ];
    print('🎧 LT: send $action${(trackId != null && trackId.isNotEmpty) ? ' track=$trackId' : ''}');
    _send('playback_action', {
      'action': action,
      if (trackId != null && trackId.isNotEmpty) 'track_id': trackId,
      'position': positionMs,
      if (trackMap != null) 'track': trackMap,
      if (insertNext) 'insert_next': true,
      if (queueMaps != null) 'queue': queueMaps,
      if (queueTitle != null && queueTitle.isNotEmpty)
        'queue_title': queueTitle,
      'server_time': _serverNow(),
      'captured_at_server_time': _serverNow(),
    });
  }

  void _sendAction(String action,
      {String? trackId,
        int positionMs = 0,
        Song? track,
        List<Song>? queue,
        bool insertNext = false,
        String? queueTitle}) {
    _sendChain = _sendChain.then((_) => _sendActionAsync(
      action,
      trackId: trackId,
      positionMs: positionMs,
      track: track,
      queue: queue,
      insertNext: insertNext,
      queueTitle: queueTitle,
    ));
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
    if (data is String) {
      _onJsonFrame(data);
      return;
    }
    Uint8List bytes;
    if (data is Uint8List) {
      bytes = data;
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else {
      return;
    }
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      } catch (e) {
        print('🎧 LT: gzip decode failed: $e');
        return;
      }
    }
    if (bytes.isNotEmpty && bytes[0] == 0x7b) {
      try {
        _onJsonFrame(utf8.decode(bytes));
      } catch (_) {}
      return;
    }

    Envelope env;
    try {
      env = PbCodec.decodeEnvelope(bytes);
    } catch (e) {
      print('🎧 LT: envelope decode failed: $e');
      return;
    }
    var payload = env.payload;
    if (env.compressed && payload.isNotEmpty) {
      try {
        payload = Uint8List.fromList(gzip.decode(payload));
      } catch (e) {
        print('🎧 LT: gzip decode failed for ${env.type}: $e');
        return;
      }
    }

    try {
      _dispatch(env.type, payload);
    } catch (e) {
      final hex = payload
          .take(32)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      print('🎧 LT: failed to parse "${env.type}" (${payload.length}B) '
          'hex[$hex]: $e');
      switch (env.type) {
        case 'join_approved':
          _isHost = false;
          _applyFollowRemote();
          _setPhase(LtPhase.inRoom);
          _pendingJoin?.complete(true);
          _pendingJoin = null;
          _send('request_sync', null);
          break;
        default:
          break;
      }
    }
  }

  void _onJsonFrame(String text) {
    Map<String, dynamic> p;
    String type;
    try {
      final msg = jsonDecode(text);
      if (msg is! Map) return;
      type = msg['type']?.toString() ?? '';
      final raw = msg['payload'];
      p = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    } catch (e) {
      print('🎧 LT: json frame parse failed: $e');
      return;
    }
    switch (type) {
      case 'server_capabilities':
        _handshaken = true;
        _setPhase(LtPhase.connected);
        break;
      case 'pong':
        _lastPongAt = DateTime.now().millisecondsSinceEpoch;
        break;
      default:
        break;
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
        _applyFollowRemote();
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
          unawaited(_adoptRoomState(state));
        }
        _setPhase(LtPhase.inRoom);
        _applyFollowRemote();
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
        if (_isHost) _resendCurrentTrack();
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
        unawaited(_applyPlaybackAction(action));
        break;
      case 'sync_state':
        if (_isHost) break;
        final st = parseSyncState(payload);
        print('🎧 LT: sync_state track=${st.track?['id']} playing=${st.isPlaying}');
        unawaited(_applySyncState(st));
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
        _applyFollowRemote();
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
        _applyFollowRemote();
        _rebindHostBroadcast();
        if (!isHost) unawaited(_adoptRoomState(state));
        break;
      default:
        break;
    }
  }

  // ═══════════════════════════════════════════
  // GUEST APPLICATION — chain-free.
  // play/pause/seek apply INSTANTLY; loads run in the background guarded
  // by _loadSeq. All host-driven calls bypass the guest lockout.
  // ═══════════════════════════════════════════

  Future<void> _adoptRoomState(LtRoomSnapshot? state) async {
    if (state == null) return;
    final track = state.currentTrack;
    if (track == null || track.id.isEmpty) return;
    if (audioHandler.currentSong?.id == track.id &&
        audioHandler.lastFailedSongId != track.id) {
      return;
    }
    _desiredPlaying = state.isPlaying;
    _pendingSeekMs = effectivePosition(
        state.positionMs, state.lastUpdateMs, state.isPlaying);
    var queue = state.queue;
    var index = queue.indexWhere((s) => s.id == track.id);
    if (index < 0) {
      queue = [track, ...queue];
      index = 0;
    }
    print('🎧 LT: adopting room track ${track.id} "${track.title}"');
    _send('buffer_ready', {'track_id': track.id});
    await _remote(() async {
      _flushStreamSeeds();
      await audioHandler.setQueue(queue, startIndex: index);
      if (!state.isPlaying) {
        await audioHandler.pause();
      } else {
        await audioHandler.play();
      }
    });
  }

  Future<void> _applyPlaybackAction(LtPlaybackAction p) async {
    switch (p.action) {
      case 'play':
        _desiredPlaying = true;
        _patchIsPlaying(true);
        final target =
        effectivePosition(p.positionMs, p.capturedAtServerTime, true);
        if (target > 0) _pendingSeekMs = target;
        unawaited(_ensureTrack(p));
        await _remote(() => audioHandler.play());
        break;
      case 'pause':
        _desiredPlaying = false;
        _patchIsPlaying(false);
        unawaited(_ensureTrack(p));
        await _remote(() => audioHandler.pause());
        break;
      case 'seek':
        _pendingSeekMs = p.positionMs;
        final curId = audioHandler.currentSong?.id;
        if (curId != null && curId == p.trackId && p.positionMs > 0) {
          try {
            await _remote(() =>
                audioHandler.seek(Duration(milliseconds: p.positionMs)));
            _pendingSeekMs = 0;
          } catch (_) {}
        }
        break;
      case 'position':
      // Non-protocol action (never sent by us anymore); kept for
      // forward-compatibility if a future server supports it.
        final curId = audioHandler.currentSong?.id;
        if (curId == null || curId != p.trackId) break;
        _patchIsPlaying(true);
        final target =
        effectivePosition(p.positionMs, p.capturedAtServerTime, true);
        await _seekIfNeeded(target);
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
  }

  Future<void> _applySyncState(LtSyncState p) async {
    final trackId = p.track?['id']?.toString() ?? '';
    final currentId = audioHandler.currentSong?.id ?? '';
    final needsLoad = trackId.isNotEmpty &&
        (currentId != trackId || audioHandler.lastFailedSongId == trackId);
    _desiredPlaying = p.isPlaying;
    if (needsLoad && p.track != null) {
      final song = mapToSong(p.track!);
      var queue = [for (final t in p.queue) mapToSong(t)];
      var index = queue.indexWhere((s) => s.id == trackId);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
      print('🎧 LT: loading track ${song.id} "${song.title}"');
      _pendingSeekMs =
          effectivePosition(p.positionMs, p.lastUpdate, p.isPlaying);
      _startGuestLoad(queue, index);
      _patchIsPlaying(p.isPlaying);
    } else {
      final target =
      effectivePosition(p.positionMs, p.lastUpdate, p.isPlaying);
      await _seekIfNeeded(target);
      if (p.isPlaying) {
        await _remote(() => audioHandler.play());
      } else {
        await _remote(() => audioHandler.pause());
      }
      _patchIsPlaying(p.isPlaying);
    }
  }

  Future<void> _applyTrackChange(LtPlaybackAction p,
      {required bool autoplay}) async {
    var track = p.track;
    // Fallback: payload missing the track — recover it from the queue.
    if (track == null && p.trackId.isNotEmpty && p.queue.isNotEmpty) {
      for (final t in p.queue) {
        if ('${t['id'] ?? ''}' == p.trackId) {
          track = t;
          print('🎧 LT: track payload missing — recovered from queue');
          break;
        }
      }
    }
    if (track == null) return;
    final song = mapToSong(track);
    _desiredPlaying = autoplay;
    _patchIsPlaying(autoplay);

    final previouslyFailed = audioHandler.lastFailedSongId == song.id;
    if (audioHandler.currentSong?.id == song.id && !previouslyFailed) {
      // Already on this track — align play state only, never restart.
      if (autoplay) {
        await _remote(() => audioHandler.play());
      } else {
        await _remote(() => audioHandler.pause());
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
    // Release the buffer gate immediately — lowest room latency.
    _send('buffer_ready', {'track_id': song.id});
    _startGuestLoad(queue, index);
    _patchCurrentTrack(song);
  }

  /// Kicks off a background load. Never blocks the apply path: later
  /// play/pause commands land instantly and win via _desiredPlaying.
  void _startGuestLoad(List<Song> queue, int index) {
    final seq = ++_loadSeq;
    unawaited(() async {
      try {
        await audioHandler.runRemote(() async {
          _flushStreamSeeds();
          await audioHandler.setQueue(queue, startIndex: index);
        });
      } catch (e) {
        print('🎧 LT: guest load error: $e');
        return;
      }
      if (seq != _loadSeq || !isInRoom) return;
      // Apply any position that was pending for this track.
      final seekTo = _pendingSeekMs;
      _pendingSeekMs = 0;
      if (seekTo > 500) {
        try {
          await _remote(
                  () => audioHandler.seek(Duration(milliseconds: seekTo)));
        } catch (_) {}
      }
      // A failed load stays flagged — ask the server for a fresh sync
      // (its reply carries the host's resolved URL) and retry.
      final failedId = audioHandler.lastFailedSongId;
      if (failedId != null && audioHandler.currentSong?.id == failedId) {
        _requestResync(failedId);
      }
    }());
  }

  Future<void> _applyQueue(List<Map<String, dynamic>> protoQueue) async {
    final queue = [for (final t in protoQueue) mapToSong(t)];
    if (queue.isEmpty) return;
    final currentId = audioHandler.currentSong?.id;
    var index = queue.indexWhere((s) => s.id == currentId);
    if (index < 0) index = 0;
    await audioHandler.runRemote(() async {
      _flushStreamSeeds();
      await audioHandler.setQueue(queue, startIndex: index);
    });
  }

  Future<void> _ensureTrack(LtPlaybackAction p) async {
    final trackId = p.trackId;
    if (trackId.isEmpty) return;
    if (audioHandler.currentSong?.id == trackId &&
        audioHandler.lastFailedSongId != trackId) {
      return;
    }
    await _applyTrackChange(p, autoplay: _desiredPlaying ?? false);
  }

  Future<void> _seekIfNeeded(int targetMs) async {
    if (targetMs <= 0) return;
    final current = _lastPositionMs;
    if ((current - targetMs).abs() > _driftToleranceMs) {
      try {
        await _remote(
                () => audioHandler.seek(Duration(milliseconds: targetMs)));
      } catch (_) {}
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
    _posSub = audioHandler.positionStream.listen((p) {
      _lastPositionMs = p.inMilliseconds;
    });
    if (!_isHost || !isInRoom) return;

    _lastPlaying = audioHandler.playbackState.value.playing;

    _playingSub = audioHandler.playingStream.listen((playing) {
      if (!_isHost || _applyingRemote > 0) return;
      if (playing == _lastPlaying) return;
      _lastPlaying = playing;
      _patchIsPlaying(playing);
      _sendAction(
        playing ? 'play' : 'pause',
        trackId: audioHandler.currentSong?.id,
        positionMs: _lastPositionMs,
      );
    });

    // Fire change_track the moment the load STARTS (mediaItem is added
    // before stream resolution) — guests begin buffering in parallel
    // with the host, which is the single biggest sync win.
    _songSub = audioHandler.mediaItem.listen((item) {
      if (!_isHost || _applyingRemote > 0 || item == null) return;
      if (item.id == _lastBroadcastSongId) return;
      _lastBroadcastSongId = item.id;
      final song = Song(
        id: item.id,
        title: item.title,
        artist: item.artist ?? 'Unknown',
        thumbnail: item.artUri?.toString() ?? '',
        duration: item.duration ?? Duration.zero,
      );
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

    // NOTE: no raw 'position' heartbeat here — the server rejects
    // unknown actions. Guests drift-correct via periodic request_sync
    // instead (see _applyGuestSyncTimer).
  }

  /// Kotlin-reference parity: introduce the current track to newcomers.
  void _resendCurrentTrack() {
    final cur = audioHandler.currentSong;
    if (cur == null) return;
    _lastBroadcastSongId = cur.id;
    _sendAction(
      'change_track',
      trackId: cur.id,
      track: cur,
      queue: audioHandler.queueSongs,
      queueTitle: 'Listen Together',
    );
    _patchCurrentTrack(cur);
    if (audioHandler.playbackState.value.playing) {
      _lastPlaying = true;
      _sendAction('play', trackId: cur.id, positionMs: _lastPositionMs);
    }
  }

  // ═══════════════════════════════════════════
  // ROOM STATE HELPERS
  // ═══════════════════════════════════════════

  void _patchIsPlaying(bool playing) {
    final r = _room;
    if (r == null) return;
    if (r.isPlaying == playing) return;
    _room = LtRoomSnapshot(
      roomCode: r.roomCode,
      hostId: r.hostId,
      users: r.users,
      currentTrack: r.currentTrack,
      isPlaying: playing,
      positionMs: r.positionMs,
      lastUpdateMs: r.lastUpdateMs,
      queue: r.queue,
    );
    roomNotifier.value = _room;
  }

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
  bool insertNext = false;
  String? queueTitle;
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
// STREAM SEEDS — guests capture the host's resolved URLs from the
// "zen1|" album hint and push them straight into the handler's memory
// cache, so playback is an instant memory hit with zero extractor work.
// ═══════════════════════════════════════════

final _pendingStreamSeeds =
<String, ({String url, Map<String, String> headers})>{};

void _noteTrackHint(Map<String, dynamic> t) {
  final album = t['album']?.toString() ?? '';
  if (!album.startsWith('zen1|')) return;
  final parts = album.split('|');
  if (parts.length < 4) return;
  final url = parts[1];
  final id = t['id']?.toString() ?? '';
  if (url.isEmpty || id.isEmpty || url.startsWith('file://')) return;
  Map<String, String> headers = const {};
  if (parts.length > 4) {
    try {
      final decoded = jsonDecode(parts.sublist(4).join('|'));
      if (decoded is Map) {
        headers = {
          for (final e in decoded.entries)
            e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {}
  }
  _pendingStreamSeeds[id] = (url: url, headers: headers);
}

void _flushStreamSeeds() {
  if (_pendingStreamSeeds.isEmpty) return;
  final seeds = Map.of(_pendingStreamSeeds);
  _pendingStreamSeeds.clear();
  for (final e in seeds.entries) {
    try {
      audioHandler.seedStreamUrl(e.key, e.value.url, e.value.headers);
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════
// PARSERS
// ═══════════════════════════════════════════

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
      case 5:
        p.insertNext = r.readRawVarint() != 0;
      case 6:
        p.queue.add(parseTrackInfo(r.readBytesRaw()));
      case 7:
        p.queueTitle = utf8.decode(r.readBytesRaw());
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

Song mapToSong(Map<String, dynamic> t) {
  _noteTrackHint(t);
  return Song(
    id: '${t['id'] ?? ''}',
    title: '${t['title'] ?? 'Unknown'}',
    artist: '${t['artist'] ?? 'Unknown'}',
    thumbnail: '${t['thumbnail'] ?? ''}',
    duration: Duration(milliseconds: ((t['duration'] as num?) ?? 0).toInt()),
  );
}

// ═══════════════════════════════════════════
// PROTO WIRE — writer + reader + envelope codec
// ═══════════════════════════════════════════

class Envelope {
  Envelope(this.type, this.payload, this.compressed);
  final String type;
  final Uint8List payload;
  final bool compressed;
}

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

  static Envelope decodeEnvelope(Uint8List data) {
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
    return Envelope(type, payload, compressed);
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