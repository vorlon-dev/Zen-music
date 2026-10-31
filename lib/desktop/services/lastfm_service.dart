import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';


const String kLastfmApiKey = '7889e20f0413188d242e87bffc1036e3';
const String kLastfmApiSecret = '087a65bc3bd239b48368f213ae2c0b94';
const int kLastfmCallbackPort = 51991;
class _Candidate {
  final String title;
  final String artist;
  final String album;
  final DateTime startedAt;

  Duration? total; // learned from the first position tick with a length
  bool scrobbled = false;

  _Candidate({
    required this.title,
    required this.artist,
    required this.album,
  }) : startedAt = DateTime.now();
}

class LastfmService {
  LastfmService._();
  static final LastfmService instance = LastfmService._();

  HttpClient? _http;
  bool _inited = false;
  bool _flushing = false;

  String? _sessionKey;
  _Candidate? _candidate;
  HttpServer? _callbackServer;
  Timer? _callbackTimeout;

  final ValueNotifier<String?> _user = ValueNotifier(null);

  /// Last.fm username once connected, null otherwise. The setup page
  /// listens to this to flip between Connect / Disconnect.
  ValueListenable<String?> get user => _user;

  bool get hasCredentials =>
      kLastfmApiKey.trim().isNotEmpty && kLastfmApiSecret.trim().isNotEmpty;

  bool get isConnected => _sessionKey != null;

