import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset, PlatformDispatcher, Rect, Size;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show runApp, WidgetsFlutterBinding;

import '../screens/mini_player_page.dart';

/// Track metadata mirrored into the mini window.
class MiniTrack {
  final String title;
  final String artist;
  final String? artUri;

  const MiniTrack({required this.title, required this.artist, this.artUri});
}

class MiniPlayerBridge {
  MiniPlayerBridge._();

  static final MiniPlayerBridge instance = MiniPlayerBridge._();

  static const String _tag = '[mini]';

  // Mini window geometry in logical pixels. The plugin's setFrame takes
  // PHYSICAL pixels, so the size is scaled by the display's
  // devicePixelRatio before being applied.
  static const double _barWidth = 420;
  static const double _barHeight = 170;

  // ── main-window side state ──────────────────────────────────────────
  int? _miniWindowId; // live mini window id (0 is the main window — ours is >0)
  bool _opening = false;
  bool _mainArmed = false;
  MiniTrack? _lastTrack;
  bool _lastPlaying = false;
  Duration _lastCurrent = Duration.zero;
  Duration _lastTotal = Duration.zero;
  DateTime _lastPosSend = DateTime.fromMillisecondsSinceEpoch(0);

  /// Transport commands coming back from the mini window:
  /// 'toggle' | 'next' | 'previous'. Wired by media_player.dart.
  void Function(String cmd)? onCommand;

  // ── mini-window side state (only used inside the mini engine) ───────
  final ValueNotifier<MiniTrack?> miniTrack = ValueNotifier<MiniTrack?>(null);
  final ValueNotifier<bool> miniPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> miniPosition =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> miniDuration =
      ValueNotifier<Duration>(Duration.zero);

  bool _miniMode = false; // true inside the mini engine
  int? _miniId; // this mini window's own id (mini engine only)

  bool get isMiniWindow => _miniMode;
  bool get isWindowOpen => _miniWindowId != null;

  // ═══════════════════════════════════════════════════════════════════
  // MAIN WINDOW SIDE
  // ═══════════════════════════════════════════════════════════════════

  /// Arms the receiver for commands coming back from mini windows.
  /// Called once from MediaPlayer's `_initMiniPlayer()`.
  Future<void> init() async {
    if (_miniMode || _mainArmed) return;
    _mainArmed = true;
    DesktopMultiWindow.setMethodHandler(_onMainEvent);
  }

  Future<dynamic> _onMainEvent(MethodCall call, int fromWindowId) async {
    if (_miniMode) return null;
    if (call.method != 'command') return null;
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? const {};
    final String cmd = args['cmd'] as String? ?? '';
    switch (cmd) {
      case 'hello':
        // A fresh mini engine finished booting — bind to it (this also
        // re-binds after the user closed an older one via its title-bar X)
        // and push the full current state so the bar is never blank.
        debugPrint('$_tag mini window $fromWindowId is up — pushing snapshot');
        _miniWindowId = fromWindowId;
        _pushSnapshot();
        break;
      case 'close':
        debugPrint('$_tag mini window asked to close');
        await closeMiniPlayer();
        break;
      case 'toggle':
      case 'next':
      case 'previous':
        debugPrint('$_tag command from mini window: $cmd');
        onCommand?.call(cmd);
        break;
      default:
        debugPrint('$_tag ignored command "$cmd" from window $fromWindowId');
    }
    return null;
  }

  /// Opens (or re-opens) the floating mini player. Always closes any
  /// previous mini window first and creates a fresh one — stale window ids
  /// are harmless (the plugin ignores unknown ids) and a fresh window can
  /// never be left pointing at a window the user already closed.
  Future<void> openMiniPlayer() async {
    if (_miniMode) {
      return;
    }
    if (_opening) {
      return;
    }
    _opening = true;
    try {
      if (_miniWindowId != null) {
        try {
          await WindowController.fromWindowId(_miniWindowId!).close();
        } catch (_) {}
        _miniWindowId = null;
      }
      final WindowController window = await DesktopMultiWindow.createWindow(
        jsonEncode(<String, String>{'type': 'zenmini'}),
      );
      _miniWindowId = window.windowId;
      final double dpr =
          PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
      await window.setTitle('ZenMusic Mini');
      await window.setFrame(
        const Offset(0, 0) & Size(_barWidth * dpr, _barHeight * dpr),
      );
      await window.center();
      await window.show();
      _pushSnapshot();
      // Insurance against the fresh engine's handler not being armed in
      // time: push once more shortly after. Harmless if redundant.
      Timer(const Duration(milliseconds: 500), _pushSnapshot);
    } catch (e) {
      debugPrint('$_tag openMiniPlayer failed (ignored): $e');
    } finally {
      _opening = false;
    }
  }

