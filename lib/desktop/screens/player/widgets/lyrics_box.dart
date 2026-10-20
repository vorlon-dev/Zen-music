// ZenMusic Desktop — ported from Echo Music (GPL-3.0), player/widgets/lyrics_box.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// DEVIATION: lyric text size / line spacing / alignment read AppearancePrefs
// (hydrated user preferences). File-local AnimatedBuilder intentionally
// shadows Flutter's — verbatim upstream design, do not remove.
// SP-10: Added Spotify Color Lyrics fallback and fixed the position stream
// to support the hidden WebView2 Spotify engine via progressBarState.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get_it/get_it.dart';
import 'package:zenmusic/desktop/models/lyrics_model.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_lyrics.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:loading_indicator_m3e/loading_indicator_m3e.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class LyricsBox extends StatefulWidget {
  const LyricsBox({
    required this.currentSong,
    required this.size,
    this.onLyricsFound,
    super.key,
  });
  final MediaItem currentSong;
  final Size size;
  final Function(bool)? onLyricsFound;

  @override
  State<LyricsBox> createState() => _LyricsBoxState();
}

class _LyricsBoxState extends State<LyricsBox> {
  Future<Lyrics>? _fetchLyricsFuture;
  bool _lyricsLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(AppearancePrefs.load());
    _initFetchLyrics();
    _initWakelock();
  }

  void _initFetchLyrics() {
    _fetchLyrics();
  }

  void _initWakelock() {
    GetIt.I<MediaPlayer>().buttonState.addListener(_updateWakelock);
  }

  void _updateWakelock() {
    if (!mounted) return;
    final isPlaying =
        GetIt.I<MediaPlayer>().buttonState.value == ButtonState.playing;
    if (isPlaying && _lyricsLoaded) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  void didUpdateWidget(covariant LyricsBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSong.id != oldWidget.currentSong.id) {
      _initFetchLyrics();
    }
  }

  void _fetchLyrics() {
    if (context.mounted) {
      setState(() {
        _lyricsLoaded = false;
        _fetchLyricsFuture = _loadLyricsInternal();
        _fetchLyricsFuture!.then((lyrics) {
          _lyricsLoaded =
              (lyrics.parsedLyrics?.lyrics.isNotEmpty ?? false) ||
                  lyrics.lyricsPlain.isNotEmpty;
          widget.onLyricsFound?.call(_lyricsLoaded);
          _updateWakelock();
        }).catchError((_) {
          _lyricsLoaded = false;
          widget.onLyricsFound?.call(false);
          _updateWakelock();
        });
      });
    }
  }

  Future<Lyrics> _loadLyricsInternal() async {
    final spUri = widget.currentSong.extras?['spotifyUri'] as String?;
    if (spUri != null && spUri.isNotEmpty) {
      final coverUrl = widget.currentSong.artUri?.toString();
      final spLyrics = await SpotifyLyricsService.instance.fetchColorLyrics(
        spUri,
        coverUrl: coverUrl,
      );
      if (spLyrics != null && spLyrics.lines.isNotEmpty) {
        return _convertSpotifyLyrics(spLyrics);
      }
    }

    // Fallback to LRCLIB
    return GetIt.I<LyricsService>().getLyrics(
      title: widget.currentSong.title,
      artist: widget.currentSong.artist,
      album: widget.currentSong.album,
      duration: widget.currentSong.duration?.inSeconds.toString(),
    );
  }

  Lyrics _convertSpotifyLyrics(SpotifyColorLyrics sp) {
    final syncedBuffer = StringBuffer();

    for (final line in sp.lines) {
      // Format as standard LRC: [mm:ss.xx] text
      final minutes = (line.startTimeMs ~/ 60000).toString().padLeft(2, '0');
      final seconds = ((line.startTimeMs % 60000) / 1000).toStringAsFixed(2).padLeft(5, '0');

      syncedBuffer.writeln('[$minutes:$seconds] ${line.words}');
    }

    // Passing the LRC string directly into lyricsPlain.
    // The Lyrics model automatically parses this if it detects the format.
    return Lyrics(
      id: widget.currentSong.id,
      title: widget.currentSong.title,
      artist: widget.currentSong.artist ?? 'Unknown',
      duration: widget.currentSong.duration?.inSeconds.toString() ?? '0',
      provider: LyricsProvider.values.first, // Avoids hardcoding the enum name
      lyricsPlain: syncedBuffer.toString().trim(),
    );
  }

  @override
  void dispose() {
    GetIt.I<MediaPlayer>().buttonState.removeListener(_updateWakelock);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _fetchLyricsFuture != null
            ? FutureBuilder<Lyrics>(
          future: _fetchLyricsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              if (snapshot.data == null) {
                return const Text('No Lyrics Found (Null)');
              }
              return LoadedLyricsWidget(lyrics: snapshot.data!);
            }
            if (snapshot.hasError) {
              return const Text('No Lyrics Found');
            }
            return const ExpressiveLoadingIndicator();
          },
        )
            : const ExpressiveLoadingIndicator(),
      ),
    );
  }
}