  /// Call once at startup (idempotent). Safe on every platform.
  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final box = Hive.box('SETTINGS');
      final String? key = box.get('LASTFM_SESSION_KEY') as String?;
      final String? name = box.get('LASTFM_USER') as String?;
      if (key != null && key.isNotEmpty) {
        _sessionKey = key;
        _user.value = (name == null || name.isEmpty) ? 'connected' : name;
        unawaited(_flushQueue()); // send whatever piled up offline
      } else if (!hasCredentials) {
        debugPrint('[lastfm] disabled — set kLastfmApiKey/kLastfmApiSecret '
            'in lastfm_service.dart');
      }
    } catch (e) {
      debugPrint('[lastfm] init skipped: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════

  /// Starts the browser login. Returns a human-readable status for the
  /// setup page. When the local callback server catches the redirect the
  /// login completes on its own (the page reacts via [user]).
  Future<String> startLogin() async {
    await init();
    if (!hasCredentials) {
      return 'Set kLastfmApiKey and kLastfmApiSecret at the top of '
          'lastfm_service.dart first.';
    }
    if (isConnected) return 'Already connected as ${_user.value}.';

    String token;
    try {
      final res = await _writeCall('auth.getToken', const {},
          needsSession: false);
      token = (res['token'] as String?) ?? '';
    } catch (e) {
      return 'Could not reach Last.fm ($e) — check your internet.';
    }
    if (token.isEmpty) {
      return 'Last.fm did not return a login token — try again.';
    }

    // Local catch server for the post-approval redirect. Optional: if the
    // port is taken (or bound too slowly) the manual token paste on the
    // setup page completes the login instead.
    HttpServer? server;
    try {
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        kLastfmCallbackPort,
      ).timeout(const Duration(seconds: 3));
    } catch (_) {
      server = null;
    }

    try {
      await launchUrl(
        Uri.parse('https://www.last.fm/api/auth/'
            '?api_key=${Uri.encodeComponent(kLastfmApiKey.trim())}'
            '&token=${Uri.encodeComponent(token)}'
            '&cb=${Uri.encodeComponent('http://localhost:$kLastfmCallbackPort/')}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _stopCallbackServer();
      return 'Could not open a browser ($e). Open the authorization page '
          'manually, approve, then paste the token shown there.';
    }

    if (server == null) {
      return 'Browser opened. After approving, Last.fm shows a token on '
          'the page — paste it below to finish.';
    }
    _callbackServer = server;
    debugPrint('[lastfm] waiting for the authorization redirect on '
        'localhost:$kLastfmCallbackPort');
    _callbackTimeout = Timer(const Duration(minutes: 10), _stopCallbackServer);
    server.listen((HttpRequest req) async {
      final String? t = req.uri.queryParameters['token'];
      try {
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body style="font-family:sans-serif;'
            'text-align:center;padding-top:60px">'
            '<h2>ZenMusic is connected to Last.fm</h2>'
            '<p>You can close this tab and return to the app.</p>'
            '</body></html>');
        await req.response.close();
      } catch (_) {}
      if (t != null && t.isNotEmpty) {
        try {
          await _exchangeSession(t);
        } catch (e) {
          debugPrint('[lastfm] session exchange failed: $e');
        }
      }
      _stopCallbackServer();
    });
    return 'Browser opened — approve access in the Last.fm tab. The login '
        'finishes automatically when you return (or paste the token below).';
  }

  /// Manual completion path: Last.fm displays the token after approval;
  /// the user pastes it into the setup page.
  Future<String> completeLoginWithToken(String token) async {
    await init();
    final String t = token.trim();
    if (t.isEmpty) return 'Paste the token from the Last.fm page first.';
    if (!hasCredentials) {
      return 'Set kLastfmApiKey and kLastfmApiSecret in '
          'lastfm_service.dart first.';
    }
    try {
      return await _exchangeSession(t);
    } catch (e) {
      return 'Login failed ($e) — approve the app in the browser first, '
          'then paste a fresh token.';
    }
  }

  Future<String> _exchangeSession(String token) async {
    final res = await _writeCall('auth.getSession', {'token': token},
        needsSession: false);
    final session = res['session'] as Map<String, dynamic>?;
    final String? key = session?['key'] as String?;
    final String? name = session?['name'] as String?;
    if (key == null || key.isEmpty) {
      return 'Last.fm did not return a session key — try again.';
    }
    _sessionKey = key;
    _user.value = (name == null || name.isEmpty) ? 'connected' : name;
    final box = Hive.box('SETTINGS');
    await box.put('LASTFM_SESSION_KEY', key);
    await box.put('LASTFM_USER', _user.value);
    unawaited(_flushQueue());
    return 'Connected as ${_user.value}.';
  }

  /// Disconnects ZenMusic. The session key also disappears from Last.fm's
  /// side only when the user revokes the app in their Last.fm settings.
  Future<void> logout() async {
    _sessionKey = null;
    _user.value = null;
    try {
      final box = Hive.box('SETTINGS');
      await box.delete('LASTFM_SESSION_KEY');
      await box.delete('LASTFM_USER');
    } catch (_) {}
  }

  void _stopCallbackServer() {
    _callbackTimeout?.cancel();
    _callbackTimeout = null;
    final server = _callbackServer;
    _callbackServer = null;
    server?.close(force: true).catchError((_) {});
  }

  // ═══════════════════════════════════════════════════════════════════
  // PLAYER WIRING (called from media_player.dart, all platforms)
  // ═══════════════════════════════════════════════════════════════════

  /// A track became current. Sends "now playing" and arms the scrobble
  /// candidacy for the client-rules check in [progress].
  void trackChanged({
    required String title,
    required String artist,
    String? album,
  }) {
    final String t = title.trim();
    final String a = artist.trim();
    _candidate = (t.isEmpty || a.isEmpty)
        ? null
        : _Candidate(title: t, artist: a, album: (album ?? '').trim());
    final _Candidate? c = _candidate;
    if (c != null && isConnected) {
      _fire(() => _updateNowPlaying(c));
    }
  }

  /// Position tick from the player. Scrobbles once per candidate when the
  /// Last.fm client rules are met: heard ≥ half the track OR ≥ 4 minutes,
  /// and the track is longer than 30 s.
  void progress(Duration position, Duration total) {
    final _Candidate? c = _candidate;
    if (c == null || c.scrobbled || !isConnected) return;
    if (total > Duration.zero) c.total = total;
    if (total <= const Duration(seconds: 30)) return;
    final bool longEnough = position >= (total ~/ 2) ||
        position >= const Duration(minutes: 4);
    if (!longEnough) return;
    c.scrobbled = true;
    _fire(() => _scrobble(c));
  }

  // ═══════════════════════════════════════════════════════════════════
  // API CALLS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> _updateNowPlaying(_Candidate c) async {
    if (!isConnected) return;
    final params = <String, String>{
      'artist': c.artist,
      'track': c.title,
      if (c.album.isNotEmpty) 'album': c.album,
      if (c.total != null && c.total!.inSeconds > 0)
        'duration': c.total!.inSeconds.toString(),
    };
    await _writeCall('track.updateNowPlaying', params);
  }

  Future<void> _scrobble(_Candidate c) async {
    if (!isConnected) return;
    final entry = <String, dynamic>{
      'artist': c.artist,
      'track': c.title,
      'album': c.album,
      'timestamp': c.startedAt.millisecondsSinceEpoch ~/ 1000,
      'duration': c.total?.inSeconds ?? 0,
    };
    try {
      await _writeCall('track.scrobble', {
        'artist': c.artist,
        'track': c.title,
        if (c.album.isNotEmpty) 'album': c.album,
        'timestamp': (c.startedAt.millisecondsSinceEpoch ~/ 1000).toString(),
        if (c.total != null && c.total!.inSeconds > 0)
          'duration': c.total!.inSeconds.toString(),
      });
      unawaited(_flushQueue()); // good moment to push the backlog too
    } catch (e) {
      debugPrint('[lastfm] scrobble queued (offline?): $e');
      _enqueue(entry);
    }
  }

  /// Offline retry queue in SETTINGS/LASTFM_QUEUE, capped at 500 entries.
  void _enqueue(Map<String, dynamic> entry) {
    try {
      final box = Hive.box('SETTINGS');
      final raw = box.get('LASTFM_QUEUE') as List? ?? const [];
      final queue = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      queue.add(entry);
      while (queue.length > 500) {
        queue.removeAt(0);
      }
      box.put('LASTFM_QUEUE', queue);
    } catch (_) {}
  }

  /// Flushes the offline queue in batches of 50 (the API maximum).
  Future<void> _flushQueue() async {
    if (!isConnected || _flushing) return;
    _flushing = true;
    try {
      final box = Hive.box('SETTINGS');
      while (true) {
        final raw = box.get('LASTFM_QUEUE') as List? ?? const [];
        if (raw.isEmpty) break;
        final queue =
            raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final batch = queue.take(50).toList();
        final params = <String, String>{};
        for (int i = 0; i < batch.length; i++) {
          final e = batch[i];
          params['artist[$i]'] = (e['artist'] as String?) ?? '';
          params['track[$i]'] = (e['track'] as String?) ?? '';
          if (((e['album'] as String?) ?? '').isNotEmpty) {
            params['album[$i]'] = e['album'] as String;
          }
          params['timestamp[$i]'] = (e['timestamp'] as int? ?? 0).toString();
          if (((e['duration'] as int?) ?? 0) > 0) {
            params['duration[$i]'] = (e['duration'] as int).toString();
          }
        }
        await _writeCall('track.scrobble', params);
        await box.put('LASTFM_QUEUE', queue.sublist(batch.length));
        debugPrint('[lastfm] flushed ${batch.length} queued '
            'scrobble(s), ${queue.length - batch.length} left');
      }
    } catch (e) {
      debugPrint('[lastfm] queue flush paused: $e');
    } finally {
      _flushing = false;
    }
  }

  // ── Transport ──

  /// Signed Last.fm write call. Signs every parameter except format
  /// (alphabetical name+value concat + secret, md5 hex), then posts the
  /// body as application/x-www-form-urlencoded and returns the JSON reply.
  Future<Map<String, dynamic>> _writeCall(
    String method,
    Map<String, String> params, {
    bool needsSession = true,
  }) async {
    final String apiKey = kLastfmApiKey.trim();
    final Map<String, String> all = {
      'method': method,
      'api_key': apiKey,
      ...params,
    };
    if (needsSession) {
      final sk = _sessionKey;
      if (sk == null || sk.isEmpty) {
        throw StateError('not connected to Last.fm');
      }
      all['sk'] = sk;
    }
    all['api_sig'] = _sign(all);
    all['format'] = 'json';

    final http = _http ??= HttpClient();
    final request = await http
        .postUrl(Uri.parse('https://ws.audioscrobbler.com/2.0/'))
        .timeout(const Duration(seconds: 15));
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'utf-8',
    );
    request.write(Uri(queryParameters: all).query);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body =
        await response.transform(utf8.decoder).join().timeout(
              const Duration(seconds: 20),
            );
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Last.fm returned a non-JSON reply (HTTP '
          '${response.statusCode})');
    }
    if (map['error'] != null) {
      throw Exception('Last.fm error ${map['error']}: ${map['message']}');
    }
    return map;
  }

  /// api_sig = md5(sorted "namevalue" pairs + shared secret). format and
  /// callback are never signed (Last.fm authspec section 8).
  String _sign(Map<String, String> params) {
    final entries = params.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final sb = StringBuffer();
    for (final e in entries) {
      sb
        ..write(e.key)
        ..write(e.value);
    }
    sb.write(kLastfmApiSecret.trim());
    return md5.convert(utf8.encode(sb.toString())).toString();
  }

  /// Fire-and-swallow wrapper — a Last.fm hiccup can never take audio
  /// playback down with it.
  void _fire(Future<void> Function() action) {
    unawaited(Future<void>(() async {
      try {
        await action();
      } catch (e) {
        debugPrint('[lastfm] call failed (ignored): $e');
      }
    }));
  }
}
