import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, PlatformDispatcher, Rect, Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show runApp, WidgetsFlutterBinding;

import '../screens/lyrics_overlay_page.dart';
import '../utils/win32_window_utils.dart';
import 'lyrics_service.dart';
import 'package:zenmusic/desktop/spotify/spotify_lyrics.dart';

/// Track metadata mirrored into the overlay window.
class OverlayTrack {
  final String title;
  final String artist;
  final String? artUri;

  /// Album name — improves the LRCLIB match (may be null).
  final String? album;

  /// Track duration in ms — powers LRCLIB's ±5 s duration gate.
  final int? durationMs;

  /// Spotify URI when the track came from the Spotify search section —
  /// enables the Color Lyrics path, same as the in-player LyricsBox.
  final String? spotifyUri;

  const OverlayTrack({
    required this.title,
    required this.artist,
    this.artUri,
    this.album,
    this.durationMs,
    this.spotifyUri,
  });
}

/// One timed lyric line mirrored into the overlay window.
class OverlayLyricLine {
  final int timeMs;
  final String text;

  const OverlayLyricLine(this.timeMs, this.text);
}

class LyricsOverlayBridge {
  LyricsOverlayBridge._();

  static final LyricsOverlayBridge instance = LyricsOverlayBridge._();

  static const String _tag = '[overlay]';

  /// FindWindow-friendly title — the Win32 topmost helper locates the
  /// overlay's HWND by this exact string.
  static const String kOverlayWindowTitle = 'ZenMusic Lyrics';

  // Overlay geometry in logical pixels. The plugin's setFrame takes
  // PHYSICAL pixels, so the size is scaled by the display's
  // devicePixelRatio before being applied.
  static const double _overlayWidth = 420;
  static const double _overlayHeight = 640;

  // ── main-window side state ──────────────────────────────────────────
  int? _overlayWindowId; // live overlay window id (main window is 0)
  bool _opening = false;
  bool _mainArmed = false;
  bool _pinned = true;
  OverlayTrack? _lastTrack;
  Duration _lastCurrent = Duration.zero;
  Duration _lastTotal = Duration.zero;
  DateTime _lastPosSend = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lyricsKey; // which track the cached lyrics payload belongs to
  Map<String, dynamic>? _lastLyricsPayload;

  // ── overlay-window side state (only used inside the overlay engine) ──
  final ValueNotifier<OverlayTrack?> overlayTrack =
      ValueNotifier<OverlayTrack?>(null);

  /// 'loading' | 'synced' | 'plain' | 'instrumental' | 'none'
  final ValueNotifier<String> overlayStatus = ValueNotifier<String>('loading');
  final ValueNotifier<List<OverlayLyricLine>?> overlayLines =
      ValueNotifier<List<OverlayLyricLine>?>(null);
  final ValueNotifier<String?> overlayPlain = ValueNotifier<String?>(null);
  final ValueNotifier<Duration> overlayPosition =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> overlayDuration =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> overlayPinned = ValueNotifier<bool>(true);

  bool _overlayMode = false; // true inside the overlay engine
  int? _overlayId; // this overlay window's own id (overlay engine only)

  bool get isOverlayWindow => _overlayMode;
  bool get isWindowOpen => _overlayWindowId != null;

  // ═══════════════════════════════════════════════════════════════════
  // MAIN WINDOW SIDE
  // ═══════════════════════════════════════════════════════════════════

  /// Arms the receiver for commands coming back from overlay windows.
  /// Called once from MediaPlayer's `_initLyricsOverlay()`.
  Future<void> init() async {
    if (_overlayMode || _mainArmed) return;
    _mainArmed = true;
    DesktopMultiWindow.setMethodHandler(_onMainEvent);
  }

