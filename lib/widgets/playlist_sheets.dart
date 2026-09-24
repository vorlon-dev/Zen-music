import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../theme/spotify_theme.dart';

/// Bottom sheet: create a new user playlist. Returns the new playlist
/// id, or null if dismissed.
Future<String?> showCreatePlaylistSheet(BuildContext context,
    {String? initialName}) {
  final controller = TextEditingController(text: initialName ?? '');
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: SpotifyColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New playlist',
                style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: initialName == null || initialName.isEmpty,
                maxLength: 60,
                style: const TextStyle(
                    color: SpotifyColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Playlist name',
                  hintStyle:
                  const TextStyle(color: SpotifyColors.textTertiary),
                  filled: true,
                  fillColor: SpotifyColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (name) {
                  final trimmed = name.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.pop(sheetContext, trimmed);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: Material(
                  color: SpotifyColors.green,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      final trimmed = controller.text.trim();
                      if (trimmed.isEmpty) return;
                      Navigator.pop(sheetContext, trimmed);
                    },
                    child: const Center(
                      child: Text(
                        'Create',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Bottom sheet: add [song] to an existing playlist (or create a new
/// one inline). Shows a snackbar with the outcome.
Future<void> showAddToPlaylistSheet(
    BuildContext context, Song song) async {
  String? selectedId;
  await showModalBottomSheet(
    context: context,
    backgroundColor: SpotifyColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final playlists = storage.getUserPlaylists();
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Add to playlist',
              style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SpotifyColors.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: SpotifyColors.textPrimary),
                    ),
                    title: const Text('New playlist',
                        style: TextStyle(
                            color: SpotifyColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    onTap: () async {
                      final name =
                      await showCreatePlaylistSheet(sheetContext);
                      if (name == null) return;
                      final id = await storage.createUserPlaylist(name);
                      await storage.addUserPlaylistSongs(id, [song]);
                      selectedId = id;
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                  ),
                  for (final p in playlists)
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: SpotifyColors.surfaceLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                            FluentIcons.music_note_1_24_filled,
                            color: SpotifyColors.textSecondary),
                      ),
                      title: Text(p.name,
                          style: const TextStyle(
                              color: SpotifyColors.textPrimary)),
                      subtitle: Text('${p.count} songs',
                          style: const TextStyle(
                              color: SpotifyColors.textSecondary,
                              fontSize: 12)),
                      onTap: () async {
                        await storage.addUserPlaylistSongs(p.id, [song]);
                        selectedId = p.id;
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
  if (selectedId != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to playlist'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}