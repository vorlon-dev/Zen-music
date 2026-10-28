// ZenMusic — SP-36 + SP-37 + SP-38 + SP-39: the Spotify section on the
// Home screen.
//
// SP-39a (compile hotfix, field log): (1) `_filterTabs` moved into
// `_TopBar` — the pills' labels were referenced there but declared in
// _SpotifyContentState (private cross-class access = compile error);
// (2) `_TopBar` now receives `state.userName ?? ''` — the cubit's
// userName is String? while the top bar wants a plain String.
//
// SP-39b (layout hotfix, field log): the fixed-height card shelves
// overflowed at >100% Windows text scaling. _RecentCard's column is
// 164 art + 6 gap + two text lines — ~205px at the user's 125% scale
// inside a 200px item box (the exact "overflowed by 5.0 pixels").
// Shelf heights bumped to cover up to 150% scaling: recents 216→232,
// home square 226→236, hot tracks 195→204, playlists 196→208.
// No visual change at 100% — the cards are top-aligned, so the extra
// height only widens the empty strip under the captions.
//
// SP-39c (color hotfix, user directive): NO Spotify green anywhere.
// Every accent — filter pills, play chips, avatars, icons — now
// follows the APP's own theme via ColorScheme.primary / onPrimary
// (white-on-black in the app's dark mode, black-on-white in light).
// The kSpotifyGreen constant is deleted; the section recolors itself
// with the app and any future theme change, zero hardcoded brand.
//
// SP-39 (Stopify port — the current look): the section now mirrors
// Stopify's Android home screen (com.shashwat.stopify.ui.screens
// .SimpHomeScreen), which the user provided as the target layout:
//   * Top bar — profile avatar (36px circle, tap → /saved/
//     spotify_library) + filter pills (All / Music / Podcasts, REAL
//     filtering) + a refresh icon (re-fetches the feed).
//   * "Jump back in" quick grid — the first 6 recently-played tracks
//     as 2-column quick-play rows (tap = that track, queue = recents).
//   * "Recently played" horizontal shelf (when > 2 recents).
//   * THE REAL SPOTIFY HOME SHELVES — data.home via the Pathfinder
//     `home` persisted query (ported 1:1 from Stopify's
//     SpotifyWebClient.fetchHomeSections): section titles + square
//     cards for tracks/albums/playlists/promos, circle cards for
//     artist shelves. Track tap = plays the section; playlist/album
//     tap = /saved/spotify_playlist (albums branch to getAlbum).
//
// Graceful degradation (the SP-36/37/38 layout is kept as the
// fallback): if the `home` query returns nothing (hash rotation,
// pathfinder hiccup), the section falls back to the previous
// account + trending layout, so a dead endpoint can never blank the
// section. The oEmbed editorial shelf and the Top-50 charts (SP-38)
// render inside that fallback.
//
// Login state: SpotifyAuth.instance.loggedIn (ValueListenable<bool>) is
// the ONLY gate. main.dart restores the session with unawaited(load())
// at boot, so the section can appear a moment AFTER Home renders — the
// ValueListenableBuilder handles that live, no restart needed.
//
// Doctrine: a dead Spotify session must never break the YouTube home
// feed. Failures collapse to a one-line retry row; nothing here throws.
//
// Reload: HomePage's pull-to-refresh reaches SpotifyHomeSectionState
// .reload() through a GlobalKey — the cubit re-fetches only when logged
// in, and the whole feed (home + recents + trending) re-fetches through
// the _reloadTick notifier.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/screens/library/spotify/cubit/spotify_library_cubit.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_home_feed.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';

class SpotifyHomeSection extends StatefulWidget {
  const SpotifyHomeSection({super.key});

  @override
  SpotifyHomeSectionState createState() => SpotifyHomeSectionState();
}

/// State is PUBLIC so HomePage's pull-to-refresh can trigger a re-fetch
/// through a GlobalKey<SpotifyHomeSectionState>.
class SpotifyHomeSectionState extends State<SpotifyHomeSection> {
  SpotifyLibraryCubit? _cubit;

