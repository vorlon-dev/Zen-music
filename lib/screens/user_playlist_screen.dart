import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';
import '../widgets/song_row.dart';
import 'player_screen.dart';

class UserPlaylistScreen extends StatefulWidget {
  const UserPlaylistScreen({super.key, required this.id, required this.name});

  final String id;
  final String name;

  @override
  State<UserPlaylistScreen> createState() => _UserPlaylistScreenState();
}

class _UserPlaylistScreenState extends State<UserPlaylistScreen> {
  List<Song> _songs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _songs = storage.getUserPlaylistSongs(widget.id));
  }

  void _openPlayer(int index) {
    audioHandler.setQueue(_songs, startIndex: index);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.name,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: SpotifyColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: SpotifyColors.textSecondary),
            tooltip: 'Delete playlist',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: SpotifyColors.surface,
                  title: const Text('Delete playlist',
                      style: TextStyle(color: SpotifyColors.textPrimary)),
                  content: Text('Delete "${widget.name}"?',
                      style:
                      const TextStyle(color: SpotifyColors.textSecondary)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await storage.deleteUserPlaylist(widget.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: _songs.isEmpty
          ? const Center(
          child: Text('No songs matched in this playlist',
              style: TextStyle(color: SpotifyColors.textSecondary)))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Text('${_songs.length} songs',
                    style: const TextStyle(
                        fontSize: 13,
                        color: SpotifyColors.textSecondary)),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: SpotifyColors.green,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: _songs.isEmpty ? null : () => _openPlayer(0),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Play',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _songs.length,
              itemBuilder: (context, i) => SongRow(
                song: _songs[i],
                onTap: () => _openPlayer(i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}