// ZenMusic Desktop — ported from Echo Music (GPL-3.0), services/import_service.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// R8d: spotify branch restored verbatim now that spotify.dart is vendored.

import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/spotify.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

class ImportState {
  final int total;
  final int current;
  final String message;
  final bool isDone;
  final bool isError;

  ImportState({
    required this.total,
    required this.current,
    required this.message,
    this.isDone = false,
    this.isError = false,
  });
}

class ImportService {
  final SpotifyService _spotify = SpotifyService();
  final YTMusic _ytMusic = GetIt.I<YTMusic>();
  final LibraryService _library = GetIt.I<LibraryService>();

  Stream<ImportState> import(String url) async* {
    if (url.contains('spotify.com')) {
      yield* _importSpotify(url);
    } else if (url.contains('youtu.be') || url.contains('youtube.com')) {
      yield* _importYouTube(url);
    } else {
      yield ImportState(
        total: 0,
        current: 0,
        message: "Invalid URL",
        isError: true,
      );
    }
  }

  Stream<ImportState> _importYouTube(String url) async* {
    yield ImportState(
      total: 0,
      current: 0,
      message: "Importing YouTube Playlist...",
    );
    try {
      final result = await _library.importPlaylist(url);
      if (result.contains('Error') || result == 'Invalid Url') {
        yield ImportState(
          total: 0,
          current: 0,
          message: result,
          isError: true,
        );
      } else {
        yield ImportState(
          total: 1,
          current: 1,
          message: result,
          isDone: true,
        );
      }
    } catch (e) {
      yield ImportState(
        total: 0,
        current: 0,
        message: "Failed to import: $e",
        isError: true,
      );
    }
  }

  Stream<ImportState> _importSpotify(String url) async* {
    try {
      yield ImportState(total: 0, current: 0, message: "Connecting to spotify...");
      final token = await _spotify.getAccessTokenCC();

      String? playlistId;
      if (url.contains('/playlist/')) {
        playlistId = url.split('/playlist/')[1].split('?')[0];
      } else if (url.contains('/album/')) {
        playlistId = url.split('/album/')[1].split('?')[0];
      }

      if (playlistId == null) {
        yield ImportState(total: 0, current: 0, message: "Invalid spotify URL", isError: true);
        return;
      }

      yield ImportState(total: 0, current: 0, message: "Fetching Playlist Tracks...");
      Map<String, Object> playlistData;

      if (url.contains('/album/')) {
        playlistData = await _spotify.getAllAlbumTracks(token, playlistId);
      } else {
        playlistData = await _spotify.getAllTracksOfPlaylist(token, playlistId);
      }

      final tracks = playlistData['tracks'] as List;
      final playlistName = playlistData['playlistName'] as String? ?? (url.contains('/album/') ? (playlistData['albumName'] as String? ?? "Imported Album") : "Imported Playlist");

      if (tracks.isEmpty) {
        yield ImportState(total: 0, current: 0, message: "No tracks found", isError: true);
        return;
      }

      // Create playlist
      yield ImportState(total: tracks.length, current: 0, message: "Created Playlist: $playlistName");
      String playlistKey = await _library.createPlaylistKey(playlistName);

      int count = 0;
      for (var track in tracks) {
        if (track == null) continue;
        String title = "";
        if (track['name'] != null) title += track['name'];
        if (track['artists'] != null && (track['artists'] as List).isNotEmpty) {
          var artists = track['artists'];
          if (artists is List) {
            title += " " + artists.map((a) => a['name']).join(" ");
          } else if (artists is String) {
            title += " " + artists;
          }
        }

        yield ImportState(
            total: tracks.length,
            current: count + 1,
            message: "Searching: $title"
        );

        // Search on YT
        final match = await _findSongOnYouTube(title);
        if (match != null) {
          await _library.addToPlaylist(item: match, key: playlistKey);
          yield ImportState(
              total: tracks.length,
              current: count + 1,
              message: "Imported: ${match['title']}"
          );
        } else {
          yield ImportState(
              total: tracks.length,
              current: count + 1,
              message: "Not found: $title"
          );
        }
        count++;
      }

      yield ImportState(
        total: tracks.length,
        current: count,
        message: "Import Complete",
        isDone: true,
      );

    } catch (e) {
      yield ImportState(total: 0, current: 0, message: "Error: $e", isError: true);
    }
  }

  // Helper to find song on YT
  Future<Map?> _findSongOnYouTube(String query) async {
    try {
      final result = await _ytMusic.search(query, filter: 'songs');
      if (result['sections'] != null && (result['sections'] as List).isNotEmpty) {
        final section = result['sections'][0];
        if (section['contents'] != null && (section['contents'] as List).isNotEmpty) {
          return section['contents'][0];
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }
}