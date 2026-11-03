// ZenMusic · vorlon-dev

import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/services/native_equalizer.dart';

void main() {
  group('NativeEqualizer layout', () {
    test('has 15 bands from 25 Hz to 16 kHz in ascending order', () {
      expect(NativeEqualizer.bandCount, 15);
      expect(NativeEqualizer.bandFreqsHz, hasLength(15));
      expect(NativeEqualizer.bandFreqsHz.first, 25);
      expect(NativeEqualizer.bandFreqsHz.last, 16000);
      final sorted = [...NativeEqualizer.bandFreqsHz]..sort();
      expect(NativeEqualizer.bandFreqsHz, sorted);
    });

    test('formats band labels', () {
      expect(NativeEqualizer.bandLabel(25), '25');
      expect(NativeEqualizer.bandLabel(630), '630');
      expect(NativeEqualizer.bandLabel(1000), '1K');
      expect(NativeEqualizer.bandLabel(1600), '1.6K');
      expect(NativeEqualizer.bandLabel(16000), '16K');
    });
  });

  group('NativeEqualizer presets', () {
    test('every preset has 15 gains within +-8 dB', () {
      for (final preset in NativeEqualizer.presets) {
        expect(preset.gains, hasLength(NativeEqualizer.bandCount),
            reason: preset.name);
        for (final gain in preset.gains) {
          expect(gain.abs(), lessThanOrEqualTo(NativeEqualizer.maxGainDb),
              reason: preset.name);
        }
      }
    });

    test('preset names are unique and do not clash with Custom', () {
      final names = NativeEqualizer.presets.map((p) => p.name).toList();
      expect(names.toSet(), hasLength(names.length));
      expect(names, isNot(contains(NativeEqualizer.customName)));
    });

    test('the default preset is flat and listed first', () {
      expect(NativeEqualizer.presets.first, NativeEqualizer.flat);
      expect(NativeEqualizer.flat.gains.every((g) => g == 0), isTrue);
    });

    test('looks presets up by name', () {
      expect(NativeEqualizer.presetByName('Rock')?.name, 'Rock');
      expect(NativeEqualizer.presetByName('No such preset'), isNull);
    });
  });

  group('NativeEqualizer without storage or a device', () {
    test('falls back to a flat, disabled equalizer', () {
      final eq = NativeEqualizer.instance;
      expect(eq.enabled, isFalse);
      expect(eq.presetName, NativeEqualizer.flat.name);
      expect(eq.gains, hasLength(NativeEqualizer.bandCount));
      expect(eq.gains.every((g) => g == 0), isTrue);
    });

    test('is not available outside Android', () async {
      expect(await NativeEqualizer.instance.isAvailable(), isFalse);
    });
  });
}
