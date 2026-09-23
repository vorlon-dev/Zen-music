import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../theme/spotify_theme.dart';
import 'wave_spinner.dart';

/// "Your month" recap: total minutes + top songs, Spotify-Wrapped style.
class ListeningRecapCard extends StatelessWidget {
  const ListeningRecapCard({
    super.key,
    required this.periodLabel,
    required this.minutes,
    required this.songs,
    required this.onSongTap,
  });

  final String periodLabel;
  final int minutes;
  final List<Map<String, dynamic>> songs;
  final void Function(int index) onSongTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            SpotifyColors.green.withOpacity(0.18),
            SpotifyColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.data_trending_24_filled,
                  color: SpotifyColors.green, size: 18),
              const SizedBox(width: 8),
              Text(periodLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: SpotifyColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$minutes minutes listened',
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: SpotifyColors.textPrimary),
          ),
          const SizedBox(height: 14),
          ...List.generate(songs.length.clamp(0, 3), (i) {
            final s = songs[i];
            final song = Song(
              id: s['ytid']?.toString() ?? '',
              title: s['title']?.toString() ?? 'Unknown',
              artist: s['artist']?.toString() ?? 'Unknown',
              thumbnail: s['image']?.toString() ?? '',
              duration: Duration.zero,
            );
            final plays = s['playCount']?.toString() ?? '0';
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSongTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text('${i + 1}.',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: SpotifyColors.green)),
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        song.thumbnail,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 38,
                            height: 38,
                            color: SpotifyColors.surfaceLight,
                            child: const Center(
                              child: WaveSpinner(size: 16, strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Container(
                          width: 38,
                          height: 38,
                          color: SpotifyColors.surfaceLight,
                          child: const Icon(Icons.music_note_rounded,
                              size: 18, color: SpotifyColors.textTertiary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: SpotifyColors.textPrimary)),
                    ),
                    Text('$plays plays',
                        style: const TextStyle(
                            fontSize: 11,
                            color: SpotifyColors.textSecondary)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}