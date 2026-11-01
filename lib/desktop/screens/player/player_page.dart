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

import 'package:zenmusic/desktop/backdrop/windows_backdrop.dart';
import 'package:zenmusic/desktop/backdrop/windows_backdrop_service.dart';
import 'package:zenmusic/desktop/core/widgets/square_artwork.dart';
import 'package:zenmusic/desktop/core/widgets/video_backdrop.dart';
import 'package:zenmusic/desktop/screens/player/widgets/animated_gradient_bg.dart';
import 'package:zenmusic/desktop/screens/player/widgets/lyrics_box.dart';
import 'package:zenmusic/desktop/screens/player/widgets/queue_list.dart';
import 'package:zenmusic/desktop/screens/player/widgets/swipe_artwork_stack.dart';
import 'package:zenmusic/desktop/screens/player/player_skins.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_canvas.dart'; // SP-9
import 'package:zenmusic/desktop/themes/colors.dart';
import 'package:zenmusic/desktop/themes/dark.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality.dart';
// TODO: change this file name if your service file is named differently.
import 'package:zenmusic/desktop/lossless/lossless_service.dart';

// ════════════════════════════════════════════════════════════════════
// ICON TABLE — every icon the page uses lives here.
// ════════════════════════════════════════════════════════════════════
class _Ic {
  _Ic._();
  static const chevronDown = FluentIcons.chevron_down_24_regular;
  static const queue = FluentIcons.text_bullet_list_ltr_24_regular;
  static const lyrics = FluentIcons.text_quote_24_regular; // empty-state only
  static const lyricsBtn = Icons.lyrics_rounded; // LastWave lyrics button
  static const hq = Icons.high_quality_rounded; // LastWave quality "HQ" badge
  static const heart = FluentIcons.heart_24_regular;
  static const heartFill = FluentIcons.heart_24_filled;
  static const more = FluentIcons.more_vertical_24_regular; // mobile
  static const moreH = FluentIcons.more_horizontal_24_regular; // desktop
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
const Color _kFallbackTint = Color(0xFF5B3FD1);

/// MOBILE (Android / iOS) uses the LastWave-style player.
/// DESKTOP (Windows / macOS / Linux) keeps the original glass-dock player.
/// Every method below is suffixed `Mobile` or `Desktop` accordingly.

/// LastWave's player has no heart button (double-tap the artwork to like).
/// Flip to `true` to put a heart button next to the lyrics button again.
const bool _kShowHeartButton = false;

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
  List<Color> paletteColors = []; // desktop gradient
  bool fetchedSong = false;
  late MediaItem? currentSong;
  bool _hasLyrics = false;
  bool _lyricsLoading = true;
  bool _showLyrics = false; // narrow layout: swap artwork <-> lyrics
  final GlobalKey<State> _lyricsBoxKey = GlobalKey();

  // Seek bar: live finger position while dragging (null = follow playback).
  double? _seekDrag;

  // Double-tap-to-like heart burst on the artwork.
  bool _heartBurst = false;

  // Video backdrop: synchronized song-video behind the artwork.
  String? _videoBackdropUrl;
  Map<String, String> _videoHeaders = const {};

  // SP-76: Spotify canvas state. [_isSpotifyCanvas] marks the current
  // backdrop as a short canvas loop (looped whole, never sync-seeked);
  // [_canvasReady] flips once its first frame is on screen and the still
  // cover hands its pixels over — the canvas-hero contract: the cover is
  // the placeholder while the video warms up, and it comes back the
  // moment the canvas leaves (no canvas / error / next track).
  bool _isSpotifyCanvas = false;
  bool _canvasReady = false;