  // SP-37: bumped by reload(); the whole feed inside _SpotifyContent
  // listens and re-fetches alongside the account cubit.
  final ValueNotifier<int> _reloadTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _cubit = SpotifyLibraryCubit();
    // Boot path: the session may already be restored when Home mounts
    // (Hive-backed load() started in main.dart) — fetch right away.
    // Mid-session logins are caught by the listener below.
    if (SpotifyAuth.instance.loggedIn.value) {
      _cubit!.load();
    }
    SpotifyAuth.instance.loggedIn.addListener(_onLoginChanged);
  }

  @override
  void dispose() {
    SpotifyAuth.instance.loggedIn.removeListener(_onLoginChanged);
    _reloadTick.dispose();
    _cubit?.close();
    super.dispose();
  }

  void _onLoginChanged() {
    if (!mounted) return;
    if (SpotifyAuth.instance.loggedIn.value) {
      _cubit?.load();
    }
  }

  /// Pull-to-refresh hook (HomePage). No-op while logged out — the cubit
  /// would only re-emit its not-logged-in error.
  void reload() {
    if (SpotifyAuth.instance.loggedIn.value) {
      _cubit?.load();
      _reloadTick.value++; // re-fetch home + recents + trending too.
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SpotifyLibraryCubit>.value(
      value: _cubit!,
      child: ValueListenableBuilder<bool>(
        valueListenable: SpotifyAuth.instance.loggedIn,
        builder: (BuildContext context, bool loggedIn, Widget? _) {
          if (!loggedIn) return const _ConnectBanner();
          return _SpotifyContent(tick: _reloadTick);
        },
      ),
    );
  }
}

// ── logged out ────────────────────────────────────────────────────────

class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: AdaptiveInkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/spotify-login'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(Icons.library_music,
                    size: 18,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connect your Spotify account',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                        'Your Spotify home — recents, shelves and charts '
                            '— will show up here.',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Text('Connect',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary)),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right,
                  size: 20, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── logged in ─────────────────────────────────────────────────────────

class _SpotifyContent extends StatefulWidget {
  const _SpotifyContent({required this.tick});
  final ValueNotifier<int> tick;

  @override
  State<_SpotifyContent> createState() => _SpotifyContentState();
}

class _SpotifyContentState extends State<_SpotifyContent> {
  SpotifyHomeSnapshot? _feed; // trending + home + recents snapshot
  bool _feedLoading = true;

