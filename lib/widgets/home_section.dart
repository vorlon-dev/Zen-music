import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import 'youtube_thumbnail.dart';

class HomeSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Song> songs;
  final void Function(Song) onTap;
  final double tileSize;

  const HomeSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.songs,
    required this.onTap,
    this.tileSize = 160,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: SpotifyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: SpotifyColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: tileSize + 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: songs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final song = songs[i];
              return GestureDetector(
                onTap: () => onTap(song),
                child: SizedBox(
                  width: tileSize,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YoutubeThumbnail(
                        videoId: song.id,
                        imageUrl: song.thumbnail,
                        width: tileSize,
                        height: tileSize,
                        borderRadius: 8,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SpotifyColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SpotifyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}