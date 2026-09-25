import 'package:flutter/material.dart';

import '../main.dart';
import '../models/collection.dart';
import '../services/home_service.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/skeleton.dart';
import '../widgets/wave_spinner.dart';
import 'collection_screen.dart';

/// New release albums — Echo Nightly NewReleaseScreen port:
/// full-screen adaptive grid of album cards, shimmer while loading,
/// long-press actions, opens the collection detail on tap.
class NewReleaseScreen extends StatefulWidget {
  const NewReleaseScreen({super.key});

  @override
  State<NewReleaseScreen> createState() => _NewReleaseScreenState();
}

class _NewReleaseScreenState extends State<NewReleaseScreen> {
  final _homeService = HomeService();

  List<Collection> _albums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _homeService.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final albums = await _homeService.getNewReleaseAlbums();
      if (!mounted) return;
      setState(() {
        _albums = albums;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _openAlbum(Collection album) {
    pushSharedAxisY(context, CollectionScreen(collection: album));
  }

  void _albumMenu(Collection album) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.album_rounded,
                  color: SpotifyColors.textPrimary),
              title: Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(album.subtitle,
                  style: const TextStyle(
                      color: SpotifyColors.textSecondary)),
            ),
            const Divider(height: 1, color: Colors.white10),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded,
                  color: SpotifyColors.textPrimary),
              title: const Text('Play',
                  style: TextStyle(color: SpotifyColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _playAlbum(album);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _playAlbum(Collection album) async {
    // Fetch the album's songs via the existing collection flow by
    // opening it — the detail screen handles loading and playback.
    pushSharedAxisY(context, CollectionScreen(collection: album));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: SpotifyColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: SpotifyColors.textPrimary),
        title: const Text('New release albums',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? _shimmerGrid()
          : _albums.isEmpty
          ? Center(
        child: Text(
          'No new releases found',
          style: TextStyle(
              color: SpotifyColors.textTertiary.withOpacity(0.8),
              fontSize: 14),
        ),
      )
          : RefreshIndicator(
        onRefresh: _load,
        color: Colors.transparent,
        backgroundColor: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Echo: adaptive columns from a ~150dp minimum.
            final columns =
            (constraints.maxWidth / 150).floor().clamp(2, 5);
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.74,
              ),
              itemCount: _albums.length,
              itemBuilder: (context, i) {
                final album = _albums[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _openAlbum(album),
                  onLongPress: () => _albumMenu(album),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius:
                                BorderRadius.circular(14),
                                child: album.imageUrl.isNotEmpty
                                    ? Image.network(
                                  album.imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __,
                                      ___) =>
                                      Container(
                                        color: SpotifyColors
                                            .surfaceLight,
                                        child: const Icon(
                                            Icons
                                                .album_rounded,
                                            size: 40,
                                            color: SpotifyColors
                                                .textTertiary),
                                      ),
                                )
                                    : Container(
                                  color: SpotifyColors
                                      .surfaceLight,
                                  child: const Icon(
                                      Icons.album_rounded,
                                      size: 40,
                                      color: SpotifyColors
                                          .textTertiary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color:
                              SpotifyColors.textPrimary)),
                      Text(album.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color:
                              SpotifyColors.textSecondary)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _shimmerGrid() {
    // Echo's ShimmerHost + GridItemPlaceHolder parity using the
    // project's own skeleton widgets.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 150).floor().clamp(2, 5);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.74,
          ),
          itemCount: 8,
          itemBuilder: (context, i) => const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SkeletonTile()),
              SizedBox(height: 7),
              SkeletonTile(),
            ],
          ),
        );
      },
    );
  }
}