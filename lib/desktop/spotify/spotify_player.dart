// ZenMusic — spotify playback resolution (SP-2).
// Ported from Stopify's SpotifyConnectService/SpotifyWebClient (MIT).
// ZenMusic remains GPL-3.0.
// Pipeline: login session (SpotifyAuth) -> Dealer WebSocket (connection-id)
// -> device registration -> connect-state play command -> state-machine
// manifest (file_ids_mp4 captured, incl. autoqueue) -> storage-resolve v2
// -> signed CDN URL. DEVIATION: Melody telemetry and cluster-state updater
// dropped (not required for resolve); errors surface instead of fallback
// bearer tokens.
//
// FIXES (CDN = null):
//  * Dealer connection-id header is matched case-insensitively (it is
//    "Spotify-Connection-Id").
//  * gzip+base64 dealer payloads are decoded.
//  * MANIFEST SCAN REWRITTEN: file ids are captured wherever they sit in a
//    payload (file_ids_mp4 / file_ids_mp4_dual), attributed to the nearest
//    enclosing spotify:track: uri, and also to relink aliases
//    (linked_from_uri / original_uri ...). Before, only
//    tracks[].manifest was read, so the requested track was missed while
//    its autoqueue neighbours were captured.
//  * RETRY USES A FRESH DEVICE ID: replaying "play" for the same context on
//    the same device produces no new state push (second attempt received
//    nothing). The retry registers a new random device id.
//  * Per-attempt wait is 10 s (two attempts fit a 30 s smoke test).
//  * Timeouts no longer turn into an empty file id; HTTP failures are
//    detected immediately; Completer double-complete fixed; concurrent
//    dealer connects de-duplicated.
//  * Diagnostics: "spotify: ..." at every stage, plus a per-payload list of
//    the tracks the dealer sent and what their manifest contained, and a
//    dump of the requested track's entry when it carries no file id.
//  * RELINK IDENTITY FIXED (wrong-song bug): a neighbour entry's file id is
//    only aliased to the requested track via explicit relink fields
//    (linked_from_uri / original_uri / ...). The old "metadata mentions the
//    wanted id" rule also matched context_uri — queue context — so the
//    SP-2 smoke aliased a radio neighbour (ATC) to the requested id and
//    would have played the wrong song.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';
import 'package:http/http.dart' as http;

class SpotifyResolvedTrack {
  const SpotifyResolvedTrack({
    required this.trackId,
    required this.uri,
    required this.cdnUrl,
    required this.fileId,
  });

  final String trackId;
  final String uri;
  final String cdnUrl;
  final String fileId;
}

class SpotifyPlayer {
  SpotifyPlayer._();
  static final SpotifyPlayer instance = SpotifyPlayer._();

  /// Set false to silence the "spotify: ..." diagnostics.
  static bool debugLogs = true;

  static const _manifestWait = Duration(seconds: 10);

  final SpotifyAuth _auth = SpotifyAuth.instance;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _pingTimer;
  bool _userClose = false;
  bool _handshaken = false;
  Future<String?>? _dealerInFlight;

  String? _connectionId;
  bool _deviceRegistered = false;
  int _seqNum = 2;

  /// Fresh random device id used by the retry attempt.
  String? _deviceOverride;

  /// Track id currently being resolved (diagnostics only).
  String? _wantedTrackId;

  // uri / trackId -> file_id (captured from state-machine manifests).
  final Map<String, String> _fileIds = {};
  // Pending resolve futures completed when the Dealer pushes a manifest.
  final Map<String, Completer<String>> _pending = {};

  void _log(String m) {
    if (debugLogs) debugPrint('spotify: $m');
  }

  String? get _deviceId {
    if (_deviceOverride != null) return _deviceOverride;
    final active =
    Hive.box('SETTINGS').get('SPOTIFY_ACTIVE_DEVICE_ID') as String?;
    return (active != null && active.isNotEmpty)
        ? active
        : SpotifyConfig.defaultDeviceId;
  }

