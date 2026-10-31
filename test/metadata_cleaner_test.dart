import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/services/lyrics_service.dart';

void main() {
  group('MetadataCleaner.clean titles', () {
    test('strips an (Official Video) tag', () {
      final r =
          MetadataCleaner.clean('Song Name (Official Video)', 'Some Artist');
      expect(r.cleanTitle, 'Song Name');
      expect(r.primaryArtist, 'Some Artist');
      expect(r.featuredArtists, isEmpty);
      expect(r.versionLabel, '');
    });

    test('keeps the raw inputs', () {
      final r = MetadataCleaner.clean('Song (Official Video)', 'Artist');
      expect(r.rawTitle, 'Song (Official Video)');
      expect(r.rawArtist, 'Artist');
    });

    test('splits "Artist - Title" when no artist is known', () {
      final r = MetadataCleaner.clean('Artist - Song Title', '');
      expect(r.cleanTitle, 'Song Title');
      expect(r.primaryArtist, 'Artist');
    });

    test('does not adopt a split when the prefix is unrelated to the artist',
        () {
      final r = MetadataCleaner.clean('Other Band - Song', 'Real Artist');
      expect(r.cleanTitle, 'Other Band - Song');
      expect(r.primaryArtist, 'Real Artist');
    });

    test('does not split when the right side is a version tag', () {
      final r = MetadataCleaner.clean('Song - Live', 'Artist');
      expect(r.cleanTitle, 'Song - Live');
      expect(r.versionLabel, 'Live');
    });

    test('removes trailing pipe junk', () {
      final r = MetadataCleaner.clean('Song | Official Visualizer', 'Artist');
      expect(r.cleanTitle, 'Song');
    });

    test('removes hashtags', () {
      final r = MetadataCleaner.clean('Song #shorts', 'Artist');
      expect(r.cleanTitle, 'Song');
    });

    test('removes emoji', () {
      final r = MetadataCleaner.clean('Song \u{1F525}', 'Artist');
      expect(r.cleanTitle, 'Song');
    });

    test('decodes HTML entities', () {
      expect(MetadataCleaner.clean('Rock &amp; Roll', 'Artist').cleanTitle,
          'Rock & Roll');
    });
  });

  group('MetadataCleaner.clean featured artists and versions', () {
    test('reads a bracketed (feat. X) credit', () {
      final r = MetadataCleaner.clean('Song (feat. Guest)', 'Main Artist');
      expect(r.cleanTitle, 'Song');
      expect(r.primaryArtist, 'Main Artist');
      expect(r.featuredArtists, ['Guest']);
    });

    test('reads an inline "feat." credit', () {
      final r = MetadataCleaner.clean('Song feat. Guest', 'Artist');
      expect(r.cleanTitle, 'Song');
      expect(r.featuredArtists, ['Guest']);
    });

    test('removes a (Live) tag and records the version', () {
      final r = MetadataCleaner.clean('Song (Live)', 'Artist');
      expect(r.cleanTitle, 'Song');
      expect(r.versionLabel, 'Live');
    });
  });

  group('MetadataCleaner.clean artists', () {
    test('removes the "- Topic" channel suffix', () {
      final r = MetadataCleaner.clean('Song', 'Some Artist - Topic');
      expect(r.primaryArtist, 'Some Artist');
      expect(r.cleanArtist, 'Some Artist');
    });

    test('removes VEVO and splits camel case', () {
      final r = MetadataCleaner.clean('Song', 'ArtistNameVEVO');
      expect(r.cleanArtist, 'Artist Name');
    });

    test('splits several artists into primary and featured', () {
      final r = MetadataCleaner.clean('Song', 'A & B, C');
      expect(r.primaryArtist, 'A');
      expect(r.featuredArtists, ['B', 'C']);
    });

    test('an empty artist gives an empty primary artist', () {
      final r = MetadataCleaner.clean('Song');
      expect(r.primaryArtist, '');
      expect(r.cleanTitle, 'Song');
    });
  });
}
