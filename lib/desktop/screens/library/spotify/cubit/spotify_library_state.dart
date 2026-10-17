part of 'spotify_library_cubit.dart';

sealed class SpotifyLibraryState {
  const SpotifyLibraryState();
}

class SpotifyLibraryLoading extends SpotifyLibraryState {
  const SpotifyLibraryLoading();
}

class SpotifyLibraryError extends SpotifyLibraryState {
  final String message;
  const SpotifyLibraryError(this.message);
}

class SpotifyLibraryLoaded extends SpotifyLibraryState {
  final String? userName;
  final List<Map<String, dynamic>> likedSongs;
  final List<Map<String, dynamic>> playlists;

  const SpotifyLibraryLoaded({
    required this.userName,
    required this.likedSongs,
    required this.playlists,
  });
}