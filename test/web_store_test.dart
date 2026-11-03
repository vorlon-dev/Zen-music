// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_store.dart';

WebSong song(String id) => WebSong(
      id: id,
      title: 't$id',
      artist: 'a',
      album: '',
      image: '',
      streamUrl: 'https://x/$id.mp4',
      duration: const Duration(seconds: 100),
    );

void main() {
  group('WebSong storage', () {
    test('toJson / fromStored round trip', () {
      final s = song('1');
      final back = WebSong.fromStored(s.toJson())!;
      expect(back.id, '1');
      expect(back.title, 't1');
      expect(back.streamUrl, s.streamUrl);
      expect(back.duration, const Duration(seconds: 100));
    });

    test('fromStored rejects bad data', () {
      expect(WebSong.fromStored(null), isNull);
      expect(WebSong.fromStored('x'), isNull);
      expect(WebSong.fromStored(<String, Object?>{'title': 'no id'}), isNull);
    });
  });

  group('WebCollection', () {
    test('parses album json', () {
      final c = WebCollection.fromJson({
        'id': '9',
        'name': 'Best &amp; Hits',
        'description': 'd',
        'image': [
          {'quality': '150x150', 'url': 'http://x/150.jpg'},
          {'quality': '500x500', 'url': 'http://x/500.jpg'},
        ],
      }, isAlbum: true);
      expect(c.title, 'Best & Hits');
      expect(c.image, 'https://x/500.jpg');
      expect(c.isAlbum, isTrue);
    });
  });

  group('WebStore (memory)', () {
    test('favourites toggle and order', () {
      final st = WebStore.memory();
      st.toggleFavourite(song('1'));
      st.toggleFavourite(song('2'));
      expect(st.favourites.map((s) => s.id), ['2', '1']);
      expect(st.isFavourite('1'), isTrue);
      st.toggleFavourite(song('1'));
      expect(st.isFavourite('1'), isFalse);
    });

    test('history is de-duplicated, newest first and capped', () {
      final st = WebStore.memory();
      st.addToHistory(song('1'));
      st.addToHistory(song('2'));
      st.addToHistory(song('1'));
      expect(st.history.map((s) => s.id), ['1', '2']);
      for (var i = 0; i < WebStore.maxHistory + 10; i++) {
        st.addToHistory(song('n$i'));
      }
      expect(st.history.length, WebStore.maxHistory);
      st.clearHistory();
      expect(st.history, isEmpty);
    });

    test('playlists', () {
      final st = WebStore.memory();
      expect(st.createPlaylist('  '), isFalse);
      expect(st.createPlaylist('Gym'), isTrue);
      expect(st.createPlaylist('Gym'), isFalse);
      st.addToPlaylist('Gym', song('1'));
      st.addToPlaylist('Gym', song('1'));
      st.addToPlaylist('Nope', song('2'));
      expect(st.playlist('Gym').length, 1);
      st.removeFromPlaylist('Gym', '1');
      expect(st.playlist('Gym'), isEmpty);
      st.deletePlaylist('Gym');
      expect(st.playlistNames, isEmpty);
    });

    test('theme mode and change notifications', () {
      final st = WebStore.memory();
      var calls = 0;
      st.addListener(() => calls++);
      expect(st.themeMode, ThemeMode.dark);
      st.setThemeMode(ThemeMode.light);
      expect(st.themeMode, ThemeMode.light);
      expect(calls, 1);
    });
  });
}
