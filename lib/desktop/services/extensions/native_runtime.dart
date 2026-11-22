// ZenMusic · vorlon-dev
//
// Optional native extension runtime (Rust + QuickJS, packages/zen_ext_rt).
// When its library is bundled, Mornye-style extensions run natively with a
// real synchronous fetch. When it is not, [available] is false and
// ZenExtensions falls back to the Dart replay runtime. Nothing here may throw
// at startup.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

class NativeRuntime {
  NativeRuntime._();

  static DynamicLibrary? _open() {
    try {
      if (Platform.isAndroid || Platform.isLinux) {
        return DynamicLibrary.open('libzen_ext_rt.so');
      }
      if (Platform.isWindows) return DynamicLibrary.open('zen_ext_rt.dll');
    } catch (_) {}
    return null;
  }

  static final bool available = _probe();

  static bool _probe() {
    final lib = _open();
    if (lib == null) return false;
    try {
      lib.lookup<NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>)>>('zen_ext_run');
      lib.lookup<NativeFunction<Void Function(Pointer<Utf8>)>>('zen_ext_free');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Runs [method] of the script on a worker isolate. Returns the runtime's
  /// response ({ok, store} or {err, store}) or null when unavailable.
  static Future<Map<String, dynamic>?> run({
    required String source,
    required String method,
    required List<dynamic> args,
    required List<String> hosts,
    required Map<String, String> store,
  }) async {
    if (!available) return null;
    final req = jsonEncode({
      'source': source,
      'method': method,
      'args': args,
      'hosts': hosts,
      'store': store,
    });
    final out = await Isolate.run(() => _runSync(req));
    final j = jsonDecode(out);
    return j is Map ? Map<String, dynamic>.from(j) : null;
  }

  static String _runSync(String req) {
    final lib = _open()!;
    final run = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)>('zen_ext_run');
    final free = lib.lookupFunction<Void Function(Pointer<Utf8>),
        void Function(Pointer<Utf8>)>('zen_ext_free');
    final input = req.toNativeUtf8();
    try {
      final o = run(input);
      try {
        return o.toDartString();
      } finally {
        free(o);
      }
    } finally {
      malloc.free(input);
    }
  }
}
