import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/ytm_artist_service.dart';
import '../theme/spotify_theme.dart';
import '../widgets/artist_hero_header.dart';
import '../widgets/wave_spinner.dart';
import '../widgets/youtube_thumbnail.dart';
import 'player_screen.dart';

/// Artist / channel page (Echo-style hero): full-bleed artwork, stat
/// pills, About section, connected Play/Shuffle group, ranked songs —
/// or, when opened from a YouTube song, THAT song's real channel with
/// its uploads. Resolution is exact (origin video id → oEmbed
/// author_url → UC id); the fuzzy name search is only a fallback.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.artistName,
    this.videoId,
  });

  final String artistName;

  /// When provided, the page shows the EXACT channel that owns this
  /// video (resolved via oEmbed) instead of fuzzy-searching the name.
  /// When null (typical: opened from the player), the current song is
  /// used as the video source if it is a YouTube video.
  final String? videoId;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final _ytm = YtmArtistService();

  YtmArtistPage? _page;
  String? _channelId;
  bool _resolvedFromVideo = false;
  bool _loading = true;
  bool _notFound = false;
  bool _scrolled = false;
  bool _aboutExpanded = false;

  List<Song> get _topSongs => _page?.topSongs ?? const [];

  /// The video whose owning channel should be shown, in resolution
  /// order:
  ///   1. Explicit [videoId] param (caller knew the raw video).
  ///   2. The origin video the handler preserved when the CURRENT song
  ///      was resolved from a raw YouTube video (strict source policy).
  ///   3. The current song's own id, when it is still a raw YouTube
  ///      video (explicit picks / strict off).
  ///   4. Null — the JioSaavn-native / unrelated-context case → the
  ///      fuzzy name-search fallback runs.
  String? get _impliedVideoId {
    if (widget.videoId != null) return widget.videoId;
    final current = audioHandler.currentSong;
    if (current == null) return null;
    // Only apply the current-song path when the page was opened for
    // the playing song (player passes song.artist).
    if (current.artist != widget.artistName) return null;
    // Origin preserved across strict resolution — the id of the video
    // the user actually picked, even though the queue now holds the
    // catalog version.
    final origin = audioHandler.originalVideoIdFor(current.id);
    if (origin != null) return origin;
    if (current.isFromJiosaavn) return null;
    return current.id;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      String? channelId;

      // EXACT: the channel that owns the video we came from.
      final videoId = _impliedVideoId;
      if (videoId != null) {
        channelId = await _guard(_ytm.resolveVideoChannel(videoId), null);
        _resolvedFromVideo = channelId != null;
      }

      // FALLBACK: fuzzy artist-name search (old behavior).
      channelId ??= await _fallbackArtistId();

      if (channelId == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }

      final page = await _guard(
        _ytm.getArtistPage(channelId, videosTab: _resolvedFromVideo),
        null,
      );
      if (!mounted) return;
      setState(() {
        _channelId = channelId;
        _page = page;
        _loading = false;
        _notFound = (page == null || page.topSongs.isEmpty) &&
            (page == null || page.shelves.isEmpty);
      });
    } catch (e) {
      print('ArtistScreen load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  Future<String?> _fallbackArtistId() async {
    try {
      final ids = await _ytm.searchArtistIds(widget.artistName, limit: 1);
      return ids.isEmpty ? null : ids.first;
    } catch (_) {
      return null;
    }
  }

  Future<T> _guard<T>(Future<T> future, T fallback) async {
    try {
      return await future;
    } catch (_) {
      return fallback;
    }
  }

  void _playAll({bool shuffle = false}) {
    if (_topSongs.isEmpty) return;
    final queue = List<Song>.from(_topSongs);
    if (shuffle) queue.shuffle();
    audioHandler.setQueue(queue, startIndex: 0);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  void _copyLink() {
    final id = _channelId;
    if (id == null) return;
    Clipboard.setData(
      ClipboardData(text: 'https://www.youtube.com/channel/$id'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  /// Display name: the REAL channel/artist name from the browse header
  /// when available, else the name we were opened with.
  String get _displayName {
    final n = _page?.header?.name ?? '';
    if (n.isNotEmpty) return n;
    return widget.artistName.split(',').first.trim().isNotEmpty
        ? widget.artistName
        : 'Artist';
  }

  String get _headerImage {
    final art = _page?.header?.imageUrl ?? '';
    if (art.isNotEmpty) return art;
    return _topSongs.isEmpty ? '' : _topSongs.first.thumbnail;
  }

  // Echo's transparent-app-bar rule: transparent while the first
  // (header) item is under 100px of scroll, solid afterwards.
  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final solid = n.metrics.pixels > 100;
    if (solid != _scrolled) {
      setState(() => _scrolled = solid);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: _loading
          ? const Center(child: WaveSpinner(size: 26))
          : _notFound
          ? _errorView()
          : Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // Hero header bleeds to the very top — it
                // must stay OUTSIDE SafeArea (bars are
                // hidden app-wide).
                ArtistHeroHeader(
                  imageUrl: _headerImage,
                  name: _displayName,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_page?.header != null)
                        _pills(_page!.header!),
                      if (_topSongs.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          _resolvedFromVideo
                              ? '${_topSongs.length} videos · YouTube channel'
                              : '${_topSongs.length} top songs · YouTube Music',
                          style: const TextStyle(
                            color: SpotifyColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_page?.header?.description != null)
                        _about(_page!.header!.description!),
                      const SizedBox(height: 4),
                      _actions(),
                    ],
                  ),
                ),
                _trackList(),
                for (final shelf in _page?.shelves ?? const [])
                  _albumShelf(shelf.title, shelf.albums),
              ],
            ),
          ),
          _topBarOverlay(),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            FluentIcons.person_24_regular,
            size: 44,
            color: SpotifyColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            'Artist page unavailable for "${widget.artistName}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SpotifyColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ── Echo stat pills (subscribers / monthly listeners) ──

  Widget _pills(YtmArtistHeader header) {
    final pills = <Widget>[
      if (header.subscriberCount != null)
        _pill(FluentIcons.person_24_regular, header.subscriberCount!),
      if (header.monthlyListeners != null)
        _pill(FluentIcons.options_24_regular,
            '${header.monthlyListeners} monthly listeners'),
    ];
    if (pills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: pills,
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: SpotifyColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Echo About section — collapsible at 3 lines ──

  Widget _about(String text) {
    final isLong = text.length > 160;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About',
            style: TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isLong
                ? () => setState(() => _aboutExpanded = !_aboutExpanded)
                : null,
            child: Text(
              text,
              maxLines: _aboutExpanded ? null : 3,
              overflow: _aboutExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          if (isLong)
            GestureDetector(
              onTap: () =>
                  setState(() => _aboutExpanded = !_aboutExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _aboutExpanded ? 'Less' : 'More',
                  style: const TextStyle(
                    color: SpotifyColors.green,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Floating top bar (Echo parity): translucent-circle back + link
  // buttons always; the bar background and title fade in on scroll. ──

  Widget _topBarOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: _scrolled
            ? SpotifyColors.background
            : Colors.transparent,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                _circleButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                Expanded(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _scrolled ? 1.0 : 0.0,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_channelId != null)
                  _circleButton(
                    icon: Icons.link_rounded,
                    onTap: _copyLink,
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    // Flutter's circular Material shape is CircleBorder (Compose's
    // CircleShape equivalent) — do not "fix" this back to CircleShape.
    return Material(
      color: SpotifyColors.surface.withOpacity(0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: SpotifyColors.textPrimary),
        ),
      ),
    );
  }

  // ── Echo connected button group: Play (green, leading rounded) +
  // Shuffle (surface, trailing rounded), 52dp, 2dp gap. ──

  Widget _actions() {
    final disabled = _topSongs.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color:
              disabled ? SpotifyColors.surfaceLight : SpotifyColors.green,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(26),
              ),
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(26),
                ),
                onTap: disabled ? null : () => _playAll(),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: disabled
                            ? SpotifyColors.textTertiary
                            : Colors.black,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        disabled
                            ? 'Play'
                            : (_resolvedFromVideo
                            ? 'Play videos'
                            : 'Play top songs'),
                        style: TextStyle(
                          color: disabled
                              ? SpotifyColors.textTertiary
                              : Colors.black,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Material(
              color: SpotifyColors.surface,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(26),
              ),
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(26),
                ),
                onTap: disabled ? null : () => _playAll(shuffle: true),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.shuffle_rounded,
                        size: 20,
                        color: disabled
                            ? SpotifyColors.textTertiary
                            : SpotifyColors.textPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Shuffle',
                        style: TextStyle(
                          color: disabled
                              ? SpotifyColors.textTertiary
                              : SpotifyColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trackList() {
    final currentId = audioHandler.currentSong?.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < _topSongs.length; i++)
            _ArtistTrackTile(
              index: i + 1,
              song: _topSongs[i],
              isCurrent: currentId == _topSongs[i].id,
              onTap: () => _playFrom(_topSongs, i),
            ),
        ],
      ),
    );
  }

  Future<void> _playFrom(List<Song> songs, int index) async {
    await audioHandler.setQueue(List<Song>.from(songs), startIndex: index);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlayerScreen()),
    );
  }

  // ── Albums / Singles shelf (Echo carousel) ──

  Widget _albumShelf(String title, List<YtmAlbumCard> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
          child: Text(
            title,
            style: const TextStyle(
              color: SpotifyColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final card = cards[i];
              return GestureDetector(
                onTap: () => _openAlbum(card),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: card.imageUrl.isNotEmpty
                            ? Image.network(
                          card.imageUrl,
                          width: 140,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 140,
                            height: 140,
                            color: SpotifyColors.surfaceLight,
                            child: const Icon(Icons.album_rounded,
                                size: 40,
                                color: SpotifyColors.textTertiary),
                          ),
                        )
                            : Container(
                          width: 140,
                          height: 140,
                          color: SpotifyColors.surfaceLight,
                          child: const Icon(Icons.album_rounded,
                              size: 40,
                              color: SpotifyColors.textTertiary),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        card.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpotifyColors.textSecondary,
                          fontSize: 11,
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

  void _openAlbum(YtmAlbumCard card) {
    pushAlbumView(context, card);
  }
}

/// Public so the album view can be opened from anywhere on this page.
void pushAlbumView(BuildContext context, YtmAlbumCard card) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => _AlbumScreen(card: card)),
  );
}

