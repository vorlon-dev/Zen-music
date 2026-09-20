import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/spotify_theme.dart';
import 'youtube_thumbnail.dart';

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final handler = audioHandler;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: SpotifyColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Up Next',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: SpotifyColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => handler.clearQueue(),
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: SpotifyColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: SpotifyColors.surfaceLight, height: 1),
          Expanded(
            child: StreamBuilder<List<dynamic>>(
              stream: handler.queueStream,
              initialData: handler.queueSongs,
              builder: (context, queueSnap) {
                final queue = queueSnap.data ?? [];
                if (queue.isEmpty) {
                  return const Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(color: SpotifyColors.textSecondary),
                    ),
                  );
                }
                return StreamBuilder<int?>(
                  stream: handler.currentIndexStream,
                  builder: (context, indexSnap) {
                    final currentIndex = indexSnap.data ?? 0;
                    return ListView.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, i) {
                        final song = queue[i];
                        final isCurrent = i == currentIndex;
                        return ListTile(
                          leading: YoutubeThumbnail(
                            videoId: song.id,
                            imageUrl: song.thumbnail,
                            width: 48,
                            height: 48,
                            borderRadius: 6,
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? SpotifyColors.green
                                  : SpotifyColors.textPrimary,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SpotifyColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: SpotifyColors.textTertiary,
                              size: 20,
                            ),
                            onPressed: () => handler.removeFromQueue(i),
                          ),
                          onTap: () => handler.skipToQueueItem(i),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}