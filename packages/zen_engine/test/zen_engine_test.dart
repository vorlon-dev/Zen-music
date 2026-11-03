import 'package:flutter_test/flutter_test.dart';
import 'package:zen_engine/zen_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZenSong model tests', () {
    test('Constructs correctly from JioSaavn JSON', () {
      final json = {
        'id': 'saavn_123',
        'title': 'Test Song &amp; Track',
        'artist': 'Test Artist',
        'duration': 180,
        'jiosaavnStreamUrl': 'https://stream.saavn.com/test.mp3',
        'thumbnails': [{'url': 'https://image.com/art.jpg'}],
      };

      final song = ZenSong.fromJioSaavn(json);
      expect(song.id, 'saavn_123');
      expect(song.title, 'Test Song & Track');
      expect(song.artist, 'Test Artist');
      expect(song.duration.inSeconds, 180);
      expect(song.streamUrl, 'https://stream.saavn.com/test.mp3');
      expect(song.source, ZenSongSource.jiosaavn);
    });

    test('Constructs correctly from YouTube JSON', () {
      final json = {
        'videoId': 'yt_abc123',
        'title': 'YouTube Song',
        'artist': 'YouTube Artist',
        'duration': 210,
        'thumbnails': [{'url': 'https://i.ytimg.com/vi/yt_abc123/hqdefault.jpg'}],
      };

      final song = ZenSong.fromYouTube(json);
      expect(song.id, 'yt_abc123');
      expect(song.title, 'YouTube Song');
      expect(song.artist, 'YouTube Artist');
      expect(song.duration.inSeconds, 210);
      expect(song.source, ZenSongSource.youtube);
    });
  });

  group('Lyrics parsing tests', () {
    test('Parses LRC timestamps properly', () {
      const lrc = '''
[00:12.34] First lyric line
[01:05.67] Second lyric line
''';

      final parsed = ParsedLyrics(syncedLyrics: lrc, duration: '180');
      expect(parsed.lyrics.length, 2);
      expect(parsed.lyrics[0].text, 'First lyric line');
      expect(parsed.lyrics[0].start.inSeconds, 12);
      expect(parsed.lyrics[1].text, 'Second lyric line');
      expect(parsed.lyrics[1].start.inSeconds, 65);
    });
  });

  group('Lossless quality tests', () {
    test('Enum values have correct keys', () {
      expect(LosslessQuality.mp3_320.tierKey, 'mp3_320');
      expect(LosslessQuality.flacCd.tierKey, 'flac_cd');
      expect(LosslessQuality.flacHiRes96.tierKey, 'flac_hires_96');
      expect(LosslessQuality.flacHiResMax.tierKey, 'flac_hires_192');
    });
  });

  group('Player State tests', () {
    test('Initial state is idle', () {
      const state = ZenPlayerState();
      expect(state.status, PlayerPlaybackStatus.idle);
      expect(state.isPlaying, false);
      expect(state.isLoading, false);
      expect(state.queue.isEmpty, true);
      expect(state.currentSong, null);
    });

    test('State copyWith updates properly', () {
      const state = ZenPlayerState();
      final song = ZenSong(id: '1', title: 'A', artist: 'B');
      final updated = state.copyWith(
        currentSong: song,
        status: PlayerPlaybackStatus.playing,
      );

      expect(updated.currentSong?.title, 'A');
      expect(updated.status, PlayerPlaybackStatus.playing);
      expect(updated.isPlaying, true);
    });
  });
}
