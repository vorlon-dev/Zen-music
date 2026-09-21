import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import 'section_header.dart';
import 'song_row.dart';

class SongListSection extends StatelessWidget {
  const SongListSection({
    super.key,
    required this.title,
    required this.songs,
    this.showPlayButton = true,
    this.trailingBuilder,
  });

  final String title;
  final List<Song> songs;
  final bool showPlayButton;

  /// Optional per-row trailing widget (e.g. add-to-queue button).
  final Widget Function(BuildContext context, Song song)? trailingBuilder;

  void _playAll(BuildContext context) {
    if (songs.isEmpty) return;
    audioHandler.setQueue(songs, startIndex: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          title: title,
          icon: Icons.auto_awesome_rounded,
          actionButton: showPlayButton && songs.isNotEmpty
              ? IconButton(
            onPressed: () => _playAll(context),
            icon: const Icon(
              Icons.play_circle_fill_rounded,
              color: SpotifyColors.green,
              size: 30,
            ),
          )
              : null,
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            return SongRow(
              song: song,
              onTap: () => audioHandler.setQueue(songs, startIndex: index),
              borderRadius: songRowRadius(index, songs.length).bottomRight.x,
              trailing: trailingBuilder?.call(context, song),
            );
          },
        ),
      ],
    );
  }
}