  Future<dynamic> _onMainEvent(MethodCall call, int fromWindowId) async {
    if (_overlayMode) return null;
    if (call.method != 'command') return null;
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? const {};
    final String cmd = args['cmd'] as String? ?? '';
    switch (cmd) {
      case 'hello':
        // A fresh overlay engine finished booting — bind to it (this also
        // re-binds after the user closed an older one via its title-bar X)
        // and push the full current state so the overlay is never blank.
        debugPrint(
            '$_tag overlay window $fromWindowId is up — pushing snapshot');
        _overlayWindowId = fromWindowId;
        _pushSnapshot();
        break;
      case 'close':
        debugPrint('$_tag overlay window asked to close');
        await closeOverlay();
        break;
      case 'pin':
        final bool value = args['value'] as bool? ?? !_pinned;
        _pinned = value;
        _applyPinned();
        _send('pinned', <String, dynamic>{'value': _pinned});
        break;
      default:
        debugPrint('$_tag ignored command "$cmd" from window $fromWindowId');
    }
    return null;
  }

  /// Opens (or re-opens) the lyrics overlay. Always closes any previous
  /// overlay window first and creates a fresh one — stale window ids are
  /// harmless (the plugin reports "target window not found") and a fresh
  /// window can never be left pointing at a window the user already
  /// closed.
  Future<void> openOverlay() async {
    if (_overlayMode) {
      return;
    }
    if (_opening) {
      return;
    }
    _opening = true;
    try {
      if (_overlayWindowId != null) {
        try {
          await WindowController.fromWindowId(_overlayWindowId!).close();
        } catch (_) {}
        _overlayWindowId = null;
      }
      final WindowController window = await DesktopMultiWindow.createWindow(
        jsonEncode(<String, String>{'type': 'zenlyrics'}),
      );
      _overlayWindowId = window.windowId;
      final double dpr =
          PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
      await window.setTitle(kOverlayWindowTitle);
      await window.setFrame(
        const Offset(0, 0) & Size(_overlayWidth * dpr, _overlayHeight * dpr),
      );
      await window.center();
      await window.show();
      debugPrint(
          '$_tag overlay window ${window.windowId} created (dpr $dpr)');
      _applyPinned();
      _pushSnapshot();
      // Insurance against the fresh engine's handler not being armed in
      // time: push once more shortly after. Harmless if redundant.
      Timer(const Duration(milliseconds: 500), _pushSnapshot);
    } catch (e) {
      debugPrint('$_tag openOverlay failed (ignored): $e');
    } finally {
      _opening = false;
    }
  }

