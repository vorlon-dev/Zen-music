import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

/// All liked songs — tap to play the whole liked list as a queue.
class LikedSongsScreen extends StatefulWidget {
  const LikedSongsScreen({super.key});

  @override
  State<LikedSongsScreen> createState() => _LikedSongsScreenState();
}

class _LikedSongsScreenState extends State<LikedSongsScreen> {
  List<Song> _songs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _songs = storage.getLikedSongs());
  }

  Future<void> _play(int index) async {
    if (_songs.isEmpty) return;
    await audioHandler.setQueue(List<Song>.from(_songs), startIndex: index);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  BackButton(color: SpotifyColors.textPrimary),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          SpotifyColors.green,
                          SpotifyColors.green.withOpacity(0.55),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(FluentIcons.heart_24_filled,
                        color: Colors.black, size: 34),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Liked songs',
                          style: TextStyle(
                            color: SpotifyColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_songs.length} songs',
                          style: const TextStyle(
                            color: SpotifyColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_songs.isNotEmpty)
                    Material(
                      color: SpotifyColors.green,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _play(0),
                        child: const SizedBox(
                          height: 48,
                          width: 48,
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.black, size: 28),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _songs.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      FluentIcons.heart_24_regular,
                      size: 48,
                      color:
                      SpotifyColors.textTertiary.withOpacity(0.6),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Songs you like will appear here',
                      style: TextStyle(
                        color: SpotifyColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the heart in the player',
                      style: TextStyle(
                        color: SpotifyColors.textTertiary
                            .withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: _songs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, i) {
                  final song = _songs[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _play(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          YoutubeThumbnail(
                            videoId: song.id,
                            imageUrl: song.thumbnail,
                            width: 48,
                            height: 48,
                            borderRadius: 6,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: SpotifyColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: SpotifyColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            splashRadius: 20,
                            tooltip: 'Unlike',
                            icon: const Icon(
                              FluentIcons.heart_24_filled,
                              color: SpotifyColors.green,
                              size: 20,
                            ),
                            onPressed: () async {
                              await storage.setLiked(song, false);
                              _load();
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}