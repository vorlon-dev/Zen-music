import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum LosslessQuality {
  mp3_320('MP3 320 kbps', 'Compressed — lightest on data', 'mp3_320'),
  flacCd('Lossless CD', 'FLAC 16-bit / 44.1 kHz — CD quality', 'flac_cd'),
  flacHiRes96('Hi-Res Lossless', 'FLAC 24-bit / up to 96 kHz', 'flac_hires_96'),
  flacHiResMax(
      'Hi-Res Max', 'FLAC 24-bit / up to 192 kHz — studio master',
      'flac_hires_192');

  const LosslessQuality(this.label, this.detail, this.tierKey);

  /// Short name shown in the settings row subtitle and the page.
  final String label;

  /// One-line explanation shown under the label on the quality page.
  final String detail;

  /// Stream key in the lossless endpoint's "streams" response.
  final String tierKey;
}

/// Persistence for the Song quality setting.
///
/// Stored in the app's standard Hive 'SETTINGS' box under 'SONG_QUALITY'
/// (an int index into [LosslessQuality.values]) — the same box and pattern
/// SettingsManager uses, but deliberately separate from SettingsManager so
/// the whole lossless feature stays inside its own folder and no base file
/// has to change for it.
class LosslessPrefs {
  LosslessPrefs._();

  static const String _hiveKey = 'SONG_QUALITY';

  /// Selected tier index — listenable so the settings row subtitle and the
  /// quality page update live when the user picks another tier.
  static final ValueNotifier<int> index = ValueNotifier<int>(_read());

  static int _read() {
    try {
      final v = Hive.box('SETTINGS').get(_hiveKey, defaultValue: 0);
      final i = v is int ? v : 0;
      if (i < 0 || i >= LosslessQuality.values.length) return 0;
      return i;
    } catch (_) {
      return 0; // box not open yet (early startup) — safe default
    }
  }

  /// The tier the user picked. Defaults to MP3 320 kbps (index 0) — the
  /// lightest upgrade, so a fresh install never streams 100 MB FLACs by
  /// surprise.
  static LosslessQuality get current {
    final n = LosslessQuality.values.length;
    final i = index.value;
    return LosslessQuality.values[(i < 0) ? 0 : (i >= n ? n - 1 : i)];
  }

  static void set(LosslessQuality quality) {
    index.value = LosslessQuality.values.indexOf(quality);
    unawaited(_persist(index.value));
  }

  static Future<void> _persist(int i) async {
    try {
      await Hive.box('SETTINGS').put(_hiveKey, i);
    } catch (_) {}
  }
}