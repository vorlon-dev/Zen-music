// ZenMusic · vorlon-dev
//
// Shared widgets for the web player.

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_api.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_player.dart';
import 'package:zenmusic/web/web_store.dart';

/// Gives every page access to the API, player and saved data.
class WebScope extends InheritedWidget {
  const WebScope({
    super.key,
    required this.api,
    required this.player,
    required this.store,
    required super.child,
  });

  final WebApi api;
  final WebPlayer player;
  final WebStore store;

  static WebScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<WebScope>();
    assert(scope != null, 'WebScope missing');
    return scope!;
  }

  @override
  bool updateShouldNotify(WebScope old) =>
      api != old.api || player != old.player || store != old.store;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class Art extends StatelessWidget {
  const Art({super.key, required this.url, required this.size, this.radius = 8});
  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: Colors.white12,
      child: Icon(Icons.music_note_rounded, size: size * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

/// Section title with optional trailing widget.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );
}

/// A list row for one song, with a menu of actions.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.extraMenu = const [],
    this.onExtra,
    this.number,
  });

  final WebSong song;
  final VoidCallback onTap;
  final int? number;

  /// Additional menu entries (label by value) handled by [onExtra].
  final List<PopupMenuEntry<String>> extraMenu;
  final void Function(String value)? onExtra;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final active = scope.player.current?.id == song.id;
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: Art(url: song.image, size: 48),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: active ? TextStyle(color: primary) : null,
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (v) => _onMenu(context, scope, v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'next', child: Text('Play next')),
          const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
          PopupMenuItem(
            value: 'fav',
            child: Text(scope.store.isFavourite(song.id)
                ? 'Remove from favourites'
                : 'Add to favourites'),
          ),
          const PopupMenuItem(
            value: 'playlist',
            child: Text('Add to playlist'),
          ),
          ...extraMenu,
        ],
      ),
      onTap: onTap,
    );
  }

  void _onMenu(BuildContext context, WebScope scope, String value) {
    switch (value) {
      case 'next':
        scope.player.playNext(song);
        toast(context, 'Playing next');
      case 'queue':
        scope.player.enqueue(song);
        toast(context, 'Added to queue');
      case 'fav':
        scope.store.toggleFavourite(song);
      case 'playlist':
        showAddToPlaylist(context, song);
      default:
        onExtra?.call(value);
    }
  }
}

/// Lets the user pick (or create) a playlist for [song].
Future<void> showAddToPlaylist(BuildContext context, WebSong song) async {
  final store = WebScope.of(context).store;
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Add to playlist'),
      children: [
        SimpleDialogOption(
          onPressed: () async {
            final created = await promptText(ctx, 'New playlist', 'Name');
            if (created != null && ctx.mounted) {
              store.createPlaylist(created);
              Navigator.pop(ctx, created.trim());
            }
          },
          child: const Row(
            children: [
              Icon(Icons.add_rounded),
              SizedBox(width: 12),
              Text('New playlist'),
            ],
          ),
        ),
        for (final n in store.playlistNames)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, n),
            child: Text(n),
          ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return;
  store.addToPlaylist(name, song);
  if (context.mounted) toast(context, 'Added to $name');
}

Future<String?> promptText(BuildContext context, String title, String hint) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Square card used in horizontal rows.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String image;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Art(url: image, size: 142, radius: 12),
              const SizedBox(height: 6),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of [MediaCard]s.
class CardRow extends StatelessWidget {
  const CardRow({super.key, required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: cards,
      ),
    );
  }
}

/// Mini player shown above the navigation.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scope = WebScope.of(context);
    final player = scope.player;
    final song = player.current;
    if (song == null) return const SizedBox.shrink();
    final total = player.duration.inMilliseconds;
    final pos = player.position.inMilliseconds.clamp(0, total > 0 ? total : 1);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: total > 0 ? pos / total : 0,
            minHeight: 2,
          ),
          ListTile(
            onTap: onOpen,
            leading: Art(url: song.image, size: 44),
            title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              player.error ?? song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Favourite',
                  icon: Icon(scope.store.isFavourite(song.id)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded),
                  onPressed: () => scope.store.toggleFavourite(song),
                ),
                IconButton(
                  tooltip: 'Previous',
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: player.previous,
                ),
                player.loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton.filled(
                        tooltip: player.playing ? 'Pause' : 'Play',
                        icon: Icon(player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                        onPressed: player.toggle,
                      ),
                IconButton(
                  tooltip: 'Next',
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: player.hasNext ? player.next : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
