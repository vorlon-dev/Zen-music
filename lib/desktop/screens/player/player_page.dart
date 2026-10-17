// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/player/player_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// PORT DEVIATIONS: sliding_up_panel vestigials dropped; WillPopScope removed;
// dispose() typed void.
//
// REDESIGN v3 (desktop + mobile, one adaptive layout):
//  * Fluent System Icons everywhere (single table: _Ic) with hover / press
//    feedback on every control, tooltips on desktop.
//  * Layouts: WIDE (>= 900 px): player column + glass lyrics panel.
//    NARROW (< 900 px): one column, lyrics swap with the artwork. Heights are
//    measured, so short windows shrink the artwork first and only then
//    scroll.
//  * Tinder-style SwipeArtworkStack kept (left = next, right = previous,
//    skip buttons trigger the same animation, palette from the front card).
//  * AUDIO QUALITY: chip under the title (tier + bitrate/codec) that opens a
//    details sheet. Reads whatever the song's MediaItem.extras carries
//    (itag, bitrate, codec, mimeType, sampleRate, bitDepth, quality...) or an
//    explicit extras['zenQuality'] map; shows "Auto" when a source reports
//    nothing — it never invents numbers.
//  * Desktop keyboard: Space play/pause, Left/Right seek 5 s, Ctrl+Left/Right
//    previous/next, L lyrics, Q queue, Esc close.
//  * ZenSlider (7 styles) seek bar, tabular time labels, legibility scrim,
//    breathing artwork, working shuffle, active-state dots, null-safety.
//  * SP-5b: transport routes through MediaPlayer.togglePlayPause / seekTo /
//    skipNext / skipPrevious (single code path for every engine).
//  * SP-8: alternative skins (from player_skins.dart) are honored. When a
//    non-classic skin is selected, this page returns PlayerSkinView. The
//    classic layout remains exactly as before.

import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, LogicalKeyboardKey;
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:text_scroll/text_scroll.dart';
import 'package:palette_generator/palette_generator.dart';

import 'package:zenmusic/desktop/core/widgets/square_artwork.dart';
import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/screens/player/widgets/animated_gradient_bg.dart';
import 'package:zenmusic/desktop/screens/player/widgets/lyrics_box.dart';
import 'package:zenmusic/desktop/screens/player/widgets/queue_list.dart';
import 'package:zenmusic/desktop/screens/player/widgets/swipe_artwork_stack.dart';
import 'package:zenmusic/desktop/screens/player/player_skins.dart'; // SP-8
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/themes/dark.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

// ════════════════════════════════════════════════════════════════════
// ICON TABLE — every Fluent icon the page uses lives here. If a name is
// missing in your fluentui_system_icons version, change it in ONE place.
// ════════════════════════════════════════════════════════════════════
class _Ic {
  _Ic._();
  static const chevronDown = FluentIcons.chevron_down_24_regular;
  static const queue = FluentIcons.text_bullet_list_ltr_24_regular;
  static const lyrics = FluentIcons.text_quote_24_regular; // alt: mic_24_regular
  static const heart = FluentIcons.heart_24_regular;
  static const heartFill = FluentIcons.heart_24_filled;
  static const more = FluentIcons.more_horizontal_24_regular;
  static const play = FluentIcons.play_24_filled;
  static const pause = FluentIcons.pause_24_filled;
  static const previous = FluentIcons.previous_24_filled;
  static const next = FluentIcons.next_24_filled;
  static const shuffle = FluentIcons.arrow_shuffle_24_regular;
  static const repeatAll = FluentIcons.arrow_repeat_all_24_regular;
  static const repeatOne = FluentIcons.arrow_repeat_1_24_regular;
  static const speaker = FluentIcons.speaker_2_24_regular;
  static const info = FluentIcons.info_24_regular;
  static const dismiss = FluentIcons.dismiss_24_regular;
}

