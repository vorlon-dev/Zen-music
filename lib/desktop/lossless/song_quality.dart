// ZenMusic · vorlon-dev
//
// Per-song stream quality choice. Overrides Settings -> Song quality for
// ONE song; stored in the SETTINGS Hive box as {videoId: tierIndex}.

import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality.dart';

class SongQuality {
  SongQuality._();
  static const String _key = 'SONG_QUALITY_OVERRIDES';

  static Map _read() {
    try {
      final v = Hive.box('SETTINGS').get(_key);
      return v is Map ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// The override for [songId], or null to use the Settings tier.
  static LosslessQuality? forSong(String songId) {
    final v = _read()[songId];
    if (v is int && v >= 0 && v < LosslessQuality.values.length) {
      return LosslessQuality.values[v];
    }
    return null;
  }

  /// Pass null to go back to the Settings tier.
  static Future<void> set(String songId, LosslessQuality? quality) async {
    final map = Map<String, dynamic>.from(_read());
    if (quality == null) {
      map.remove(songId);
    } else {
      map[songId] = LosslessQuality.values.indexOf(quality);
    }
    // Keep the box small.
    while (map.length > 300) {
      map.remove(map.keys.first);
    }
    try {
      await Hive.box('SETTINGS').put(_key, map);
    } catch (_) {}
  }
}
