// ZenMusic — Spotify account library (Saved page entry).
// Liked Songs card + grid of the user's Spotify playlists. Taps route
// through MediaPlayer.playFromSection so the queue drawer reflects the
// whole section, and the Windows engine takes over for Spotify tracks.
//
// SP-6: data comes from Pathfinder (see spotify_library.dart). Playlist
// ids are full URIs (spotify:playlist:...), passed through to
// SpotifyPlaylistPage which calls fetchPlaylistTracks.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/library/spotify/cubit/spotify_library_cubit.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';

class SpotifyLibraryPage extends StatelessWidget {
  const SpotifyLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SpotifyLibraryCubit()..load(),
      child: BlocBuilder<SpotifyLibraryCubit, SpotifyLibraryState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Spotify', style: appBarTitleStyle()),
              centerTitle: true,
            ),
            body: switch (state) {
              SpotifyLibraryLoading() =>
              const Center(child: AdaptiveProgressRing()),
              SpotifyLibraryError(:final message) =>
                  Center(child: Text(message)),
              SpotifyLibraryLoaded(
                  :final userName,
                  :final likedSongs,
                  :final playlists,
              ) =>
                  _Body(
                    userName: userName,
                    likedSongs: likedSongs,
                    playlists: playlists,
                  ),
            },
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.userName,
    required this.likedSongs,
    required this.playlists,
  });

  final String? userName;
  final List<Map<String, dynamic>> likedSongs;
  final List<Map<String, dynamic>> playlists;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (userName != null && userName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Signed in as $userName',
                    style: TextStyle(
                        color: Theme.of(context).hintColor, fontSize: 13)),
              ),
            if (likedSongs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _LikedSongsCard(songs: likedSongs),
              ),
            if (playlists.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Your Playlists',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, i) =>
                    _SpotifyPlaylistCard(playlist: playlists[i]),
              ),
            ],
            if (likedSongs.isEmpty && playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No Spotify content yet')),
              ),
          ],
        ),
      ),
    );
  }
}

class _LikedSongsCard extends StatelessWidget {
  const _LikedSongsCard({required this.songs});
  final List<Map<String, dynamic>> songs;

  @override
  Widget build(BuildContext context) {
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        GetIt.I<MediaPlayer>().playFromSection(songs, 0);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFF43278C), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite, size: 48, color: Colors.white),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Liked Songs',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text('${songs.length} songs',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.75))),
                ],
              ),
            ),
            const Icon(Icons.play_arrow, size: 36, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _SpotifyPlaylistCard extends StatelessWidget {
  const _SpotifyPlaylistCard({required this.playlist});
  final Map<String, dynamic> playlist;

  @override
  Widget build(BuildContext context) {
    final thumb = (playlist['thumbnails'] as List?)?.isNotEmpty == true
        ? (playlist['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        // playlist['id'] is a full URI (spotify:playlist:...) — passed as-is
        // and consumed by SpotifyPlaylistPage.fetchPlaylistTracks.
        context.push(
          '/saved/spotify_playlist',
          extra: {
            'playlistId': playlist['id'],
            'title': playlist['title'],
          },
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: thumb.isEmpty
                  ? const Icon(Icons.queue_music, size: 40)
                  : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                    imageUrl: thumb, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(playlist['title'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(playlist['subtitle'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
              TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }
}