import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/utils/format_duration.dart';

void main() {
  group('formatDuration', () {
    test('zero renders as 0:00', () {
      expect(formatDuration(Duration.zero), '0:00');
    });

    test('pads seconds under a minute', () {
      expect(formatDuration(const Duration(seconds: 5)), '0:05');
      expect(formatDuration(const Duration(seconds: 59)), '0:59');
    });

    test('pads seconds when minutes are present', () {
      expect(formatDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
      expect(formatDuration(const Duration(minutes: 1, seconds: 5)), '1:05');
    });

    test('does not pad minutes below one hour', () {
      expect(formatDuration(const Duration(minutes: 10)), '10:00');
      expect(formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('keeps zero minutes once hours are present', () {
      expect(
        formatDuration(const Duration(hours: 1, seconds: 5)),
        '1:00:05',
      );
    });

    test('pads minutes and seconds with hours', () {
      expect(
        formatDuration(const Duration(hours: 2, minutes: 7, seconds: 9)),
        '2:07:09',
      );
    });

    test('negative durations are clamped to zero', () {
      expect(formatDuration(const Duration(seconds: -30)), '0:00');
    });
  });
}
