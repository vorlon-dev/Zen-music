// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:zenmusic/desktop/screens/library/favourites/cubit/favourites_cubit.dart';
import 'package:zenmusic/desktop/screens/library/widgets/library_tile.dart';
import 'package:zenmusic/desktop/screens/library/widgets/my_playlist_header.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class FavouritesPage extends StatelessWidget {
  const FavouritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FavouritesCubit()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Favourites'.tr),
          centerTitle: true,
        ),
        body: BlocBuilder<FavouritesCubit, FavouritesState>(
          builder: (context, state) {
            return switch (state) {
              FavouritesLoading() =>
              const Center(child: AdaptiveProgressRing()),
              FavouritesError(:final message) => Center(child: Text(message)),
              FavouritesLoaded(:final songs) => _FavouritesBody(songs: songs),
            };
          },
        ),
      ),
    );
  }
}

class _FavouritesBody extends StatelessWidget {
  const _FavouritesBody({required this.songs});

  final List songs;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              MyPlayistHeader(
                playlist: {'songs': songs},
              ),
              Column(
                children: List.generate(songs.length, (index) {
                  final song = songs[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SwipeActionCell(
                      key: ObjectKey(song),
                      backgroundColor: Colors.transparent,
                      trailingActions: [
                        SwipeAction(
                          title: 'Remove'.tr,
                          color: Colors.red,
                          onTap: (handler) async {
                            final confirm = await Modals.showConfirmBottomModal(
                              context,
                              message:
                              'Remove this song from your favourites?',
                              isDanger: true,
                            );

                            if (confirm && context.mounted) {
                              context
                                  .read<FavouritesCubit>()
                                  .remove(song['id'] ?? song['videoId']);
                            }
                          },
                        ),
                      ],
                      child: LibraryTile(
                        songs: songs,
                        index: index,
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
