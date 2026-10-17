import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

import 'package:zenmusic/desktop/spotify/spotify_library.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';

part 'spotify_library_state.dart';

class SpotifyLibraryCubit extends Cubit<SpotifyLibraryState> {
  SpotifyLibraryCubit() : super(const SpotifyLibraryLoading());

  Future<void> load() async {
    emit(const SpotifyLibraryLoading());
    if (!SpotifyAuth.instance.loggedIn.value) {
      emit(const SpotifyLibraryError(
          'Not logged in to Spotify. Open the login page first.'));
      return;
    }
    try {
      final lib = SpotifyLibrary.instance;

      // Profile.
      final me = await lib.me();
      final userName = me?['display_name']?.toString();

      // Liked songs — isolated so a failure doesn't kill playlists.
      var liked = <Map<String, dynamic>>[];
      try {
        liked = await lib.userLikedSongs(limit: 100);
      } catch (e) {
        debugPrint('[spotify-lib] liked songs failed: $e');
      }

      // Playlists.
      final playlists = await lib.userPlaylists(limit: 50);

      emit(SpotifyLibraryLoaded(
        userName: userName,
        likedSongs: liked,
        playlists: playlists,
      ));
    } catch (e) {
      emit(SpotifyLibraryError(e.toString()));
    }
  }
}