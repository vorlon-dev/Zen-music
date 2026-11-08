// ZenMusic · lyrics translation.
// Default: free Google Translate endpoint (no key).
// Optional: any OpenAI-compatible API (set in Hive 'SETTINGS'):
//   LYRICS_TR_API_URL  e.g. https://api.openai.com/v1/chat/completions
//   LYRICS_TR_API_KEY, LYRICS_TR_MODEL
//   LYRICS_TR_LANG     target language code, default 'en'
import 'dart:async';
import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

class LyricsTranslator {
  LyricsTranslator._();

  // The overlay window runs in its own engine where Hive may not be
  // initialised, so every Hive access is guarded and falls back to defaults.
  static bool get _hiveReady => Hive.isBoxOpen('SETTINGS');

  static Box? _cacheBox;
  static Future<Box?> _cache() async {
    try {
      return _cacheBox ??= await Hive.openBox('lyrics_translation');
    } catch (_) {
      return null;
    }
  }

  static String get targetLang => _hiveReady
      ? (Hive.box('SETTINGS').get('LYRICS_TR_LANG', defaultValue: 'en') as String)
      : 'en';
  static Future<void> setTargetLang(String code) async {
    if (_hiveReady) await Hive.box('SETTINGS').put('LYRICS_TR_LANG', code);
  }

  /// Returns translated lines in the SAME order/length as [lines], or null.
  /// [cacheKey] should identify the song (e.g. videoId or artist|title).
  static Future<List<String>?> translate(List<String> lines, {required String cacheKey, String? lang}) async {
    if (lines.isEmpty) return const [];
    final tl = lang ?? targetLang;
    final key = 'tr|$tl|$cacheKey';
    final box = await _cache();
    final hit = box?.get(key);
    if (hit is List && hit.length == lines.length) return hit.cast<String>();

    final s = _hiveReady ? Hive.box('SETTINGS') : null;
    final apiUrl = (s?.get('LYRICS_TR_API_URL') ?? '').toString().trim();
    final apiKey = (s?.get('LYRICS_TR_API_KEY') ?? '').toString().trim();
    List<String>? out;
    if (apiUrl.isNotEmpty && apiKey.isNotEmpty) {
      out = await _viaApi(lines, tl, apiUrl, apiKey, (s?.get('LYRICS_TR_MODEL') ?? 'gpt-4o-mini').toString());
    }
    out ??= await _viaGoogle(lines, tl);
    if (out != null && out.length == lines.length) {
      await box?.put(key, out);
      return out;
    }
    return null;
  }

  /// Plain machine translation for UI strings (no cache, no API key).
  static Future<List<String>?> translateUi(List<String> lines, String lang) =>
      _viaGoogle(lines, lang);

  // ---------- Google (free) ----------
  static Future<String?> _googleOne(String text, String tl) async {
    if (text.trim().isEmpty) return text;
    try {
      final r = await http.get(Uri.https('translate.googleapis.com', '/translate_a/single',
          {'client': 'gtx', 'sl': 'auto', 'tl': tl, 'dt': 't', 'q': text}))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return (j[0] as List).map((e) => e[0] ?? '').join();
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>?> _viaGoogle(List<String> lines, String tl) async {
    final out = List<String>.filled(lines.length, '');
    var next = 0;
    var failed = false;
    // 4 parallel workers: fast, but gentle on the endpoint.
    Future<void> worker() async {
      while (!failed) {
        final i = next++;
        if (i >= lines.length) return;
        final t = await _googleOne(lines[i], tl);
        if (t == null) { failed = true; return; }
        out[i] = t;
      }
    }
    await Future.wait(List.generate(4, (_) => worker()));
    return failed ? null : out;
  }

  // ---------- OpenAI-compatible ----------
  static Future<List<String>?> _viaApi(List<String> lines, String tl, String url, String key, String model) async {
    try {
      final r = await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $key'},
          body: jsonEncode({
            'model': model,
            'temperature': 0.2,
            'messages': [
              {'role': 'system', 'content': 'You translate song lyrics. Reply with ONLY a JSON array of strings, exactly ${lines.length} items, same order, translated to language code "$tl". Keep empty strings empty.'},
              {'role': 'user', 'content': jsonEncode(lines)},
            ],
          })).timeout(const Duration(seconds: 40));
      if (r.statusCode != 200) return null;
      var txt = (jsonDecode(utf8.decode(r.bodyBytes))['choices'][0]['message']['content'] as String).trim();
      txt = txt.replaceAll(RegExp(r'^```(?:json)?|```$', multiLine: true), '').trim();
      final arr = (jsonDecode(txt) as List).map((e) => e.toString()).toList();
      return arr.length == lines.length ? arr : null;
    } catch (_) {
      return null;
    }
  }
}
