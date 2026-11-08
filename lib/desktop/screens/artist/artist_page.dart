// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:async';

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/services/media_player.dart'
    show MediaPlayer, ButtonState;
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/progress_ring.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';


class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.name, this.browseId});

  /// Artist display name — also the canvas/search fallback key.
  final String name;

  /// YTM channel browseId (UC…), optional: resolved by search when absent.
  final String? browseId;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  static const int _initialSongLimit = 10;

  bool _loading = true;
  String? _error;

  String _name = '';
  String? _browseId;
  String? _artworkUrl; // hero photo from the artist page header
  String? _searchArtwork; // fallback from the artist search row
  String? _subscribers; // "12.3M subscribers" style pill
  String? _radioPlaylistId; // header "start radio" playlist (RD…)

  List<Map<String, dynamic>> _topSongs = [];
  List<Map<String, dynamic>> _albums = [];
  List<Map<String, dynamic>> _singles = [];
  List<Map<String, dynamic>> _similar = [];

  bool _showAllSongs = false;
  bool _showHeroVideo = true;
  bool _fullscreenMotion = false;
  String? _canvasUrl; // hero motion video (Spotify canvas)
  bool _canvasReady = false;


  @override
  void initState() {
    super.initState();
    _name = _primaryArtist(widget.name);
    _browseId = widget.browseId;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // One timeout over the whole resolve+load, like the upstream
      // repository: a stalled lookup becomes an error with Retry instead
      // of a spinner that never ends.
      await _loadArtist().timeout(const Duration(seconds: 30));
      if (!mounted) return;

      final hollow = _topSongs.isEmpty &&
          _albums.isEmpty &&
          _singles.isEmpty &&
          _artworkUrl == null &&
          _searchArtwork == null;
      setState(() {
        _loading = false;
        if (hollow) {
          _error = 'No playable tracks found for "$_name" right now.';
        }
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Couldn\'t load "$_name". Check your connection and try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }

    // Motion video is best-effort and never blocks the photo hero.
    _loadCanvas();
  }

  Future<void> _loadArtist() async {
    final ytm = GetIt.I<YTMusic>();

    // 1. Resolve the browseId when the caller could not provide one.
    if (_browseId == null || !_browseId!.startsWith('UC')) {
      try {
        final res = await ytm.search(_name, filter: 'artists', limit: 5);
        final sections = (res['sections'] as List?) ?? const [];
        final rows = sections
            .expand((s) =>
                ((s is Map ? s['contents'] : null) as List?) ?? const [])
            .whereType<Map>()
            .toList();
        if (rows.isNotEmpty) {
          final exact = rows.firstWhere(
            (r) =>
                (r['title'] ?? '').toString().toLowerCase() ==
                _name.toLowerCase(),
            orElse: () => rows.first,
          );
          _browseId =
              (exact['endpoint'] is Map ? exact['endpoint']['browseId'] : null)
                  ?.toString();
          final t = (exact['thumbnails'] as List?) ?? const [];
          if (t.isNotEmpty) {
            _searchArtwork = _hiRes(t.last['url'].toString(), 1200);
          }
        }
      } catch (_) {
        // Search resolution is optional — the song-search fallback below
        // still builds a playable page without it.
      }
    }

    // 2. The artist page browse: header + shelves.
    String? pageName;
    if (_browseId != null && _browseId!.startsWith('UC')) {
      try {
        final data = await ytm.browse(body: {'browseId': _browseId}, limit: 2);
        final header = data['header'] as Map<String, dynamic>?;
        final sections = (data['sections'] as List?) ?? const [];

        if (header != null) {
          pageName = header['title']?.toString();
          _subscribers = header['subtitle']?.toString();
          _radioPlaylistId = header['playlistRadioId']?.toString();
          final thumbs = (header['thumbnails'] as List?) ?? const [];
          if (thumbs.isNotEmpty) {
            _artworkUrl = _hiRes(thumbs.last['url'].toString(), 1280);
          }
        }

        for (final section in sections) {
          if (section is! Map || section['contents'] is! List) continue;
          final title = (section['title'] ?? '').toString().toLowerCase();
          final items = (section['contents'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();

          if (_topSongs.isEmpty &&
              (title.contains('song') ||
                  title.contains('popular') ||
                  title.contains('top'))) {
            _topSongs = items
                .where((i) => (i['videoId'] ?? '').toString().isNotEmpty)
                .toList();
          } else if (title.contains('album')) {
            _albums = items;
          } else if (title.contains('single')) {
            _singles = items;
          } else if (title.contains('fans')) {
            _similar = items;
          }
        }
      } catch (_) {
        // A dead artist browse falls through to the search fallback below.
      }
    }

    if (pageName != null && pageName.trim().isNotEmpty) {
      _name = _primaryArtist(pageName);
    }

    // 3. Songs shelf empty → artist-filtered song search (upstream parity).
    if (_topSongs.isEmpty && _name.isNotEmpty) {
      try {
        final res = await ytm.search('$_name songs', filter: 'songs', limit: 30);
        final sections = (res['sections'] as List?) ?? const [];
        final rows = sections
            .expand((s) =>
                ((s is Map ? s['contents'] : null) as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        final existing = _topSongs
            .map((s) => (s['videoId'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toSet();
        final want = _name.toLowerCase();
        _topSongs = rows
            .where((r) => (r['videoId'] ?? '').toString().isNotEmpty)
            .where((r) => !existing.contains((r['videoId'] ?? '').toString()))
            .where((r) {
          final artist =
              (r['subtitle'] ?? r['artist'] ?? '').toString().toLowerCase();
          return artist.contains(want) || want.contains(artist) || artist.isEmpty;
        })
            .map((r) {
          if ((r['artist'] ?? '').toString().isEmpty) {
            r['artist'] = _name;
          }
          return r;
        })
            .take(30)
            .toList();
      } catch (_) {
        // Stay empty — the page still shows hero + carousels.
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadCanvas() async {
    // Same gate as the player screen: canvas is a logged-in-Spotify feature.
    if (!SpotifyAuth.instance.loggedIn.value) return;
    try {
      final url =
          await SpotifyCanvas.instance.resolveCanvasUrl(title: _name, artist: _name);
      if (!mounted || url == null || url.isEmpty) return;
      setState(() => _canvasUrl = url);
    } catch (_) {
      // Silent: the hero is a photo without it.
    }
  }


  MediaPlayer get _player => GetIt.I<MediaPlayer>();

  void _haptic() => HapticFeedback.mediumImpact();

  void _playAll({int index = 0}) {
    if (_topSongs.isEmpty) return;
    _haptic();
    _player.playAll(
      List<Map<String, dynamic>>.from(_topSongs),
      index: index.clamp(0, _topSongs.length - 1),
    );
  }

  void _shuffle() {
    if (_topSongs.isEmpty) return;
    _haptic();
    _player.playAll(List<Map<String, dynamic>>.from(_topSongs)..shuffle());
  }

  Future<void> _radio() async {
    if (_topSongs.isEmpty) return;
    _haptic();
    try {
      if (_radioPlaylistId != null && _radioPlaylistId!.isNotEmpty) {
        final songs = await GetIt.I<YTMusic>().getPlaylistSongs(_radioPlaylistId!);
        final playable = songs
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => (m['videoId'] ?? '').toString().isNotEmpty)
            .toList();
        if (playable.isNotEmpty) {
          await _player.playAll(playable);
          return;
        }
      }
    } catch (_) {/* fall through to the local mix */}
    _player.playAll(List<Map<String, dynamic>>.from(_topSongs)..shuffle());
  }

  void _openAlbum(Map item) {
    final endpoint = item['endpoint'];
    if (endpoint is Map && (endpoint['browseId'] ?? '').toString().isNotEmpty) {
      _haptic();
      context.push('/browse', extra: {
        'endpoint': Map<String, dynamic>.from(endpoint),
      });
    }
  }

  void _openArtist(Map item) {
    _haptic();
    final endpoint = item['endpoint'];
    final id = endpoint is Map ? (endpoint['browseId'] ?? '').toString() : '';
    context.push('/artist', extra: {
      'name': (item['title'] ?? '').toString(),
      if (id.startsWith('UC')) 'browseId': id,
    });
  }


  bool get _isArtistPlaying {
    final song = _player.currentSongNotifier.value;
    if (song == null || _player.buttonState.value != ButtonState.playing) {
      return false;
    }
    final playingArtist = (song.artist ?? '').toLowerCase();
    final want = _name.toLowerCase();
    return playingArtist.contains(want) || want.contains(playingArtist);
  }

  bool _isTrackPlaying(Map track) {
    final song = _player.currentSongNotifier.value;
    if (song == null || _player.buttonState.value != ButtonState.playing) {
      return false;
    }
    final title = (track['title'] ?? '').toString().toLowerCase();
    return song.title.toLowerCase() == title;
  }

  bool get _hasHeroVideo =>
      _canvasUrl != null && _canvasUrl!.isNotEmpty && _showHeroVideo;


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: _loading
          ? const Center(child: AdaptiveProgressRing())
          : _error != null
              ? _buildError(cs)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildContent(cs),
                    // Fullscreen "Artist Motion" overlay (hero video tap).
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      child: _fullscreenMotion
                          ? _buildFullscreenMotion(cs)
                          : const SizedBox.shrink(key: ValueKey('no-motion')),
                    ),
                  ],
                ),
    );
  }

  Widget _buildError(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error, fontSize: 15),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                _browseId = widget.browseId;
                _load();
              },
              child: Text('Retry'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme cs) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(cs)),
        SliverToBoxAdapter(child: _buildActionBar(cs)),
        if (_topSongs.isNotEmpty) ..._buildTopSongsSection(cs),
        if (_albums.isNotEmpty)
          _buildCarouselSection(cs, 'Albums', _albums, height: 208),
        if (_singles.isNotEmpty)
          _buildCarouselSection(cs, 'Singles & EPs', _singles, height: 208),
        if (_similar.isNotEmpty) _buildSimilarSection(cs),
        SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPad)),
      ],
    );
  }


  Widget _buildHero(ColorScheme cs) {
    final artworkCandidates = [_artworkUrl, _searchArtwork]
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .toList();

    return RepaintBoundary(
      child: SizedBox(
        height: 460,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo with the upstream fallback chain (artwork → search row).
            if (artworkCandidates.isNotEmpty)
              Positioned.fill(
                child: _HeroArtwork(
                  candidates: artworkCandidates,
                  placeholder: _heroPlaceholder(cs),
                ),
              )
            else
              _heroPlaceholder(cs),

            // Motion video on top of the photo (Spotify canvas, login-gated).
            if (_hasHeroVideo)
              Positioned.fill(
                child: VideoBackdrop(
                  key: ValueKey('artist-canvas-$_name'),
                  streamUrl: _canvasUrl!,
                  playing: true,
                  shortLoop: true,
                  onReadyChanged: (ready) {
                    if (mounted && ready != _canvasReady) {
                      setState(() => _canvasReady = ready);
                    }
                  },
                  onUnavailable: (_) {
                    if (mounted) setState(() => _canvasUrl = null);
                  },
                ),
              ),

            // Seamless gradient: status-bar scrim → clear → deep fade into
            // the page background (exact upstream stop positions).
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.25, 0.55, 0.82, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.50),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.78),
                      cs.surface,
                    ],
                  ),
                ),
              ),
            ),

            // Top chrome: back (left) + video/photo toggle & expand (right).
            SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 10),
                    child: _HeroCircleButton(
                      tooltip: 'Back'.tr,
                      onTap: () => context.pop(),
                      child: const Icon(FluentIcons.chevron_left_24_regular,
                          size: 22, color: Colors.white),
                    ),
                  ),
                  if (_canvasUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 16, top: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_hasHeroVideo)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _HeroCircleButton(
                                tooltip: 'Expand fullscreen'.tr,
                                onTap: () {
                                  _haptic();
                                  setState(() => _fullscreenMotion = true);
                                },
                                child: const Icon(
                                    FluentIcons.full_screen_maximize_24_regular,
                                    size: 18,
                                    color: Colors.white),
                              ),
                            ),
                          _HeroCircleButton(
                            tooltip: _showHeroVideo
                                ? 'Show photo'
                                : 'Show motion video',
                            onTap: () {
                              _haptic();
                              setState(() => _showHeroVideo = !_showHeroVideo);
                            },
                            child: Icon(
                              _showHeroVideo
                                  ? FluentIcons.video_24_regular
                                  : FluentIcons.image_24_regular,
                              size: 18,
                              color: _showHeroVideo
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // "This artist is playing" wave pill.
            if (_isArtistPlaying)
              Positioned(
                right: 20,
                bottom: 24,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const _PlayingWaveBars(),
                ),
              ),

            // Title + verified + subscriber pill (bottom start).
            Positioned(
              left: 20,
              right: _isArtistPlaying ? 84 : 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 33,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.verified,
                          size: 24, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                  if (_subscribers != null && _subscribers!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        _subscribers!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.person, size: 112, color: cs.primary),
    );
  }


  Widget _buildActionBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          _TonalCircle(
            tooltip: 'Shuffle'.tr,
            icon: FluentIcons.arrow_shuffle_24_regular,
            onTap: _topSongs.isEmpty ? null : _shuffle,
          ),
          const SizedBox(width: 12),
          _TonalCircle(
            tooltip: 'Radio'.tr,
            icon: FluentIcons.sound_wave_circle_24_regular,
            onTap: _topSongs.isEmpty ? null : () => _radio(),
          ),
          const Spacer(),
          // Large primary play button (56dp circle upstream).
          GestureDetector(
            onTap: _topSongs.isEmpty ? null : () => _playAll(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _topSongs.isEmpty
                    ? cs.primary.withValues(alpha: 0.4)
                    : cs.primary,
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                _isArtistPlaying
                    ? FluentIcons.pause_24_filled
                    : FluentIcons.play_24_filled,
                size: 28,
                color: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }


  List<Widget> _buildTopSongsSection(ColorScheme cs) {
    final visible = (_showAllSongs || _topSongs.length <= _initialSongLimit)
        ? _topSongs
        : _topSongs.take(_initialSongLimit).toList();

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text('Songs'.tr,
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
        ),
      ),
      SliverList.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) => _buildSongRow(cs, visible[index], index),
      ),
      if (_topSongs.length > _initialSongLimit)
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                onTap: () {
                  _haptic();
                  setState(() => _showAllSongs = !_showAllSongs);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showAllSongs ? 'Show less' : 'Show all',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _showAllSongs
                            ? FluentIcons.chevron_up_24_regular
                            : FluentIcons.chevron_down_24_regular,
                        size: 16,
                        color: cs.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildSongRow(ColorScheme cs, Map track, int index) {
    final playing = _isTrackPlaying(track);
    final thumbs = (track['thumbnails'] as List?) ?? const [];
    final art =
        thumbs.isNotEmpty ? _hiRes(thumbs.last['url'].toString(), 300) : '';
    final subtitle = (track['subtitle'] ?? track['artist'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Material(
        color: playing
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _playAll(index: index),
          onLongPress: () => _showTrackMenu(track),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (art.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: art,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(FluentIcons.music_note_2_24_regular,
                                  color: cs.onSurfaceVariant),
                            ),
                          )
                        else
                          Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(FluentIcons.music_note_2_24_regular,
                                color: cs.onSurfaceVariant),
                          ),
                        if (playing)
                          const Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: EdgeInsets.all(3),
                              child: _PlayingWaveBars(compact: true),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (track['title'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: playing ? FontWeight.w700 : FontWeight.w600,
                          color: playing ? cs.primary : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showTrackMenu(track),
                  icon: Icon(FluentIcons.more_vertical_24_regular,
                      size: 18, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTrackMenu(Map track) {
    _haptic();
    // The app-wide song bottom sheet (same funnel as search results);
    // it expects the shared shelf-row shape, which is exactly what
    // the Songs shelf carries.
    final item = Map<String, dynamic>.from(track);
    item.putIfAbsent('artist', () => item['subtitle'] ?? _name);
    Modals.showSongBottomModal(context, item);
  }


  Widget _buildCarouselSection(ColorScheme cs, String title,
      List<Map<String, dynamic>> items,
      {required double height}) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text(title,
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ),
          SizedBox(
            height: height,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) => _buildAlbumCard(cs, items[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumCard(ColorScheme cs, Map item) {
    final thumbs = (item['thumbnails'] as List?) ?? const [];
    final art =
        thumbs.isNotEmpty ? _hiRes(thumbs.last['url'].toString(), 400) : '';
    final subtitle = (item['subtitle'] ?? '').toString();
    // YTM subtitle shape: "Album • 2021" / "Single" / "EP • 2020".
    final year = RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(subtitle)?.group(0);
    final kind = subtitle.contains('Single')
        ? 'Single'
        : subtitle.contains('EP')
            ? 'EP'
            : 'Album';

    return GestureDetector(
      onTap: () => _openAlbum(item),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: art.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: art,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(FluentIcons.album_24_regular,
                                    color: cs.onSurfaceVariant),
                              ),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(FluentIcons.album_24_regular,
                                  color: cs.onSurfaceVariant),
                            ),
                    ),
                  ),
                  if (year != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          year,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              (item['title'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              kind,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimilarSection(ColorScheme cs) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Text('Fans might also like'.tr,
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
          ),
          SizedBox(
            height: 156,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: _similar.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final item = _similar[index];
                final thumbs = (item['thumbnails'] as List?) ?? const [];
                final art = thumbs.isNotEmpty
                    ? _hiRes(thumbs.last['url'].toString(), 300)
                    : '';
                return GestureDetector(
                  onTap: () => _openArtist(item),
                  child: Container(
                    width: 130,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: ClipOval(
                            child: art.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: art,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: cs.surfaceContainerHighest,
                                      child:
                                          Icon(Icons.person, color: cs.primary),
                                    ),
                                  )
                                : Container(
                                    color: cs.surfaceContainerHighest,
                                    child: Icon(Icons.person, color: cs.primary),
                                  ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          (item['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface),
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
    );
  }


  Widget _buildFullscreenMotion(ColorScheme cs) {
    return Positioned.fill(
      key: const ValueKey('artist-motion'),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_canvasUrl != null)
              VideoBackdrop(
                key: ValueKey('artist-motion-canvas-$_name'),
                streamUrl: _canvasUrl!,
                playing: true,
                shortLoop: true,
                onUnavailable: (_) {
                  if (mounted) setState(() => _fullscreenMotion = false);
                },
              ),
            // Top bar: back + "Artist Motion" badge.
            SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: _HeroCircleButton(
                      size: 44,
                      tooltip: 'Back'.tr,
                      background: Colors.black.withValues(alpha: 0.5),
                      onTap: () => setState(() => _fullscreenMotion = false),
                      child: const Icon(FluentIcons.chevron_left_24_regular,
                          size: 22, color: Colors.white),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16, top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        'Artist Motion'.tr,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom vignette + identity + play controls (upstream parity).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(24, 40, 24,
                    28 + MediaQuery.paddingOf(context).bottom),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.verified, size: 20, color: cs.primary),
                            ],
                          ),
                          if (_subscribers != null && _subscribers!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _subscribers!,
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: Colors.white.withValues(alpha: 0.75)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _topSongs.isEmpty
                          ? null
                          : () {
                              setState(() => _fullscreenMotion = false);
                              _shuffle();
                            },
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        child: const Icon(FluentIcons.arrow_shuffle_24_regular,
                            size: 20, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _topSongs.isEmpty
                          ? null
                          : () {
                              setState(() => _fullscreenMotion = false);
                              _playAll();
                            },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, color: cs.primary),
                        child: Icon(
                            _isArtistPlaying
                                ? FluentIcons.pause_24_filled
                                : FluentIcons.play_24_filled,
                            size: 28,
                            color: cs.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Hero photo with the upstream fallback chain: each failed candidate
/// advances to the next artwork automatically (artworkIndex++ pattern).
class _HeroArtwork extends StatelessWidget {
  const _HeroArtwork({required this.candidates, required this.placeholder});

  final List<String> candidates;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        // Candidates painted in REVERSE so the first (best) artwork sits on
        // top; a failed one renders nothing and the next candidate below
        // shows through — the upstream artworkIndex++ behaviour, stacked.
        for (final url in candidates.reversed)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// Circular translucent hero button (upstream: Surface + CircleShape).
class _HeroCircleButton extends StatelessWidget {
  const _HeroCircleButton({
    required this.onTap,
    required this.child,
    this.tooltip,
    this.size = 38,
    this.background,
  });

  final VoidCallback? onTap;
  final Widget child;
  final String? tooltip;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? Colors.black.withValues(alpha: 0.45),
        ),
        child: Center(child: child),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 48dp tonal circle for shuffle/radio (upstream FilledTonalIconButton).
class _TonalCircle extends StatelessWidget {
  const _TonalCircle({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.secondaryContainer,
          ),
          child: Icon(icon, size: 20, color: cs.primary),
        ),
      ),
    );
  }
}

/// The little equaliser bars that mark "this artist/track is playing"
/// (upstream PlayingWaveBars). Transform-free — just resizing bars on one
/// repeating ticker, cheap enough to sit inside a list row.
class _PlayingWaveBars extends StatefulWidget {
  const _PlayingWaveBars({this.compact = false});

  final bool compact;

  @override
  State<_PlayingWaveBars> createState() => _PlayingWaveBarsState();
}

class _PlayingWaveBarsState extends State<_PlayingWaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.compact ? 2.5 : 3.0;
    final maxHeight = widget.compact ? 12.0 : 15.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < 4; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 3 ? 0 : barWidth),
                child: Container(
                  width: barWidth,
                  height: maxHeight *
                      (0.35 +
                          0.65 *
                              (0.5 +
                                  0.5 *
                                      math.sin(_controller.value *
                                          2 *
                                          math.pi *
                                          2 +
                                          i * 0.9))),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}


/// "A$AP Rocky, Playboi Carti" → "A$AP Rocky" (upstream ArtistHelper).
String _primaryArtist(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return trimmed;
  for (final sep in const [',', ' & ', ' x ', ' X ', ' feat. ', ' ft. ']) {
    final idx = trimmed.indexOf(sep);
    if (idx > 0) return trimmed.substring(0, idx).trim();
  }
  return trimmed;
}

/// Best-size YouTube thumbnail (same rules as search_page._hiRes).
String _hiRes(String url, [int size = 300]) {
  final re = RegExp(r'=w\d+-h\d+');
  if (re.hasMatch(url)) return url.replaceFirst(re, '=w$size-h$size-l90-rj');
  final s = RegExp(r'=s\d+');
  if (s.hasMatch(url)) return url.replaceFirst(s, '=s$size');
  return url;
}
