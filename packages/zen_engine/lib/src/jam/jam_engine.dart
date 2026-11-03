import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/song_model.dart';

enum JamRole { host, guest, none }

/// Listen Together (Jam) real-time synchronized playback engine.
class JamEngine {
  JamEngine({this.serverUrl = 'wss://metroserver.up.railway.app'});

  final String serverUrl;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  JamRole _role = JamRole.none;
  String? _roomId;
  bool _connected = false;

  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messagesStream => _messagesController.stream;
  JamRole get role => _role;
  String? get roomId => _roomId;
  bool get isConnected => _connected;

  /// Create a new Listen Together room as Host
  Future<String?> createRoom() async {
    final completer = Completer<String?>();
    try {
      _disconnect();
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _channel!.sink.add(jsonEncode({'type': 'create_room'}));

      _sub = _channel!.stream.listen((data) {
        final map = jsonDecode(data as String) as Map<String, dynamic>;
        if (map['type'] == 'room_created') {
          _roomId = map['room_id'] as String?;
          _role = JamRole.host;
          _connected = true;
          if (!completer.isCompleted) completer.complete(_roomId);
        }
        _messagesController.add(map);
      }, onError: (e) {
        _disconnect();
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        _disconnect();
      });
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// Join an existing room as Guest
  Future<bool> joinRoom(String roomId) async {
    final completer = Completer<bool>();
    try {
      _disconnect();
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _channel!.sink.add(jsonEncode({
        'type': 'join_room',
        'room_id': roomId,
      }));

      _sub = _channel!.stream.listen((data) {
        final map = jsonDecode(data as String) as Map<String, dynamic>;
        if (map['type'] == 'joined_room' || map['type'] == 'room_state') {
          _roomId = roomId;
          _role = JamRole.guest;
          _connected = true;
          if (!completer.isCompleted) completer.complete(true);
        }
        _messagesController.add(map);
      }, onError: (e) {
        _disconnect();
        if (!completer.isCompleted) completer.complete(false);
      }, onDone: () {
        _disconnect();
      });
    } catch (e) {
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  /// Broadcast track change to all members in room (Host only)
  void broadcastTrack(ZenSong song) {
    if (_role != JamRole.host || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'sync_track',
      'room_id': _roomId,
      'song': song.toMap(),
    }));
  }

  /// Broadcast play/pause state to all members
  void broadcastPlayback(bool playing, Duration position) {
    if (_role != JamRole.host || _channel == null) return;
    _channel!.sink.add(jsonEncode({
      'type': 'sync_playback',
      'room_id': _roomId,
      'playing': playing,
      'positionMs': position.inMilliseconds,
    }));
  }

  void leaveRoom() {
    _disconnect();
  }

  void _disconnect() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _role = JamRole.none;
    _roomId = null;
    _connected = false;
  }

  void dispose() {
    _disconnect();
    _messagesController.close();
  }
}
