// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/player/player_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// PORT DEVIATIONS: sliding_up_panel vestigials dropped; WillPopScope removed;
// dispose() typed void; artwork via SwipeArtworkStack (Tinder-style swipe:
// left = next, right = previous, preloaded behind-cards, edge rubber-band,
// skip buttons trigger the same animation; palette from the front card);
// progress bar via ZenSlider (7 styles, AppearancePrefs-driven) with
// tabular time labels; synchronized VIDEO BACKDROP behind the artwork
// (Android only, canvas pref gated);
// REDESIGN: legibility scrim, "Now Playing" header, breathing stack,
// lyrics toggle on narrow screens, working shuffle, active-state dots,
// null-safety fixes (song may be null; backdrop reacts to play state).

import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
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
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/themes/dark.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

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

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final song = currentSong;
    return Theme(
      data: darkTheme(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryWhite,
          primary: primaryWhite,
          brightness: Brightness.dark,
        ),
      ),
      child: (widget.videoId != null && !fetchedSong) || song == null
          ? const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: AdaptiveProgressRing()),
      )
          : Scaffold(
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
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.60),
                      ],
                      stops: const [0, 0.45, 1],
                    ),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 800;
                  return Column(
                    children: [
                      _buildTopBar(song, isWide: isWide),
                      Expanded(
                        child: isWide
                            ? _buildWide(song)
                            : _buildNarrow(song),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- top bar

  Widget _buildTopBar(MediaItem song, {required bool isWide}) {
    final subtitle = song.album;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          AdaptiveIconButton(
            onPressed: () => context.pop(),
            icon: Icon(AdaptiveIcons.chevron_down, color: Colors.white),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.65),
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
          if (!isWide)
            AdaptiveIconButton(
              onPressed: _hasLyrics
                  ? () => setState(() => _showLyrics = !_showLyrics)
                  : null,
              icon: Icon(
                _showLyrics ? Icons.lyrics : Icons.lyrics_outlined,
                color: Colors.white.withValues(alpha: _hasLyrics ? 1 : 0.3),
              ),
            ),
          AdaptiveIconButton(
            onPressed: () => _key.currentState?.openEndDrawer(),
            icon: Icon(AdaptiveIcons.queue, color: Colors.white),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- wide layout

  Widget _buildWide(MediaItem song) {
    return Row(
      children: [
        // LEFT: artwork + controls
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(48, 16, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Expanded(child: Center(child: _buildArtwork(song))),
                    const SizedBox(height: 28),
                    _buildTitleAndControls(context),
                  ],
                ),
              ),
            ),
          ),
        ),
        // RIGHT: lyrics (or placeholder)
        Expanded(
          flex: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 48, 32),
            child: LayoutBuilder(
              builder: (context, c) {
                if (_hasLyrics) {
                  return _lyricsBox(song, Size(c.maxWidth, c.maxHeight));
                }
                return Stack(
                  children: [
                    Center(
                      child: _lyricsLoading
                          ? const CircularProgressIndicator(
                          color: Colors.white)
                          : Text(
                        'No Lyrics',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    // Hidden probe so lyrics can be discovered
                    Offstage(child: _lyricsBox(song, Size.zero)),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------- narrow layout

  Widget _buildNarrow(MediaItem song) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final lyricsVisible = _showLyrics && _hasLyrics;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Stack(
                    children: [
                      // Artwork stays mounted (keeps palette updates alive)
                      Offstage(
                        offstage: lyricsVisible,
                        child: Center(child: _buildArtwork(song)),
                      ),
                      // Single, stable lyrics slot — never re-parented
                      Offstage(
                        offstage: !lyricsVisible,
                        child: _lyricsBox(
                          song,
                          lyricsVisible
                              ? Size(c.maxWidth, c.maxHeight - 32)
                              : Size.zero,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          _buildTitleAndControls(context, centered: false),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- pieces

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

  /// Tinder-style swipeable artwork: swipe left = next song, right =
  /// previous; neighbor cards pre-built underneath; queue-edge rubber-band;
  /// skip buttons trigger the same animation via the key. Palette updates
  /// from the front card only.
  Widget _buildArtwork(MediaItem song) {
    final items = List<MediaItem>.from(
        GetIt.I<MediaPlayer>().songList.map((src) => src.tag).whereType<MediaItem>());
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
          onSwipeNext: () => GetIt.I<MediaPlayer>().player.seekToNext(),
          onSwipePrevious: () =>
              GetIt.I<MediaPlayer>().player.seekToPrevious(),
          cardBuilder: (context, item, isFront) => SquareArtwork(
            song: item.extras ?? {'videoId': item.id, 'title': item.title},
            borderRadius: 16,
            onImageReady: isFront ? updateBackgroundColor : null,
          ),
        );
      },
    );
  }

  /// Icon button with a small dot underneath when active (shuffle / repeat).
  Widget _toggleButton({
    required IconData icon,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AdaptiveIconButton(
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 24,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.6),
          ),
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

  Widget _buildTitleAndControls(BuildContext context, {bool centered = false}) {
    final song = currentSong;
    if (song == null) return const SizedBox();
    final MediaPlayer mediaPlayer = context.watch<MediaPlayer>();
    final videoId = song.extras?['videoId'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
      centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        // Title / artist / favourite / menu
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  TextScroll(
                    song.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    mode: TextScrollMode.endless,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist ??
                        song.album ??
                        song.extras?['subtitle'] ??
                        '',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder(
              valueListenable: Hive.box('FAVOURITES').listenable(),
              builder: (context, value, child) {
                final Map? item = value.get(videoId);
                return AdaptiveIconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      item == null
                          ? AdaptiveIcons.heart
                          : AdaptiveIcons.heart_fill,
                      key: ValueKey(item != null),
                      size: 26,
                      color: item == null
                          ? Colors.white.withValues(alpha: 0.7)
                          : Colors.redAccent,
                    ),
                  ),
                  onPressed: () async {
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
                );
              },
            ),
            Builder(
              builder: (buttonContext) => AdaptiveIconButton(
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
                icon: Icon(
                  Icons.more_horiz,
                  size: 24,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Seek bar (7 styles, AppearancePrefs-driven) + tabular time labels
        ValueListenableBuilder(
          valueListenable: mediaPlayer.progressBarState,
          builder: (context, ProgressBarState value, child) {
            final totalMs = value.total.inMilliseconds;
            final posMs = value.current.inMilliseconds;
            final playing =
                mediaPlayer.buttonState.value == ButtonState.playing;
            const labelStyle = TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            );
            return Column(
              children: [
                ZenSlider(
                  style: ZenSliderStyle.fromName(
                      AppearancePrefs.sliderStyle.value),
                  value:
                  totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0,
                  isPlaying: playing,
                  onChanged: (v) => mediaPlayer.player
                      .seek(Duration(milliseconds: (v * totalMs).round())),
                  onChangeEnd: (v) => mediaPlayer.player
                      .seek(Duration(milliseconds: (v * totalMs).round())),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
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
        ),

        const SizedBox(height: 12),

        // Transport controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            StreamBuilder<bool>(
              stream: mediaPlayer.player.shuffleModeEnabledStream,
              initialData: false,
              builder: (context, snap) {
                final on = snap.data ?? false;
                return _toggleButton(
                  icon: Icons.shuffle,
                  active: on,
                  onPressed: () async {
                    await mediaPlayer.player.setShuffleModeEnabled(!on);
                    if (!on) await mediaPlayer.player.shuffle();
                  },
                );
              },
            ),
            AdaptiveIconButton(
              onPressed: () {
                if (!(_swipeKey.currentState?.swipePrev() ?? false)) {
                  mediaPlayer.player.seekToPrevious();
                }
              },
              icon: Icon(AdaptiveIcons.skip_previous,
                  size: 38, color: Colors.white),
            ),
            // Play / pause
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ValueListenableBuilder(
                valueListenable: mediaPlayer.buttonState,
                builder: (context, ButtonState value, child) {
                  if (value == ButtonState.loading) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 3),
                      ),
                    );
                  }
                  final playing = value == ButtonState.playing;
                  return IconButton(
                    onPressed: () => playing
                        ? mediaPlayer.player.pause()
                        : mediaPlayer.player.play(),
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Icon(
                        playing ? Icons.pause : Icons.play_arrow,
                        key: ValueKey(playing),
                        size: 40,
                        color: Colors.black,
                      ),
                    ),
                  );
                },
              ),
            ),
            AdaptiveIconButton(
              onPressed: () {
                if (!(_swipeKey.currentState?.swipeNext() ?? false)) {
                  mediaPlayer.player.seekToNext();
                }
              },
              icon: Icon(AdaptiveIcons.skip_next,
                  size: 38, color: Colors.white),
            ),
            ValueListenableBuilder(
              valueListenable: mediaPlayer.loopMode,
              builder: (context, value, child) {
                return _toggleButton(
                  icon: value == LoopMode.one
                      ? AdaptiveIcons.repeat_one
                      : AdaptiveIcons.repeat_all,
                  active: value != LoopMode.off,
                  onPressed: () => mediaPlayer.changeLoopMode(),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}