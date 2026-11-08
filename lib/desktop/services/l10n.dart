// ZenMusic · app translations. Use:  Text('Home'.tr)
// 10 languages for the core UI strings; anything not listed stays English.
// To translate more screens: wrap their strings with .tr and add the English
// text as a new entry at the END of _keys plus one value at the end of each list.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'lyrics_translator.dart';

const List<String> _keys = [
  'Home', 'Search', 'Saved', 'Settings', 'Downloads', 'Favourites', 'History',
  'Queue', 'Lyrics', 'Play', 'Pause', 'Next', 'Previous', 'Shuffle',
  'Sleep timer', 'Equalizer', 'Language', 'Cancel', 'Save', 'Delete',
  'Download', 'Share', 'Loading...', 'No results', 'Sing', 'Translate lyrics',
  'Lyric style', 'Appearance', 'Offline',
];

const Map<String, List<String>> _vals = {
  'es': ['Inicio', 'Buscar', 'Guardado', 'Ajustes', 'Descargas', 'Favoritos', 'Historial', 'Cola', 'Letras', 'Reproducir', 'Pausa', 'Siguiente', 'Anterior', 'Aleatorio', 'Temporizador de sueño', 'Ecualizador', 'Idioma', 'Cancelar', 'Guardar', 'Eliminar', 'Descargar', 'Compartir', 'Cargando...', 'Sin resultados', 'Cantar', 'Traducir letras', 'Estilo de letra', 'Apariencia', 'Sin conexión'],
  'hi': ['होम', 'खोजें', 'सहेजे गए', 'सेटिंग्स', 'डाउनलोड', 'पसंदीदा', 'इतिहास', 'कतार', 'गीत के बोल', 'चलाएँ', 'रोकें', 'अगला', 'पिछला', 'शफ़ल', 'स्लीप टाइमर', 'इक्वलाइज़र', 'भाषा', 'रद्द करें', 'सहेजें', 'हटाएँ', 'डाउनलोड करें', 'साझा करें', 'लोड हो रहा है...', 'कोई परिणाम नहीं', 'गाएँ', 'बोल का अनुवाद करें', 'बोल की शैली', 'दिखावट', 'ऑफ़लाइन'],
  'fr': ['Accueil', 'Rechercher', 'Enregistrés', 'Paramètres', 'Téléchargements', 'Favoris', 'Historique', "File d'attente", 'Paroles', 'Lecture', 'Pause', 'Suivant', 'Précédent', 'Aléatoire', 'Minuteur de sommeil', 'Égaliseur', 'Langue', 'Annuler', 'Enregistrer', 'Supprimer', 'Télécharger', 'Partager', 'Chargement...', 'Aucun résultat', 'Chanter', 'Traduire les paroles', 'Style des paroles', 'Apparence', 'Hors ligne'],
  'de': ['Start', 'Suche', 'Gespeichert', 'Einstellungen', 'Downloads', 'Favoriten', 'Verlauf', 'Warteschlange', 'Songtexte', 'Wiedergabe', 'Pause', 'Weiter', 'Zurück', 'Zufall', 'Einschlaf-Timer', 'Equalizer', 'Sprache', 'Abbrechen', 'Speichern', 'Löschen', 'Herunterladen', 'Teilen', 'Wird geladen...', 'Keine Ergebnisse', 'Singen', 'Songtext übersetzen', 'Textstil', 'Darstellung', 'Offline'],
  'pt': ['Início', 'Buscar', 'Salvos', 'Configurações', 'Downloads', 'Favoritos', 'Histórico', 'Fila', 'Letras', 'Reproduzir', 'Pausar', 'Próxima', 'Anterior', 'Aleatório', 'Temporizador de sono', 'Equalizador', 'Idioma', 'Cancelar', 'Salvar', 'Excluir', 'Baixar', 'Compartilhar', 'Carregando...', 'Nenhum resultado', 'Cantar', 'Traduzir letra', 'Estilo da letra', 'Aparência', 'Offline'],
  'ru': ['Главная', 'Поиск', 'Сохранённое', 'Настройки', 'Загрузки', 'Избранное', 'История', 'Очередь', 'Текст песни', 'Играть', 'Пауза', 'Далее', 'Назад', 'Перемешать', 'Таймер сна', 'Эквалайзер', 'Язык', 'Отмена', 'Сохранить', 'Удалить', 'Скачать', 'Поделиться', 'Загрузка...', 'Нет результатов', 'Караоке', 'Перевести текст', 'Стиль текста', 'Оформление', 'Офлайн'],
  'ar': ['الرئيسية', 'بحث', 'المحفوظات', 'الإعدادات', 'التنزيلات', 'المفضلة', 'السجل', 'قائمة الانتظار', 'الكلمات', 'تشغيل', 'إيقاف مؤقت', 'التالي', 'السابق', 'عشوائي', 'مؤقت النوم', 'المعادل الصوتي', 'اللغة', 'إلغاء', 'حفظ', 'حذف', 'تنزيل', 'مشاركة', 'جارٍ التحميل...', 'لا توجد نتائج', 'غنِّ', 'ترجمة الكلمات', 'نمط الكلمات', 'المظهر', 'بدون اتصال'],
  'tr': ['Ana Sayfa', 'Ara', 'Kaydedilenler', 'Ayarlar', 'İndirilenler', 'Favoriler', 'Geçmiş', 'Sıra', 'Şarkı sözleri', 'Oynat', 'Duraklat', 'Sonraki', 'Önceki', 'Karıştır', 'Uyku zamanlayıcısı', 'Ekolayzer', 'Dil', 'İptal', 'Kaydet', 'Sil', 'İndir', 'Paylaş', 'Yükleniyor...', 'Sonuç yok', 'Söyle', 'Sözleri çevir', 'Söz stili', 'Görünüm', 'Çevrimdışı'],
  'id': ['Beranda', 'Cari', 'Tersimpan', 'Pengaturan', 'Unduhan', 'Favorit', 'Riwayat', 'Antrean', 'Lirik', 'Putar', 'Jeda', 'Berikutnya', 'Sebelumnya', 'Acak', 'Timer tidur', 'Equalizer', 'Bahasa', 'Batal', 'Simpan', 'Hapus', 'Unduh', 'Bagikan', 'Memuat...', 'Tidak ada hasil', 'Bernyanyi', 'Terjemahkan lirik', 'Gaya lirik', 'Tampilan', 'Offline'],
  'ja': ['ホーム', '検索', '保存済み', '設定', 'ダウンロード', 'お気に入り', '履歴', 'キュー', '歌詞', '再生', '一時停止', '次へ', '前へ', 'シャッフル', 'スリープタイマー', 'イコライザー', '言語', 'キャンセル', '保存', '削除', 'ダウンロード', '共有', '読み込み中...', '結果なし', '歌う', '歌詞を翻訳', '歌詞スタイル', '外観', 'オフライン'],
};

