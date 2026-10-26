import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality.dart';

void main() {
  group('LosslessQuality', () {
    test('lightest tier (MP3 320) comes first', () {
      expect(LosslessQuality.values.first, LosslessQuality.mp3_320);
      expect(LosslessQuality.values.first.tierKey, 'mp3_320');
    });

    test('every tier has a label, detail and unique stream key', () {
      final keys = <String>{};
      for (final q in LosslessQuality.values) {
        expect(q.label, isNotEmpty);
        expect(q.detail, isNotEmpty);
        expect(q.tierKey, isNotEmpty);
        expect(keys.add(q.tierKey), isTrue, reason: 'duplicate ${q.tierKey}');
      }
    });
  });

  group('LosslessPrefs', () {
    // Hive is not initialised in unit tests, which exercises the
    // "box not open yet" fallbacks.
    setUp(() => LosslessPrefs.index.value = 0);

    test('defaults to MP3 320 when nothing is stored', () {
      expect(LosslessPrefs.current, LosslessQuality.mp3_320);
    });

    test('set() updates current and the notifier', () {
      LosslessPrefs.set(LosslessQuality.flacCd);

      expect(LosslessPrefs.current, LosslessQuality.flacCd);
      expect(
        LosslessPrefs.index.value,
        LosslessQuality.values.indexOf(LosslessQuality.flacCd),
      );
    });

    test('out-of-range index is clamped', () {
      LosslessPrefs.index.value = -5;
      expect(LosslessPrefs.current, LosslessQuality.values.first);

      LosslessPrefs.index.value = 999;
      expect(LosslessPrefs.current, LosslessQuality.values.last);
    });
  });
}
