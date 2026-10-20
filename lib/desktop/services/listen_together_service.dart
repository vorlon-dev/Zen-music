// ZenMusic Desktop — ported from the retired mobile stack's
// listen_together_service.dart. ZenMusic remains GPL-3.0.
// Listen Together client for the metroserver protocol (protobuf Envelope).
// PORT DEVIATIONS: bindings target the desktop MediaPlayer (GetIt); Song ->
// local LtSong; guest lockout dropped (request_sync + heartbeat re-align
// guests); host stream-hints metadata-only (legacy Hive cache retired).
//
// v3 (1 Hz sync): ping/pong every second, host heartbeat every second,
// heartbeat-driven drift control that never fights a buffering player
// (settle window, 2-in-a-row hysteresis, +/-3% speed nudge), clock offset
// plausibility checks (falls back to RTT when the server timestamps are not
// what we expect), fallback request_sync polling when heartbeats do not
// arrive, liveness by ANY inbound frame, and a live LtSyncStats notifier +
// one "lt:" log line per second (rtt, offset, drift, heartbeat age).
//
// SYNC DEVIATIONS (marked, bug-fix / feature):
//  * Host seek broadcast is back: seeks (slider, +/-10s, anything that moves
//    the position) are detected from the position stream and sent instantly
//    as 'seek' (leading edge immediate, trailing coalesced while dragging).
//    hostSeek() now carries track_id (guests used to ignore it).
//  * Host heartbeat ('position' every 3 s) so guests keep correcting drift.
//  * Guests compensate network latency using the server clock offset and the
//    host's captured_at_server_time, and apply seek -> play in that order.
//  * Clock offset: fixed NTP formula, burst pings right after the handshake,
//    best (lowest RTT) of the recent samples is used.
//  * Guest drift correction: hard seek only when far off, otherwise a tiny
//    playback-speed nudge (+/-3%) so there is no audible glitch.
//  * Guest actions run through a serial queue (no play/seek/pause races) and
//    stale rapid seeks are dropped (latest wins).
//  * Pending seeks while a track is loading are advanced by the time spent
//    loading, so the guest lands on the live position.
//  * connect() now waits for the handshake, so the reconnect message is
//    really sent after a dropped socket.
//  * Duplicate change_track for the already-loaded track is a no-op (it used
//    to force play and cause a blip for existing guests when someone joined).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:zenmusic/desktop/services/media_player.dart';

class ListenTogetherService {
  ListenTogetherService._();
  static final ListenTogetherService instance = ListenTogetherService._();

  /// Prints one "lt: ..." line per second plus key events.
  static bool debugLogs = true;

  static const _wsUrl = 'wss://zen-listen-together.antideploy.com/ws';
  static const _clientVersion = 'ZenMusic/1.0';
  static const _pingInterval = Duration(seconds: 1); // ping/pong every second
  static const _livenessTimeoutMs = 12000; // no inbound frame this long -> reconnect
  static const _maxReconnectAttempts = 5;

  // ── sync tuning ──
  static const _heartbeatInterval = Duration(seconds: 1); // host position heartbeat
  static const _hardSeekMs = 300; // playing: seek only if drift is bigger
  static const _pausedSeekMs = 120; // paused: be exact, nobody hears it
  static const _forceSeekMinMs = 60; // explicit host seek: ignore tiny diffs
  static const _softSync = true; // speed-nudge instead of seeking small drift
  static const _softSyncMinMs = 30;
  static const _nudgeRate = 0.03; // +/-3% speed while catching up
  static const _seekDetectMs = 450; // host position jump that counts as seek
  static const _seekThrottleMs = 90; // coalesce seeks while dragging
  static const _trackChangeQuietMs = 800; // ignore position noise on skip
  static const _clockSamplesMax = 8;
  static const _heartbeatStaleMs = 3500; // no heartbeat this long -> poll request_sync
  static const _fallbackSyncMs = 2000;
  static const _settleMs = 1200; // after a hard seek: no new corrections
  static const _statsInterval = Duration(seconds: 1);

  MediaPlayer get _player => GetIt.I<MediaPlayer>();

  final Stopwatch _mono = Stopwatch()..start();

  void _log(String m) {
    if (debugLogs) debugPrint('lt: $m');
  }

  String? get _currentSongId => _player.currentSongNotifier.value?.id;
  bool get _playingNow => _player.player.playing;
  int get _livePositionMs => _player.player.position.inMilliseconds;

  bool _isCurrentTrack(String trackId) =>
      trackId.isEmpty || _currentSongId == trackId;

  List<LtSong> _queueLtSongs() {
    final out = <LtSong>[];
    for (final src in _player.songList) {
      final tag = src.tag;
      if (tag is MediaItem) {
        out.add(LtSong(
          id: tag.id,
          title: tag.title,
          artist: tag.artist ?? 'Unknown',
          thumbnail: tag.artUri?.toString() ?? '',
          duration: tag.duration ?? Duration.zero,
        ));
      }
    }
    return out;
  }

  LtSong? get _currentLtSong {
    final item = _player.currentSongNotifier.value;
    if (item == null) return null;
    return LtSong(
      id: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown',
      thumbnail: item.artUri?.toString() ?? '',
      duration: item.duration ?? Duration.zero,
    );
  }

  Map<String, dynamic> _ltToMap(LtSong s) => {
    'videoId': s.id,
    'title': s.title,
    'artists': [
      {'name': s.artist},
    ],
    'thumbnails': [
      {'url': s.thumbnail},
    ],
  };

