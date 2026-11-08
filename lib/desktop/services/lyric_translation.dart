// ZenMusic · shared state for "show translation under lyrics".
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'lyrics_translator.dart';

class LyricsTranslation {
  LyricsTranslation._();
  static final LyricsTranslation instance = LyricsTranslation._();

  final ValueNotifier<bool> enabled = ValueNotifier(false);
  final ValueNotifier<bool> loading = ValueNotifier(false);
  final ValueNotifier<List<String>?> lines = ValueNotifier(null);
  final ValueNotifier<int> version = ValueNotifier(0); // bumps on any change

  String? _forKey;
  int _token = 0;

  void load() {
    enabled.value = Hive.box('SETTINGS').get('LYRICS_TR_ON', defaultValue: false) as bool;
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    await Hive.box('SETTINGS').put('LYRICS_TR_ON', v);
    if (!v) {
      _token++;
      loading.value = false;
    }
    _forKey = null;
    version.value++;
  }

  Future<void> setLang(String code) async {
    await LyricsTranslator.setTargetLang(code);
    _forKey = null;
    lines.value = null;
    await setEnabled(true);
  }

  /// Translation for line [i], or null when off / not ready / same as original.
  String? textFor(int i, String original) {
    if (!enabled.value) return null;
    final l = lines.value;
    if (l == null || i >= l.length) return null;
    final t = l[i].trim();
    return (t.isEmpty || t == original.trim()) ? null : t;
  }

  Future<void> ensure(List<String> texts) async {
    if (!enabled.value || texts.isEmpty) return;
    final id = texts.join('\n').hashCode;
    final key = '$id|${LyricsTranslator.targetLang}';
    if (key == _forKey) return; // already loaded or in flight (also stops retry loops)
    _forKey = key;
    final t = ++_token;
    loading.value = true;
    lines.value = null;
    final res = await LyricsTranslator.translate(texts, cacheKey: '$id');
    if (t != _token) return;
    loading.value = false;
    lines.value = res;
    version.value++;
  }
}