class LoadedLyricsWidget extends StatelessWidget {
  final Lyrics lyrics;
  const LoadedLyricsWidget({
    super.key,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    if ((lyrics.parsedLyrics?.lyrics.isEmpty ?? true) &&
        lyrics.lyricsPlain.isNotEmpty) {
      return PlainLyricsWidget(lyrics: lyrics);
    } else if (lyrics.parsedLyrics?.lyrics.isNotEmpty ?? false) {
      return SyncedLyricsWidget(
        lyrics: lyrics,
      );
    }
    return const Center(
      child: Text("No Lyrics found!"),
    );
  }
}

class PlainLyricsWidget extends StatelessWidget {
  final Lyrics lyrics;
  const PlainLyricsWidget({
    super.key,
    required this.lyrics,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        child: SelectableText(
          "\n${lyrics.lyricsPlain}\n",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppearancePrefs.lyricsTextSize.value + 15,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: AppearancePrefs.lyricsLineSpacing.value + 0.1,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class SyncedLyricsWidget extends StatefulWidget {
  final Lyrics lyrics;
  const SyncedLyricsWidget({
    required this.lyrics,
    super.key,
  });

  @override
  State<SyncedLyricsWidget> createState() => _SyncedLyricsWidgetState();
}

class _SyncedLyricsWidgetState extends State<SyncedLyricsWidget>
    with TickerProviderStateMixin {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
  ItemPositionsListener.create();
  Duration duration = Duration.zero;
  int _currentLyricIndex = 0;

  bool _isUserScrolling = false;
  Timer? _userScrollTimer;
  final Duration _userScrollCooldown = const Duration(milliseconds: 1500);

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.2, end: 0.9).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    final mp = GetIt.I<MediaPlayer>();
    duration = mp.progressBarState.value.current;
    mp.progressBarState.addListener(_onProgress);
  }

  void _onProgress() {
    if (!mounted) return;
    final mp = GetIt.I<MediaPlayer>();
    final newPos = mp.progressBarState.value.current;
    if (newPos != duration) {
      duration = newPos;
      final newIndex = _findCurrentLyricIndex();
      if (newIndex != _currentLyricIndex) {
        setState(() {
          _currentLyricIndex = newIndex;
        });
        _scrollToCurrentLyric(newIndex);
      }
    }
  }

  @override
  void dispose() {
    GetIt.I<MediaPlayer>().progressBarState.removeListener(_onProgress);
    _userScrollTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  void _scrollToCurrentLyric(int index) {
    if (_itemScrollController.isAttached && !_isUserScrolling) {
      _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    }
  }

  int _findCurrentLyricIndex() {
    if (widget.lyrics.parsedLyrics == null) return 0;

    final lines = widget.lyrics.parsedLyrics!.lyrics;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i]!.start.inMilliseconds > duration.inMilliseconds) {
        return i > 0 ? i - 1 : 0;
      }
    }
    return lines.length - 1;
  }

  bool isCurrentLyric(int index) {
    return index == _currentLyricIndex;
  }

  void _seekToLyric(int index) {
    if (widget.lyrics.parsedLyrics == null) return;
    final lyric = widget.lyrics.parsedLyrics!.lyrics[index];
    if (lyric != null) {
      GetIt.I<MediaPlayer>().seekTo(lyric.start);
      _scrollToCurrentLyric(index);
    }
  }

  TextAlign _align() {
    switch (AppearancePrefs.lyricsPosition.value) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.parsedLyrics == null) return const SizedBox();

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction != ScrollDirection.idle) {
            setState(() {
              _isUserScrolling = true;
            });
            _userScrollTimer?.cancel();
          } else {
            _userScrollTimer?.cancel();
            _userScrollTimer = Timer(_userScrollCooldown, () {
              if (mounted) {
                setState(() {
                  _isUserScrolling = false;
                });
                _scrollToCurrentLyric(_currentLyricIndex);
              }
            });
          }
          return false;
        },
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: widget.lyrics.parsedLyrics!.lyrics.length,
            padding: EdgeInsets.symmetric(
                vertical: MediaQuery.of(context).size.height / 2.5),
            itemBuilder: (context, index) {
              final isCurrent = isCurrentLyric(index);
              final lyricText =
                  widget.lyrics.parsedLyrics!.lyrics[index]?.text ?? '';
              final baseSize = AppearancePrefs.lyricsTextSize.value;

              return GestureDetector(
                onTap: () => _seekToLyric(index),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(vertical: 16.0, horizontal: 32),
                  child: AnimatedBuilder(
                    animation: _glowAnimation,
                    builder: (context, child) {
                      return AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: isCurrent ? baseSize + 10 : baseSize,
                          fontWeight:
                          isCurrent ? FontWeight.w900 : FontWeight.w600,
                          color: isCurrent
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.35),
                          height: AppearancePrefs.lyricsLineSpacing.value,
                          letterSpacing: isCurrent ? 0.5 : -0.3,
                          shadows: isCurrent
                              ? [
                            Shadow(
                              color: Colors.white.withValues(
                                  alpha: _glowAnimation.value * 0.8),
                              blurRadius: 15,
                            ),
                            Shadow(
                              color: Colors.white.withValues(
                                  alpha: _glowAnimation.value * 0.4),
                              blurRadius: 30,
                            ),
                            Shadow(
                              color: Colors.blueAccent.withValues(
                                  alpha: _glowAnimation.value * 0.3),
                              blurRadius: 50,
                            ),
                          ]
                              : [],
                        ),
                        child: Text(
                          lyricText,
                          textAlign: _align(),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}