  List<Map<String, dynamic>> _ltToMaps(List<LtSong> songs) =>
      [for (final s in songs) _ltToMap(s)];

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _guestSyncTimer;
  Timer? _heartbeatTimer;
  Timer? _nudgeTimer;
  Timer? _seekTrailing;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _posSub;
  VoidCallback? _songListener;

  bool _userDisconnect = false;
  bool _handshaken = false;
  Completer<void>? _handshakeDone;
  int _reconnectAttempts = 0;
  int _pingSeq = 0;
  int _lastRxMono = 0; // any inbound frame (liveness)
  int _lastHeartbeatRxMono = 0;
  int _lastFallbackSyncMono = 0;
  int _settleUntilMono = 0;
  int _bigDrift = 0;
  int _lastDriftMs = 0;
  bool _clockValid = false;
  Timer? _statsTimer;
  int _applyingRemote = 0;
  bool _lastPlaying = false;
  String? _lastBroadcastSongId;
  int _lastPositionMs = 0;

  // clock sync (server time = local time + _serverOffsetMs)
  int _serverOffsetMs = 0;
  int _rttMs = 0;
  final List<(int, int)> _clockSamples = []; // (rtt, offset)

  // guest apply state
  int _loadSeq = 0;
  bool _desiredPlaying = false;
  int? _pendingSeekMs;
  int _pendingSeekMono = 0;
  int _seekGen = 0;
  int _seekLeadMs = 60; // measured time a seek takes while playing
  double _currentSpeed = 1.0;
  Future<void> _chain = Future<void>.value();

  // host seek detection
  String? _hostPosSongId;
  int _hostLastPosMs = 0;
  int _hostLastPosMono = 0;
  bool _hostLastAdvancing = false;
  int _seekQuietUntilMono = 0;
  int _lastSeekSentMono = 0;
  int? _seekPendingMs;

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
  /// Live sync health (rtt, clock offset, drift, heartbeat age) - bind a
  /// small badge to this in the Listen Together page if you like.
  final ValueNotifier<LtSyncStats> syncStats =
  ValueNotifier<LtSyncStats>(LtSyncStats.idle);
  final _events = StreamController<LtEvent>.broadcast();

  Stream<LtEvent> get events => _events.stream;
  LtPhase get phase => _phase;
  LtRoomSnapshot? get room => _room;
  bool get isHost => _isHost;
  bool get isInRoom => _roomCode != null;
  String? get roomCode => _roomCode;

  /// Last measured round trip to the server in ms (0 = not measured yet).
  int get roundTripMs => _rttMs;

  // ── CONNECTION ──

  Future<void> connect() async {
    if (_channel != null) {
      await _awaitHandshake();
      return;
    }
    _userDisconnect = false;
    _setPhase(LtPhase.connecting);
    _handshakeDone = Completer<void>();

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
    await _awaitHandshake();
  }

