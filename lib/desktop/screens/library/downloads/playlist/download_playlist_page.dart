// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:zenmusic/desktop/screens/library/downloads/playlist/cubit/download_playlist_cubit.dart';
import 'package:zenmusic/desktop/screens/library/downloads/playlist/widgets/download_playlist_header.dart';
import 'package:zenmusic/desktop/screens/library/downloads/playlist/widgets/download_song_tile.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class DownloadPlaylistPage extends StatelessWidget {
  const DownloadPlaylistPage({
    super.key,
    required this.playlistId,
  });

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DownloadPlaylistCubit(playlistId)..load(),
      child: BlocBuilder<DownloadPlaylistCubit, DownloadPlaylistState>(
        builder: (context, state) {
          if (state is DownloadPlaylistLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state is DownloadPlaylistError) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Text('Playlist not available'.tr),
              ),
            );
          }
          final loaded = state as DownloadPlaylistLoaded;
          return _PlaylistView(
            playlist: loaded.playlist,
            songs: loaded.songs,
            playlistId: playlistId,
          );
        },
      ),
    );
  }
}

class _PlaylistView extends StatelessWidget {
  const _PlaylistView({
    required this.playlist,
    required this.songs,
    required this.playlistId,
  });

  final Map playlist;
  final List songs;
  final String playlistId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: playlist['type'] == 'SONGS'
            ? Text('Songs'.tr)
            : Text(playlist['title']),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(maxWidth: 1000),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    DownloadPlaylistHeader(
                      playlist: playlist,
                      imageType: playlist['type'],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final song = songs[index];

                    return SwipeActionCell(
                      key: ObjectKey(song['videoId']),
                      backgroundColor: Colors.transparent,
                      trailingActions: [
                        SwipeAction(
                          title: 'Remove'.tr,
                          color: Colors.red,
                          onTap: (handler) async {
                            final confirm = await Modals.showConfirmBottomModal(
                              context,
                              message:
                              'Remove this song from the playlist?',
                              isDanger: true,
                            );

                            if (confirm && context.mounted) {
                              final message = await context
                                  .read<DownloadPlaylistCubit>()
                                  .removeSong(song);

                              if (context.mounted) {
                                BottomMessage.showText(
                                  context,
                                  message.toString(),
                                );
                              }
                            }
                          },
                        ),
                      ],
                      child: DownloadedSongTile(song: song),
                    );
                  },
                  childCount: songs.length,
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
