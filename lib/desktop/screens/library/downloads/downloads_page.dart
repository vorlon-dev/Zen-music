// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/library/downloads/cubit/downloads_cubit.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/core/extensions.dart';
import 'package:zenmusic/desktop/utils/modals_extra.dart';
import 'package:zenmusic/desktop/utils/playlist_thumbnail.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DownloadsCubit()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Downloads'.tr),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () {
                DownloadModals.showDownloadBottomModal(context);
              },
              icon: const Icon(Icons.more_vert, size: 25),
            ),
          ],
        ),
        body: BlocBuilder<DownloadsCubit, DownloadsState>(
          builder: (context, state) {
            return switch (state) {
              DownloadsLoading() =>
              const Center(child: CircularProgressIndicator()),
              DownloadsError(:final message) => Center(child: Text(message)),
              DownloadsLoaded(:final playlists) =>
                  _DownloadsBody(playlists: playlists),
            };
          },
        ),
      ),
    );
  }
}

class _DownloadsBody extends StatelessWidget {
  const _DownloadsBody({required this.playlists});

  final Map playlists;

  @override
  Widget build(BuildContext context) {
    List<MapEntry> sortedEntries = playlists.entries.toList();

    sortedEntries.sort((a, b) {
      if (a.key == DownloadManager.songsPlaylistId) {
        return -1;
      } else if (b.key == DownloadManager.songsPlaylistId) {
        return 1;
      } else {
        return a.value['title'].compareTo(b.value['title']);
      }
    });

    return SingleChildScrollView(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: sortedEntries.map((entry) {
              final playlist = entry.value;

              return AdaptiveListTile(
                margin: const EdgeInsets.symmetric(vertical: 4),
                title: playlist['type'] == 'SONGS'
                    ? Text('Songs'.tr)
                    : Text(playlist['title']),
                leading: _leading(context, playlist),
                subtitle: Text(
                  '${playlist['songs'].length} songs',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  context.push(
                    '/saved/downloads_page/download_playlist_page',
                    extra: {'playlistId': playlist['id']},
                  );
                },
                onSecondaryTap: () {
                  DownloadModals.showDownloadDetailsBottomModal(
                    context,
                    playlist,
                  );
                },
                onLongPress: () {
                  DownloadModals.showDownloadDetailsBottomModal(
                    context,
                    playlist,
                  );
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _leading(BuildContext context, Map playlist) {
    if (playlist['type'] == 'SONGS') {
      return Container(
        height: 50,
        width: 50,
        decoration: BoxDecoration(
          color: greyColor,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Icon(
          Icons.music_note,
          color: context.isDarkMode ? Colors.white : Colors.black,
        ),
      );
    }

    if (playlist['type'] == 'ALBUM') {
      return PlaylistThumbnail(
        playslist: [playlist['songs'][0]],
        size: 50,
      );
    }

    return PlaylistThumbnail(
      playslist: playlist['songs'],
      size: 50,
    );
  }
}
