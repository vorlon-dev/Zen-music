// ZenMusic · vorlon-dev
//
// Shared widgets for the web player.

import 'package:flutter/material.dart';
import 'package:zenmusic/web/web_api.dart';
import 'package:zenmusic/web/web_models.dart';
import 'package:zenmusic/web/web_player.dart';
import 'package:zenmusic/web/web_store.dart';
import 'package:zenmusic/web/web_theme.dart';

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

/// Section title with an optional small trailing text.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
              ),
            ),
            if (trailing != null)
              Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
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
      leading: Art(url: song.image, size: 56, radius: 12),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: active ? primary : null,
        ),
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

/// Large artwork card with a play button, used in horizontal rows.
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
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Art(url: image, size: 160, radius: 18),
                  const Positioned(right: 8, bottom: 8, child: PlayDot()),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
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
      height: 238,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: cards,
      ),
    );
  }
}

/// Compact tile with a small cover, a title and a play button (quick picks).
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.image,
    required this.title,
    required this.onTap,
  });

  final String image;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Art(url: image, size: 56, radius: 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: PlayDot(size: 34),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wide video-style result: 16:9 cover with a duration badge.
class VideoCard extends StatelessWidget {
  const VideoCard({
    super.key,
    required this.song,
    required this.onTap,
  });

  final WebSong song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    song.image.isEmpty
                        ? Container(color: kCard)
                        : Image.network(
                            song.image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: kCard),
                          ),
                    if (song.duration > Duration.zero)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            clock(song.duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded icon button on a dark square, as in the app's player.
class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 48,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: color ?? Colors.white10,
      borderRadius: BorderRadius.circular(size * 0.33),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: iconColor, size: size * 0.5),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Floating mini player shown above the navigation.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Material(
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        color: Colors.transparent,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [kMiniStart, kMiniEnd]),
          ),
          child: InkWell(
            onTap: onOpen,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
                  child: Row(
                    children: [
                      Art(url: song.image, size: 52, radius: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              player.error ?? song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Favourite',
                        color: Colors.white,
                        icon: Icon(scope.store.isFavourite(song.id)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded),
                        onPressed: () => scope.store.toggleFavourite(song),
                      ),
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white38, width: 2),
                        ),
                        child: player.loading
                            ? const Padding(
                                padding: EdgeInsets.all(13),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : IconButton(
                                tooltip: player.playing ? 'Pause' : 'Play',
                                padding: EdgeInsets.zero,
                                color: Colors.white,
                                icon: Icon(player.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded),
                                onPressed: player.toggle,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        color: Colors.white,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: player.hasNext ? player.next : null,
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: total > 0 ? pos / total : 0,
                  minHeight: 3,
                  color: kAccent,
                  backgroundColor: Colors.white12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
