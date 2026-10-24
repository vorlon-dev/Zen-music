// ZenMusic Desktop — utils/win32_window_utils.dart (GPL-3.0).
//
// SP-28: tiny user32 helpers used by lyrics_overlay_bridge.dart.
// desktop_multi_window 0.2.1 has no always-on-top API — but a lyrics
// overlay is only useful floating ABOVE other apps, so we ask user32
// directly via dart:ffi:
//     FindWindowW(NULL, <title>)             → the overlay window's HWND
//     SetWindowPos(HWND_TOPMOST / NOTOPMOST) → pin / unpin
//     ShowWindow + SetForegroundWindow       → bring to front (future use)
//
// Windows-only: every public method no-ops silently on other platforms and
// user32.dll is only opened lazily from inside a Windows guard. A failed
// call just means the window behaves as a normal window — nothing else is
// affected. Zero playback involvement.

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class Win32WindowUtils {
  Win32WindowUtils._();

  static final Win32WindowUtils instance = Win32WindowUtils._();

  static const int _hwndTopmost = -1;
  static const int _hwndNotopmost = -2;
  static const int _swpNomove = 0x0002;
  static const int _swpNosize = 0x0001;
  static const int _swShow = 5;

  DynamicLibrary? _user32Lib;
  int Function(Pointer<Utf16>, Pointer<Utf16>)? _findWindowW;
  int Function(int, int, int, int, int, int, int)? _setWindowPos;
  int Function(int, int)? _showWindow;
  int Function(int)? _setForegroundWindow;

  bool _ensureUser32() {
    if (!Platform.isWindows) return false;
    if (_user32Lib != null) return true;
    try {
      final DynamicLibrary lib = DynamicLibrary.open('user32.dll');
      _findWindowW = lib.lookupFunction<
          IntPtr Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)>('FindWindowW');
      _setWindowPos = lib.lookupFunction<
          Int32 Function(IntPtr, IntPtr, Int32, Int32, Int32, Int32, Uint32),
          int Function(int, int, int, int, int, int, int)>('SetWindowPos');
      _showWindow = lib.lookupFunction<Int32 Function(IntPtr, Int32),
          int Function(int, int)>('ShowWindow');
      _setForegroundWindow = lib
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
              'SetForegroundWindow');
      _user32Lib = lib;
      return true;
    } catch (_) {
      _user32Lib = null;
      return false;
    }
  }

  /// Returns the HWND of the first top-level window titled [title] (exact,
  /// case-insensitive match), or null when not found / not Windows / user32
  /// unavailable.
  int? findWindowByTitle(String title) {
    if (!_ensureUser32()) return null;
    final Pointer<Utf16> nativeTitle = title.toNativeUtf16();
    try {
      final int hwnd = _findWindowW!(nullptr, nativeTitle);
      return hwnd != 0 ? hwnd : null;
    } catch (_) {
      return null;
    } finally {
      malloc.free(nativeTitle);
    }
  }

  /// Pins (or unpins) the window titled [title] above all other windows.
  void setTopmostByTitle(String title, bool topmost) {
    final int? hwnd = findWindowByTitle(title);
    if (hwnd == null) return;
    try {
      _setWindowPos!(
        hwnd,
        topmost ? _hwndTopmost : _hwndNotopmost,
        0,
        0,
        0,
        0,
        _swpNomove | _swpNosize,
      );
    } catch (_) {}
  }

  /// Shows the window titled [title] and tries to bring it to the front.
  /// Kept for future use (e.g. "restore main window" from a sub window).
  void bringToFrontByTitle(String title) {
    final int? hwnd = findWindowByTitle(title);
    if (hwnd == null) return;
    try {
      _showWindow!(hwnd, _swShow);
      _setForegroundWindow!(hwnd);
    } catch (_) {}
  }
}
