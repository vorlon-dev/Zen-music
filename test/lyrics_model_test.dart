import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/desktop/models/lyrics_model.dart';

Lyrics _lyrics({String? synced, String? duration}) => Lyrics(
      id: 'id-1',
      artist: 'Artist',
      title: 'Title',
      lyricsPlain: 'plain lyrics text',
      provider: LyricsProvider.lrcnet,
      lyricsSynced: synced,
      duration: duration,
    );

void main() {
  group('ParsedLyrics', () {
    test('parses minutes, seconds, milliseconds and text', () {
      final parsed = ParsedLyrics(
        syncedLyrics: '[01:02.345] Hello world',
        duration: '200',
      );

      expect(parsed.lyrics, hasLength(1));
      expect(parsed.lyrics.first.text, 'Hello world');
      expect(
        parsed.lyrics.first.start,
        const Duration(minutes: 1, seconds: 2, milliseconds: 345),
      );
    });

    test('parses multiple lines in order', () {
      final parsed = ParsedLyrics(
        syncedLyrics: '[00:05.000] First\n[00:10.000] Second\n[01:00.000] Third',
        duration: '90',
      );

      expect(parsed.lyrics.map((l) => l.text), ['First', 'Second', 'Third']);
      expect(parsed.lyrics.map((l) => l.start.inSeconds), [5, 10, 60]);
    });

    test('ignores lines without a timestamp', () {
      final parsed = ParsedLyrics(
        syncedLyrics: '[ar:Some Artist]\nno timestamp here\n[00:03.000] Real line',
        duration: '60',
      );

      expect(parsed.lyrics, hasLength(1));
      expect(parsed.lyrics.first.text, 'Real line');
    });

    test('empty input produces no lines', () {
      final parsed = ParsedLyrics(syncedLyrics: '', duration: '0');
      expect(parsed.lyrics, isEmpty);
    });
  });

  group('Lyrics', () {
    test('builds parsedLyrics when synced lyrics are provided', () {
      final lyrics = _lyrics(synced: '[00:01.000] Line one', duration: '120');

      expect(lyrics.parsedLyrics, isNotNull);
      expect(lyrics.parsedLyrics!.lyrics, hasLength(1));
      expect(lyrics.parsedLyrics!.duration, '120');
    });

    test('leaves parsedLyrics null without synced lyrics', () {
      expect(_lyrics().parsedLyrics, isNull);
    });

    test('copyWith overrides only the given fields', () {
      final original = _lyrics(duration: '100');
      final copy = original.copyWith(title: 'New Title');

      expect(copy.title, 'New Title');
      expect(copy.artist, original.artist);
      expect(copy.id, original.id);
      expect(copy.lyricsPlain, original.lyricsPlain);
      expect(copy.provider, original.provider);
      expect(copy.duration, '100');
    });
  });
}
