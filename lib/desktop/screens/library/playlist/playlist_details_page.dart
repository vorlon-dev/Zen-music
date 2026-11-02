// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/screens/library/playlist/cubit/playlist_details_cubit.dart';
import 'package:zenmusic/desktop/screens/library/widgets/my_playlist_header.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class PlaylistDetailsPage extends StatelessWidget {
  const PlaylistDetailsPage({
    super.key,
    required this.playlistkey,
  });

  final String playlistkey;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlaylistDetailsCubit(playlistkey)..load(),
      child: BlocBuilder<PlaylistDetailsCubit, PlaylistDetailsState>(
        builder: (context, state) {
          return switch (state) {
            PlaylistDetailsLoading() => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            PlaylistDetailsError() => const Scaffold(
              body: Center(child: Text('Not available')),
            ),
            PlaylistDetailsLoaded(:final playlist) => _PlaylistView(
              playlist: playlist,
              playlistKey: playlistkey,
            ),
          };
        },
      ),
    );
  }
}

class _PlaylistView extends StatelessWidget {
  const _PlaylistView({
    required this.playlist,
    required this.playlistKey,
  });

  final Map playlist;
  final String playlistKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist['title']),
        centerTitle: true,
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(maxWidth: 1000),
          child: ListView(
            children: [
              MyPlayistHeader(playlist: playlist),
              const SizedBox(height: 8),
              ...playlist['songs'].map<Widget>((song) {
                return SwipeActionCell(
                  backgroundColor: Colors.transparent,
                  key: ObjectKey(song['videoId']),
                  trailingActions: [
                    SwipeAction(
                      title: 'Remove',
                      color: Colors.red,
                      onTap: (handler) async {
                        final confirm = await Modals.showConfirmBottomModal(
                          context,
                          message: 'Remove this song from the playlist?',
                          isDanger: true,
                        );

                        if (confirm) {
                          final message = await context
                              .read<PlaylistDetailsCubit>()
                              .removeSong(song);

                          BottomMessage.showText(context, message);
                        }
                      },
                    ),
                  ],
                  child: SongTile(
                    song: song,
                    playlistId: playlistKey,
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }
}