const Color _kHeartRed = Color(0xFFFF4D6D);

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, this.videoId});
  final String? videoId;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final GlobalKey<ScaffoldState> _key = GlobalKey();
  final GlobalKey<SwipeArtworkStackState> _swipeKey =
  GlobalKey<SwipeArtworkStackState>();
  Color? color;
  List<Color> paletteColors = [];
  bool fetchedSong = false;
  late MediaItem? currentSong;
  bool _hasLyrics = false;
  bool _lyricsLoading = true;
  bool _showLyrics = false; // narrow layout: swap artwork <-> lyrics
  final GlobalKey<State> _lyricsBoxKey = GlobalKey();

  // Video backdrop: synchronized song-video behind the artwork.
  String? _videoBackdropUrl;
  Map<String, String> _videoHeaders = const {};

  // ------------------------------------------------------------ lifecycle

  @override
  void initState() {
    super.initState();
    if (widget.videoId != null) {
      GetIt.I<YTMusic>().getSongDetails(widget.videoId!).then((song) {
        if (song != null) {
          GetIt.I<MediaPlayer>().playSong(song);
          if (mounted) setState(() => fetchedSong = true);
        }
      });
    }
    currentSong = GetIt.I<MediaPlayer>().currentSongNotifier.value;
    GetIt.I<MediaPlayer>().currentSongNotifier.addListener(songListener);
    _maybeLoadVideoBackdrop();
  }

  @override
  void dispose() {
    GetIt.I<MediaPlayer>().currentSongNotifier.removeListener(songListener);
    super.dispose();
  }

  void songListener() {
    if (currentSong != GetIt.I<MediaPlayer>().currentSongNotifier.value) {
      if (mounted) {
        setState(() {
          currentSong = GetIt.I<MediaPlayer>().currentSongNotifier.value;
          _lyricsLoading = true;
          _hasLyrics = false;
          _showLyrics = false;
          // Stale video of the previous song must not linger.
          _videoBackdropUrl = null;
        });
      }
      _maybeLoadVideoBackdrop();
    }
  }

  /// Android + native bridge + canvas pref + YTM-shaped id. Silent no-op
  /// otherwise — the gradient stays the backdrop.
  Future<void> _maybeLoadVideoBackdrop() async {
    if (!Platform.isAndroid) return;
    if (!AppearancePrefs.canvasEnabled.value) return;
    final id = currentSong?.id ?? '';
    if (id.length != 11) return; // YTM ids only — JioSaavn/local skip
    final streams = await InnertubexBridge.extractVideo(id, maxHeight: 720);
    if (!mounted || currentSong?.id != id) return; // song changed mid-flight
    if (streams?.videoUrl != null) {
      setState(() {
        _videoBackdropUrl = streams!.videoUrl;
        _videoHeaders = streams.headers;
      });
    }
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  String _qualityString(MediaItem song) {
    final q = _AudioQuality.of(song);
    if (q.chipDetail != null) {
      return '${q.label}, ${q.chipDetail}';
    }
    return q.label;
  }

  Future<void> updateBackgroundColor(ImageProvider image) async {
    final palette = await PaletteGenerator.fromImageProvider(
      image,
      maximumColorCount: 20,
    );
    if (!mounted) return;
    List<Color> extracted = [
      palette.dominantColor?.color,
      palette.vibrantColor?.color,
      palette.mutedColor?.color,
      palette.darkVibrantColor?.color,
      palette.darkMutedColor?.color,
      palette.lightVibrantColor?.color,
    ].whereType<Color>().toList();

    if (extracted.isEmpty && palette.colors.isNotEmpty) {
      extracted = palette.colors.take(4).toList();
    }
    setState(() {
      color = palette.dominantColor?.color;
      paletteColors = extracted;
    });
  }

  MaterialColor primaryWhite = const MaterialColor(
    0xFFFFFFFF,
    <int, Color>{
      50: Color(0xFFFFFFFF),
      100: Color(0xFFFFFFFF),
      200: Color(0xFFFFFFFF),
      300: Color(0xFFFFFFFF),
      400: Color(0xFFFFFFFF),
      500: Color(0xFFFFFFFF),
      600: Color(0xFFFFFFFF),
      700: Color(0xFFFFFFFF),
      800: Color(0xFFFFFFFF),
      900: Color(0xFFFFFFFF),
    },
  );

  static MediaPlayer mediaPlayerOf(BuildContext context) =>
      context.read<MediaPlayer>();

  // ---------------------------------------------------------- small actions

  void _seekBy(int seconds) {
    final mp = GetIt.I<MediaPlayer>();
    final s = mp.progressBarState.value;
    final total = s.total.inMilliseconds;
    if (total <= 0) return;
    final target = (s.current.inMilliseconds + seconds * 1000).clamp(0, total);
    mp.seekTo(Duration(milliseconds: target.toInt()));
  }

  void _skipNext() {
    if (!(_swipeKey.currentState?.swipeNext() ?? false)) {
      GetIt.I<MediaPlayer>().skipNext();
    }
  }

  void _skipPrevious() {
    if (!(_swipeKey.currentState?.swipePrev() ?? false)) {
      GetIt.I<MediaPlayer>().skipPrevious();
    }
  }

  void _toggleLyrics() {
    if (_hasLyrics) setState(() => _showLyrics = !_showLyrics);
  }

  void _openQuality(MediaItem song) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _QualitySheet(info: _AudioQuality.of(song)),
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts() => {
    const SingleActivator(LogicalKeyboardKey.space): () =>
        GetIt.I<MediaPlayer>().togglePlayPause(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-5),
    const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(5),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
    _skipPrevious,
    const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
    _skipNext,
    const SingleActivator(LogicalKeyboardKey.keyL): _toggleLyrics,
    const SingleActivator(LogicalKeyboardKey.keyQ): () =>
        _key.currentState?.openEndDrawer(),
    const SingleActivator(LogicalKeyboardKey.escape): () {
      if (mounted) context.pop();
    },
  };

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final song = currentSong;
    final loading = (widget.videoId != null && !fetchedSong) || song == null;
    return Theme(
      data: darkTheme(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryWhite,
          primary: primaryWhite,
          brightness: Brightness.dark,
        ),
      ),
      child: loading
          ? const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: AdaptiveProgressRing()),
      )
          : _buildScaffold(context, song),
    );
  }

  Widget _buildScaffold(BuildContext context, MediaItem song) {
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder<String>(
          valueListenable: PlayerSkinPrefs.skin,
          builder: (context, skinName, _) {
            final skin = PlayerSkin.fromName(skinName);
            if (skin != PlayerSkin.classic) {
              final mediaPlayer = GetIt.I<MediaPlayer>();
              final currentIndex = mediaPlayer.currentIndex.value ?? 0;
              final total = mediaPlayer.songList.length > 0 ? mediaPlayer.songList.length : 1;

              final ctx = PlayerCtx(
                song: song,
                index: currentIndex + 1,
                total: total,
                quality: _qualityString(song),
                hasLyrics: _hasLyrics,
                showLyrics: _showLyrics,
                lyrics: (size) => _lyricsBox(song, size),
                swipeArt: _buildArtwork(song),
                art: (radius) => SquareArtwork(
                  song: song.extras ?? {'videoId': song.id, 'title': song.title},
                  borderRadius: radius,
                ),
                close: () => context.pop(),
                openQueue: () => _key.currentState?.openEndDrawer(),
                openQuality: () => _openQuality(song),
                toggleLyrics: _toggleLyrics,
                next: _skipNext,
                prev: _skipPrevious,
                tint: color,
              );

              return Scaffold(
                backgroundColor: Colors.black,
                body: PlayerSkinView(skin: skin, ctx: ctx),
              );
            }

            return Scaffold(
              key: _key,
              backgroundColor: Colors.black,
              endDrawer: SizedBox(
                width: min(400, MediaQuery.of(context).size.width) - 50,
                child: const QueueList(),
              ),
              body: Stack(
                children: [
                  // Animated palette gradient
                  Positioned.fill(
                    child: AnimatedGradientBackground(
                      colors: paletteColors.isNotEmpty
                          ? paletteColors
                          : [
                        Colors.deepPurple.shade900,
                        Colors.deepPurple.shade700,
                        Colors.purple.shade800,
                        Colors.indigo.shade900,
                      ],
                    ),
                  ),

                  // Synchronized video backdrop (reacts to play/pause)
                  if (_videoBackdropUrl != null)
                    Positioned.fill(
                      child: ValueListenableBuilder<ButtonState>(
                        valueListenable: mediaPlayerOf(context).buttonState,
                        builder: (context, state, _) => VideoBackdrop(
                          streamUrl: _videoBackdropUrl!,
                          playing: state == ButtonState.playing,
                          synchronized: true,
                          positionStream:
                          mediaPlayerOf(context).player.positionStream,
                          posterUrl: song.artUri?.toString(),
                          httpHeaders: _videoHeaders,
                          onUnavailable: (_) {
                            if (mounted) {
                              setState(() => _videoBackdropUrl = null);
                            }
                          },
                        ),
                      ),
                    ),

                  // Legibility scrim: lighter at top, heavier behind controls
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.10),
                              Colors.black.withValues(alpha: 0.28),
                              Colors.black.withValues(alpha: 0.66),
                            ],
                            stops: const [0, 0.45, 1],
                          ),
                        ),
                      ),
                    ),
                  ),

                  SafeArea(
                    child: Column(
                      children: [
                        _buildTopBar(song),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) => _buildBody(song, box),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------- top bar

  Widget _buildTopBar(MediaItem song) {
    final subtitle = song.album;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _IconBtn(
            icon: _Ic.chevronDown,
            tooltip: 'Close',
            filled: true,
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _IconBtn(
            icon: _Ic.queue,
            tooltip: 'Queue (Q)',
            filled: true,
            onPressed: () => _key.currentState?.openEndDrawer(),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _buildBody(MediaItem song, BoxConstraints box) {
    final wide = box.maxWidth >= 900;

    if (wide) {
      return Row(
        children: [
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: LayoutBuilder(
                    builder: (context, inner) =>
                        _buildPlayerColumn(song, inner, swap: false),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 40, 28),
              child: _buildLyricsPanel(song),
            ),
          ),
        ],
      );
    }

    final hPad = box.maxWidth >= 600 ? 40.0 : 24.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, inner) =>
                _buildPlayerColumn(song, inner, swap: true),
          ),
        ),
      ),
    );
  }

  /// Artwork (or lyrics) + info + quality + seek + transport. The artwork
  /// takes whatever height is left; if even the minimum does not fit, the
  /// column scrolls instead of overflowing.
  Widget _buildPlayerColumn(MediaItem song, BoxConstraints box,
      {required bool swap}) {
    const controlsH = 322.0; // info + quality + seek + transport + gaps
    const gap = 16.0;
    final room = box.maxHeight - controlsH - gap;
    final side = room.clamp(150.0, min(box.maxWidth, 520.0)).toDouble();
    final needsScroll = side + gap + controlsH > box.maxHeight + 0.5;
    final lyricsVisible = swap && _showLyrics && _hasLyrics;

    final media = SizedBox(
      width: box.maxWidth,
      height: side,
      child: Stack(
        children: [
          // Artwork stays mounted (keeps palette updates alive).
          Offstage(
            offstage: lyricsVisible,
            child: Center(
              child: SizedBox(
                  width: side, height: side, child: _buildArtwork(song)),
            ),
          ),
          // Narrow layout: one stable lyrics slot, never re-parented.
          if (swap)
            Offstage(
              offstage: !lyricsVisible,
              child: _lyricsBox(
                song,
                lyricsVisible ? Size(box.maxWidth, side) : Size.zero,
              ),
            ),
        ],
      ),
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        media,
        const SizedBox(height: gap),
        _buildInfoRow(song),
        const SizedBox(height: 10),
        _buildQualityRow(song, swap: swap),
        const SizedBox(height: 14),
        _buildSeekBar(),
        const SizedBox(height: 10),
        _buildTransport(),
      ],
    );

    if (needsScroll) {
      return SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: content,
      );
    }
    return Align(alignment: Alignment.center, child: content);
  }

  // -------------------------------------------------------------- artwork

  /// Tinder-style swipeable artwork: swipe left = next song, right =
  /// previous; neighbor cards pre-built underneath; queue-edge rubber-band;
  /// skip buttons trigger the same animation via the key. Palette updates
  /// from the front card only.
  Widget _buildArtwork(MediaItem song) {
    final items = List<MediaItem>.from(GetIt.I<MediaPlayer>()
        .songList
        .map((src) => src.tag)
        .whereType<MediaItem>());
    final idx = items.indexWhere((m) => m.id == song.id);
    final next = (idx >= 0 && idx + 1 < items.length) ? items[idx + 1] : null;
    final prev = (idx > 0) ? items[idx - 1] : null;

    return ValueListenableBuilder<ButtonState>(
      valueListenable: mediaPlayerOf(context).buttonState,
      builder: (context, state, _) {
        final active =
            state == ButtonState.playing || state == ButtonState.loading;
        return SwipeArtworkStack(
          key: _swipeKey,
          current: song,
          next: next,
          previous: prev,
          active: active,
          onSwipeNext: () => GetIt.I<MediaPlayer>().skipNext(), // SP-5b
          onSwipePrevious: () => GetIt.I<MediaPlayer>().skipPrevious(), // SP-5b
          cardBuilder: (context, item, isFront) => SquareArtwork(
            song: item.extras ?? {'videoId': item.id, 'title': item.title},
            borderRadius: 16,
            onImageReady: isFront ? updateBackgroundColor : null,
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- lyrics

  Widget _lyricsBox(MediaItem song, Size size) {
    return LyricsBox(
      key: _lyricsBoxKey,
      currentSong: song,
      size: size,
      onLyricsFound: (found) {
        if (mounted) {
          setState(() {
            _hasLyrics = found;
            _lyricsLoading = false;
            if (!found) _showLyrics = false;
          });
        }
      },
    );
  }

  /// WIDE layout: frosted panel on the right.
  Widget _buildLyricsPanel(MediaItem song) {
    return _Glass(
      radius: 28,
      child: LayoutBuilder(
        builder: (context, c) {
          if (_hasLyrics) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _lyricsBox(song, Size(c.maxWidth - 16, c.maxHeight - 16)),
            );
          }
          return Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_lyricsLoading)
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white70),
                      )
                    else
                      Icon(_Ic.lyrics,
                          size: 44,
                          color: Colors.white.withValues(alpha: 0.30)),
                    const SizedBox(height: 14),
                    Text(
                      _lyricsLoading
                          ? 'Looking for lyrics…'
                          : 'No lyrics for this song',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Hidden probe so lyrics can be discovered.
              Offstage(child: _lyricsBox(song, Size.zero)),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ info row

  Widget _buildInfoRow(MediaItem song) {
    final mediaPlayer = mediaPlayerOf(context);
    final videoId = song.extras?['videoId'];
    return SizedBox(
      height: 62,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextScroll(
                  song.title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                  mode: TextScrollMode.endless,
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist ?? song.album ?? song.extras?['subtitle'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder(
            valueListenable: Hive.box('FAVOURITES').listenable(),
            builder: (context, value, child) {
              final Map? item = value.get(videoId);
              final liked = item != null;
              return _IconBtn(
                tooltip: liked ? 'Remove from favourites' : 'Add to favourites',
                size: 26,
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  if (item == null) {
                    await Hive.box('FAVOURITES').put(
                      song.extras!['videoId'],
                      {
                        ...song.extras!,
                        'createdAt': DateTime.now().millisecondsSinceEpoch,
                      },
                    );
                  } else {
                    await value.delete(song.extras!['videoId']);
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    liked ? _Ic.heartFill : _Ic.heart,
                    key: ValueKey(liked),
                    size: 26,
                    color: liked
                        ? _kHeartRed
                        : Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              );
            },
          ),
          Builder(
            builder: (buttonContext) => _IconBtn(
              icon: _Ic.more,
              tooltip: 'More',
              onPressed: () {
                final RenderBox renderBox =
                buttonContext.findRenderObject() as RenderBox;
                final position = renderBox.localToGlobal(Offset.zero);
                final size = renderBox.size;
                Modals.showPlayerOptionsModal(
                  context,
                  mediaPlayer.currentSongNotifier.value!.extras!,
                  buttonPosition: position,
                  buttonSize: size,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- quality row

  Widget _buildQualityRow(MediaItem song, {required bool swap}) {
    final q = _AudioQuality.of(song);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          _QualityChip(info: q, onTap: () => _openQuality(song)),
          const Spacer(),
          if (swap)
            _Pill(
              icon: _Ic.lyrics,
              label: 'Lyrics',
              active: _showLyrics && _hasLyrics,
              enabled: _hasLyrics,
              onTap: _toggleLyrics,
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- seek bar

  Widget _buildSeekBar() {
    final mediaPlayer = mediaPlayerOf(context);
    return ValueListenableBuilder(
      valueListenable: mediaPlayer.progressBarState,
      builder: (context, ProgressBarState value, child) {
        final totalMs = value.total.inMilliseconds;
        final posMs = value.current.inMilliseconds;
        final playing = mediaPlayer.buttonState.value == ButtonState.playing;
        const labelStyle = TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFeatures: [FontFeature.tabularFigures()],
        );
        return Column(
          children: [
            ZenSlider(
              style: ZenSliderStyle.fromName(AppearancePrefs.sliderStyle.value),
              value: totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0,
              isPlaying: playing,
              // SP-5b: route through MediaPlayer so the engine handles seek.
              onChanged: (v) => mediaPlayer
                  .seekTo(Duration(milliseconds: (v * totalMs).round())),
              onChangeEnd: (v) => mediaPlayer
                  .seekTo(Duration(milliseconds: (v * totalMs).round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatMs(posMs), style: labelStyle),
                  Text(_formatMs(totalMs), style: labelStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------ transport

  Widget _buildTransport() {
    final mediaPlayer = mediaPlayerOf(context);
    return SizedBox(
      height: 84,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StreamBuilder<bool>(
            stream: mediaPlayer.player.shuffleModeEnabledStream,
            initialData: false,
            builder: (context, snap) {
              final on = snap.data ?? false;
              return _ToggleBtn(
                icon: _Ic.shuffle,
                active: on,
                tooltip: on ? 'Shuffle on' : 'Shuffle off',
                onPressed: () async {
                  await mediaPlayer.player.setShuffleModeEnabled(!on);
                  if (!on) await mediaPlayer.player.shuffle();
                },
              );
            },
          ),
          _IconBtn(
            icon: _Ic.previous,
            tooltip: 'Previous (Ctrl+←)',
            size: 32,
            box: 52,
            onPressed: _skipPrevious,
          ),
          ValueListenableBuilder<ButtonState>(
            valueListenable: mediaPlayer.buttonState,
            builder: (context, state, _) => _PlayButton(
              state: state,
              onPressed: () {
                HapticFeedback.selectionClick();
                mediaPlayer.togglePlayPause(); // SP-5b
              },
            ),
          ),
          _IconBtn(
            icon: _Ic.next,
            tooltip: 'Next (Ctrl+→)',
            size: 32,
            box: 52,
            onPressed: _skipNext,
          ),
          ValueListenableBuilder(
            valueListenable: mediaPlayer.loopMode,
            builder: (context, value, child) {
              return _ToggleBtn(
                icon: value == LoopMode.one ? _Ic.repeatOne : _Ic.repeatAll,
                active: value != LoopMode.off,
                tooltip: switch (value) {
                  LoopMode.one => 'Repeat one',
                  LoopMode.all => 'Repeat all',
                  _ => 'Repeat off',
                },
                onPressed: () => mediaPlayer.changeLoopMode(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// AUDIO QUALITY
// ════════════════════════════════════════════════════════════════════

enum _Tier { lossless, hiRes, high, standard, low, unknown }

class _AudioQuality {
  const _AudioQuality({
    required this.tier,
    this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitDepth,
    this.source,
  });

  final _Tier tier;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitDepth;
  final String? source;

  String get label => switch (tier) {
    _Tier.lossless => 'Lossless',
    _Tier.hiRes => 'Hi-Res',
    _Tier.high => 'High',
    _Tier.standard => 'Standard',
    _Tier.low => 'Low',
    _Tier.unknown => 'Auto',
  };

  String get description => switch (tier) {
    _Tier.lossless => 'Bit-perfect audio with no compression loss.',
    _Tier.hiRes => 'Higher resolution than CD quality.',
    _Tier.high => 'Near-transparent quality for most listening.',
    _Tier.standard => 'A balance of quality and data use.',
    _Tier.low => 'Data saver quality.',
    _Tier.unknown =>
    'This source does not report its stream format, so the quality is '
        'chosen automatically.',
  };

  Color get accent => switch (tier) {
    _Tier.lossless || _Tier.hiRes => const Color(0xFFFFD166),
    _Tier.high => const Color(0xFF8BE9B3),
    _Tier.standard => const Color(0xFFD7D7E0),
    _Tier.low => const Color(0xFFFFB38A),
    _Tier.unknown => const Color(0xFFB4B4C0),
  };

  /// Short detail for the chip: bitrate, else sample rate, else codec.
  String? get chipDetail {
    if (bitrateKbps != null) return '$bitrateKbps kbps';
    if (sampleRateHz != null) return _khz(sampleRateHz!);
    return codec;
  }

  static String _khz(int hz) {
    final k = hz / 1000;
    return '${k == k.roundToDouble() ? k.toInt() : k.toStringAsFixed(1)} kHz';
  }

  String get sampleRateLabel => _khz(sampleRateHz!);

  // YouTube/YTM itag -> (codec, kbps)
  static const Map<int, (String, int)> _itags = {
    139: ('AAC', 48),
    140: ('AAC', 128),
    141: ('AAC', 256),
    249: ('Opus', 50),
    250: ('Opus', 70),
    251: ('Opus', 160),
    256: ('AAC', 192),
    258: ('AAC', 384),
    327: ('AAC', 256),
  };

  static Map<String, dynamic> _flatten(Map? extras) {
    final out = <String, dynamic>{};
    if (extras == null) return out;
    void add(Map m) {
      for (final e in m.entries) {
        out[e.key.toString().toLowerCase()] = e.value;
      }
    }

    add(extras);
    // One nested level (stream / audio / format info maps).
    for (final key in const [
      'zenquality',
      'stream',
      'streaminfo',
      'audio',
      'format',
    ]) {
      final v = out[key];
      if (v is Map) add(v);
    }
    return out;
  }

  static Object? _get(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k.toLowerCase()];
      if (v != null && '$v'.isNotEmpty) return v;
    }
    return null;
  }

  static num? _num(Object? v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.replaceAll(RegExp(r'[^0-9.]'), ''));
    return null;
  }

  static String? _codecFrom(String text) {
    final t = text.toLowerCase();
    if (t.trim().isEmpty) return null;
    if (t.contains('opus')) return 'Opus';
    if (t.contains('flac')) return 'FLAC';
    if (t.contains('alac')) return 'ALAC';
    if (t.contains('mp4a') || t.contains('aac') || t.contains('m4a')) {
      return 'AAC';
    }
    if (t.contains('mp3') || t.contains('mpeg')) return 'MP3';
    if (t.contains('vorbis') || t.contains('ogg')) return 'Vorbis';
    if (t.contains('wav') || t.contains('pcm')) return 'WAV';
    return null;
  }

  static _AudioQuality of(MediaItem song) {
    final m = _flatten(song.extras);

    String? codec;
    int? kbps;

    // 1. itag (YouTube family) gives codec + bitrate in one go.
    final itag = _num(_get(m, ['itag']))?.toInt();
    if (itag != null && _itags.containsKey(itag)) {
      codec = _itags[itag]!.$1;
      kbps = _itags[itag]!.$2;
    }

    // 2. explicit fields.
    codec ??= _codecFrom('${_get(m, ['codec', 'audioCodec', 'acodec']) ?? ''} '
        '${_get(m, ['mimeType', 'mime', 'contentType']) ?? ''} '
        '${_get(m, ['container', 'ext', 'extension']) ?? ''}');
    final rawBitrate = _num(_get(m, [
      'bitrateKbps',
      'bitrate',
      'abr',
      'averageBitrate',
      'avgBitrate',
      'audioBitrate'
    ]));
    if (rawBitrate != null && rawBitrate > 0) {
      kbps = (rawBitrate > 2000 ? rawBitrate / 1000 : rawBitrate).round();
    }

    var rate = _num(_get(m, ['sampleRate', 'audioSampleRate', 'sample_rate']));
    if (rate != null && rate > 0 && rate < 1000) rate = rate * 1000;
    final sampleRate = (rate != null && rate > 0) ? rate.round() : null;
    final depthNum = _num(_get(m, ['bitDepth', 'bit_depth', 'bits']));
    final depth = (depthNum != null && depthNum > 0) ? depthNum.round() : null;

    final qualityText = '${_get(m, [
      'quality',
      'audioQuality',
      'audio_quality',
      'streamQuality'
    ]) ?? ''}'
        .toLowerCase();

    final codecL = (codec ?? '').toLowerCase();
    final lossless = codecL == 'flac' ||
        codecL == 'alac' ||
        codecL == 'wav' ||
        qualityText.contains('lossless');

    _Tier tier;
    if (lossless) {
      tier = ((depth ?? 16) >= 24 || (sampleRate ?? 44100) > 48000)
          ? _Tier.hiRes
          : _Tier.lossless;
    } else if (qualityText.contains('hi') && qualityText.contains('res')) {
      tier = _Tier.hiRes;
    } else if (kbps != null) {
      final opus = codecL == 'opus';
      final highAt = opus ? 128 : 256;
      final stdAt = opus ? 64 : 128;
      tier = kbps >= highAt
          ? _Tier.high
          : (kbps >= stdAt ? _Tier.standard : _Tier.low);
    } else if (qualityText.contains('high') ||
        qualityText.contains('premium') ||
        qualityText.contains('extreme') ||
        qualityText.contains('320')) {
      tier = _Tier.high;
    } else if (qualityText.contains('medium') ||
        qualityText.contains('normal') ||
        qualityText.contains('standard')) {
      tier = _Tier.standard;
    } else if (qualityText.contains('low')) {
      tier = _Tier.low;
    } else {
      tier = _Tier.unknown;
    }

    final src = _get(m, ['source', 'provider', 'engine', 'platform']);
    return _AudioQuality(
      tier: tier,
      codec: codec,
      bitrateKbps: kbps,
      sampleRateHz: sampleRate,
      bitDepth: depth,
      source: src?.toString(),
    );
  }
}

class _QualityChip extends StatefulWidget {
  const _QualityChip({required this.info, required this.onTap});
  final _AudioQuality info;
  final VoidCallback onTap;

  @override
  State<_QualityChip> createState() => _QualityChipState();
}

class _QualityChipState extends State<_QualityChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.info;
    final detail = q.chipDetail;
    return Tooltip(
      message: 'Audio quality',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: q.accent.withValues(alpha: _hover ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: q.accent.withValues(alpha: 0.42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_Ic.speaker, size: 16, color: q.accent),
                const SizedBox(width: 7),
                Text(
                  q.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: q.accent,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: q.accent.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.72),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(_Ic.info,
                    size: 14, color: Colors.white.withValues(alpha: 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({required this.info});
  final _AudioQuality info;

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14, color: Colors.white.withValues(alpha: 0.55))),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = info;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 18 + bottom),
      decoration: BoxDecoration(
        color: const Color(0xFF17171B),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: q.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_Ic.speaker, color: q.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Audio quality',
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.5))),
                    const SizedBox(height: 2),
                    Text(q.label,
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: q.accent)),
                  ],
                ),
              ),
              _IconBtn(
                icon: _Ic.dismiss,
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(q.description,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(height: 10),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 22),
          _row('Format', q.codec),
          _row('Bitrate',
              q.bitrateKbps != null ? '${q.bitrateKbps} kbps' : null),
          _row('Sample rate',
              q.sampleRateHz != null ? q.sampleRateLabel : null),
          _row('Bit depth', q.bitDepth != null ? '${q.bitDepth}-bit' : null),
          _row('Source', q.source),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ════════════════════════════════════════════════════════════════════

/// Frosted panel.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 24, this.blur = 22});
  final Widget child;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: r,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Icon button with hover ring (desktop), press scale, tooltip, disabled
/// state. Either [icon] or a custom [child].
class _IconBtn extends StatefulWidget {
  const _IconBtn({
    this.icon,
    this.child,
    required this.onPressed,
    this.tooltip,
    this.size = 24,
    this.box = 44,
    this.filled = false,
    this.color,
  }) : assert(icon != null || child != null);

  final IconData? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double box;
  final bool filled;
  final Color? color;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final bg = widget.filled
        ? Colors.white.withValues(alpha: _hover ? 0.18 : 0.10)
        : Colors.white.withValues(alpha: _hover ? 0.10 : 0.0);

    Widget btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: widget.box,
            height: widget.box,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Center(
              child: Opacity(
                opacity: enabled ? 1 : 0.3,
                child: widget.child ??
                    Icon(widget.icon,
                        size: widget.size, color: widget.color ?? Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// Shuffle / repeat: dim when off, white + dot when on.
class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.icon,
    required this.active,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: icon,
          tooltip: tooltip,
          size: 24,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
          onPressed: onPressed,
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? Colors.white : Colors.transparent,
          ),
        ),
      ],
    );
  }
}

/// Big white play / pause button with loading ring.
class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.state, required this.onPressed});
  final ButtonState state;
  final VoidCallback onPressed;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final loading = widget.state == ButtonState.loading;
    final playing = widget.state == ButtonState.playing;
    final scale = _down ? 0.93 : (_hover ? 1.05 : 1.0);
    return Tooltip(
      message: playing ? 'Pause (Space)' : 'Play (Space)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child: loading
                    ? const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      color: Colors.black, strokeWidth: 3),
                )
                    : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    playing ? _Ic.pause : _Ic.play,
                    key: ValueKey(playing),
                    size: 34,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small rounded action pill (lyrics toggle on narrow layouts).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.black : Colors.white;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: enabled ? 0.12 : 0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}