  Future<void> _awaitHandshake() async {
    if (_handshaken) return;
    try {
      await _handshakeDone?.future.timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  void _onHandshake() {
    _handshaken = true;
    _log('handshake ok');
    final c = _handshakeDone;
    if (c != null && !c.isCompleted) c.complete();
    _setPhase(LtPhase.connected);
    _burstPings();
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
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    _seekTrailing?.cancel();
    _seekTrailing = null;
    _seekPendingMs = null;
    _resetSpeed();
    _playingSub?.cancel();
    _playingSub = null;
    _posSub?.cancel();
    _posSub = null;
    if (_songListener != null) {
      _player.currentSongNotifier.removeListener(_songListener!);
      _songListener = null;
    }
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _handshaken = false;
    _handshakeDone = null;
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
    _seekGen++;
    _pendingSeekMs = null;
    _clockSamples.clear();
    _hostPosSongId = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastHeartbeatRxMono = 0;
    _settleUntilMono = 0;
    _bigDrift = 0;
    _lastDriftMs = 0;
    _clockValid = false;
    syncStats.value = LtSyncStats.idle;
  }

  // ── ROOM OPERATIONS ──

  Future<String?> createRoom(String username) async {
    await connect();
    _username = username;
    final completer = Completer<String?>();
    _pendingCreate = completer;
    _send('create_room', {'username': username});
    return completer.future
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
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
    return completer.future
        .timeout(const Duration(seconds: 30), onTimeout: () => false);
  }

  void approveJoin(String userId) => _send('approve_join', {'user_id': userId});

  void rejectJoin(String userId, {String? reason}) =>
      _send('reject_join', {'user_id': userId, 'reason': reason ?? ''});

  void kickUser(String userId, {String? reason}) =>
      _send('kick_user', {'user_id': userId, 'reason': reason ?? ''});

  void transferHost(String newHostId) =>
      _send('transfer_host', {'new_host_id': newHostId});

  void leaveRoom() => disconnect();

  /// Explicit host seek. Optional: seeks are also auto-detected from the
  /// player position, so calling this is only needed if you want to push a
  /// seek without moving the local player first.
  void hostSeek(int positionMs) {
    if (!_isHost || !isInRoom) return;
    _hostLastPosMs = positionMs;
    _hostLastPosMono = _mono.elapsedMilliseconds;
    _seekTrailing?.cancel();
    _seekTrailing = null;
    _seekPendingMs = null;
    _sendHostSeekNow(positionMs);
  }

  void suggestTrack(LtSong song) =>
      _send('suggest_track', {'track_info': _trackMap(song)});

  void approveSuggestion(String suggestionId) =>
      _send('approve_suggestion', {'suggestion_id': suggestionId});

  void rejectSuggestion(String suggestionId, {String? reason}) =>
      _send('reject_suggestion',
          {'suggestion_id': suggestionId, 'reason': reason ?? ''});

  // ── GUEST MODE ──

  void _applyGuestSyncTimer() {
    _startStats();
    _guestSyncTimer?.cancel();
    _guestSyncTimer = null;
    if (!isInRoom || _isHost) return;
    _lastHeartbeatRxMono = 0;
    _guestSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isInRoom || _isHost) return;
      final now = _mono.elapsedMilliseconds;
      final heartbeatOk = _lastHeartbeatRxMono > 0 &&
          now - _lastHeartbeatRxMono < _heartbeatStaleMs;
      if (heartbeatOk) return;
      // No heartbeat (host paused, or the server does not relay them):
      // poll the server state instead.
      final playing = (_room?.isPlaying ?? false) || _playingNow;
      final every = playing ? _fallbackSyncMs : 5000;
      if (now - _lastFallbackSyncMono < every) return;
      _lastFallbackSyncMono = now;
      _send('request_sync', null);
    });
  }

  /// One status line + LtSyncStats per second while in a room.
  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(_statsInterval, (_) {
      if (!isInRoom) return;
      final now = _mono.elapsedMilliseconds;
      final hbAge = _isHost
          ? 0
          : (_lastHeartbeatRxMono == 0 ? -1 : now - _lastHeartbeatRxMono);
      final st = _player.player.processingState.name;
      syncStats.value = LtSyncStats(
        isHost: _isHost,
        rttMs: _rttMs,
        clockOffsetMs: _serverOffsetMs,
        clockValid: _clockValid,
        driftMs: _lastDriftMs,
        heartbeatAgeMs: hbAge,
        speed: _currentSpeed,
        playerState: st,
      );
      _log('${_isHost ? 'host ' : 'guest'} rtt=${_rttMs}ms '
          'off=${_serverOffsetMs}ms${_clockValid ? '' : '(?)'} '
          'drift=${_lastDriftMs}ms hb=${hbAge}ms '
          'speed=${_currentSpeed.toStringAsFixed(2)} $st');
    });
  }

  // ── SEND ──

  void _sendRaw(String type, Uint8List payloadBytes) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(PbCodec.encodeEnvelope(type, payloadBytes));
    } catch (_) {}
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
      case 'join_room':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['room_code'] ?? ''}');
        w.stringField(2, '${payloadJson?['username'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'approve_join':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'reject_join':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'kick_user':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['user_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'transfer_host':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['new_host_id'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'suggest_track':
        final w = PbWriter();
        w.messageField(1,
            _encodeTrackInfo((payloadJson?['track_info'] ?? const {}) as Map));
        payloadBytes = w.toBytes();
      case 'approve_suggestion':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['suggestion_id'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'reject_suggestion':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['suggestion_id'] ?? ''}');
        w.stringField(2, '${payloadJson?['reason'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'buffer_ready':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['track_id'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'ping':
        final w = PbWriter();
        w.int64Field(1, DateTime.now().millisecondsSinceEpoch);
        w.int64Field(2, ++_pingSeq);
        payloadBytes = w.toBytes();
      case 'reconnect':
        final w = PbWriter();
        w.stringField(1, '${payloadJson?['session_token'] ?? ''}');
        payloadBytes = w.toBytes();
      case 'request_sync':
      case 'leave_room':
        payloadBytes = Uint8List(0);
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
      default:
        payloadBytes = Uint8List(0);
    }

    _sendRaw(type, payloadBytes);
  }

  Future<void> _sendActionAsync(String action,
      {String? trackId,
        int positionMs = 0,
        LtSong? track,
        List<LtSong>? queue,
        String? queueTitle}) async {
    Map<String, dynamic>? trackMap;
    if (track != null) {
      trackMap = {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'thumbnail': track.thumbnail,
        'duration': track.duration.inMilliseconds,
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
    // Only stamp server time when our clock offset is trustworthy; the
    // guest falls back to the RTT estimate when the stamp is 0.
    final now = _clockValid ? _serverNow() : 0;
    _send('playback_action', {
      'action': action,
      if (trackId != null && trackId.isNotEmpty) 'track_id': trackId,
      'position': positionMs,
      if (trackMap != null) 'track': trackMap,
      if (queueMaps != null) 'queue': queueMaps,
      if (queueTitle != null && queueTitle.isNotEmpty)
        'queue_title': queueTitle,
      'server_time': now,
      'captured_at_server_time': now,
    });
  }

  void _sendAction(String action,
      {String? trackId,
        int positionMs = 0,
        LtSong? track,
        List<LtSong>? queue,
        String? queueTitle}) {
    unawaited(_sendActionAsync(
      action,
      trackId: trackId,
      positionMs: positionMs,
      track: track,
      queue: queue,
      queueTitle: queueTitle,
    ));
  }

  Map<String, dynamic> _trackMap(LtSong s) => {
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

  int _serverNow() => DateTime.now().millisecondsSinceEpoch + _serverOffsetMs;

  // ── INCOMING ──

  void _onData(dynamic data) {
    _lastRxMono = _mono.elapsedMilliseconds;
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
      } catch (_) {
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
    } catch (_) {
      return;
    }
    var payload = env.payload;
    if (env.compressed && payload.isNotEmpty) {
      try {
        payload = Uint8List.fromList(gzip.decode(payload));
      } catch (_) {
        return;
      }
    }

    try {
      _dispatch(env.type, payload);
    } catch (_) {}
  }

  void _onJsonFrame(String text) {
    String type;
    try {
      final msg = jsonDecode(text);
      if (msg is! Map) return;
      type = msg['type']?.toString() ?? '';
    } catch (_) {
      return;
    }
    switch (type) {
      case 'server_capabilities':
        _onHandshake();
      case 'pong':
        break; // liveness already recorded in _onData
      default:
        break;
    }
  }

  void _dispatch(String type, Uint8List payload) {
    switch (type) {
      case 'server_capabilities':
        _onHandshake();
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
        _applyGuestSyncTimer();
        _rebindHostBroadcast();
        _pendingCreate?.complete(roomCode);
        _pendingCreate = null;
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
          _enqueue(() => _adoptRoomState(state));
        }
        _setPhase(LtPhase.inRoom);
        _applyGuestSyncTimer();
        _send('request_sync', null);
        _pendingJoin?.complete(true);
        _pendingJoin = null;
      case 'join_rejected':
        final r = PbReader(payload);
        final reason = r.readString(1);
        _pendingJoin?.complete(false);
        _pendingJoin = null;
        _events.add(LtErrorEvent('join_rejected', reason));
      case 'join_request':
        final r = PbReader(payload);
        final uid = r.readString(1);
        final uname = r.readString(2);
        if (_isHost) _events.add(LtJoinRequestEvent(uid, uname));
      case 'user_joined':
        final p = readUserIdName(payload);
        _patchUser(p.$1, p.$2, isHost: false, connected: true);
        _events.add(LtUserEvent(p.$1, p.$2, LtUserEventKind.joined));
        if (_isHost) _resendCurrentTrack();
      case 'user_left':
        final p = readUserIdName(payload);
        _removeUser(p.$1);
        _events.add(LtUserEvent(p.$1, p.$2, LtUserEventKind.left));
      case 'user_disconnected':
        final p = readUserIdName(payload);
        _patchConnected(p.$1, false);
      case 'user_reconnected':
        final p = readUserIdName(payload);
        _patchConnected(p.$1, true);
      case 'sync_playback':
        if (_isHost) break;
        final act = parsePlaybackAction(payload);
        final isSeek = act.action == 'seek';
        final gen = isSeek ? ++_seekGen : _seekGen;
        _enqueue(() async {
          // Rapid seeks (host dragging): only the newest one matters.
          if (isSeek && gen != _seekGen) return;
          await _applyPlaybackAction(act);
        });
      case 'sync_state':
        if (_isHost) break;
        final st = parseSyncState(payload);
        _enqueue(() => _applySyncState(st));
      case 'buffer_wait':
        final r = PbReader(payload);
        final trackId = r.readString(1);
        if (_currentSongId == trackId) {
          _send('buffer_ready', {'track_id': trackId});
        }
      case 'host_changed':
        final r = PbReader(payload);
        final hostId = r.readString(1);
        final hostName = r.readString(2);
        _isHost = hostId == _userId;
        _patchHost(hostId);
        _applyGuestSyncTimer();
        _events.add(LtHostChangedEvent(hostId, hostName));
        _rebindHostBroadcast();
      case 'kicked':
        final r = PbReader(payload);
        _events.add(LtKickedEvent(r.readString(1)));
        _teardown();
        _setPhase(LtPhase.disconnected);
      case 'pong':
        final r = PbReader(payload);
        final t0 = r.readInt(1); // client send
        final t1 = r.readInt(2); // server receive
        final t2 = r.readInt(3); // server send
        final t3 = DateTime.now().millisecondsSinceEpoch; // client receive
        _addClockSample(t0, t1, t2, t3);
      case 'error':
        final r = PbReader(payload);
        final code = r.readString(1);
        final message = r.readString(2);
        if (code == 'join_rejected') {
          _pendingJoin?.complete(false);
          _pendingJoin = null;
        }
        _events.add(LtErrorEvent(code, message));
      case 'suggestion_received':
        final r = PbReader(payload);
        final sid = r.readString(1);
        r.readString(2);
        final fromName = r.readString(3);
        final trackBytes = r.readBytes(4);
        if (_isHost && trackBytes.isNotEmpty) {
          final t = parseTrackInfo(trackBytes);
          _events.add(LtSuggestionEvent(sid, fromName, mapToLtSong(t)));
        }
      case 'suggestion_approved':
        final r = PbReader(payload);
        final sid = r.readString(1);
        final trackBytes = r.readBytes(2);
        if (trackBytes.isNotEmpty) {
          _events.add(LtSuggestionApprovedEvent(
              sid, mapToLtSong(parseTrackInfo(trackBytes))));
        }
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
        _applyGuestSyncTimer();
        _rebindHostBroadcast();
        if (!isHost) _enqueue(() => _adoptRoomState(state));
      default:
        break;
    }
  }

  // ── CLOCK SYNC ──

  /// NTP style: offset = ((t1 - t0) + (t2 - t3)) / 2, rtt = (t3 - t0) - (t2 - t1).
  /// The sample with the lowest RTT among the recent ones is the most
  /// trustworthy (least queueing delay), so that one is used.
  void _addClockSample(int t0, int t1, int t2, int t3) {
    if (t0 <= 0 || t1 <= 0) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Plausibility: the echoed client time must be recent and the server time
    // a real epoch-ms value; otherwise the pong layout is not what we think
    // and no clock offset may be derived from it.
    if ((nowMs - t0).abs() > 15000 || (t1 - nowMs).abs() > 86400000) {
      _clockValid = false;
      return;
    }
    if (t2 <= 0) t2 = t1; // server did not fill send time
    final rtt = (t3 - t0) - (t2 - t1);
    if (rtt < 0) return;
    final offset = ((t1 - t0) + (t2 - t3)) ~/ 2;
    _clockSamples.add((rtt, offset));
    if (_clockSamples.length > _clockSamplesMax) _clockSamples.removeAt(0);
    var best = _clockSamples.first;
    for (final s in _clockSamples) {
      if (s.$1 < best.$1) best = s;
    }
    final changed = (best.$2 - _serverOffsetMs).abs() > 25;
    _rttMs = best.$1;
    _serverOffsetMs = best.$2;
    _clockValid = _clockSamples.length >= 3 && _rttMs < 3000;
    if (changed) {
      _log('clock: offset=${_serverOffsetMs}ms rtt=${_rttMs}ms valid=$_clockValid');
    }
  }

  /// Several quick pings right after the handshake so the clock offset is
  /// good from the very first second (not after the first 25 s keepalive).
  void _burstPings() {
    for (var i = 0; i < 6; i++) {
      Timer(Duration(milliseconds: 120 * i), () {
        if (_channel != null && _handshaken) _send('ping', null);
      });
    }
  }

  // ── SERIAL APPLY QUEUE ──

  /// Guest actions run strictly one after another, so play/seek/pause can
  /// never interleave and fight each other.
  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) => job()).catchError((_) {});
  }

  // ── GUEST APPLICATION ──

  void _setPendingSeek(int ms) {
    _pendingSeekMs = ms;
    _pendingSeekMono = _mono.elapsedMilliseconds;
  }

  /// Pending seek advanced by the time that passed while the track loaded,
  /// so the guest lands on the host's LIVE position, not the old one.
  int? _takePendingSeek() {
    final ms = _pendingSeekMs;
    if (ms == null) return null;
    _pendingSeekMs = null;
    if (!_desiredPlaying) return ms;
    return ms + (_mono.elapsedMilliseconds - _pendingSeekMono);
  }

  Future<void> _adoptRoomState(LtRoomSnapshot? state) async {
    if (state == null || !isInRoom) return;
    final track = state.currentTrack;
    if (track == null || track.id.isEmpty) return;
    _desiredPlaying = state.isPlaying;
    final target = effectivePosition(
        state.positionMs, state.lastUpdateMs, state.isPlaying);
    if (_currentSongId == track.id) {
      await _alignTo(target, playing: state.isPlaying);
      return;
    }
    _setPendingSeek(target);
    var queue = state.queue;
    var index = queue.indexWhere((s) => s.id == track.id);
    if (index < 0) {
      queue = [track, ...queue];
      index = 0;
    }
    _send('buffer_ready', {'track_id': track.id});
    _startGuestLoad(queue, index);
  }

  Future<void> _applyPlaybackAction(LtPlaybackAction p) async {
    if (!isInRoom || _isHost) return;
    switch (p.action) {
      case 'play':
        _desiredPlaying = true;
        _patchIsPlaying(true);
        final target =
        effectivePosition(p.positionMs, p.capturedAtServerTime, true);
        if (!_isCurrentTrack(p.trackId)) {
          // Don't play the OLD track while the new one is loading.
          _setPendingSeek(target);
          unawaited(_ensureTrack(p));
          return;
        }
        await _alignTo(target, playing: true);
      case 'pause':
        _desiredPlaying = false;
        _patchIsPlaying(false);
        if (!_isCurrentTrack(p.trackId)) {
          _setPendingSeek(p.positionMs);
          unawaited(_ensureTrack(p));
          await _player.player.pause();
          return;
        }
        await _alignTo(p.positionMs, playing: false);
      case 'seek':
        final target = effectivePosition(
            p.positionMs, p.capturedAtServerTime, _desiredPlaying);
        if (!_isCurrentTrack(p.trackId)) {
          _setPendingSeek(target);
          return;
        }
        await _alignTo(target, playing: _desiredPlaying, force: true);
      case 'position':
      // Host heartbeat: keeps everybody locked to the host.
        if (p.trackId.isEmpty || _currentSongId != p.trackId) break;
        if (_lastHeartbeatRxMono == 0) _log('first heartbeat received');
        _lastHeartbeatRxMono = _mono.elapsedMilliseconds;
        _desiredPlaying = true;
        _patchIsPlaying(true);
        await _alignHeartbeat(
            effectivePosition(p.positionMs, p.capturedAtServerTime, true));
      case 'change_track':
        await _applyTrackChange(p, autoplay: true);
      case 'skip_next':
      case 'skip_prev':
        break;
      case 'sync_queue':
      case 'queue_add':
      case 'queue_remove':
      case 'queue_clear':
        await _applyQueue(p.queue);
      default:
        break;
    }
  }

  Future<void> _applySyncState(LtSyncState p) async {
    if (!isInRoom || _isHost) return;
    final trackId = p.track?['id']?.toString() ?? '';
    final currentId = _currentSongId ?? '';
    final needsLoad = trackId.isNotEmpty && currentId != trackId;
    _desiredPlaying = p.isPlaying;
    final target = effectivePosition(p.positionMs, p.lastUpdate, p.isPlaying);
    if (needsLoad && p.track != null) {
      final song = mapToLtSong(p.track!);
      var queue = [for (final t in p.queue) mapToLtSong(t)];
      var index = queue.indexWhere((s) => s.id == trackId);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
      _setPendingSeek(target);
      _startGuestLoad(queue, index);
      _patchIsPlaying(p.isPlaying);
    } else {
      if (p.isPlaying) {
        await _alignHeartbeat(target);
      } else {
        await _alignTo(target, playing: false);
      }
      _patchIsPlaying(p.isPlaying);
    }
  }

  Future<void> _applyTrackChange(LtPlaybackAction p,
      {required bool autoplay}) async {
    var track = p.track;
    if (track == null && p.trackId.isNotEmpty && p.queue.isNotEmpty) {
      for (final t in p.queue) {
        if ('${t['id'] ?? ''}' == p.trackId) {
          track = t;
          break;
        }
      }
    }
    if (track == null) return;
    final song = mapToLtSong(track);

    if (_currentSongId == song.id) {
      // Already on this track (e.g. host re-announced it because somebody
      // joined): leave playback alone, the play/pause action that follows
      // carries the real state.
      _patchCurrentTrack(song);
      _send('buffer_ready', {'track_id': song.id});
      return;
    }

    _desiredPlaying = autoplay;
    _patchIsPlaying(autoplay);
    _pendingSeekMs = null; // new track starts from the beginning

    var queue = [for (final t in p.queue) mapToLtSong(t)];
    var index = queue.indexWhere((s) => s.id == song.id);
    if (index < 0) {
      queue = [song, ...queue];
      index = 0;
    }
    _send('buffer_ready', {'track_id': song.id});
    _startGuestLoad(queue, index);
    _patchCurrentTrack(song);
  }

  void _startGuestLoad(List<LtSong> queue, int index) {
    final seq = ++_loadSeq;
    unawaited(() async {
      try {
        await _player.playAll(_ltToMaps(queue), index: index);
      } catch (_) {
        return;
      }
      if (seq != _loadSeq || !isInRoom) return;
      final seekTo = _takePendingSeek();
      if (seekTo != null && seekTo > 150) {
        await _hardSeek(seekTo, playing: _desiredPlaying);
      }
      if (seq != _loadSeq || !isInRoom) return;
      final p = _player.player;
      try {
        if (_desiredPlaying) {
          if (!p.playing) await p.play();
        } else {
          await p.pause();
        }
      } catch (_) {}
    }());
  }

  Future<void> _applyQueue(List<Map<String, dynamic>> protoQueue) async {
    final queue = [for (final t in protoQueue) mapToLtSong(t)];
    if (queue.isEmpty) return;
    final currentId = _currentSongId;
    var index = queue.indexWhere((s) => s.id == currentId);
    if (index < 0) index = 0;
    await _player.playAll(_ltToMaps(queue), index: index);
  }

  Future<void> _ensureTrack(LtPlaybackAction p) async {
    final trackId = p.trackId;
    if (trackId.isEmpty) return;
    if (_currentSongId == trackId) return;
    await _applyTrackChange(p, autoplay: _desiredPlaying);
  }

  // ── DRIFT CORRECTION ──

  /// Hard seek that lands on the right spot AFTER the seek finished: while
  /// playing, the target is moved forward by the measured seek duration.
  Future<void> _hardSeek(int targetMs, {required bool playing}) async {
    final p = _player.player;
    final live = playing && p.playing;
    final lead = live ? _seekLeadMs : 0;
    final t0 = _mono.elapsedMilliseconds;
    // No further corrections while the seek is in flight / settling.
    _settleUntilMono = t0 + 30000;
    try {
      await p.seek(Duration(milliseconds: math.max(0, targetMs + lead)));
    } catch (_) {}
    final done = _mono.elapsedMilliseconds;
    _settleUntilMono = done + _settleMs;
    if (live) {
      _seekLeadMs = ((_seekLeadMs + (done - t0)) / 2).round().clamp(0, 400);
    }
  }

  /// Brings the local player to [targetMs] and the right play state.
  ///  * far off      -> hard seek (then play)
  ///  * slightly off -> +/-3% speed nudge, inaudible, no glitch
  ///  * in sync      -> do nothing
  Future<void> _alignTo(int targetMs,
      {required bool playing, bool force = false}) async {
    final p = _player.player;
    final drift = _livePositionMs - targetMs; // + = guest ahead
    _lastDriftMs = drift;
    final abs = drift.abs();
    final hardLimit =
    force ? _forceSeekMinMs : (playing ? _hardSeekMs : _pausedSeekMs);

    if (abs > hardLimit) {
      _resetSpeed();
      await _hardSeek(targetMs, playing: playing);
    } else if (playing && _softSync && p.playing && abs >= _softSyncMinMs) {
      _nudge(drift);
    } else {
      _resetSpeed();
    }

    try {
      if (playing) {
        if (!p.playing) await p.play();
      } else if (p.playing) {
        await p.pause();
      }
    } catch (_) {}
  }

  /// Heartbeat-driven correction (1 Hz). Gentler than _alignTo:
  ///  * never while a seek is settling or the player is buffering/loading
  ///    (that would restart the buffer = audible glitch),
  ///  * a hard seek needs the big drift on 2 consecutive heartbeats (or a
  ///    huge one), so a single delayed packet cannot make us jump,
  ///  * small drift is eased out with the +/-3% speed nudge.
  Future<void> _alignHeartbeat(int targetMs) async {
    final p = _player.player;
    final now = _mono.elapsedMilliseconds;
    if (!p.playing) {
      try {
        await p.play();
      } catch (_) {}
      return;
    }
    if (p.processingState != ProcessingState.ready) return;
    if (now < _settleUntilMono) return;

    final drift = _livePositionMs - targetMs; // + = guest ahead
    _lastDriftMs = drift;
    final abs = drift.abs();

    if (abs > _hardSeekMs) {
      _bigDrift++;
      if (_bigDrift >= 2 || abs > _hardSeekMs * 3) {
        _bigDrift = 0;
        _resetSpeed();
        _log('hard seek: drift ${drift}ms');
        await _hardSeek(targetMs, playing: true);
      } else if (_softSync) {
        _nudge(drift); // start easing right away
      }
      return;
    }
    _bigDrift = 0;
    if (_softSync && abs >= _softSyncMinMs) {
      _nudge(drift);
    } else {
      _resetSpeed();
    }
  }

  void _nudge(int driftMs) {
    final speed = driftMs > 0 ? 1.0 - _nudgeRate : 1.0 + _nudgeRate;
    _setSpeed(speed);
    _nudgeTimer?.cancel();
    final ms = (driftMs.abs() / _nudgeRate).round().clamp(250, 5000);
    _nudgeTimer = Timer(Duration(milliseconds: ms), _resetSpeed);
  }

  void _resetSpeed() {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
    if (_currentSpeed != 1.0) _setSpeed(1.0);
  }

  void _setSpeed(double speed) {
    if (_currentSpeed == speed) return;
    _currentSpeed = speed;
    try {
      unawaited(_player.player.setSpeed(speed).catchError((_) {}));
    } catch (_) {}
  }

  int effectivePosition(int position, int capturedAt, bool playing) {
    if (position <= 0 || !playing) return position;
    // Trustworthy clocks: exact transit time. Otherwise assume about one
    // round trip of transit (host -> server -> guest).
    final elapsed = (_clockValid && capturedAt > 0)
        ? _serverNow() - capturedAt
        : _rttMs;
    if (elapsed < 0 || elapsed > 60000) return position;
    return position + elapsed;
  }

  // ── HOST AUTO-BROADCAST ──

  void _rebindHostBroadcast() {
    _playingSub?.cancel();
    _playingSub = null;
    if (_songListener != null) {
      _player.currentSongNotifier.removeListener(_songListener!);
      _songListener = null;
    }
    _posSub?.cancel();
    _posSub = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _seekTrailing?.cancel();
    _seekTrailing = null;
    _seekPendingMs = null;
    if (!_isHost || !isInRoom) return;

    _resetSpeed(); // a host must never run at a nudged speed
    _lastPlaying = _playingNow;
    _hostPosSongId = _currentSongId;
    _hostLastPosMs = _livePositionMs;
    _hostLastPosMono = _mono.elapsedMilliseconds;
    _hostLastAdvancing = _isAdvancing();

    _posSub = _player.player.positionStream.listen(_onHostPosition);

    _playingSub = _player.player.playingStream.listen((playing) {
      if (!_isHost || _applyingRemote > 0) return;
      if (playing == _lastPlaying) return;
      _lastPlaying = playing;
      _patchIsPlaying(playing);
      _sendAction(
        playing ? 'play' : 'pause',
        trackId: _currentSongId,
        positionMs: _livePositionMs,
      );
    });

    // change_track fires the moment the load STARTS — guests buffer in
    // parallel with the host.
    _songListener = () {
      if (!_isHost || _applyingRemote > 0) return;
      final cur = _currentLtSong;
      if (cur == null || cur.id == _lastBroadcastSongId) return;
      _seekQuietUntilMono = _mono.elapsedMilliseconds + _trackChangeQuietMs;
      _broadcastTrack(cur);
    };
    _player.currentSongNotifier.addListener(_songListener!);

    // Heartbeat: guests compare it with their own position and correct.
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_isHost || !isInRoom) return;
      if (!_isAdvancing()) return;
      final id = _currentSongId;
      if (id == null) return;
      _sendAction('position', trackId: id, positionMs: _livePositionMs);
    });

    final current = _currentLtSong;
    if (current != null && current.id != _lastBroadcastSongId) {
      _broadcastTrack(current);
    }
  }

  bool _isAdvancing() {
    final p = _player.player;
    return p.playing && p.processingState == ProcessingState.ready;
  }

  /// Seek detection: position jumped away from where playback should be.
  /// Time is only counted as "advancing" when both the previous and the
  /// current sample were playing+ready, so pauses and buffering stalls do
  /// not look like seeks, while a real seek (even one that lands in
  /// buffering) does.
  void _onHostPosition(Duration d) {
    final pos = d.inMilliseconds;
    final now = _mono.elapsedMilliseconds;
    final id = _currentSongId;
    final adv = _isAdvancing();

    final songChanged = id != _hostPosSongId;
    final expected = _hostLastPosMs +
        ((_hostLastAdvancing && adv) ? now - _hostLastPosMono : 0);

    _hostPosSongId = id;
    _hostLastPosMs = pos;
    _hostLastPosMono = now;
    _hostLastAdvancing = adv;
    _lastPositionMs = pos;

    if (songChanged) {
      _seekQuietUntilMono = now + _trackChangeQuietMs;
      return;
    }
    if (!_isHost || !isInRoom || _applyingRemote > 0) return;
    if (now < _seekQuietUntilMono) return;
    if ((pos - expected).abs() > _seekDetectMs) _queueHostSeek(pos);
  }

  /// Leading edge goes out immediately (instant feel); while the user keeps
  /// dragging, further seeks are coalesced into one trailing send.
  void _queueHostSeek(int posMs) {
    final now = _mono.elapsedMilliseconds;
    final since = now - _lastSeekSentMono;
    if (since >= _seekThrottleMs && _seekTrailing == null) {
      _sendHostSeekNow(posMs);
      return;
    }
    _seekPendingMs = posMs;
    _seekTrailing ??= Timer(
        Duration(milliseconds: math.max(1, _seekThrottleMs - since)), () {
      _seekTrailing = null;
      final pending = _seekPendingMs;
      _seekPendingMs = null;
      if (pending != null && _isHost && isInRoom) _sendHostSeekNow(pending);
    });
  }

  void _sendHostSeekNow(int positionMs) {
    _lastSeekSentMono = _mono.elapsedMilliseconds;
    _sendAction('seek', trackId: _currentSongId, positionMs: positionMs);
  }

  void _broadcastTrack(LtSong cur) {
    _lastBroadcastSongId = cur.id;
    _sendAction(
      'change_track',
      trackId: cur.id,
      track: cur,
      queue: _queueLtSongs(),
      queueTitle: 'Listen Together',
    );
    _patchCurrentTrack(cur);
    final playing = _playingNow;
    _lastPlaying = playing;
    _sendAction(
      playing ? 'play' : 'pause',
      trackId: cur.id,
      positionMs: _livePositionMs,
    );
  }

  void _resendCurrentTrack() {
    final cur = _currentLtSong;
    if (cur == null) return;
    _broadcastTrack(cur);
  }

  // ── ROOM STATE HELPERS ──

  void _patchIsPlaying(bool playing) {
    final r = _room;
    if (r == null || r.isPlaying == playing) return;
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

  void _patchCurrentTrack(LtSong song) {
    final r = _room;
    if (r == null || r.currentTrack?.id == song.id) return;
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
    if (r == null || r.users.any((u) => u.userId == userId)) return;
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

  // ── KEEPALIVE + RECONNECT ──

  void _startPing() {
    _pingTimer?.cancel();
    _lastRxMono = _mono.elapsedMilliseconds;
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_channel == null) return;
      // Liveness = ANY inbound frame (pong, heartbeat, state...).
      if (_mono.elapsedMilliseconds - _lastRxMono > _livenessTimeoutMs) {
        _log('no inbound data for ${_livenessTimeoutMs}ms');
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
    _log('connection lost - reconnect attempt $_reconnectAttempts');
    _setPhase(LtPhase.reconnecting);
    _reconnectTimer =
        Timer(Duration(seconds: 2 * _reconnectAttempts), () async {
          try {
            await connect(); // now waits for the handshake
          } catch (_) {}
          if (_sessionToken != null && _handshaken) {
            _send('reconnect', {'session_token': _sessionToken});
          }
        });
  }

  void _setPhase(LtPhase p) {
    if (_phase == p) return;
    _phase = p;
    phaseNotifier.value = p;
    if (p == LtPhase.inRoom) _reconnectAttempts = 0;
  }
}

// ── MODELS ──

/// Sync health, refreshed once per second while in a room.
class LtSyncStats {
  const LtSyncStats({
    this.isHost = false,
    this.rttMs = 0,
    this.clockOffsetMs = 0,
    this.clockValid = false,
    this.driftMs = 0,
    this.heartbeatAgeMs = -1,
    this.speed = 1.0,
    this.playerState = 'idle',
  });

  static const idle = LtSyncStats();

  final bool isHost;
  final int rttMs;
  final int clockOffsetMs;
  final bool clockValid;

  /// Guest position minus host position (+ = guest ahead).
  final int driftMs;

  /// Milliseconds since the last host heartbeat (-1 = none yet).
  final int heartbeatAgeMs;
  final double speed;
  final String playerState;

  /// True when the guest is within ~150 ms of the host.
  bool get inSync => driftMs.abs() < 150;
}

enum LtPhase { disconnected, connecting, connected, inRoom, reconnecting }

class LtSong {
  LtSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final String thumbnail;
  final Duration duration;
}

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
  });

  final String roomCode;
  final String hostId;
  final List<LtUser> users;
  final LtSong? currentTrack;
  final bool isPlaying;
  final int positionMs;
  final int lastUpdateMs;
  final List<LtSong> queue;
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
  final LtSong song;
}