  bool get _canvasOwnsScreen =>
      _isSpotifyCanvas && _videoBackdropUrl != null && _canvasReady;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

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
          _seekDrag = null;
          _videoBackdropUrl = null; // stale video must not linger
          _isSpotifyCanvas = false; // stale canvas must not linger
          _canvasReady = false; // cover returns until the next canvas renders
        });
      }
      _maybeLoadVideoBackdrop();
    }
  }

  /// SP-76: Spotify canvas for every track while a Spotify session is up
  /// (direct id when the song carries one, title/artist resolve otherwise),
  /// else the stock behaviour — Android (YT video) backdrop. Anonymous
  /// sessions never ask for a canvas, so not-logged-in looks exactly as
  /// it did before.
  Future<void> _maybeLoadVideoBackdrop() async {
    if (!AppearancePrefs.canvasEnabled.value) return;
    final id = currentSong?.id ?? '';
    final song = currentSong;
    final spUri = song?.extras?['spotifyUri'] as String?;

    // 1. Spotify Canvas
    if (song != null && SpotifyAuth.instance.loggedIn.value) {
      final directMs = song.duration?.inMilliseconds ?? 0;
      final totalMs = directMs > 0
          ? directMs
          : GetIt.I<MediaPlayer>().progressBarState.value.total.inMilliseconds;
      final url = await SpotifyCanvas.instance.resolveCanvasUrl(
        spotifyUri: (spUri?.isNotEmpty ?? false) ? spUri : null,
        title: song.title,
        artist:
            (song.artist ?? song.album ?? song.extras?['subtitle'] ?? '')
                .toString(),
        album: song.album,
        durationMs: totalMs > 0 ? totalMs : null,
      );
      if (!mounted || currentSong?.id != id) return;
      if (url != null) {
        setState(() {
          _videoBackdropUrl = url;
          _videoHeaders = const {};
          _isSpotifyCanvas = true;
        });
        if (Platform.isWindows) {
          // The canvas owns the screen — ask the blurred Windows video
          // backdrop to stand down for this track (media_player re-feeds
          // it on the next track change).
          WindowsBackdropService.instance.trackChanged(videoId: null);
        }
        return;
      }
    }

    // 2. YouTube Music video backdrop (Android only) — unchanged.
    if (!Platform.isAndroid) return;
    if (id.length != 11) return;

    final streams = await InnertubexBridge.extractVideo(id, maxHeight: 720);
    if (!mounted || currentSong?.id != id) return;
    if (streams?.videoUrl != null) {
      setState(() {
        _videoBackdropUrl = streams!.videoUrl;
        _videoHeaders = streams.headers;
        _isSpotifyCanvas = false;
      });
    }
  }

  /// The Windows video backdrop stood down while the canvas owned the
  /// screen — hand this track back to it when the canvas fails. Spotify-
  /// engine tracks never get the backdrop (media_player's guard), so they
  /// are skipped here too.
  void _giveWindowsBackdropBack() {
    if (!Platform.isWindows) return;
    final spUri = currentSong?.extras?['spotifyUri'] as String?;
    if (spUri != null && spUri.isNotEmpty) return;
    WindowsBackdropService.instance.trackChanged(videoId: currentSong?.id);
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final mm = d.inMinutes.remainder(60).toString();
    // Mobile (LastWave style): 2:47.  Desktop: 02:47.
    final m = (_isMobile && d.inHours == 0) ? mm : mm.padLeft(2, '0');
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
      color = palette.vibrantColor?.color ?? palette.dominantColor?.color;
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

  Color get _tint => color ?? _kFallbackTint;

  // ------------------------------------------------ LastWave colour roles
  // LastWave derives a Material-You style scheme from the cover art:
  // a pale accent (seek bar / play button / titles), a mid-dark tonal
  // surface (prev / next) and a near-black surface (chips, bottom row).

  HSLColor get _hsl => HSLColor.fromColor(_tint);

  Color _role(double sat, double light) => _hsl
      .withSaturation(_hsl.saturation.clamp(sat * 0.5, sat).toDouble())
      .withLightness(light)
      .toColor();

  Color get _accent => _role(0.55, 0.83); // seek bar, play button, header
  Color get _onAccent => _role(0.50, 0.13); // icon on the play button
  Color get _tonal => _role(0.22, 0.27); // prev / next
  Color get _tonalActive => _role(0.30, 0.31); // shuffle / repeat when on
  Color get _accentSoft => Color.lerp(_accent, Colors.white, 0.45)!;
  static final Color _surface = Colors.white.withValues(alpha: 0.075);

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

  Future<void> _toggleFavourite(MediaItem song) async {
    final extras = song.extras;
    final id = extras?['videoId'];
    if (extras == null || id == null) return;
    HapticFeedback.lightImpact();
    final box = Hive.box('FAVOURITES');
    if (box.get(id) == null) {
      await box.put(id, {
        ...extras,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      await box.delete(id);
    }
  }

  /// Double-tap on the artwork = like (never un-likes by accident).
  Future<void> _doubleTapLike(MediaItem song) async {
    final extras = song.extras;
    final id = extras?['videoId'];
    if (extras != null && id != null) {
      final box = Hive.box('FAVOURITES');
      if (box.get(id) == null) {
        HapticFeedback.lightImpact();
        await box.put(id, {
          ...extras,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
    if (!mounted) return;
    setState(() => _heartBurst = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) setState(() => _heartBurst = false);
  }

  void _openMore(BuildContext buttonContext) {
    final song = GetIt.I<MediaPlayer>().currentSongNotifier.value;
    if (song?.extras == null) return;
    final RenderBox renderBox = buttonContext.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    Modals.showPlayerOptionsModal(
      context,
      song!.extras!,
      buttonPosition: position,
      buttonSize: size,
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
              final total = mediaPlayer.songList.length > 0
                  ? mediaPlayer.songList.length
                  : 1;

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
                body: Stack(
                  children: [
                    // SP-33: video backdrop under custom skins too
                    if (Platform.isWindows) const WindowsVideoBackdrop(),
                    PlayerSkinView(skin: skin, ctx: ctx),
                  ],
                ),
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
                  if (_isMobile)
                  // LastWave look: near-black base, only a whisper of the
                  // cover colour behind the artwork.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 700),
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.30),
                                radius: 1.0,
                                colors: [
                                  _tint.withValues(alpha: 0.16),
                                  _tint.withValues(alpha: 0.05),
                                  Colors.black,
                                ],
                                stops: const [0, 0.55, 1],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                  // Desktop: animated palette gradient (own repaint layer)
                    Positioned.fill(
                      child: RepaintBoundary(
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
                    ),

                  // SP-33: Windows video backdrop (muted, 16:9, blurred)
                  const WindowsVideoBackdrop(),

                  // Video backdrop: a full-length YT music video locked to
                  // the audio position — or, SP-76, a Spotify canvas that
                  // loops as a short silent clip while it owns the screen.
                  if (_videoBackdropUrl != null)
                    Positioned.fill(
                      child: ValueListenableBuilder<ButtonState>(
                        valueListenable: mediaPlayerOf(context).buttonState,
                        builder: (context, state, _) => VideoBackdrop(
                          streamUrl: _videoBackdropUrl!,
                          playing: state == ButtonState.playing,
                          shortLoop: _isSpotifyCanvas,
                          synchronized: !_isSpotifyCanvas,
                          positionStream: _isSpotifyCanvas
                              ? null
                              : mediaPlayerOf(context).player.positionStream,
                          posterUrl: song.artUri?.toString(),
                          httpHeaders: _videoHeaders,
                          onReadyChanged: (ready) {
                            if (mounted && ready != _canvasReady) {
                              setState(() => _canvasReady = ready);
                            }
                          },
                          onUnavailable: (_) {
                            if (mounted) {
                              setState(() {
                                _videoBackdropUrl = null;
                                _isSpotifyCanvas = false;
                                _canvasReady = false;
                              });
                              _giveWindowsBackdropBack();
                            }
                          },
                        ),
                      ),
                    ),

                  // Desktop only: cover-colour ambient wash (top-centre glow)
                  if (!_isMobile)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 700),
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.45),
                                radius: 1.05,
                                colors: [
                                  _tint.withValues(alpha: 0.38),
                                  _tint.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Legibility scrim. Desktop: always. Mobile: only over video.
                  if (!_isMobile || _videoBackdropUrl != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _isMobile
                                  ? [
                                Colors.black.withValues(alpha: 0.25),
                                Colors.black.withValues(alpha: 0.45),
                                Colors.black.withValues(alpha: 0.80),
                              ]
                                  : [
                                Colors.black.withValues(alpha: 0.12),
                                Colors.black.withValues(alpha: 0.30),
                                Colors.black.withValues(alpha: 0.72),
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
                        _topBar(song),
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
  // [ v ]        NOW PLAYING        [ ⋮ ]
  //              <playlist/album>

  Widget _topBar(MediaItem song) =>
      _isMobile ? _buildTopBarMobile(song) : _buildTopBarDesktop(song);

  Widget _playerColumn(MediaItem song, BoxConstraints box,
      {required bool swap}) =>
      _isMobile
          ? _buildPlayerColumnMobile(song, box, swap: swap)
          : _buildPlayerColumnDesktop(song, box, swap: swap);

  Widget _buildTopBarMobile(MediaItem song) {
    final subtitle = song.album;
    final wide = MediaQuery.of(context).size.width >= 900;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _Squircle(
                width: 46,
                height: 46,
                radius: 17,
                color: _surface,
                tooltip: 'Close',
                onTap: () => context.pop(),
                child: const Icon(_Ic.chevronDown,
                    size: 26, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 112),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _key.currentState?.openEndDrawer(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _accentSoft,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The queue lives in the end drawer (Q / tap the title).
                  // On wide desktop windows keep an explicit button too.
                  if (wide) ...[
                    _Squircle(
                      width: 46,
                      height: 46,
                      radius: 17,
                      color: _surface,
                      tooltip: 'Queue (Q)',
                      onTap: () => _key.currentState?.openEndDrawer(),
                      child: const Icon(_Ic.queue,
                          size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Builder(
                    builder: (buttonContext) => _Squircle(
                      width: 46,
                      height: 46,
                      radius: 17,
                      color: _surface,
                      tooltip: 'More',
                      onTap: () => _openMore(buttonContext),
                      child: const Icon(_Ic.more,
                          size: 24, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                        _playerColumn(song, inner, swap: false),
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

    final hPad = box.maxWidth >= 600 ? 40.0 : (_isMobile ? 20.0 : 22.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(
            builder: (context, inner) =>
                _playerColumn(song, inner, swap: true),
          ),
        ),
      ),
    );
  }

  /// Artwork (or lyrics) + title/artist + seek + transport + bottom row.
  /// Artwork takes the height that is left; if even the minimum does not
  /// fit, the column scrolls instead of overflowing.
  ///
  /// Smooth swap: artwork and lyrics both stay mounted and cross-fade with
  /// a slide-up (lyrics rise from below, artwork drifts up + shrinks).
  Widget _buildPlayerColumnMobile(MediaItem song, BoxConstraints box,
      {required bool swap}) {
    const controlsH = 318.0; // info + seek + transport + bottom row + gaps
    const gap = 26.0;
    final room = box.maxHeight - controlsH - gap;
    final side = room.clamp(150.0, min(box.maxWidth, 520.0)).toDouble();
    final needsScroll = side + gap + controlsH > box.maxHeight + 0.5;
    final lyricsVisible = swap && _showLyrics && _hasLyrics;
    final mobile = Platform.isAndroid || Platform.isIOS;

    final media = SizedBox(
      width: box.maxWidth,
      height: side,
      child: Stack(
        children: [
          // Artwork stays mounted (keeps palette updates alive).
          Positioned.fill(
            child: _SlideFade(
              show: !lyricsVisible,
              dy: -0.04,
              fromScale: 0.94,
              child: Center(
                child: RepaintBoundary(
                  // SP-76: while the Spotify canvas is on screen the still
                  // cover fades out in step with the video's fade-in and
                  // hands the pixels over (canvas-hero handover). Opacity
                  // only — swipes and double-tap-like keep working.
                  child: AnimatedOpacity(
                    opacity: _canvasOwnsScreen ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () => _doubleTapLike(song),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 600),
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(36),
                          boxShadow: [
                            BoxShadow(
                              color: _tint.withValues(alpha: 0.32),
                              blurRadius: mobile ? 44 : 60,
                              spreadRadius: -10,
                              offset: const Offset(0, 24),
                            ),
                          ],
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildArtwork(song, breathing: true),
                            // Double-tap heart burst.
                            IgnorePointer(
                              child: Center(
                                child: AnimatedScale(
                                  scale: _heartBurst ? 1.0 : 0.4,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedOpacity(
                                    opacity: _heartBurst ? 1 : 0,
                                    duration: const Duration(milliseconds: 220),
                                    child: Icon(
                                      _Ic.heartFill,
                                      size: min(side * 0.34, 120),
                                      color: Colors.white,
                                      shadows: const [
                                        Shadow(
                                            color: Colors.black54,
                                            blurRadius: 24),
                                      ],
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
                ),
              ),
            ),
          ),
          // Narrow layout: one stable lyrics slot, never re-parented.
          // Always real size so it does not collapse while fading out.
          if (swap)
            Positioned.fill(
              child: _SlideFade(
                show: lyricsVisible,
                dy: 0.08,
                child: _lyricsBox(song, Size(box.maxWidth, side)),
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
        _buildInfoRowMobile(song, swap: swap),
        const SizedBox(height: 14),
        _buildSeekBarMobile(),
        const SizedBox(height: 14),
        _buildTransportMobile(),
        const SizedBox(height: 18),
        _buildBottomRowMobile(song),
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
  /// previous. [breathing] (classic layout only) shrinks the cover slightly
  /// while paused and restores it on play. Skins call without it.
  Widget _buildArtwork(MediaItem song, {bool breathing = false}) {
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
        final stack = SwipeArtworkStack(
          key: _swipeKey,
          current: song,
          next: next,
          previous: prev,
          active: active,
          onSwipeNext: () => GetIt.I<MediaPlayer>().skipNext(), // SP-5b
          onSwipePrevious: () => GetIt.I<MediaPlayer>().skipPrevious(), // SP-5b
          cardBuilder: (context, item, isFront) => SquareArtwork(
            song: item.extras ?? {'videoId': item.id, 'title': item.title},
            borderRadius: _isMobile ? 36 : 16,
            onImageReady: isFront ? updateBackgroundColor : null,
          ),
        );
        if (!breathing) return stack;
        return AnimatedScale(
          scale: active ? 1.0 : (_isMobile ? 0.9 : 0.93),
          duration: const Duration(milliseconds: 520),
          curve: Curves.easeOutCubic,
          child: stack,
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

  /// WIDE layout: dark rounded panel on the right. Placeholder and lyrics
  /// cross-fade; the lyrics box stays in ONE slot so it is never rebuilt.
  Widget _buildLyricsPanel(MediaItem song) {
    return _Glass(
      radius: _isMobile ? 32 : 30,
      child: LayoutBuilder(
        builder: (context, c) {
          final boxSize = Size(
            max(0.0, c.maxWidth - 16),
            max(0.0, c.maxHeight - 16),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: _SlideFade(
                  show: !_hasLyrics,
                  dy: 0,
                  fromScale: 0.96,
                  child: Center(
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
                ),
              ),
              Positioned.fill(
                child: _SlideFade(
                  show: _hasLyrics,
                  dy: 0.05,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: _lyricsBox(song, boxSize),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------ info row
  //  Odysseus                                   [ lyrics ]
  //  [ Ludwig Göransson ]

  Widget _buildInfoRowMobile(MediaItem song, {required bool swap}) {
    final videoId = song.extras?['videoId'];
    final artist =
    (song.artist ?? song.album ?? song.extras?['subtitle'] ?? '').toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextScroll(
                  song.title,
                  style: const TextStyle(
                    fontSize: 31,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                  mode: TextScrollMode.endless,
                ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _role(0.30, 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: _accentSoft,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_kShowHeartButton)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ValueListenableBuilder(
              valueListenable: Hive.box('FAVOURITES').listenable(),
              builder: (context, value, child) {
                final liked = value.get(videoId) != null;
                return _Squircle(
                  width: 48,
                  height: 48,
                  radius: 18,
                  color: _surface,
                  tooltip:
                  liked ? 'Remove from favourites' : 'Add to favourites',
                  onTap: () => _toggleFavourite(song),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      liked ? _Ic.heartFill : _Ic.heart,
                      key: ValueKey(liked),
                      size: 24,
                      color: liked
                          ? _kHeartRed
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                );
              },
            ),
          ),
        // Wide layout already shows lyrics in the side panel.
        if (swap)
          Opacity(
            opacity: _hasLyrics ? 1 : 0.4,
            child: _Squircle(
              width: 48,
              height: 48,
              radius: 18,
              color: (_showLyrics && _hasLyrics) ? _accent : _surface,
              tooltip: 'Lyrics (L)',
              onTap: _hasLyrics ? _toggleLyrics : null,
              child: Icon(
                _Ic.lyricsBtn,
                size: 26,
                color: (_showLyrics && _hasLyrics)
                    ? _onAccent
                    : Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- seek bar

  Widget _buildSeekBarMobile() {
    final mediaPlayer = mediaPlayerOf(context);
    return ValueListenableBuilder(
      valueListenable: mediaPlayer.progressBarState,
      builder: (context, ProgressBarState value, child) {
        final totalMs = value.total.inMilliseconds;
        final posMs = value.current.inMilliseconds;
        final playing = mediaPlayer.buttonState.value == ButtonState.playing;
        final double live =
        totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0).toDouble() : 0.0;
        final double fraction = (_seekDrag ?? live).clamp(0.0, 1.0).toDouble();
        final shownMs = _seekDrag != null ? (fraction * totalMs).round() : posMs;
        final remainMs = max(0, totalMs - shownMs);
        final labelStyle = TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

        void commit(double v) {
          if (totalMs > 0) {
            mediaPlayer.seekTo(Duration(milliseconds: (v * totalMs).round()));
          }
          setState(() => _seekDrag = null);
        }

        return Column(
          children: [
            _ChunkySeekBar(
              fraction: fraction,
              enabled: totalMs > 0,
              active: _accent,
              inactive: Colors.white.withValues(alpha: 0.20),
              onDrag: (v) => setState(() => _seekDrag = v),
              onCommit: commit,
              onCancel: () => setState(() => _seekDrag = null),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatMs(shownMs), style: labelStyle),
                  Text('\u2212${_formatMs(remainMs)}', style: labelStyle),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------ transport
  //   [ |< ]  [  ||  ]  [ >| ]

  Widget _buildTransportMobile() {
    final mediaPlayer = mediaPlayerOf(context);
    return SizedBox(
      height: 74,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Squircle(
            width: 56,
            height: 56,
            radius: 19,
            color: _tonal,
            tooltip: 'Previous (Ctrl+←)',
            pressScale: 0.85,
            onTap: _skipPrevious,
            child: Icon(_Ic.previous,
                size: 28, color: Colors.white.withValues(alpha: 0.94)),
          ),
          const SizedBox(width: 16),
          ValueListenableBuilder<ButtonState>(
            valueListenable: mediaPlayer.buttonState,
            builder: (context, state, _) {
              final loading = state == ButtonState.loading;
              final playing = state == ButtonState.playing;
              return _Squircle(
                width: 74,
                height: 72,
                radius: 28,
                color: _accent,
                tooltip: playing ? 'Pause (Space)' : 'Play (Space)',
                pressScale: 0.9,
                onTap: () {
                  HapticFeedback.selectionClick();
                  mediaPlayer.togglePlayPause(); // SP-5b
                },
                child: loading
                    ? SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: _onAccent, strokeWidth: 3),
                )
                    : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    playing ? _Ic.pause : _Ic.play,
                    key: ValueKey(playing),
                    size: 34,
                    color: _onAccent,
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          _Squircle(
            width: 56,
            height: 56,
            radius: 19,
            color: _tonal,
            tooltip: 'Next (Ctrl+→)',
            pressScale: 0.85,
            onTap: _skipNext,
            child: Icon(_Ic.next,
                size: 28, color: Colors.white.withValues(alpha: 0.94)),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- bottom row
  //  [ shuffle ]  [ HQ  FLAC 24/96 ]  [ repeat ]

  Widget _buildBottomRowMobile(MediaItem song) {
    final mediaPlayer = mediaPlayerOf(context);
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            flex: 10,
            child: StreamBuilder<bool>(
              stream: mediaPlayer.player.shuffleModeEnabledStream,
              initialData: false,
              builder: (context, snap) {
                final on = snap.data ?? false;
                return _ModeBtn(
                  icon: _Ic.shuffle,
                  active: on,
                  activeColor: _tonalActive,
                  restColor: _surface,
                  tooltip: on ? 'Shuffle on' : 'Shuffle off',
                  onTap: () async {
                    await mediaPlayer.player.setShuffleModeEnabled(!on);
                    if (!on) await mediaPlayer.player.shuffle();
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 13,
            // Rebuilds when the lossless service reports a served tier.
            child: ListenableBuilder(
              listenable: LosslessService.servedRevision,
              builder: (context, _) {
                final q = _AudioQuality.of(song);
                return _QualityPill(
                  info: q,
                  color: _surface,
                  onTap: () => _openQuality(song),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: ValueListenableBuilder(
              valueListenable: mediaPlayer.loopMode,
              builder: (context, value, child) {
                return _ModeBtn(
                  icon: value == LoopMode.one ? _Ic.repeatOne : _Ic.repeatAll,
                  active: value != LoopMode.off,
                  activeColor: _tonalActive,
                  restColor: _surface,
                  tooltip: switch (value) {
                    LoopMode.one => 'Repeat one',
                    LoopMode.all => 'Repeat all',
                    _ => 'Repeat off',
                  },
                  onTap: () => mediaPlayer.changeLoopMode(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  // DESKTOP — original player (unchanged look)
  // ════════════════════════════════════════════════════════════════

  Widget _buildTopBarDesktop(MediaItem song) {
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
                    letterSpacing: 2.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.6),
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

  Widget _buildPlayerColumnDesktop(MediaItem song, BoxConstraints box,
      {required bool swap}) {
    const controlsH = 352.0; // info + quality + dock + gaps
    const gap = 18.0;
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
          Positioned.fill(
            child: _SlideFade(
              show: !lyricsVisible,
              dy: -0.04,
              fromScale: 0.94,
              child: Center(
                child: RepaintBoundary(
                  // SP-76: same cover-to-canvas handover as the mobile
                  // column — the still cover fades out while the looping
                  // canvas behind owns the screen, and returns the moment
                  // the canvas leaves.
                  child: AnimatedOpacity(
                    opacity: _canvasOwnsScreen ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOut,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: _tint.withValues(alpha: 0.50),
                            blurRadius: 64,
                            spreadRadius: -8,
                            offset: const Offset(0, 26),
                          ),
                        ],
                      ),
                      child: _buildArtwork(song, breathing: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (swap)
            Positioned.fill(
              child: _SlideFade(
                show: lyricsVisible,
                dy: 0.08,
                child: _lyricsBox(song, Size(box.maxWidth, side)),
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
        _buildInfoRowDesktop(song),
        const SizedBox(height: 8),
        _buildQualityRowDesktop(song, swap: swap),
        const SizedBox(height: 12),
        _buildDockDesktop(),
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

  /// Frosted dock holding the seek bar and the transport row.
  Widget _buildDockDesktop() {
    return _Glass(
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSeekBarDesktop(),
            const SizedBox(height: 6),
            _buildTransportDesktop(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowDesktop(MediaItem song) {
    final mediaPlayer = mediaPlayerOf(context);
    final videoId = song.extras?['videoId'];
    return SizedBox(
      height: 66,
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
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.6,
                  ),
                  mode: TextScrollMode.endless,
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist ?? song.album ?? song.extras?['subtitle'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
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
              icon: _Ic.moreH,
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

  Widget _buildQualityRowDesktop(MediaItem song, {required bool swap}) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // Rebuilds when the lossless service reports a served tier.
          ListenableBuilder(
            listenable: LosslessService.servedRevision,
            builder: (context, _) {
              final q = _AudioQuality.of(song);
              return _QualityChip(info: q, onTap: () => _openQuality(song));
            },
          ),
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

  Widget _buildSeekBarDesktop() {
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

  Widget _buildTransportDesktop() {
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
              glow: _tint,
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

  /// Short detail: bitrate, else sample rate, else codec.
  String? get chipDetail {
    if (bitrateKbps != null) return '$bitrateKbps kbps';
    if (sampleRateHz != null) return _khz(sampleRateHz!);
    return codec;
  }

  /// LastWave-style badge text: "FLAC 24/96", "AAC 128", "MP3 320".
  String get pillText {
    final c = codec;
    if (c != null && bitDepth != null && sampleRateHz != null) {
      return '$c $bitDepth/${_khzNum(sampleRateHz!)}';
    }
    if (c != null && bitrateKbps != null) return '$c $bitrateKbps';
    if (bitrateKbps != null) return '$bitrateKbps kbps';
    if (c != null) return c;
    return label;
  }

  static String _khzNum(int hz) {
    final k = hz / 1000;
    return k == k.roundToDouble() ? '${k.toInt()}' : k.toStringAsFixed(1);
  }

  static String _khz(int hz) => '${_khzNum(hz)} kHz';

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

  /// The tier the lossless service actually served for this song.
  static _AudioQuality _fromTier(LosslessQuality tier) {
    switch (tier) {
      case LosslessQuality.mp3_320:
        return const _AudioQuality(
          tier: _Tier.high,
          codec: 'MP3',
          bitrateKbps: 320,
          source: 'Qobuz',
        );
      case LosslessQuality.flacCd:
        return const _AudioQuality(
          tier: _Tier.lossless,
          codec: 'FLAC',
          sampleRateHz: 44100,
          bitDepth: 16,
          source: 'Qobuz',
        );
      case LosslessQuality.flacHiRes96:
        return const _AudioQuality(
          tier: _Tier.hiRes,
          codec: 'FLAC',
          sampleRateHz: 96000,
          bitDepth: 24,
          source: 'Qobuz',
        );
      case LosslessQuality.flacHiResMax:
        return const _AudioQuality(
          tier: _Tier.hiRes,
          codec: 'FLAC',
          sampleRateHz: 192000,
          bitDepth: 24,
          source: 'Qobuz',
        );
    }
  }

  static _AudioQuality of(MediaItem song) {
    // Lossless service served this song -> exact tier it really got.
    final served = LosslessService.instance.servedTierFor(song.id);
    if (served != null) return _fromTier(served);

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

/// Centre pill of the bottom row: [HQ]  FLAC 24/96
class _QualityPill extends StatelessWidget {
  const _QualityPill({
    required this.info,
    required this.color,
    required this.onTap,
  });
  final _AudioQuality info;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Squircle(
      height: 46,
      radius: 20,
      color: color,
      tooltip: 'Audio quality',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_Ic.hq,
                  size: 22, color: Colors.white.withValues(alpha: 0.92)),
              const SizedBox(width: 8),
              Text(
                info.pillText,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.95),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
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

/// Fade + slide + scale in one go. Keeps the child mounted (state and
/// GlobalKeys survive) and blocks touches while hidden.
class _SlideFade extends StatelessWidget {
  const _SlideFade({
    required this.show,
    required this.child,
    this.dy = 0.06,
    this.fromScale = 1.0,
    this.ms = 480,
  });

  final bool show;
  final Widget child;
  final double dy; // hidden offset as a fraction of the child's height
  final double fromScale;
  final int ms;

  @override
  Widget build(BuildContext context) {
    final d = Duration(milliseconds: ms);
    const c = Curves.easeOutCubic;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: d,
        curve: c,
        child: AnimatedSlide(
          offset: show ? Offset.zero : Offset(0, dy),
          duration: d,
          curve: c,
          child: AnimatedScale(
            scale: show ? 1 : fromScale,
            duration: d,
            curve: c,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Dark rounded panel (wide-layout lyrics). Lighter blur on phones
/// (BackdropFilter is the most expensive thing on the page) and isolated
/// into its own repaint layer.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.radius = 24, double? blur})
      : _blur = blur;
  final Widget child;
  final double radius;
  final double? _blur;

  @override
  Widget build(BuildContext context) {
    final mobile = Platform.isAndroid || Platform.isIOS;
    final blur = _blur ?? (mobile ? 12.0 : 22.0);
    final r = BorderRadius.circular(radius);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: mobile ? 0.06 : 0.07),
              borderRadius: r,
              border: Border.all(
                  color: Colors.white.withValues(alpha: mobile ? 0.08 : 0.12)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Circular icon button (only the quality sheet's close button uses it now).
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

/// LastWave's building block: a rounded-square ("squircle") button with
/// press-scale, hover lift (desktop) and tooltip. Leave [width] null to
/// fill the parent's width (inside an Expanded).
class _Squircle extends StatefulWidget {
  const _Squircle({
    required this.child,
    required this.onTap,
    required this.color,
    required this.height,
    this.width,
    this.radius = 18,
    this.tooltip,
    this.pressScale = 0.92,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final double height;
  final double? width;
  final double radius;
  final String? tooltip;
  final double pressScale;

  @override
  State<_Squircle> createState() => _SquircleState();
}

class _SquircleState extends State<_Squircle> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = _hover && enabled
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.07), widget.color)
        : widget.color;

    Widget btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? widget.pressScale : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: widget.width,
            height: widget.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: widget.child,
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

/// Shuffle / repeat button: dark rounded rectangle, tinted + dot when on.
class _ModeBtn extends StatelessWidget {
  const _ModeBtn({
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.restColor,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool active;
  final Color activeColor;
  final Color restColor;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return _Squircle(
      height: 46,
      radius: 20,
      color: active ? activeColor : restColor,
      tooltip: tooltip,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon,
              size: 22,
              color: Colors.white.withValues(alpha: active ? 1 : 0.85)),
          Positioned(
            bottom: 5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? Colors.white : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// LastWave seek bar: thick rounded capsule that stops short of a tall
/// vertical thumb, then a thick inactive capsule and a tiny end marker.
class _ChunkySeekBar extends StatelessWidget {
  const _ChunkySeekBar({
    required this.fraction,
    required this.enabled,
    required this.active,
    required this.inactive,
    required this.onDrag,
    required this.onCommit,
    required this.onCancel,
  });

  final double fraction;
  final bool enabled;
  final Color active;
  final Color inactive;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onCommit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double at(Offset p) => w <= 0 ? 0 : (p.dx / w).clamp(0.0, 1.0);
        return MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: enabled ? (d) => onCommit(at(d.localPosition)) : null,
            onHorizontalDragStart:
            enabled ? (d) => onDrag(at(d.localPosition)) : null,
            onHorizontalDragUpdate:
            enabled ? (d) => onDrag(at(d.localPosition)) : null,
            onHorizontalDragEnd: enabled
                ? (_) => onCommit(fraction)
                : null,
            onHorizontalDragCancel: enabled ? onCancel : null,
            child: SizedBox(
              height: 44,
              width: double.infinity,
              child: CustomPaint(
                painter: _SeekPainter(
                  fraction: fraction,
                  active: active,
                  inactive: inactive,
                  dim: !enabled,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.fraction,
    required this.active,
    required this.inactive,
    required this.dim,
  });

  final double fraction;
  final Color active;
  final Color inactive;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final centerY = size.height / 2;
    const trackH = 14.0;
    const thumbW = 5.0;
    const thumbH = 38.0;
    const clearance = 9.0;
    final r = const Radius.circular(trackH / 2);

    final fg = dim ? active.withValues(alpha: 0.5) : active;

    final rawX = fraction * width;
    final thumbCx = width > thumbW
        ? rawX.clamp(thumbW / 2, width - thumbW / 2).toDouble()
        : width / 2;
    final activeEnd = (thumbCx - clearance).clamp(0.0, width).toDouble();
    final inactiveStart = (thumbCx + clearance).clamp(0.0, width).toDouble();

    // Active capsule.
    if (activeEnd > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, centerY - trackH / 2, activeEnd,
            centerY + trackH / 2, r),
        Paint()..color = fg,
      );
    }

    // Inactive capsule.
    if (inactiveStart < width) {
      canvas.drawRRect(
        RRect.fromLTRBR(inactiveStart, centerY - trackH / 2, width,
            centerY + trackH / 2, r),
        Paint()..color = inactive,
      );
    }

    // End-of-track marker.
    final endX = width - trackH / 2;
    if (inactiveStart < endX) {
      canvas.drawCircle(
          Offset(endX, centerY), 2, Paint()..color = fg.withValues(alpha: 0.9));
    }

    // Thumb: soft dark halo for separation + the pill itself.
    final thumbRect = RRect.fromLTRBR(
      thumbCx - thumbW / 2,
      centerY - thumbH / 2,
      thumbCx + thumbW / 2,
      centerY + thumbH / 2,
      const Radius.circular(thumbW / 2),
    );
    canvas.drawRRect(
      thumbRect.inflate(1),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawRRect(thumbRect, Paint()..color = fg);
  }

  @override
  bool shouldRepaint(_SeekPainter o) =>
      o.fraction != fraction ||
          o.active != active ||
          o.inactive != inactive ||
          o.dim != dim;
}


// ════════════════════════════════════════════════════════════════════
// DESKTOP-ONLY WIDGETS (original player)
// ════════════════════════════════════════════════════════════════════

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

/// Big white play / pause button with loading ring and cover-colour glow.
class _PlayButton extends StatefulWidget {
  const _PlayButton({
    required this.state,
    required this.onPressed,
    this.glow = _kFallbackTint,
  });
  final ButtonState state;
  final VoidCallback onPressed;
  final Color glow;

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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.glow.withValues(alpha: playing ? 0.55 : 0.25),
                    blurRadius: 30,
                    spreadRadius: 1,
                  ),
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

/// Small rounded action pill (lyrics toggle on narrow desktop layouts).
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