const Map<String, String> kAppLanguages = {
  'en': 'English', 'es': 'Español', 'hi': 'हिन्दी', 'fr': 'Français',
  'de': 'Deutsch', 'pt': 'Português', 'ru': 'Русский', 'ar': 'العربية',
  'tr': 'Türkçe', 'id': 'Bahasa Indonesia', 'ja': '日本語',
};

class L10n {
  L10n._();
  static final ValueNotifier<String> lang = ValueNotifier('en');
  static Map<String, String> _m = const {};

  // Machine-translated strings (cached on disk). Used for every string that
  // has no hand-written entry above, so the whole app follows the language.
  static Box? _dynBox;
  static final Map<String, String> _dyn = {};
  static final Set<String> _pending = {};
  static final Map<String, DateTime> _failed = {};
  static Timer? _timer;

  /// Call once after Hive is open. First run follows the phone's language.
  static Future<void> load() async {
    try {
      _dynBox = await Hive.openBox('ui_translation');
      for (final k in _dynBox!.keys) {
        _dyn[k as String] = _dynBox!.get(k) as String;
      }
    } catch (_) {}
    final saved = Hive.box('SETTINGS').get('APP_LANG') as String?;
    final device = ui.PlatformDispatcher.instance.locale.languageCode;
    _apply(saved ?? (kAppLanguages.containsKey(device) ? device : 'en'));
  }

  static Future<void> set(String code) async {
    await Hive.box('SETTINGS').put('APP_LANG', code);
    _apply(code);
    _rebuildAll();
  }

  static void _apply(String code) {
    final v = _vals[code];
    _m = (v == null || v.length != _keys.length)
        ? const {}
        : {for (var i = 0; i < _keys.length; i++) _keys[i]: v[i]};
    lang.value = code;
  }

  static String t(String k) {
    final s = _m[k];
    if (s != null) return s;
    final code = lang.value;
    if (code == 'en') return k;
    final d = _dyn['$code|$k'];
    if (d != null) return d;
    _enqueue(code, k);
    return k;
  }

  static bool get isRtl => lang.value == 'ar';

  static void _enqueue(String code, String k) {
    if (k.length > 90 || !RegExp(r'[A-Za-z]').hasMatch(k)) return;
    final f = _failed['$code|$k'];
    if (f != null && DateTime.now().isBefore(f)) return;
    _pending.add(k);
    _timer ??= Timer(const Duration(milliseconds: 350), _flush);
  }

  static Future<void> _flush() async {
    _timer = null;
    final code = lang.value;
    if (code == 'en' || _pending.isEmpty) {
      _pending.clear();
      return;
    }
    final batch = _pending.take(40).toList();
    _pending.removeAll(batch);
    final res = await LyricsTranslator.translateUi(batch, code);
    if (res == null || res.length != batch.length) {
      final retry = DateTime.now().add(const Duration(minutes: 2));
      for (final k in batch) {
        _failed['$code|$k'] = retry; // offline: try again later, no loop
      }
    } else {
      for (var i = 0; i < batch.length; i++) {
        final key = '$code|${batch[i]}';
        _dyn[key] = res[i];
        _dynBox?.put(key, res[i]);
      }
      if (code == lang.value) _rebuildAll();
    }
    if (_pending.isNotEmpty) _timer = Timer(const Duration(milliseconds: 200), _flush);
  }

  /// Rebuild every widget in place (keeps navigation and player state).
  static void _rebuildAll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }
      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    });
    WidgetsBinding.instance.scheduleFrame();
  }
}

extension TrX on String {
  String get tr => L10n.t(this);
}

/// Settings row: shows the current language and opens a picker.
class LanguagePickerTile extends StatelessWidget {
  const LanguagePickerTile({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: L10n.lang,
        builder: (context, code, _) => ListTile(
          leading: const Icon(Icons.language),
          title: Text('Language'.tr),
          subtitle: Text(kAppLanguages[code] ?? code),
          onTap: () => showLanguageDialog(context),
        ),
      );
}

void showLanguageDialog(BuildContext context) {
  final code = L10n.lang.value;
  showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Language'.tr),
      children: [
        for (final e in kAppLanguages.entries)
          SimpleDialogOption(
            onPressed: () {
              L10n.set(e.key);
              Navigator.pop(ctx);
            },
            child: Text(e.value,
                style: TextStyle(fontWeight: e.key == code ? FontWeight.w800 : FontWeight.w400)),
          ),
      ],
    ),
  );
}