class LtSuggestionApprovedEvent extends LtEvent {
  LtSuggestionApprovedEvent(this.suggestionId, this.song);
  final String suggestionId;
  final LtSong song;
}

// ── PARSERS ──

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
    currentTrack: currentTrack == null ? null : mapToLtSong(currentTrack),
    isPlaying: isPlaying,
    positionMs: positionMs,
    lastUpdateMs: lastUpdate,
    queue: [for (final t in queue) mapToLtSong(t)],
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
      userId: userId,
      username: username,
      isHost: isHost,
      isConnected: connected);
}

(String, String) readUserIdName(Uint8List payload) {
  final r = PbReader(payload);
  return (r.readString(1), r.readString(2));
}

LtSong mapToLtSong(Map<String, dynamic> t) {
  return LtSong(
    id: '${t['id'] ?? ''}',
    title: '${t['title'] ?? 'Unknown'}',
    artist: '${t['artist'] ?? 'Unknown'}',
    thumbnail: '${t['thumbnail'] ?? ''}',
    duration: Duration(milliseconds: ((t['duration'] as num?) ?? 0).toInt()),
  );
}

// ── PROTO WIRE ──

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
    if (!value) return;
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

  int readIntField() => _varint();

  int readRawVarint() => _varint();

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        _varint();
      case 1:
        _pos += 8;
      case 2:
        _pos += _varint();
      case 5:
        _pos += 4;
      default:
        throw FormatException('unsupported wire type $wireType');
    }
  }
}