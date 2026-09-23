import 'dart:convert';

import 'package:flutter/services.dart';

/// Bridge to the extension engine (Echo-contract extensions loaded
/// via DexClassLoader on the native side).
class ExtensionBridge {
  static const _channel = MethodChannel('zen/extensions');

  /// Installed extensions: {id, name, version, description, author,
  /// isActive}.
  static Future<List<Map<String, dynamic>>> list() async {
    try {
      final raw = await _channel.invokeMethod<String>('list');
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PlatformException {
      return [];
    }
  }

  /// Installs an extension package (.eapk / .apk) from a local file path.
  /// Throws with the native error message on failure.
  static Future<Map<String, dynamic>> install(String filePath) async {
    final r = await _channel.invokeMethod('install', {'uri': filePath});
    if (r == null) throw Exception('Install failed natively');
    return Map<String, dynamic>.from(r);
  }

  /// Selects the active music extension. Returns true on success;
  /// readiness arrives via search working afterwards.
  static Future<bool> select(String id) async {
    try {
      return await _channel.invokeMethod('select', {'id': id}) == true;
    } on PlatformException {
      return false;
    }
  }

  /// Searches via the selected extension. Returns flat track maps:
  /// {id, title, artist, thumbnail, durationMs}.
  /// Throws with the native error — caller should catch and display.
  static Future<List<Map<String, dynamic>>> search(String query) async {
    final raw = await _channel.invokeMethod<String>('search', {'query': query});
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Resolves the playable stream for a track json.
  static Future<({String url, Map<String, String> headers, String sourceType})>
  resolveStream(Map<String, dynamic> track) async {
    final raw = await _channel.invokeMethod<String>(
        'resolveStream', {'track': jsonEncode(track)});
    if (raw == null) throw Exception('Stream resolution failed');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final headers = (map['headers'] as Map<dynamic, dynamic>? ?? {})
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    return (
    url: map['url'] as String,
    headers: headers,
    sourceType: map['sourceType'] as String? ?? 'PROGRESSIVE',
    );
  }
}