// ZenMusic · vorlon-dev

import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/web/web_models.dart';

void main() {
  group('WebSong.fromJson', () {
    test('picks best stream/image, joins artists, upgrades to https', () {
      final s = WebSong.fromJson({
        'id': 'abc',
        'name': 'Rock &amp; Roll &quot;Live&quot;',
        'duration': '215',
        'album': {'name': 'Hits &amp; More'},
        'artists': {
          'primary': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        },
        'image': [
          {'quality': '50x50', 'url': 'http://x/50.jpg'},
          {'quality': '500x500', 'url': 'http://x/500.jpg'},
        ],
        'downloadUrl': [
          {'quality': '96kbps', 'url': 'http://x/96.mp4'},
          {'quality': '320kbps', 'url': 'http://x/320.mp4'},
          {'quality': '160kbps', 'url': 'http://x/160.mp4'},
        ],
      });
      expect(s.title, 'Rock & Roll "Live"');
      expect(s.album, 'Hits & More');
      expect(s.artist, 'A, B');
      expect(s.image, 'https://x/500.jpg');
      expect(s.streamUrl, 'https://x/320.mp4');
      expect(s.duration, const Duration(seconds: 215));
      expect(s.playable, isTrue);
    });

    test('missing fields give an unplayable empty song', () {
      final s = WebSong.fromJson({'id': 'z'});
      expect(s.playable, isFalse);
      expect(s.duration, Duration.zero);
      expect(s.artist, '');
    });
  });

  group('parseLrc', () {
    test('parses timestamps, multi-stamps and sorts', () {
      final l = parseLrc('[ti:x]\n[00:10.50] second\n[00:01.5][00:20.00] first\r\n');
      expect(l.map((e) => e.text), ['first', 'second', 'first']);
      expect(l[0].time, const Duration(seconds: 1, milliseconds: 500));
      expect(l[1].time, const Duration(seconds: 10, milliseconds: 500));
    });

    test('empty input gives no lines', () {
      expect(parseLrc(''), isEmpty);
    });
  });

  group('activeLyricIndex', () {
    final lines = parseLrc('[00:05.00] a\n[00:10.00] b\n[00:15.00] c');
    test('before first line is -1', () {
      expect(activeLyricIndex(lines, const Duration(seconds: 2)), -1);
    });
    test('finds the current line', () {
      expect(activeLyricIndex(lines, const Duration(seconds: 5)), 0);
      expect(activeLyricIndex(lines, const Duration(seconds: 12)), 1);
      expect(activeLyricIndex(lines, const Duration(minutes: 5)), 2);
    });
    test('empty list is -1', () {
      expect(activeLyricIndex(const [], const Duration(seconds: 1)), -1);
    });
  });

  test('clock formats', () {
    expect(clock(const Duration(seconds: 65)), '1:05');
    expect(clock(const Duration(hours: 1, seconds: 3)), '1:00:03');
    expect(clock(const Duration(seconds: -4)), '0:00');
  });
}