  // SP-39: All / Music / Podcasts — real filtering over data.home.
  // (The tab labels live in _TopBar — the only widget that renders
  // them; see SP-39a.)
  int _filterIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchFeed();
    widget.tick.addListener(_onTick);
  }

  @override
  void didUpdateWidget(_SpotifyContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tick != widget.tick) {
      oldWidget.tick.removeListener(_onTick);
      widget.tick.addListener(_onTick);
    }
  }

  @override
  void dispose() {
    widget.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) _fetchFeed();
  }

  Future<void> _fetchFeed() async {
    setState(() => _feedLoading = true);
    final snapshot = await SpotifyHomeFeed.instance.snapshot();
    if (!mounted) return;
    setState(() {
      _feed = snapshot;
      _feedLoading = false;
    });
  }

  /// A section whose items are ALL podcast/episode kind.
  bool _isPodcastSection(Map<String, dynamic> section) {
    final items = (section['items'] as List?) ?? const [];
    if (items.isEmpty) return false;
    for (final it in items) {
      final k = ((it as Map?)?['kind'])?.toString() ?? '';
      if (k != 'podcast' && k != 'episode') return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SpotifyLibraryCubit, SpotifyLibraryState>(
      builder: (BuildContext context, SpotifyLibraryState state) {
        if (state is SpotifyLibraryLoading) {
          return const _SlimRow(
            label: 'Spotify…',
            leading: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        if (state is SpotifyLibraryError) {
          return _SlimRow(
            label: 'Spotify could not be loaded',
            leading: Icon(Icons.cloud_off,
                size: 14, color: Theme.of(context).hintColor),
            trailing: IconButton(
              tooltip: 'Retry',
              iconSize: 18,
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  context.read<SpotifyLibraryCubit>().load(),
            ),
          );
        }
        if (state is SpotifyLibraryLoaded) {
          final f = _feed;

          List<Map<String, dynamic>> visible = const [];
          if (f != null && f.homeSections.isNotEmpty) {
            final all = f.homeSections;
            visible = _filterIndex == 1
                ? all.where((s) => !_isPodcastSection(s)).toList()
                : _filterIndex == 2
                ? all.where(_isPodcastSection).toList()
                : all;
          }

          final bool contentEmpty = state.likedSongs.isEmpty &&
              state.playlists.isEmpty &&
              !_feedLoading &&
              (f == null ||
                  (f.charts.isEmpty &&
                      f.featured.isEmpty &&
                      f.homeSections.isEmpty &&
                      f.recent.isEmpty));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SP-39: Stopify top bar — avatar + filter pills + refresh.
              // (?? '' — SpotifyLibraryLoaded.userName is String?, the
              // bar wants a plain String; SP-39a fix.)
              _TopBar(
                userName: state.userName ?? '',
                avatarUrl: f?.account?['avatar']?.toString() ?? '',
                filterIndex: _filterIndex,
                onFilter: (int i) => setState(() => _filterIndex = i),
                onRefresh: _fetchFeed,
              ),
              if (_feedLoading && f == null)
                const _HomeShimmer()
              else if (f != null && f.homeSections.isNotEmpty) ...[
                // SP-39: Stopify home layout — quick grid, recents
                // shelf, then the REAL Spotify homepage shelves.
                if (f.recent.isNotEmpty)
                  _QuickGrid(recent: f.recent),
                if (f.recent.length > 2)
                  _RecentShelf(
                    recent: f.recent,
                    onPlay: (int i) => GetIt.I<MediaPlayer>()
                        .playFromSection(f.recent, i),
                  ),
                for (final section in visible)
                  _HomeShelf(
                    section: section,
                    onOpen: _openItem,
                  ),
                if (visible.isEmpty && _filterIndex == 2)
                  const _SlimRow(
                      label:
                      'No podcasts in your Spotify home right now.'),
              ] else ...[
                // FALLBACK (SP-36/37/38 layout): the `home` query came
                // back empty — account header + trending + library.
                _Header(userName: state.userName, details: f?.account),
                _TrendingSection(feed: f, loading: _feedLoading),
                if (state.likedSongs.isNotEmpty)
                  _LikedSongsCard(songs: state.likedSongs),
                if (state.playlists.isNotEmpty)
                  _PlaylistShelf(playlists: state.playlists,
                      title: 'Your playlists'),
              ],
              if (contentEmpty)
                const _SlimRow(
                    label: 'No Spotify content yet — pull down to refresh.'),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// SP-39: item tap semantics (Stopify's onMediaItemClick, mapped to
  /// ZenMusic's existing destinations):
  ///   track    → whole section's playable tracks in the queue,
  ///              starting at this one (playFromSection).
  ///   playlist → /saved/spotify_playlist (Pathfinder fetchPlaylist).
  ///   album    → same route; the page branches to getAlbum.
  ///   artist / podcast / episode → no destination page yet (card is
  ///              visual only — the artist/podcast screens are a
  ///              follow-up arc).
  void _openItem(List<Map<String, dynamic>> items, int index) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    final kind = item['kind']?.toString() ?? '';
    final uri = item['uri']?.toString() ?? '';
    if (kind == 'track') {
      final tracks = <Map<String, dynamic>>[
        for (final m in items)
          if (m['kind'] == 'track' && m['track'] is Map<String, dynamic>)
            m['track'] as Map<String, dynamic>,
      ];
      final playIndex = tracks.indexOf(item['track']);
      if (tracks.isNotEmpty && playIndex >= 0) {
        GetIt.I<MediaPlayer>().playFromSection(tracks, playIndex);
      }
    } else if (kind == 'playlist' || kind == 'album') {
      if (uri.isEmpty) return;
      context.push('/saved/spotify_playlist', extra: {
        'playlistId': uri,
        'title': item['title']?.toString() ?? '',
      });
    }
  }
}

// ── SP-39: Stopify top bar (avatar + pills + refresh) ─────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.userName,
    required this.avatarUrl,
    required this.filterIndex,
    required this.onFilter,
    required this.onRefresh,
  });

  final String userName;
  final String avatarUrl;
  final int filterIndex;
  final void Function(int) onFilter;
  final VoidCallback onRefresh;

  // All / Music / Podcasts — declared HERE (not in _SpotifyContentState)
  // because this is the class that renders the pills (SP-39a fix).
  static const List<String> _filterTabs = ['All', 'Music', 'Podcasts'];

  @override
  Widget build(BuildContext context) {
    final String initial =
    (userName.isNotEmpty ? userName[0] : 'S').toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          AdaptiveInkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/saved/spotify_library'),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context).colorScheme.primary,
              backgroundImage: avatarUrl.isEmpty
                  ? null
                  : CachedNetworkImageProvider(avatarUrl),
              child: avatarUrl.isEmpty
                  ? Text(initial,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color:
                      Theme.of(context).colorScheme.onPrimary))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _filterTabs.length; i++) ...[
                    _Pill(
                      label: _filterTabs[i],
                      selected: filterIndex == i,
                      onTap: () => onFilter(i),
                    ),
                    if (i < _filterTabs.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh Spotify home',
            onPressed: onRefresh,
            iconSize: 18,
            icon: Icon(Icons.refresh,
                color: Theme.of(context).hintColor),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ── SP-39: "Jump back in" quick grid (6 recents, 2 columns) ───────────

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.recent});
  final List<Map<String, dynamic>> recent;

  @override
  Widget build(BuildContext context) {
    final int n = recent.length < 6 ? recent.length : 6;
    final List<Widget> rows = [];
    for (var i = 0; i < n; i += 2) {
      rows.add(Row(
        children: [
          Expanded(
            child: _QuickPlayCard(
              track: recent[i],
              onTap: () =>
                  GetIt.I<MediaPlayer>().playFromSection(recent, i),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: (i + 1 < n)
                ? _QuickPlayCard(
              track: recent[i + 1],
              onTap: () => GetIt.I<MediaPlayer>()
                  .playFromSection(recent, i + 1),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Column(
        children: [
          for (final row in rows) ...[row, const SizedBox(height: 8)],
        ],
      ),
    );
  }
}

class _QuickPlayCard extends StatelessWidget {
  const _QuickPlayCard({required this.track, required this.onTap});
  final Map<String, dynamic> track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String thumb =
    (track['thumbnails'] as List?)?.isNotEmpty == true
        ? (track['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              child: thumb.isEmpty
                  ? Container(
                  width: 52,
                  height: 52,
                  color: Colors.grey.withValues(alpha: 0.14),
                  child: Icon(Icons.album,
                      size: 24,
                      color: Theme.of(context).colorScheme.primary))
                  : CachedNetworkImage(
                  imageUrl: thumb,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(track['title']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.play_arrow,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── SP-39: "Recently played" shelf ────────────────────────────────────

class _RecentShelf extends StatelessWidget {
  const _RecentShelf({required this.recent, required this.onPlay});
  final List<Map<String, dynamic>> recent;
  final void Function(int) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recently played',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text('${recent.length} tracks',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor)),
            ],
          ),
        ),
        // 232, not 216 (SP-39b): the card column is 164 art + 6 gap +
        // two text lines — ~205px at 125% Windows text scaling, which
        // overflowed the old 200px item box by exactly 5.0px. 232 -
        // 16 list padding = 216 per item: safe up to 150% scaling.
        SizedBox(
          height: 232,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) =>
                _RecentCard(
                  track: recent[index],
                  onTap: () => onPlay(index),
                ),
          ),
        ),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.track, required this.onTap});
  final Map<String, dynamic> track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String thumb =
    (track['thumbnails'] as List?)?.isNotEmpty == true
        ? (track['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 164,
              height: 164,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.25)),
              ),
              child: thumb.isEmpty
                  ? Icon(Icons.album,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary)
                  : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        width: 164,
                        height: 164),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color:
                        Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(track['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            Text(track['artist'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

// ── SP-39: the REAL Spotify home shelves ──────────────────────────────

class _HomeShelf extends StatelessWidget {
  const _HomeShelf({required this.section, required this.onOpen});
  final Map<String, dynamic> section;
  final void Function(List<Map<String, dynamic>>, int) onOpen;

  bool get _isArtistShelf {
    final String title = (section['title'] ?? '').toString().toLowerCase();
    if (title.contains('artist')) return true;
    final items = (section['items'] as List?) ?? const [];
    if (items.isEmpty) return false;
    for (final it in items) {
      if (((it as Map?)?['kind'])?.toString() != 'artist') return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final items =
        (section['items'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text((section['title'] ?? '').toString(),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        // 236, not 226 (SP-39b): same scaling headroom as
        // _RecentShelf — the square-card stack is ~209px at 125%,
        // which left only 1.4px under the old 210px item box.
        SizedBox(
          height: _isArtistShelf ? 195 : 236,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final item = items[index];
              if (_isArtistShelf ||
                  item['kind']?.toString() == 'artist') {
                return _ArtistCircleCard(
                  item: item,
                  onTap: () => onOpen(items, index),
                );
              }
              return _SquareCard(
                item: item,
                onTap: () => onOpen(items, index),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// SimpSquareCard port: 168-wide column, 164px art, play overlay,
/// name + subtitle.
class _SquareCard extends StatelessWidget {
  const _SquareCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String thumb =
    (item['thumbnails'] as List?)?.isNotEmpty == true
        ? (item['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 164,
              height: 164,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: thumb.isEmpty
                  ? Icon(Icons.album,
                  size: 48,
                  color: Theme.of(context).hintColor)
                  : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        width: 164,
                        height: 164),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow,
                          size: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(item['title']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(item['subtitle']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

/// SimpArtistCircleCard port: 115-wide column, 105px circle, centered
/// name + "Artist" caption.
class _ArtistCircleCard extends StatelessWidget {
  const _ArtistCircleCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String thumb =
    (item['thumbnails'] as List?)?.isNotEmpty == true
        ? (item['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 115,
        child: Column(
          children: [
            Container(
              width: 105,
              height: 105,
              decoration: const BoxDecoration(
                color: Color(0x1A9E9E9E),
                shape: BoxShape.circle,
              ),
              child: thumb.isEmpty
                  ? Icon(Icons.person,
                  size: 44, color: Theme.of(context).hintColor)
                  : ClipOval(
                child: CachedNetworkImage(
                    imageUrl: thumb,
                    fit: BoxFit.cover,
                    width: 105,
                    height: 105),
              ),
            ),
            const SizedBox(height: 8),
            Text(item['title']?.toString() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Artist',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

/// First-load skeleton — 3 shimmer sections, Stopify-style.
class _HomeShimmer extends StatelessWidget {
  const _HomeShimmer();

  @override
  Widget build(BuildContext context) {
    final Color box = Colors.grey.withValues(alpha: 0.14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    width: 160,
                    height: 22,
                    decoration: BoxDecoration(
                        color: box,
                        borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 12),
                SizedBox(
                  height: 150,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 14),
                    itemBuilder: (BuildContext context, int index) =>
                        Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                                color: box,
                                borderRadius: BorderRadius.circular(12))),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── legacy fallback (SP-36/37/38 shelves — used when the `home`
//    query returns nothing) ────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({this.userName, this.details});
  final String? userName;
  final Map<String, dynamic>? details; // profile fields (pathfinder/v1)

  @override
  Widget build(BuildContext context) {
    final String avatar = (details?['avatar'] as String?) ?? '';
    // Plan · country · followers — only the pieces we actually got,
    // e.g. "Premium · IN · 1.2K followers".
    final List<String> parts = <String>[];
    final String product = (details?['product'] as String?) ?? '';
    if (product.isNotEmpty) {
      parts.add(product[0].toUpperCase() + product.substring(1));
    }
    final String country = (details?['country'] as String?) ?? '';
    if (country.isNotEmpty) parts.add(country);
    final int followers =
        (details?['followers'] as num?)?.toInt() ?? 0;
    if (followers > 0) parts.add('${_compactCount(followers)} followers');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(avatar),
            child: avatar.isEmpty
                ? Icon(Icons.library_music,
                size: 16,
                color: Theme.of(context).colorScheme.onPrimary)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your Spotify',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                if (userName != null && userName!.isNotEmpty)
                  Text(
                    parts.isEmpty
                        ? 'Signed in as $userName'
                        : 'Signed in as $userName · ${parts.join(' · ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).hintColor),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open Spotify library',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => context.push('/saved/spotify_library'),
          ),
        ],
      ),
    );
  }
}

// ── SP-37: trending on Spotify (fallback shelves) ─────────────────────

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({required this.feed, required this.loading});
  final SpotifyHomeSnapshot? feed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    // First load: a reserved slim row so the page doesn't jump once
    // the shelves arrive.
    if (loading && feed == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShelfTitle('Trending on Spotify'),
          _SlimRow(
            label: 'Loading Spotify trending…',
            leading: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }
    final f = feed;
    if (f == null) return const SizedBox.shrink();
    final primary = f.primaryChart;
    final bool hasHot = primary != null && primary.tracks.isNotEmpty;
    if (f.charts.isEmpty && f.featured.isEmpty && !hasHot) {
      // Everything failed (or the region has no charts) — render
      // nothing; the account shelves above carry the section.
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ShelfTitle('Trending on Spotify'),
        if (hasHot) _HotTracksRow(chart: primary),
        if (f.charts.isNotEmpty) _ChartsShelf(charts: f.charts),
        if (f.featured.isNotEmpty)
          _PlaylistShelf(playlists: f.featured,
              title: 'Popular on Spotify'),
      ],
    );
  }
}

class _ShelfTitle extends StatelessWidget {
  const _ShelfTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(Icons.graphic_eq,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _ShelfSubtitle extends StatelessWidget {
  const _ShelfSubtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).hintColor));
  }
}

/// The first 12 tracks of the primary regional chart, Spotify-homepage
/// style: square art + title + artist, one tap = that chart in the
/// queue starting at this track.
class _HotTracksRow extends StatelessWidget {
  const _HotTracksRow({required this.chart});
  final SpotifyChart chart;

  @override
  Widget build(BuildContext context) {
    final int count = chart.tracks.length < 12 ? chart.tracks.length : 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _ShelfSubtitle(chart.title),
        ),
        // 204, not 195 (SP-39b): 136 art + 6 + two text lines is
        // ~184px at 150% scaling — the old 179px item box had only
        // 1.9px of margin at 125%. Bumped for the same headroom.
        SizedBox(
          height: 204,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> track = chart.tracks[index];
              return _TrackCard(
                track: track,
                onTap: () {
                  // Same entry point as Liked Songs: the whole chart
                  // lands in the queue and playback starts here.
                  GetIt.I<MediaPlayer>()
                      .playFromSection(chart.tracks, index);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.onTap});
  final Map<String, dynamic> track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String thumb =
    (track['thumbnails'] as List?)?.isNotEmpty == true
        ? (track['thumbnails'].first as Map)['url']?.toString() ?? ''
        : '';
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 136,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: thumb.isEmpty
                  ? const Icon(Icons.music_note, size: 36)
                  : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                        imageUrl: thumb,
                        fit: BoxFit.cover,
                        width: 136,
                        height: 136),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color:
                        Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.play_arrow,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(track['title'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(track['artist'] ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

/// Top 50 cards — the playlist's branded art with a dark scrim and
/// the chart name over it. One tap = the whole chart in the queue.
class _ChartsShelf extends StatelessWidget {
  const _ChartsShelf({required this.charts});
  final List<SpotifyChart> charts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _ShelfSubtitle('Spotify Charts'),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: charts.length,
            separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) =>
                _ChartCard(chart: charts[index]),
          ),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart});
  final SpotifyChart chart;

  @override
  Widget build(BuildContext context) {
    return AdaptiveInkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        GetIt.I<MediaPlayer>().playFromSection(chart.tracks, 0);
      },
      child: Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: chart.coverUrl.isEmpty
            ? const Icon(Icons.leaderboard, size: 40)
            : Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                  imageUrl: chart.coverUrl,
                  fit: BoxFit.cover,
                  width: 168,
                  height: 168),
            ),
            // Dark scrim so the white text reads on any art.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chart.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  if (chart.topLine.isNotEmpty)
                    Text('#1 ${chart.topLine}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white
                                .withValues(alpha: 0.8))),
                ],
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.play_arrow,
                    size: 20,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikedSongsCard extends StatelessWidget {
  const _LikedSongsCard({required this.songs});
  final List<Map<String, dynamic>> songs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: AdaptiveInkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Same entry point as the Saved page card: the whole section
          // lands in the queue drawer and the engine takes over.
          GetIt.I<MediaPlayer>().playFromSection(songs, 0);
        },
        child: Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFF43278C), Color(0xFF1E1B4B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.favorite, size: 28, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Liked Songs',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    Text('${songs.length} songs',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                            Colors.white.withValues(alpha: 0.75))),
                  ],
                ),
              ),
              const Icon(Icons.play_arrow, size: 28, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistShelf extends StatelessWidget {
  const _PlaylistShelf({required this.playlists, this.title});
  final List<Map<String, dynamic>> playlists;
  final String? title; // optional shelf label

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _ShelfSubtitle(title!),
          ),
        // 208, not 196 (SP-39b): 136 art + 6 + title + "Playlist"
        // caption is ~186px at 150% scaling — bumped for the same
        // headroom as the other shelves.
        SizedBox(
          height: 208,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> p = playlists[index];
              final String thumb =
              (p['thumbnails'] as List?)?.isNotEmpty == true
                  ? (p['thumbnails'].first as Map)['url']?.toString() ?? ''
                  : '';
              return AdaptiveInkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  // p['id'] is the full URI (spotify:playlist:…) — consumed
                  // as-is by SpotifyPlaylistPage.fetchPlaylistTracks.
                  context.push('/saved/spotify_playlist', extra: {
                    'playlistId': p['id'],
                    'title': p['title'],
                  });
                },
                child: SizedBox(
                  width: 136,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 136,
                        height: 136,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: thumb.isEmpty
                            ? const Icon(Icons.queue_music, size: 36)
                            : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                              imageUrl: thumb, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(p['title'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Playlist',
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).hintColor)),
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

// ── shared slim row ───────────────────────────────────────────────────

class _SlimRow extends StatelessWidget {
  const _SlimRow({required this.label, this.leading, this.trailing});
  final String label;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: Theme.of(context).hintColor)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 1123 → "1.1K", 2400000 → "2.4M" — follower count in one glance.
String _compactCount(int n) {
  String trim(String v) => v.endsWith('.0') ? v.substring(0, v.length - 2) : v;
  if (n >= 1000000) return '${trim((n / 1000000).toStringAsFixed(1))}M';
  if (n >= 1000) return '${trim((n / 1000).toStringAsFixed(1))}K';
  return '$n';
}