  // ── DEALER WEBSOCKET ──

  Future<String?> _ensureDealer() {
    if (_channel != null && _handshaken) return Future.value(_connectionId);
    // One connect at a time (parallel resolves used to open several sockets).
    return _dealerInFlight ??=
        _connectDealer().whenComplete(() => _dealerInFlight = null);
  }

  /// Header lookup is case-insensitive; falls back to the pusher uri.
  String? _connIdFrom(Map json) {
    final headers = json['headers'];
    if (headers is Map) {
      for (final e in headers.entries) {
        final k = e.key.toString().toLowerCase();
        if (k == 'spotify-connection-id' || k == 'x-spotify-connection-id') {
          final v = e.value?.toString() ?? '';
          if (v.isNotEmpty) return v;
        }
      }
    }
    final uri = json['uri']?.toString() ?? '';
    const prefix = 'hm://pusher/v1/connections/';
    if (uri.startsWith(prefix) && uri.length > prefix.length) {
      return Uri.decodeComponent(uri.substring(prefix.length));
    }
    return null;
  }

  Future<String?> _connectDealer() async {
    final token = await _auth.getAccessToken();
    if (token == null) {
      _log('no access token: ${_auth.lastError ?? "unknown"}');
      return null;
    }

    _userClose = false;
    _connectionId = null;
    final completer = Completer<String?>();

    // NOTE: build the url as a string. Uri.replace(queryParameters: ...) on a
    // wss:// uri yields an explicit ":0" port and the connect then fails with
    // "was not upgraded to websocket".
    final baseUrl = SpotifyConfig.dealerWsUrl;
    final sep = baseUrl.contains('?') ? '&' : '?';
    final wsUri = Uri.parse(
        '$baseUrl${sep}access_token=${Uri.encodeQueryComponent(token)}');
    _log('dealer: connecting ${wsUri.host}');
    final channel = WebSocketChannel.connect(wsUri);
    _channel = channel;
    // Connection failures also surface on these futures; without handlers
    // they become "Unhandled Exception"s.
    channel.ready.then((_) {}, onError: (_) {});
    channel.sink.done.catchError((_) {});

    void closed() {
      // Ignore callbacks from an old, already replaced socket.
      if (!identical(_channel, channel)) return;
      _log('dealer: socket closed');
      _channel = null;
      _handshaken = false;
      _deviceRegistered = false;
      _connectionId = null;
      if (!completer.isCompleted) completer.complete(null);
    }

    _wsSub = channel.stream.listen(
          (data) {
        if (data is! String) return;
        try {
          final json = jsonDecode(data);
          if (json is! Map) return;

          if (_connectionId == null) {
            final connId = _connIdFrom(json);
            if (connId != null) {
              _connectionId = connId;
              _log('dealer: connection id received');
              if (!completer.isCompleted) completer.complete(connId);
            }
          }

          final type = json['type']?.toString() ?? '';
          if (type == 'pong') return;

          for (final pObj in _payloads(json)) {
            _scanPayload(pObj, json['uri']?.toString());

            // Remote commands (browser/phone control) — surfaced, not acted on.
            final cmd = pObj['command'];
            if (cmd is Map) {
              _log('remote command ${cmd['endpoint']}');
            }
          }
        } catch (e) {
          _log('dealer: message parse error $e');
        }
      },
      onDone: closed,
      onError: (e) {
        _log('dealer: socket error $e');
        closed();
      },
    );

    _startPing();
    final id = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (id != null && id.isNotEmpty) {
      _handshaken = true;
      return id;
    }
    _log('dealer: no connection id within 10 s');
    return null;
  }

