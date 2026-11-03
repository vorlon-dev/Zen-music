import 'lyrics_model.dart';
import 'lrcnet_service.dart';
import 'kugou_service.dart';

/// Unified Lyrics Engine combining LRCLIB and Kugou.
class LyricsEngine {
  LyricsEngine({
    LrcNetService? lrcNet,
    KugouLyricsService? kugou,
  })  : _lrcNet = lrcNet ?? LrcNetService(),
        _kugou = kugou ?? KugouLyricsService();

  final LrcNetService _lrcNet;
  final KugouLyricsService _kugou;

  /// Fetch lyrics with primary (LRCLIB) and fallback (Kugou) strategies.
  Future<Lyrics?> getLyrics({
    required String title,
    String? artist,
    String? album,
    String? duration,
    int? durationMs,
  }) async {
    // 1. Try LRCLIB
    try {
      final lrclibResult = await _lrcNet.getLyrics(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      );
      if (lrclibResult != null && lrclibResult.hasSyncedLyrics) {
        return lrclibResult;
      }
      if (lrclibResult != null) {
        // If Kugou has synced, prefer Kugou; else return plain from LRCLIB
        final kugouResult = await _kugou.lookup(
          title: title,
          artist: artist ?? '',
          album: album,
          durationMs: durationMs,
        );
        if (kugouResult != null && kugouResult.hasSyncedLyrics) {
          return kugouResult;
        }
        return lrclibResult;
      }
    } catch (_) {}

    // 2. Try Kugou
    try {
      final kugouResult = await _kugou.lookup(
        title: title,
        artist: artist ?? '',
        album: album,
        durationMs: durationMs,
      );
      if (kugouResult != null) return kugouResult;
    } catch (_) {}

    return null;
  }

  void dispose() {
    _lrcNet.dispose();
    _kugou.dispose();
  }
}
