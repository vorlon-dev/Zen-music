import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import 'youtube_thumbnail.dart';

class StartListeningList extends StatelessWidget {
  final List<Song> songs;
  final void Function(Song) onTap;

  const StartListeningList({
    super.key,
    required this.songs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 28, 20, 6),
          child: Text(
            'Jump into a session based on your tastes',
            style: TextStyle(
              fontSize: 13,
              color: SpotifyColors.textSecondary,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Text(
            'Start listening',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: SpotifyColors.textPrimary,
            ),
          ),
        ),
        ...songs.map((song) => ListTile(
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: YoutubeThumbnail(
            videoId: song.id,
            imageUrl: song.thumbnail,
            width: 56,
            height: 56,
            borderRadius: 6,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: SpotifyColors.textPrimary,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: SpotifyColors.textSecondary,
            ),
          ),
          trailing: const Icon(
            Icons.more_vert,
            color: SpotifyColors.textSecondary,
            size: 20,
          ),
          onTap: () => onTap(song),
        )),
      ],
    );
  }
}