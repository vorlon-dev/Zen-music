import 'package:flutter_test/flutter_test.dart';

import '../lib/services/song_source_resolver.dart';
import '../lib/models/song.dart';

Song _song(String title, String artist, {int seconds = 200}) => Song(
  id: 'id-${title.hashCode}-${artist.hashCode}',
  title: title,
  artist: artist,
  thumbnail: '',
  duration: Duration(seconds: seconds),
);

void main() {
  group('normalizeTitle', () {
    test('strips parens, brackets and noise words', () {
      expect(
        SongSourceResolver.normalizeTitleForTest(
            'Tum Hi Ho (Official Video) [4K]'),
        'tum hi ho',
      );
      expect(
        SongSourceResolver.normalizeTitleForTest(
            'Kesariya - Lyrical | Audio Jukebox'),
        contains('kesariya'),
      );
    });

    test('collapses punctuation and whitespace', () {
      expect(
        SongSourceResolver.normalizeTitleForTest('A--B!!  C   D'),
        'a b c d',
      );
    });
  });

  group('wordOverlap', () {
    test('full overlap on same words', () {
      expect(
        SongSourceResolver.wordOverlapForTest('ice on my baby', 'baby ice on my'),
        1.0,
      );
    });

    test('zero overlap', () {
      expect(
        SongSourceResolver.wordOverlapForTest('one two three', 'four five six'),
        0.0,
      );
    });
  });

  group('scoreCandidate', () {
    test('exact title + artist scores high', () {
      final score = SongSourceResolver.scoreForTest(
        _song('One Sun One Moon', 'Anirudh Ravichander'),
        _song('One Sun One Moon', 'Anirudh Ravichander'),
      );
      expect(score, greaterThanOrEqualTo(18));
    });

    test('unrelated title is rejected outright', () {
      expect(
        SongSourceResolver.scoreForTest(
          _song('Completely Different Song', 'Someone Else'),
          _song('One Sun One Moon', 'Anirudh Ravichander'),
        ),
        isNull,
      );
    });

    test('empty original artist is not a free pass', () {
      // Original with no artist must not fuzzy-match random songs.
      expect(
        SongSourceResolver.scoreForTest(
          _song('One Sun One Moon', 'Random Cover Band'),
          _song('One Sun One Moon', ''),
        ),
        isNull,
      );
    });
  });

  group('pickBest', () {
    test('prefers the exact studio match over a live version', () {
      final original = _song('One Sun One Moon', 'Anirudh Ravichander');
      final exact = _song('One Sun One Moon', 'Anirudh Ravichander',
          seconds: 200);
      final live = _song('One Sun One Moon Live', 'Anirudh Ravichander',
          seconds: 320);
      final best = SongSourceResolver.pickBestForTest([live, exact], original);
      expect(best?.title, 'One Sun One Moon');
    });

    test('duration proximity breaks ties toward the studio length', () {
      final original = _song('Same Title', 'Same Artist', seconds: 200);
      final close = _song('Same Title', 'Same Artist', seconds: 201);
      final far = _song('Same Title', 'Same Artist', seconds: 300);
      final best =
      SongSourceResolver.pickBestForTest([far, close], original);
      expect(best?.duration, close.duration);
    });

    test('returns null when nothing clears the confidence floor', () {
      final original = _song('Obscure Track', 'Obscure Artist');
      final weak = _song('Obscure Track', 'Totally Different Singer');
      // Title matches (containment) but artist overlap ~0 → rejected
      // by the artist gate.
      expect(
        SongSourceResolver.pickBestForTest([weak], original),
        isNull,
      );
    });
  });
}