  /// Dealer payloads: plain JSON objects, JSON strings, or gzip+base64
  /// strings (Transfer-Encoding: gzip).
  List<Map> _payloads(Map json) {
    final out = <Map>[];
    final arr = json['payloads'];
    if (arr is! List) return out;

    var gzipped = false;
    final headers = json['headers'];
    if (headers is Map) {
      for (final e in headers.entries) {
        if (e.key.toString().toLowerCase() == 'transfer-encoding' &&
            e.value.toString().toLowerCase() == 'gzip') {
          gzipped = true;
        }
      }
    }

    for (final item in arr) {
      if (item is Map) {
        out.add(item);
      } else if (item is String) {
        final s = item.trim();
        try {
          dynamic decoded;
          if (gzipped || s.startsWith('H4sI')) {
            decoded = jsonDecode(utf8.decode(gzip.decode(base64Decode(s))));
          } else if (s.startsWith('{')) {
            decoded = jsonDecode(s);
          }
          if (decoded is Map) out.add(decoded);
        } catch (_) {}
      }
    }
    return out;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      _send('ping', null);
    });
  }

  void _send(String type, Map<String, dynamic>? args) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode({
        'type': type,
        if (args != null && args.isNotEmpty) 'payloads': [args],
      }));
    } catch (_) {}
  }

  void _resetDealer() {
    _pingTimer?.cancel();
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _handshaken = false;
    _deviceRegistered = false;
    _connectionId = null;
    _dealerInFlight = null;
  }

  // ── DEVICE REGISTRATION ──

  Future<bool> _ensureRegistered() async {
    if (_deviceRegistered && _connectionId != null) return true;
    final connId = await _ensureDealer();
    if (connId == null || connId.isEmpty) return false;

    final token = await _auth.getAccessToken();
    if (token == null) return false;
    final clientToken = await _auth.getClientToken();
    final deviceId = _deviceId;

    try {
      final resp = await http
          .post(
          Uri.parse(
              '${SpotifyConfig.spclientBase}/track-playback/v1/devices'),
          headers: {
            'authorization': 'Bearer $token',
            'client-token': clientToken,
            'content-type': 'application/json;charset=UTF-8',
            'app-platform': SpotifyConfig.appPlatform,
            'spotify-app-version': SpotifyConfig.spotifyAppVersion,
            'origin': 'https://open.spotify.com',
            'referer': 'https://open.spotify.com/',
          },
          body: jsonEncode({
            'device': {
              'brand': 'spotify',
              'capabilities': {
                'change_volume': true,
                'enable_play_token': true,
                'supports_file_media_type': true,
                'play_token_lost_behavior': 'pause',
                'disable_connect': false,
                'audio_podcasts': true,
                'video_playback': true,
                'manifest_formats': ['file_ids_mp4', 'file_ids_mp4_dual'],
                'supports_preferred_media_type': true,
                'supports_playback_offsets': true,
                'supports_playback_speed': true,
              },
              'device_id': deviceId,
              'device_type': 'computer',
              'metadata': {},
              'model': 'web_player',
              'name': 'ZenMusic Player',
              'platform_identifier': SpotifyConfig.userAgent
                  .replaceAll('Mozilla/5.0 ', ''),
              'is_group': false,
              'is_public': true,
              'client_version': 'harmony:4.80.0-3cdf02c91',
            },
            'outro_endcontent_snooping': false,
            'connection_id': connId,
            'client_version': 'harmony:4.80.0-3cdf02c91',
            'volume': 65535,
          }))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _deviceRegistered = true;
        _log('device registered (${resp.statusCode})');
        try {
          final seq =
          (jsonDecode(resp.body) as Map)['initial_seq_num'] as int?;
          if (seq != null && seq > 0) _seqNum = seq;
        } catch (_) {}
        return true;
      }
      _log('device registration FAILED ${resp.statusCode}: '
          '${_short(resp.body)}');
      return false;
    } catch (e) {
      _log('device registration error: $e');
      return false;
    }
  }

  // ── CONNECT-STATE PLAY COMMAND ──

  Future<bool> _sendPlayCommand(String trackUri) async {
    final token = await _auth.getAccessToken();
    if (token == null) return false;
    final clientToken = await _auth.getClientToken();
    final deviceId = _deviceId;
    final cmdId = _hex(32);

    try {
      final resp = await http
          .post(
          Uri.parse(
              '${SpotifyConfig.spclientBase}/connect-state/v1/player/command/from/$deviceId/to/$deviceId'),
          headers: {
            'authorization': 'Bearer $token',
            'client-token': clientToken,
            'content-type': 'application/json;charset=UTF-8',
            'app-platform': SpotifyConfig.appPlatform,
            'spotify-app-version': SpotifyConfig.spotifyAppVersion,
            'origin': 'https://open.spotify.com',
            'referer': 'https://open.spotify.com/',
            'user-agent': SpotifyConfig.userAgent,
          },
          body: jsonEncode({
            'command': {
              'context': {
                'uri': trackUri,
                'url': 'context://$trackUri',
                'metadata': {},
              },
              'play_origin': {
                'feature_identifier': 'search',
                'feature_version':
                'web-player_2026-10-12_1791795388600_2b2ea800fe12',
                'referrer_identifier': 'search',
              },
              'options': {
                'license': 'tft',
                'skip_to': {},
                'player_options_override': {},
              },
              'logging_params': {
                'page_instance_ids': [
                  'b5bed12a-02cd-4529-8659-da9f174cdeca'
                ],
                'interaction_ids': [
                  'ee768f0f-6e4c-49ed-8f17-338dad1a83f2'
                ],
                'command_id': cmdId,
              },
              'endpoint': 'play',
            },
          }))
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _log('play command accepted (${resp.statusCode})');
        return true;
      }
      _log('play command FAILED ${resp.statusCode}: ${_short(resp.body)}');
      return false;
    } catch (e) {
      _log('play command error: $e');
      return false;
    }
  }

  String _hex(int n) {
    final r = Random.secure();
    const hex = '0123456789abcdef';
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(hex[r.nextInt(16)]);
    }
    return sb.toString();
  }

  String _short(String s, [int n = 200]) =>
      s.length > n ? '${s.substring(0, n)}…' : s;

  // ── MANIFEST CAPTURE (file_ids + autoqueue) ──

  /// Walks a dealer payload, captures every file id it can attribute to a
  /// spotify:track: uri, and prints what tracks the dealer sent.
  void _scanPayload(Map payload, String? messageUri) {
    final diag = <String>[];
    _scan(payload, null, 0, diag);
    if (diag.isNotEmpty) {
      _log('dealer ${messageUri ?? ''} tracks: ${diag.join('  ')}');
      final w = _wantedTrackId;
      if (w != null && !_fileIds.containsKey('spotify:track:$w')) {
        _log('payload structure (manifests redacted): '
            '${_short(jsonEncode(_redact(payload)), 3500)}');
      }
    }
  }

  /// Copy of a payload without file ids / manifests and with long strings
  /// and lists cut, safe to print.
  dynamic _redact(dynamic n, [int depth = 0]) {
    if (depth > 10) return '…';
    if (n is Map) {
      final out = <String, dynamic>{};
      n.forEach((k, v) {
        final key = '$k';
        out[key] = (key == 'manifest' || key.startsWith('file_ids'))
            ? '<redacted>'
            : _redact(v, depth + 1);
      });
      return out;
    }
    if (n is List) {
      final items = [for (final v in n.take(6)) _redact(v, depth + 1)];
      if (n.length > 6) items.add('…+${n.length - 6} more');
      return items;
    }
    if (n is String && n.length > 80) return '${n.substring(0, 80)}…';
    return n;
  }

  void _scan(dynamic node, String? ctxUri, int depth, List<String> diag) {
    if (depth > 14) return;
    if (node is List) {
      for (final v in node) {
        _scan(v, ctxUri, depth + 1, diag);
      }
      return;
    }
    if (node is! Map) return;

    final ownUri = _trackUriOf(node);
    final uri = ownUri ?? ctxUri;

    // File id sitting directly in this node (e.g. the manifest map itself).
    final fileId = _fileIdIn(node);
    if (fileId != null && uri != null) {
      _remember(uri, fileId, _aliasesOf(node));
    }

    for (final v in node.values) {
      _scan(v, uri, depth + 1, diag);
    }

    // Diagnostics for track-like entries (metadata.uri present).
    final meta = node['metadata'];
    if (ownUri != null && meta is Map) {
      final clean = ownUri.replaceAll('spotify:track:', '');
      final manifest = node['manifest'];
      final mk = manifest is Map ? manifest.keys.join(',') : 'none';
      final got = _fileIds.containsKey(ownUri) ? 'ok' : 'NO-FILE-ID';
      diag.add('$clean[manifest:$mk|$got]');

      final wanted = _wantedTrackId;
      if (wanted != null && clean != wanted) {
        final wantedUri = 'spotify:track:$wanted';
        final fid = _fileIds[ownUri];
        // Relinked track: identity comes from explicit relink fields ONLY
        // (linked_from_uri & co, via _aliasesOf). NEVER context_uri — that
        // is queue context, and matching on any mention once aliased a
        // radio neighbour's file id to the requested track.
        if (fid != null &&
            !_fileIds.containsKey(wantedUri) &&
            _aliasesOf(node).contains('spotify:track:$wanted')) {
          _log('entry $clean references $wanted -> using it as the '
              'relinked version');
          _remember(wantedUri, fid);
        }
        _log('entry $clean metadata: ${_short(jsonEncode(_redact(meta)), 600)}');
      }
      if (clean == _wantedTrackId && got == 'NO-FILE-ID') {
        _log('wanted track entry without file id: '
            '${_short(jsonEncode(node), 1500)}');
      }
    }
  }

  String? _trackUriOf(Map node) {
    final meta = node['metadata'];
    final candidates = [
      if (meta is Map) meta['uri'],
      node['track_uri'],
      node['uri'],
    ];
    for (final c in candidates) {
      if (c is String && c.startsWith('spotify:track:')) return c;
    }
    return null;
  }

  /// Relinked tracks: the playable file belongs to another track id.
  List<String> _aliasesOf(Map node) {
    final out = <String>[];
    final meta = node['metadata'];
    if (meta is Map) {
      for (final k in const [
        'linked_from_uri',
        'original_uri',
        'canonical_uri',
        'original_track_uri',
        'linked_from',
      ]) {
        final v = meta[k];
        if (v is String && v.startsWith('spotify:track:')) out.add(v);
        if (v is Map && v['uri'] is String) {
          final u = v['uri'] as String;
          if (u.startsWith('spotify:track:')) out.add(u);
        }
      }
    }
    return out;
  }

  String? _fileIdIn(Map node) {
    for (final key in const ['file_ids_mp4', 'file_ids_mp4_dual']) {
      final arr = node[key];
      if (arr is List) {
        for (final e in arr) {
          final id = e is Map ? e['file_id']?.toString() : null;
          if (id != null && id.isNotEmpty) return id;
        }
      }
    }
    return null;
  }

  void _remember(String uri, String fileId, [List<String> aliases = const []]) {
    for (final u in [uri, ...aliases]) {
      final clean = u.replaceAll('spotify:track:', '');
      final isNew = _fileIds[u] != fileId;
      _fileIds[u] = fileId;
      _fileIds[clean] = fileId;
      if (isNew) {
        final orig = uri.replaceAll('spotify:track:', '');
        _log('manifest captured for $clean'
            '${u == uri ? '' : ' (alias of $orig)'}');
      }
      _completePending(u, fileId);
      _completePending(clean, fileId);
    }
  }

  void _completePending(String key, String fileId) {
    final c = _pending.remove(key);
    if (c != null && !c.isCompleted) c.complete(fileId);
  }

  // ── PUBLIC RESOLVE ──

  /// Resolves a track (id or spotify:track: uri) to a signed CDN URL.
  /// Returns null on failure; the reason is printed as "spotify: ...".
  Future<String?> resolveTrack(String trackIdOrUri) async {
    final uri = trackIdOrUri.startsWith('spotify:track:')
        ? trackIdOrUri
        : 'spotify:track:$trackIdOrUri';
    final trackId = uri.replaceAll('spotify:track:', '');

    // 1. Cached file_id?
    var fileId = _fileIds[uri] ?? _fileIds[trackId];

    // 2. Dealer pipeline. The retry starts from a fresh connection AND a
    //    fresh device id (re-playing on the same device pushes no new state).
    for (var attempt = 0; attempt < 2 && fileId == null; attempt++) {
      if (attempt > 0) {
        _log('retrying $trackId with a fresh dealer connection + device id');
        _resetDealer();
        _deviceOverride = _hex(40);
      }
      fileId = await _fetchFileId(uri, trackId);
    }

    if (fileId == null) {
      _log('no file_id for $trackId');
      return null;
    }
    final cdn = await _resolveCdn(fileId);
    _log(cdn == null ? 'CDN resolve FAILED for $trackId' : 'CDN ok for $trackId');
    return cdn;
  }

  /// register -> play command -> wait for the manifest on the Dealer.
  Future<String?> _fetchFileId(String uri, String trackId) async {
    if (!await _ensureRegistered()) return null;

    _wantedTrackId = trackId;
    final pending = Completer<String>();
    _pending[uri] = pending;
    _pending[trackId] = pending;

    try {
      if (!await _sendPlayCommand(uri)) return null;

      final id = await pending.future.timeout(
        _manifestWait,
        onTimeout: () => '',
      );
      if (id.isNotEmpty) return id;

      // The manifest may have landed just before the timeout fired.
      final cached = _fileIds[uri] ?? _fileIds[trackId];
      if (cached == null) {
        _log('timeout: dealer never pushed a manifest for $trackId');
      }
      return cached;
    } finally {
      _pending.remove(uri);
      _pending.remove(trackId);
    }
  }

  /// storage-resolve v2 -> signed CDN URL (audio-ak.spotifycdn.com).
  Future<String?> _resolveCdn(String fileId) async {
    final token = await _auth.getAccessToken();
    if (token == null) return null;
    final clientToken = await _auth.getClientToken();
    try {
      final resp = await http
          .get(
          Uri.parse(
              '${SpotifyConfig.spclientBase}/storage-resolve/v2/files/audio/interactive/10/$fileId?version=10000000&product=9&platform=39&alt=json'),
          headers: {
            'Authorization': 'Bearer $token',
            'client-token': clientToken,
            'User-Agent': SpotifyConfig.userAgent,
            'app-platform': SpotifyConfig.appPlatform,
            'spotify-app-version': SpotifyConfig.spotifyAppVersion,
          })
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _log('storage-resolve FAILED ${resp.statusCode}: ${_short(resp.body)}');
        return null;
      }
      final body = jsonDecode(resp.body) as Map;
      final cdn = body['cdnurl'] as List?;
      if (cdn != null && cdn.isNotEmpty) return cdn.first as String;
      _log('storage-resolve returned no cdnurl: ${_short(resp.body)}');
      return null;
    } catch (e) {
      _log('storage-resolve error: $e');
      return null;
    }
  }

  /// Pre-resolve in the background (queue warm-up).
  Future<void> preResolve(String trackIdOrUri) async {
    unawaited(resolveTrack(trackIdOrUri).catchError((_) => null));
  }

  void dispose() {
    _userClose = true;
    _resetDealer();
  }
}