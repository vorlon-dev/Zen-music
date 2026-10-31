import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/services/lyrics_service.dart';

void main() {
  group('LrcParser.parse timestamps', () {
    test('hundredths (.xx) are scaled to milliseconds', () {
      final lines = LrcParser.parse('[00:12.50] Hello');
      expect(lines, hasLength(1));
      expect(lines.first.timeMs, 12500);
      expect(lines.first.text, 'Hello');
    });

    test('milliseconds (.xxx) are used as they are', () {
      expect(LrcParser.parse('[01:02.345] x').single.timeMs, 62345);
    });

    test('tenths (.x) are scaled to milliseconds', () {
      expect(LrcParser.parse('[00:05.5] x').single.timeMs, 5500);
    });

    test('a timestamp without a fraction is whole seconds', () {
      expect(LrcParser.parse('[00:05] x').single.timeMs, 5000);
    });

    test('a colon before the fraction is accepted', () {
      expect(LrcParser.parse('[00:05:25] x').single.timeMs, 5250);
    });
  });

  group('LrcParser.parse structure', () {
    test('a line with several timestamps yields one entry per timestamp', () {
      final lines = LrcParser.parse('[00:20.00][00:10.00] Chorus');
      expect(lines.map((l) => l.timeMs), [10000, 20000]);
      expect(lines.every((l) => l.text == 'Chorus'), isTrue);
    });

    test('output is sorted by time', () {
      final lines = LrcParser.parse('[00:30.00] c\n[00:10.00] a\n[00:20.00] b');
      expect(lines.map((l) => l.text), ['a', 'b', 'c']);
    });

    test('whitespace in the text is collapsed and trimmed', () {
      expect(LrcParser.parse('[00:01.00]   Hello    world  ').single.text,
          'Hello world');
    });

    test('metadata tags and plain lines are ignored', () {
      expect(LrcParser.parse('[ar:Artist]\n[ti:Title]\nplain text'), isEmpty);
    });

    test('empty input produces no lines', () {
      expect(LrcParser.parse(''), isEmpty);
    });
  });

  group('LrcParser.parse offset tag', () {
    test('a positive offset shifts lines earlier', () {
      expect(LrcParser.parse('[offset:+500]\n[00:10.00] Line').single.timeMs,
          9500);
    });

    test('a negative offset shifts lines later', () {
      expect(LrcParser.parse('[offset:-500]\n[00:10.00] Line').single.timeMs,
          10500);
    });

    test('times never go below zero', () {
      expect(LrcParser.parse('[offset:5000]\n[00:01.00] a').single.timeMs, 0);
    });
  });
}