  /// Always-on-top is what makes an overlay useful. desktop_multi_window
  /// 0.2.1 has no API for it, so win32_window_utils.dart asks user32
  /// directly (Windows only). The native window can lag a few frames
  /// behind creation, so the pin is re-applied shortly after opening —
  /// FindWindow + SetWindowPos are idempotent.
  void _applyPinned() {
    if (_overlayMode) return;
    Win32WindowUtils.instance.setTopmostByTitle(kOverlayWindowTitle, _pinned);
    if (!_pinned) return;
    for (final int delayMs in const <int>[400, 1200]) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (_overlayWindowId != null && _pinned && !_overlayMode) {
          Win32WindowUtils.instance
              .setTopmostByTitle(kOverlayWindowTitle, true);
        }
      });
    }
  }

  Future<void> closeOverlay() async {
    final int? id = _overlayWindowId;
    _overlayWindowId = null;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).close();
    } catch (e) {
      debugPrint('$_tag close failed (ignored): $e');
    }
  }

  /// Closes the overlay window (and sweeps any strays). Called from
  /// MediaPlayer.dispose().
  Future<void> shutdown() async {
    await closeOverlay();
    try {
      final List<int> strays = await DesktopMultiWindow.getAllSubWindowIds();
      for (final int id in strays) {
        try {
          await WindowController.fromWindowId(id).close();
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ── state pushes (wired to the MediaPlayer notifiers) ───────────────

  void pushTrack(OverlayTrack? track) {
    if (_overlayMode) return;
    _lastTrack = track;
    _send('track', <String, dynamic>{
      'title': track?.title,
      'artist': track?.artist,
      'artUri': track?.artUri,
    });
    unawaited(_fetchLyrics(track));
  }

  /// Same chain the in-player LyricsBox uses (SP-10 Spotify Color Lyrics →
  /// SP-15 LRCLIB with cleaned metadata + duration gate + Hive cache).
  /// The overlay engine never fetches — it only renders.
  Future<void> _fetchLyrics(OverlayTrack? track) async {
    if (track == null) {
      _lyricsKey = null;
      _lastLyricsPayload = null;
      _send('lyrics', const <String, dynamic>{'status': 'none'});
      return;
    }
    final String key =
        '${track.title}|${track.artist}|${track.durationMs ?? 0}';
    if (_lyricsKey == key) return; // already fetched (or fetching)
    _lyricsKey = key;
    _lastLyricsPayload = null;
    _send('lyrics', const <String, dynamic>{'status': 'loading'});
    try {
      LyricsData? data;

      // 1. Spotify Color Lyrics (SP-10 path, same as LyricsBox).
      if ((track.spotifyUri ?? '').isNotEmpty) {
        try {
          final dynamic sp = await SpotifyLyricsService.instance
              .fetchColorLyrics(track.spotifyUri!, coverUrl: track.artUri);
          if (sp != null && sp.lines.isNotEmpty) {
            final StringBuffer buf = StringBuffer();
            for (final dynamic line in sp.lines) {
              final String minutes =
                  (line.startTimeMs ~/ 60000).toString().padLeft(2, '0');
              final String seconds = ((line.startTimeMs % 60000) / 1000)
                  .toStringAsFixed(2)
                  .padLeft(5, '0');
              buf.writeln('[$minutes:$seconds] ${line.words}');
            }
            final List<LyricLine> lines = LrcParser.parse(buf.toString().trim());
            if (lines.isNotEmpty) {
              data = LyricsData(
                trackName: track.title,
                artistName: track.artist,
                synced: lines,
                plain: null,
                instrumental: false,
                wordSync: false,
              );
            }
          }
        } catch (_) {}
      }

      // 2. LRCLIB (SP-15): cleaned metadata, ±5 s duration gate, Hive cache.
      data ??= await LyricsService.lookup(
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMs: track.durationMs,
      );

      // A newer track may have taken over while we were fetching.
      if (_lyricsKey != key) return;

      final bool hasAny = data != null &&
          (data.hasSynced ||
              data.instrumental ||
              (data.plain != null && data.plain!.trim().isNotEmpty));
      if (!hasAny) {
        _lastLyricsPayload = const <String, dynamic>{'status': 'none'};
      } else if (data.hasSynced) {
        _lastLyricsPayload = <String, dynamic>{
          'status': 'synced',
          'lines': <Map<String, dynamic>>[
            for (final LyricLine l in data.synced!)
              <String, dynamic>{'t': l.timeMs, 'text': l.text},
          ],
        };
      } else if (data.instrumental) {
        _lastLyricsPayload = const <String, dynamic>{'status': 'instrumental'};
      } else {
        _lastLyricsPayload = <String, dynamic>{
          'status': 'plain',
          'plain': data.plain,
        };
      }
      _send('lyrics', _lastLyricsPayload!);
    } catch (e) {
      if (_lyricsKey == key) {
        _lastLyricsPayload = const <String, dynamic>{'status': 'none'};
        _send('lyrics', _lastLyricsPayload!);
      }
    }
  }

  void pushPosition(Duration current, Duration total) {
    if (_overlayMode) return;
    _lastCurrent = current;
    _lastTotal = total;
    // Line-following only needs ~2 updates per second.
    final DateTime now = DateTime.now();
    if (now.difference(_lastPosSend) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastPosSend = now;
    _send('position', <String, dynamic>{
      'currentMs': current.inMilliseconds,
      'totalMs': total.inMilliseconds,
    });
  }

  void _pushSnapshot() {
    if (_overlayMode || _overlayWindowId == null) return;
    _send('track', <String, dynamic>{
      'title': _lastTrack?.title,
      'artist': _lastTrack?.artist,
      'artUri': _lastTrack?.artUri,
    });
    _send('pinned', <String, dynamic>{'value': _pinned});
    _send('position', <String, dynamic>{
      'currentMs': _lastCurrent.inMilliseconds,
      'totalMs': _lastTotal.inMilliseconds,
    });
    if (_lastLyricsPayload != null) {
      _send('lyrics', _lastLyricsPayload!);
    } else if (_lastTrack != null) {
      // Track known but no lyrics yet (still fetching) — the in-flight
      // fetch pushes when done; re-arm the loading state just in case.
      _send('lyrics', const <String, dynamic>{'status': 'loading'});
    }
  }

  void _send(String method, Map<String, dynamic> args) {
    final int? target = _overlayWindowId;
    if (target == null) return;
    unawaited(_doSend(target, method, args));
  }

  Future<void> _doSend(
      int target, String method, Map<String, dynamic> args) async {
    try {
      await DesktopMultiWindow.invokeMethod(target, method, args);
    } catch (e) {
      // An overlay closed via its native title-bar X surfaces here as
      // "target window not found" — forget it so the pushes stop.
      if ('$e'.contains('not found')) _overlayWindowId = null;
      debugPrint('$_tag push "$method" failed (ignored): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // OVERLAY WINDOW SIDE (runs inside the second engine)
  // ═══════════════════════════════════════════════════════════════════

  /// Entry for the overlay engine — routed from lib/desktop/main.dart when
  /// main() receives the plugin's ['multi_window', windowId, …] args with
  /// payload type 'zenlyrics'. Fire-and-forget so main() returns at once.
  static void runLyricsOverlay(int windowId) {
    _bootstrapOverlay(windowId);
  }

  static Future<void> _bootstrapOverlay(int windowId) async {
    WidgetsFlutterBinding.ensureInitialized();
    final LyricsOverlayBridge bridge = instance;
    bridge._overlayMode = true;
    bridge._overlayId = windowId;
    DesktopMultiWindow.setMethodHandler(bridge._onOverlayEvent);
    // Tell the main window we exist so it binds to us and pushes a
    // snapshot.
    await _sendToMain('command', const <String, dynamic>{'cmd': 'hello'});
    runApp(const LyricsOverlayApp());
  }

  Future<dynamic> _onOverlayEvent(MethodCall call, int fromWindowId) async {
    if (!_overlayMode) return null;
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? const {};
    switch (call.method) {
      case 'track':
        final String? title = args['title'] as String?;
        overlayTrack.value = title == null
            ? null
            : OverlayTrack(
                title: title,
                artist: args['artist'] as String? ?? '',
                artUri: args['artUri'] as String?,
              );
        break;
      case 'lyrics':
        final String status = args['status'] as String? ?? 'none';
        overlayStatus.value = status;
        if (status == 'synced') {
          final List<dynamic> raw = (args['lines'] as List?) ?? const [];
          overlayLines.value = raw
              .map((dynamic e) => OverlayLyricLine(
                    (e['t'] as num?)?.toInt() ?? 0,
                    (e['text'] as String?) ?? '',
                  ))
              .toList();
          overlayPlain.value = null;
        } else if (status == 'plain') {
          overlayPlain.value = args['plain'] as String?;
          overlayLines.value = null;
        } else {
          overlayLines.value = null;
          overlayPlain.value = null;
        }
        break;
      case 'position':
        overlayPosition.value = Duration(
            milliseconds: (args['currentMs'] as num?)?.toInt() ?? 0);
        overlayDuration.value =
            Duration(milliseconds: (args['totalMs'] as num?)?.toInt() ?? 0);
        break;
      case 'pinned':
        overlayPinned.value = args['value'] as bool? ?? true;
        break;
      default:
        break;
    }
    return null;
  }

  /// Button pressed inside the overlay. 'close' additionally arms a
  /// self-close fallback in case the main window is gone.
  static void sendCommand(String cmd, {bool? pinned}) {
    _sendToMain('command', <String, dynamic>{
      'cmd': cmd,
      if (pinned != null) 'value': pinned,
    });
    if (cmd == 'close') {
      Timer(const Duration(milliseconds: 700), () async {
        final int? id = instance._overlayId;
        if (id == null) return;
        try {
          await WindowController.fromWindowId(id).close();
        } catch (_) {}
      });
    }
  }

  static Future<void> _sendToMain(
      String method, Map<String, dynamic> args) async {
    try {
      // Window id 0 is the main window (verified against the 0.2.1
      // source during SP-26).
      await DesktopMultiWindow.invokeMethod(0, method, args);
    } catch (e) {
      debugPrint('$_tag send to main failed (ignored): $e');
    }
  }
}
