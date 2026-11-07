// ZenMusic · vorlon-dev
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zenmusic/desktop/services/automix.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart' show TempoSource;
import 'package:zenmusic/desktop/services/lyrics_providers/genius.dart';

class _Fixed implements TempoSource {
  _Fixed(this.bpm);
  final Map<String, double> bpm;
  @override
  Future<double?> tempoFor(String title, String artist) async => bpm[title];
}

Map<String, dynamic> _song(String title) =>
    {'title': title, 'artists': [{'name': 'A'}]};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Genius text cleanup', () {
    test('drops the Embed tail and collapses blank runs', () {
      final raw = Genius.stripArtifacts('[Verse 1]\nHello\n\n\n\nWorld\n12Embed');
      expect(Genius.textToLines(raw), '[Verse 1]\nHello\n\nWorld');
    });
    test('parses lyrics containers and keeps line breaks', () {
      const page = '<div data-lyrics-container="true">One<br>Two<br><br>Three'
          '</div>';
      expect(Genius.parseHtml(page), 'One\nTwo\n\nThree');
    });
  });

  group('Automix planner', () {
    test('close tempos are stretched toward each other', () async {
      final a = Automix(tempoSource: _Fixed({'out': 120, 'in': 124}));
      final p = (await a.plan(_song('out'), _song('in')))!;
      expect(p.stretches, isTrue);
      expect(p.incomingStartSpeed, closeTo(120 / 124, 1e-6));
      expect(p.outgoingEndSpeed, closeTo(124 / 120, 1e-6));
      // 16 beats at 120 BPM = 8 s.
      expect(p.window.inMilliseconds, 8000);
    });
    test('far tempos fall back to a short plain fade', () async {
      final a = Automix(tempoSource: _Fixed({'out': 90, 'in': 128}));
      final p = (await a.plan(_song('out'), _song('in')))!;
      expect(p.stretches, isFalse);
      expect(p.window.inSeconds, 4);
    });
    test('half/double time counts as the same groove', () async {
      final a = Automix(tempoSource: _Fixed({'out': 70, 'in': 140}));
      final p = (await a.plan(_song('out'), _song('in')))!;
      expect(p.stretches, isFalse); // exactly double: ratio 1 after folding
      expect(p.window.inMilliseconds, greaterThan(4000));
    });
  });
}