  Future<void> closeMiniPlayer() async {
    final int? id = _miniWindowId;
    _miniWindowId = null;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).close();
    } catch (e) {
      debugPrint('$_tag close failed (ignored): $e');
    }
  }

  /// Closes the mini window (and sweeps any strays). Called from
  /// MediaPlayer.dispose().
  Future<void> shutdown() async {
    await closeMiniPlayer();
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

  void pushTrack(MiniTrack? track) {
    if (_miniMode) return;
    _lastTrack = track;
    _send('track', <String, dynamic>{
      'title': track?.title,
      'artist': track?.artist,
      'artUri': track?.artUri,
    });
  }

  void pushPlaying(bool playing) {
    if (_miniMode) return;
    _lastPlaying = playing;
    _send('playing', <String, dynamic>{'value': playing});
  }

  void pushProgress(Duration current, Duration total) {
    if (_miniMode) return;
    _lastCurrent = current;
    _lastTotal = total;
    // The mini bar only needs ~2 updates per second.
    final DateTime now = DateTime.now();
    if (now.difference(_lastPosSend) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastPosSend = now;
    _send('position', <String, dynamic>{
      'currentMs': current.inMilliseconds,
      'totalMs': total.inMilliseconds,
    });
  }

  void _pushSnapshot() {
    if (_miniMode || _miniWindowId == null) return;
    debugPrint(
        '$_tag snapshot → "${_lastTrack?.title}" playing=$_lastPlaying');
    _send('track', <String, dynamic>{
      'title': _lastTrack?.title,
      'artist': _lastTrack?.artist,
      'artUri': _lastTrack?.artUri,
    });
    _send('playing', <String, dynamic>{'value': _lastPlaying});
    _send('position', <String, dynamic>{
      'currentMs': _lastCurrent.inMilliseconds,
      'totalMs': _lastTotal.inMilliseconds,
    });
  }

  void _send(String method, Map<String, dynamic> args) {
    final int? target = _miniWindowId;
    if (target == null) return;
    unawaited(_doSend(target, method, args));
  }

  Future<void> _doSend(int target, String method, Map<String, dynamic> args) async {
    try {
      await DesktopMultiWindow.invokeMethod(target, method, args);
    } catch (e) {
      // A mini window closed via its native title-bar X surfaces here as
      // "target window not found" — forget it so the pushes stop.
      if ('$e'.contains('not found')) _miniWindowId = null;
      debugPrint('$_tag push "$method" failed (ignored): $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // MINI WINDOW SIDE (runs inside the second engine)
  // ═══════════════════════════════════════════════════════════════════

  /// Entry for the mini engine — called from lib/desktop/main.dart when
  /// main() receives the plugin's ['multi_window', windowId, …] args.
  /// Fire-and-forget by design so main() returns immediately.
  static void runMiniWindow(int windowId) {
    _bootstrapMini(windowId);
  }

  static Future<void> _bootstrapMini(int windowId) async {
    WidgetsFlutterBinding.ensureInitialized();
    final MiniPlayerBridge bridge = instance;
    bridge._miniMode = true;
    bridge._miniId = windowId;
    DesktopMultiWindow.setMethodHandler(bridge._onMiniEvent);
    // Tell the main window we exist so it binds to us and pushes a snapshot.
    await _sendToMain('command', const <String, dynamic>{'cmd': 'hello'});
    runApp(const MiniPlayerApp());
  }

  Future<dynamic> _onMiniEvent(MethodCall call, int fromWindowId) async {
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? const {};
    switch (call.method) {
      case 'track':
        final String? title = args['title'] as String?;
        miniTrack.value = title == null
            ? null
            : MiniTrack(
                title: title,
                artist: args['artist'] as String? ?? '',
                artUri: args['artUri'] as String?,
              );
        break;
      case 'playing':
        miniPlaying.value = args['value'] as bool? ?? false;
        break;
      case 'position':
        miniPosition.value = Duration(
            milliseconds: (args['currentMs'] as num?)?.toInt() ?? 0);
        miniDuration.value =
            Duration(milliseconds: (args['totalMs'] as num?)?.toInt() ?? 0);
        break;
      default:
        break;
    }
    return null;
  }

  /// Transport button pressed inside the mini bar. 'close' additionally
  /// arms a self-close fallback in case the main window is gone.
  static void sendCommand(String cmd) {
    _sendToMain('command', <String, dynamic>{'cmd': cmd});
    if (cmd == 'close') {
      Timer(const Duration(milliseconds: 700), () async {
        final int? id = instance._miniId;
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
      await DesktopMultiWindow.invokeMethod(0, method, args);
    } catch (e) {
      debugPrint('$_tag send to main failed (ignored): $e');
    }
  }
}