// ═════════════════════════════════════════════
// ALBUM VIEW — lightweight track list for a YT Music album
// (MPREb_ browse id). Independent of the JioSaavn Collection flow.
// ═════════════════════════════════════════════

class _AlbumScreen extends StatefulWidget {
  const _AlbumScreen({required this.card});

  final YtmAlbumCard card;

  @override
  State<_AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<_AlbumScreen> {
  final _ytm = YtmArtistService();

  List<Song> _tracks = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tracks = await _ytm.getAlbumTracks(widget.card.browseId);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
        _failed = tracks.isEmpty;
      });
    } catch (e) {
      print('AlbumScreen load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      body: _loading
          ? const Center(child: WaveSpinner(size: 26))
          : _failed
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.album_rounded,
              size: 44,
              color: SpotifyColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Album unavailable',
              style: TextStyle(
                color: SpotifyColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      )
          : ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SafeArea(
            bottom: false,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Material(
                  color: SpotifyColors.surface.withOpacity(0.6),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(context),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(Icons.arrow_back_rounded,
                          size: 22,
                          color: SpotifyColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: widget.card.imageUrl.isNotEmpty
                    ? Image.network(
                  widget.card.imageUrl,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 200,
                    color: SpotifyColors.surfaceLight,
                    child: const Icon(Icons.album_rounded,
                        size: 56,
                        color: SpotifyColors.textTertiary),
                  ),
                )
                    : Container(
                  width: 200,
                  height: 200,
                  color: SpotifyColors.surfaceLight,
                  child: const Icon(Icons.album_rounded,
                      size: 56,
                      color: SpotifyColors.textTertiary),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SpotifyColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                if (widget.card.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.card.subtitle,
                    style: const TextStyle(
                      color: SpotifyColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (_tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Material(
                      color: SpotifyColors.green,
                      borderRadius: BorderRadius.circular(24),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () async {
                          await audioHandler.setQueue(
                              List<Song>.from(_tracks),
                              startIndex: 0);
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                const PlayerScreen()),
                          );
                        },
                        child: Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Colors.black, size: 24),
                              SizedBox(width: 6),
                              Text(
                                'Play album',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No tracks found for this album',
                  style: TextStyle(
                    color: SpotifyColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  for (var i = 0; i < _tracks.length; i++)
                    _ArtistTrackTile(
                      index: i + 1,
                      song: _tracks[i],
                      isCurrent: audioHandler.currentSong?.id ==
                          _tracks[i].id,
                      onTap: () async {
                        await audioHandler.setQueue(
                            List<Song>.from(_tracks),
                            startIndex: i);
                        if (!context.mounted) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PlayerScreen()),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtistTrackTile extends StatelessWidget {
  final int index;
  final Song song;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ArtistTrackTile({
    required this.index,
    required this.song,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: SpotifyColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
            Stack(
              children: [
                YoutubeThumbnail(
                  videoId: song.id,
                  imageUrl: song.thumbnail,
                  width: 48,
                  height: 48,
                  borderRadius: 6,
                ),
                if (isCurrent)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded,
                          size: 20, color: SpotifyColors.green),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? SpotifyColors.green
                          : SpotifyColors.textPrimary,
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
            if (song.duration.inSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _fmt(song.duration),
                  style: const TextStyle(
                    color: SpotifyColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: SpotifyColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}