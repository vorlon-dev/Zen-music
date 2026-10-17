// ZenMusic — Saved (Library) page. SP-6: adds a "Spotify" card when the
// user is logged in (routes to the Spotify library screen). Non-Spotify
// users see the page unchanged.

import 'dart:collection';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/screens/library/cubit/library_cubit.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/internet_guard.dart';
import 'package:zenmusic/desktop/utils/playlist_thumbnail.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LibraryCubit(GetIt.I<LibraryService>())..loadLibrary(),
      child: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          return InternetGuard(
            child: Scaffold(
              appBar: AppBar(
                title: Text('Saved', style: appBarTitleStyle()),
                centerTitle: true,
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    onPressed: () {
                      Modals.showImportplaylistModal(context);
                    },
                    icon: const Icon(
                      Icons.import_export_outlined,
                      size: 25,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Modals.showCreateplaylistModal(context);
                    },
                    icon: const Icon(
                      Icons.add,
                      size: 25,
                    ),
                  ),
                ],
              ),
              body: switch (state) {
                LibraryLoading() => const Center(child: AdaptiveProgressRing()),
                LibraryError(:final message) => Center(child: Text(message)),
                LibraryLoaded(
                    :final playlists,
                    :final favouritesCount,
                    :final downloadsCount,
                    :final historyCount
                ) =>
                    _LibraryBody(
                      playlists: playlists,
                      favouritesCount: favouritesCount,
                      downloadsCount: downloadsCount,
                      historyCount: historyCount,
                    ),
              },
            ),
          );
        },
      ),
    );
  }
}

class _LibraryBody extends StatelessWidget {
  const _LibraryBody(
      {required this.playlists,
        this.favouritesCount = 0,
        this.downloadsCount = 0,
        this.historyCount = 0});

  final Map playlists;
  final int favouritesCount;
  final int downloadsCount;
  final int historyCount;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SpotifyAuth.instance.loggedIn,
      builder: (context, spotifyLoggedIn, _) {
        final List<Map<String, dynamic>> gridItems = [];

        gridItems.add({
          'title': 'Favourites',
          'subtitle': '$favouritesCount songs',
          'icon': AdaptiveIcons.heart_fill,
          'onTap': () => context.push('/saved/favourites_page'),
        });

        gridItems.add({
          'title': 'Downloads',
          'subtitle': '$downloadsCount songs',
          'icon': AdaptiveIcons.download,
          'onTap': () => context.push('/saved/downloads_page'),
        });

        gridItems.add({
          'title': 'History',
          'subtitle': '$historyCount songs',
          'icon': Icons.history,
          'onTap': () => context.push('/saved/history_page'),
        });

        // SP-6: Spotify account entry, only when logged in.
        if (spotifyLoggedIn) {
          gridItems.add({
            'title': 'Spotify',
            'subtitle': 'Your account',
            'icon': Icons.library_music,
            'onTap': () => context.push('/saved/spotify_library'),
          });
        }

        final sortedPlaylists = SplayTreeMap.from(playlists);
        for (var entry in sortedPlaylists.entries) {
          if (entry.value == null) continue;
          final key = entry.key;
          final item = entry.value;

          gridItems.add({
            'title': item['title'],
            'subtitle': (item['songs'] != null || item['isPredefined'])
                ? (item['isPredefined'] == true
                ? item['subtitle']
                : '${item['songs'].length} songs')
                : '',
            'playlist_item': item,
            'playlist_key': key,
            'onTap': () {
              if (item['isPredefined'] == true) {
                context.push(
                  '/browse',
                  extra: {
                    'endpoint': item['endpoint'].cast<String, dynamic>(),
                  },
                );
              } else {
                context.push(
                  '/saved/playlist_details',
                  extra: {
                    'playlistkey': key,
                  },
                );
              }
            },
            'onSecondaryTap': () {
              if (item['videoId'] == null && item['playlistId'] != null) {
                Modals.showPlaylistBottomModal(context, item);
              } else if (item['isPredefined'] == false) {
                Modals.showPlaylistBottomModal(
                  context,
                  {...item, 'playlistId': key},
                );
              }
            }
          });
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.8,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: gridItems.length,
              itemBuilder: (context, index) {
                final item = gridItems[index];
                return _LibraryGridCard(item: item);
              },
            );
          },
        );
      },
    );
  }
}

class _LibraryGridCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _LibraryGridCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: item['onTap'],
      onSecondaryTap: item['onSecondaryTap'],
      onLongPress: item['onSecondaryTap'],
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
              child: _buildImage(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item['title'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (item['subtitle'] != null && item['subtitle'].toString().isNotEmpty)
            Text(
              item['subtitle'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
        ],
      ),
    );
  }

  Widget _buildImage(BuildContext context) {
    if (item['icon'] != null) {
      return Icon(
        item['icon'],
        size: 40,
        color: Theme.of(context).iconTheme.color,
      );
    }

    final playlistItem = item['playlist_item'];
    if (playlistItem != null) {
      if (playlistItem['isPredefined'] == true) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: playlistItem['thumbnails']
                .first['url']
                .replaceAll('w540-h225', 'w512-h512'),
            fit: BoxFit.cover,
          ),
        );
      }

      if (playlistItem['songs'] != null && playlistItem['songs'].isNotEmpty) {
        return PlaylistThumbnail(
          playslist: playlistItem['songs'],
          size: 200,
          radius: 12,
        );
      }
    }

    return const Icon(CupertinoIcons.music_note_list, size: 40);
  }
}