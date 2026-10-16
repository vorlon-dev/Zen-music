// ZenMusic Desktop — ported from Echo Music (GPL-3.0), services/media_player.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// PORT DEVIATIONS:
//  1. Android audio pipeline: restored for ANDROID ONLY at the EQ round —
//     AudioPipeline(AndroidEqualizer) gives device-band EQ on phones.
//     Desktop (Windows/Linux/macOS): plain player — EQ arrives via the mpv
//     arc. All EQ methods no-op safely off-Android.
//  2. just_audio_background imported for the MediaItem tag class ONLY — never
//     initialized on desktop (its init is the recorded Windows crash); the
//     MOBILE entry (lib/main.dart) initializes it.
//  3. YTMusic-dependent paths restored verbatim (stats timer, autofetch,
//     startRelated, startPlaylistSongs, online-playlist branches).
//  4. JioSaavn: direct 320kbps branch (jiosaavnStreamUrl in the song map).
//  5. Thumbnails upgraded via getEnhancedImage (regex size normalization).
//  6. playAll is chart-aware: isChart rows resolve via the search-and-play
//     path the tiles use, then play the resolved list.
//  7. Spotify branch: song maps from the Spotify search section carry
//     'spotifyUri'.
//     ANDROID: Widevine L3 DRM playback via the patched just_audio host
//     (x-zen-drm header marker -> DrmConfiguration; Stopify recipe, MIT).
//     Resolved CDN URL + license headers are built from SpotifyAuth.
//     DESKTOP: mpv/media_kit has no Widevine CDM (CENC ciphertext conf) —
//     the same song is played via YT Music (search-and-play, isChart-style)
//     with the original Spotify tag so artwork/title stay correct.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:rxdart/rxdart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/add_history.dart';
import '../utils/enhanced_image.dart';
import 'eq_models.dart';
import 'settings_manager.dart';
import 'yt_audio_stream.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/spotify/spotify_player.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_config.dart';

// From Stopify's SpotifyAudioPlayer (MIT) — Widevine license endpoint for
// web-player CENC audio. Consumed by the patched just_audio Android host.
const _kSpotifyWidevineLicenseUrl =
    'https://gae2-spclient.spotify.com/widevine-license/v1/audio/license';

class MediaPlayer extends ChangeNotifier {
  late final AudioPlayer _player;

  // Android-only session EQ (device bands). Null on every other platform —
  // all EQ methods no-op safely when null.
  AndroidEqualizer? _eq;
  AndroidEqualizerParameters? _eqParams;

  bool get eqAvailable => Platform.isAndroid && _eq != null;

  List<IndexedAudioSource> _songList = [];
  final ValueNotifier<MediaItem?> _currentSongNotifier = ValueNotifier(null);
  final ValueNotifier<int?> _currentIndex = ValueNotifier(null);
  final ValueNotifier<ButtonState> _buttonState =
  ValueNotifier(ButtonState.loading);
  Timer? _timer;
  final ValueNotifier<Duration?> _timerDuration = ValueNotifier(null);

  final ValueNotifier<LoopMode> _loopMode = ValueNotifier(LoopMode.off);

  final ValueNotifier<ProgressBarState> _progressBarState =
  ValueNotifier(ProgressBarState());

  bool _shuffleModeEnabled = false;

  bool autoFetching = false;

  MediaPlayer() {
    // ANDROID: session EQ pipeline (device bands). Desktop: plain player —
    // EQ arrives via the mpv arc.
    if (Platform.isAndroid) {
      _eq = AndroidEqualizer();
      _player = AudioPlayer(
        audioPipeline: AudioPipeline(androidAudioEffects: [_eq!]),
      );
    } else {
      _player = AudioPlayer();
    }
    _init();
  }

  AudioPlayer get player => _player;
  List<IndexedAudioSource> get songList => List.unmodifiable(_songList);
  ValueNotifier<MediaItem?> get currentSongNotifier => _currentSongNotifier;
  ValueNotifier<int?> get currentIndex => _currentIndex;
  ValueNotifier<ButtonState> get buttonState => _buttonState;
  ValueNotifier<ProgressBarState> get progressBarState => _progressBarState;
  bool get shuffleModeEnabled => _shuffleModeEnabled;
  ValueNotifier<LoopMode> get loopMode => _loopMode;
  ValueNotifier<Duration?> get timerDuration => _timerDuration;

  Stream<
      ({
      List<IndexedAudioSource>? sequence,
      int? currentIndex,
      MediaItem? currentItem
      })> get currentTrackStream => Rx.combineLatest2<
      List<IndexedAudioSource>?,
      int?,
      ({
      List<IndexedAudioSource>? sequence,
      int? currentIndex,
      MediaItem? currentItem
      })>(
    _player.sequenceStream,
    _player.currentIndexStream,
        (sequence, currentIndex) {
      MediaItem? currentItem;
      if (sequence != null &&
          currentIndex != null &&
          currentIndex >= 0 &&
          currentIndex < sequence.length) {
        final tag = sequence[currentIndex].tag;
        if (tag is MediaItem) currentItem = tag;
      }
      return (
      sequence: sequence,
      currentIndex: currentIndex,
      currentItem: currentItem,
      );
    },
  );

  Future<void> _init() async {
    _listenToChangesInPlaylist();
    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToChangesInSong();
    _listenToShuffle();
    _listenToAutofetch();
    _listenToPlayerErrors();
    unawaited(_restoreEq());

    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (currentSongNotifier.value != null && _player.playing) {
        GetIt.I<YTMusic>()
            .addPlayingStats(currentSongNotifier.value!.id, _player.position);
      }
    });
  }

  void _listenToChangesInPlaylist() {
    _player.sequenceStream.listen((playlist) {
      final List<IndexedAudioSource> newList =
      (playlist).cast<IndexedAudioSource>();

      if (listEquals(newList, _songList)) return;

      final bool shouldAdd = (_songList.isEmpty && newList.isNotEmpty);

      if (newList.isEmpty) {
        _currentSongNotifier.value = null;
        _currentIndex.value = null;
        _songList = [];
      } else {
        _songList = newList;

        _currentIndex.value ??= 0;
        _currentSongNotifier.value =
        (_songList.length > (_currentIndex.value ?? 0))
            ? _songList[_currentIndex.value ?? 0].tag
            : null;
      }

      if (shouldAdd == true && _currentSongNotifier.value != null) {
        addHistory(_currentSongNotifier.value!.extras!);
      }

      notifyListeners();
    });
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((event) {
      final isPlaying = event.playing;
      final processingState = event.processingState;
      if (processingState == ProcessingState.loading ||
          processingState == ProcessingState.buffering) {
        _buttonState.value = ButtonState.loading;
      } else if (processingState == ProcessingState.ready) {
        _buttonState.value =
        isPlaying ? ButtonState.playing : ButtonState.paused;
      } else if (processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
        _buttonState.value = ButtonState.paused;
      } else {
        // idle state
        _buttonState.value = ButtonState.paused;
      }
    });
  }

  void _listenToPlayerErrors() {
    _player.playbackEventStream.listen(
          (event) {},
      onError: (Object e, StackTrace st) {
        _buttonState.value = ButtonState.paused;
        notifyListeners();
      },
    );
  }

  void _listenToCurrentPosition() {
    _player.positionStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.current != position) {
        _progressBarState.value = ProgressBarState(
          current: position,
          buffered: oldState.buffered,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.buffered != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: position,
          total: oldState.total,
        );
      }
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((position) {
      final oldState = _progressBarState.value;
      if (oldState.total != position) {
        _progressBarState.value = ProgressBarState(
          current: oldState.current,
          buffered: oldState.buffered,
          total: position ?? Duration.zero,
        );
      }
    });
  }

  void _listenToShuffle() {
    _player.shuffleModeEnabledStream.listen((data) {
      _shuffleModeEnabled = data;
      notifyListeners();
    });
  }

  void _listenToChangesInSong() {
    _player.currentIndexStream.listen((index) {
      if (_songList.isNotEmpty && _currentIndex.value != index) {
        _currentIndex.value = index;
        _currentSongNotifier.value =
        index != null && _songList.isNotEmpty && index < _songList.length
            ? _songList[index].tag
            : null;
        if (_songList.isNotEmpty && _currentIndex.value != null) {
          final MediaItem item = _songList[_currentIndex.value!].tag;
          addHistory(item.extras!);
        }
        notifyListeners();
      }
    });
  }

  void changeLoopMode() {
    switch (_loopMode.value) {
      case LoopMode.off:
        _loopMode.value = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode.value = LoopMode.one;
        break;
      default:
        _loopMode.value = LoopMode.off;
        break;
    }
    _player.setLoopMode(_loopMode.value);
  }

  Future<void> skipSilence(bool value) async {
    await _player.setSkipSilenceEnabled(value);
    GetIt.I<SettingsManager>().skipSilence = value;
  }

  Future<AudioSource> _getAudioSource(Map<String, dynamic> song) async {
    MediaItem tag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );

    final bool isDownloaded = song['status'] == 'DOWNLOADED' &&
        song['path'] != null &&
        (await File(song['path']).exists());

    if (isDownloaded) {
      return AudioSource.file(song['path'], tag: tag);
    } else {
      // Spotify (SP-3): song maps from the Spotify search section carry
      // spotifyUri.
      final spotifyUri = song['spotifyUri'] as String?;
      if (spotifyUri != null && spotifyUri.isNotEmpty) {
        // ANDROID: real Spotify audio — resolve CDN + Widevine L3 DRM via
        // the patched just_audio host. On any failure, fall back to YT so
        // playback never dies on an expired/missing session.
        if (Platform.isAndroid) {
          try {
            final cdn = await SpotifyPlayer.instance.resolveTrack(spotifyUri);
            final token = await SpotifyAuth.instance.getAccessToken();
            if (cdn != null && token != null && cdn.isNotEmpty) {
              final clientToken =
              await SpotifyAuth.instance.getClientToken();
              print('[spotify-play] DRM source for $spotifyUri');
              return AudioSource.uri(Uri.parse(cdn), tag: tag, headers: {
                'User-Agent': SpotifyConfig.userAgent,
                'Origin': 'https://open.spotify.com',
                'Referer': 'https://open.spotify.com/',
                // Marker consumed by the just_audio host (never sent as an
                // HTTP header): license URL + license request headers.
                'x-zen-drm': jsonEncode({
                  'licenseUri': _kSpotifyWidevineLicenseUrl,
                  'headers': {
                    'authorization': 'Bearer $token',
                    'client-token': clientToken,
                    'app-platform': SpotifyConfig.appPlatform,
                    'spotify-app-version': SpotifyConfig.spotifyAppVersion,
                    'origin': 'https://open.spotify.com',
                    'referer': 'https://open.spotify.com/',
                    'user-agent': SpotifyConfig.userAgent,
                  },
                }),
              });
            }
            print('[spotify-play] DRM resolve failed, falling back to YT');
          } catch (e) {
            print('[spotify-play] DRM error: $e, falling back to YT');
          }
        }
        // DESKTOP (or Android failure): same song via YT Music.
        return _ytFallbackSource(song, tag);
      }
      // JioSaavn: direct 320kbps URL baked into the song map — no
      // extraction needed, plays on every platform.
      final saavnUrl = song['jiosaavnStreamUrl'] as String?;
      if (saavnUrl != null && saavnUrl.isNotEmpty) {
        return AudioSource.uri(Uri.parse(saavnUrl), tag: tag);
      }
      // Use direct URL approach for macOS for better compatibility with AVFoundation
      if (Platform.isMacOS) {
        final quality =
        GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase();
        return await getDirectUrlAudioSource(song['videoId'], quality, tag);
      }
      return YouTubeAudioSource(
        videoId: song['videoId'],
        quality: GetIt.I<SettingsManager>().streamingQuality.name.toLowerCase(),
        tag: tag,
      );
    }
  }

  /// Spotify rows on DRM-less platforms (desktop) and Android DRM failures:
  /// play the same song via YT Music (isChart-style search-and-play) while
  /// keeping the ORIGINAL Spotify tag so artwork/title stay from Spotify.
  Future<AudioSource> _ytFallbackSource(
      Map<String, dynamic> song, MediaItem tag) async {
    try {
      final query = '${song['title'] ?? ''} ${song['artist'] ?? ''}'.trim();
      final result = await GetIt.I<YTMusic>().search(query, filter: 'songs');
      final sections = result['sections'] as List?;
      if (sections != null && sections.isNotEmpty) {
        final contents = sections[0]['contents'] as List?;
        if (contents != null && contents.isNotEmpty) {
          final ytSong = Map<String, dynamic>.from(contents[0] as Map);
          print('[spotify-play] YT fallback: ${ytSong['videoId']}');
          return YouTubeAudioSource(
            videoId: ytSong['videoId'],
            quality: GetIt.I<SettingsManager>()
                .streamingQuality
                .name
                .toLowerCase(),
            tag: tag,
          );
        }
      }
    } catch (e) {
      print('[spotify-play] YT fallback error: $e');
    }
    throw Exception('Spotify playback unavailable (no YT fallback match)');
  }

  int _lastPlayRequestId = 0;

  Future<void> playSong(Map<String, dynamic> song) async {
    if (song['videoId'] == null) return;

    final int requestId = DateTime.now().millisecondsSinceEpoch;
    _lastPlayRequestId = requestId;

    // OPTIMISTIC UPDATE: show the song immediately with loading state.
    MediaItem tempTag = MediaItem(
      id: song['videoId'],
      title: song['title'] ?? 'Title',
      album: song['album']?['name'],
      artUri: Uri.parse(getEnhancedImage(
          song['thumbnails']?.first['url'] ?? '',
          quality: 'high')),
      artist: song['artists']?.map((artist) => artist['name']).join(','),
      extras: song,
    );
    _currentSongNotifier.value = tempTag;
    _buttonState.value = ButtonState.loading;
    notifyListeners();

    // stop and set the tapped song as the single source so it plays immediately
    try {
      await _player.pause();
      await _player.stop();
      if (_lastPlayRequestId != requestId) return; // Stale request
      await _player.clearAudioSources();
      if (_lastPlayRequestId != requestId) return; // Stale request
    } catch (e) {
      // Ignore stop errors
    }

    try {
      final source = await _getAudioSource(song);
      if (_lastPlayRequestId != requestId) return; // Stale request

      await _player.setAudioSource(source);
      if (_lastPlayRequestId != requestId) return;

      await _player.play();
    } catch (e) {
      if (_lastPlayRequestId == requestId) {
        print("Error playing song: $e");
        _buttonState.value = ButtonState.paused;
        notifyListeners();
      }
    }
  }

  Future<void> playNext(Map<String, dynamic> mediaItem) async {
    // Case 1: A single video/song
    if (mediaItem['videoId'] != null) {
      final audioSource = await _getAudioSource(mediaItem);

      final currentIndex = _player.currentIndex ?? -1;
      final sequenceLength = _player.sequence.length;
      final insertIndex = (currentIndex + 1).clamp(0, sequenceLength);

      if (sequenceLength > 0) {
        await _player.insertAudioSource(insertIndex, audioSource);
      } else {
        await _player.setAudioSource(audioSource);
      }

      // Case 2: Custom or Downloaded Playlist
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: true);

      // Case 3: Online Playlist
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
          .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: true);
    }
  }

  Future<void> playAll(List songs, {int index = 0}) async {
    if (songs.isEmpty) return;

    _buttonState.value = ButtonState.loading;
    notifyListeners();

    try {
      await _player.stop();

      final selectedSong = Map<String, dynamic>.from(songs[index]);

      // Chart-aware (deviation 6): isChart rows carry no stream — resolve
      // each via the search-and-play path the tiles use, then play the
      // resolved list.
      if (selectedSong['isChart'] == true) {
        final resolved = <Map<String, dynamic>>[];
        for (final s in songs) {
          final m = Map<String, dynamic>.from(s);
          if (m['isChart'] != true) {
            resolved.add(m);
            continue;
          }
          try {
            final query = '${m['title']} ${m['subtitle'] ?? ''}';
            final result =
            await GetIt.I<YTMusic>().search(query, filter: 'songs');
            final sections = result['sections'] as List?;
            if (sections != null && sections.isNotEmpty) {
              final sec = sections[0];
              final contents = sec['contents'] as List?;
              if (contents != null && contents.isNotEmpty) {
                resolved.add(Map<String, dynamic>.from(contents[0]));
              }
            }
          } catch (_) {
            // Skip rows that fail to resolve.
          }
        }
        if (resolved.isEmpty) {
          _buttonState.value = ButtonState.paused;
          notifyListeners();
          return;
        }
        songs = resolved;
        index = index.clamp(0, resolved.length - 1);
      }

      final selectedSong2 = Map<String, dynamic>.from(songs[index]);
      final firstSource = await _getAudioSource(selectedSong2);

      await _player.setAudioSource(firstSource);
      _player.play(); // Don't await — start playing while we add more

      if (songs.length > 1) {
        Future(() => _addRemainingToPlaylist(songs, index));
      }
    } catch (e) {
      print('Error in playAll: $e');
      _buttonState.value = ButtonState.paused;
      notifyListeners();
    }
  }

  // Lazy loading: only preload the next few songs, not the entire playlist.
  Future<void> _addRemainingToPlaylist(List songs, int playedIndex) async {
    try {
      final int maxPreload = 3;
      int added = 0;

      for (int i = playedIndex + 1;
      i < songs.length && added < maxPreload;
      i++) {
        try {
          final source =
          await _getAudioSource(Map<String, dynamic>.from(songs[i]));
          await _player.addAudioSource(source);
          added++;
        } catch (e) {
          // Skip failed songs silently
        }
      }
    } catch (e) {
      print('Error adding remaining songs: $e');
    }
  }

  Future<void> addToQueue(Map<String, dynamic> mediaItem) async {
    if (mediaItem['videoId'] != null) {
      await _player.addAudioSource(await _getAudioSource(mediaItem));
    } else if (mediaItem['songs'] != null) {
      List songs = mediaItem['songs'];
      await _addSongListToQueue(songs, isNext: false);
    } else if (mediaItem['playlistId'] != null) {
      List songs = mediaItem['type'] == 'ARTIST'
          ? await GetIt.I<YTMusic>()
          .getNextSongList(playlistId: mediaItem['playlistId'])
          : await GetIt.I<YTMusic>().getPlaylistSongs(mediaItem['playlistId']);
      await _addSongListToQueue(songs, isNext: false);
    }
  }

  Future<void> startRelated(Map<String, dynamic> song,
      {bool radio = false, bool shuffle = false, bool isArtist = false}) async {
    await _player.clearAudioSources();
    if (!isArtist) {
      await addToQueue(song);
    }
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        videoId: song['videoId'],
        playlistId: song['playlistRadioId'],
        radio: radio,
        shuffle: shuffle);
    if (songs.isNotEmpty) songs.removeAt(0);
    await _addSongListToQueue(songs, isNext: false);
    await _player.play();
  }

  Future<void> startPlaylistSongs(Map endpoint) async {
    await _player.clearAudioSources();
    List songs = await GetIt.I<YTMusic>().getNextSongList(
        playlistId: endpoint['playlistId'], params: endpoint['params']);

    if (songs.isNotEmpty && songs.first['videoId'] == null) {
      // if API returned a placeholder, convert or handle accordingly
    }

    await _addSongListToQueue(songs);
    await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    await _player.clearAudioSources();
    await _player.seek(Duration.zero, index: 0);
    _currentIndex.value = null;
    _currentSongNotifier.value = null;
    notifyListeners();
  }

  Future<void> _addSongListToQueue(List songs, {bool isNext = false}) async {
    if (songs.isEmpty) return;

    final newSources = await Future.wait(songs.map((song) async {
      final mapSong = Map<String, dynamic>.from(song);
      return await _getAudioSource(mapSong);
    }));

    final queueLength = _player.sequence.length;

    if (isNext) {
      final currentIndex = _player.currentIndex ?? -1;
      int insertIndex = (currentIndex + 1).clamp(0, queueLength);
      await _player.insertAudioSources(insertIndex, newSources);
    } else {
      await _player.addAudioSources(newSources);
    }
  }

  void _listenToAutofetch() {
    player.currentIndexStream.listen((index) async {
      if (index == null) return;
      if (player.sequence.length - index < 5 &&
          GetIt.I<SettingsManager>().autofetchSongs &&
          autoFetching == false) {
        autoFetching = true;
        List nextSongs = await GetIt.I<YTMusic>()
            .getNextSongList(videoId: player.sequence[index].tag.id);
        if (nextSongs.isNotEmpty) nextSongs.removeAt(0);
        await _addSongListToQueue(nextSongs);
        autoFetching = false;
      }
    });
  }

  void setTimer(Duration duration) {
    int seconds = duration.inSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      seconds--;
      _timerDuration.value = Duration(seconds: seconds);
      if (seconds == 0) {
        cancelTimer();
        _player.pause();
      }
      notifyListeners();
    });
  }

  void cancelTimer() {
    _timerDuration.value = null;
    _timer?.cancel();
    notifyListeners();
  }

  // ── EQUALIZER (Android session EQ) ──

  static const _eqEnabledKey = 'EQ_ENABLED';
  static const _eqBandsKey = 'EQ_BANDS';

  /// Parameters for the EQ screen: null when unavailable (non-Android or
  /// pipeline not ready yet — the screen retries on next open).
  Future<EqParams?> getEqParameters() async {
    final eq = _eq;
    if (eq == null || !Platform.isAndroid) return null;
    try {
      _eqParams ??= await eq.parameters;
      final p = _eqParams!;
      return EqParams(
        minDb: p.minDecibels,
        maxDb: p.maxDecibels,
        bands: [
          for (final b in p.bands)
            EqBand(centerHz: b.centerFrequency, gain: b.gain),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setEqEnabled(bool enabled) async {
    final box = Hive.box('SETTINGS');
    await box.put(_eqEnabledKey, enabled);
    try {
      await _eq?.setEnabled(enabled);
    } catch (_) {}
  }

  Future<bool> getEqEnabled() async {
    return Hive.box('SETTINGS').get(_eqEnabledKey, defaultValue: false);
  }

  Future<void> setEqBandGain(int index, double gain) async {
    final p = _eqParams;
    if (p == null || index < 0 || index >= p.bands.length) return;
    try {
      await p.bands[index].setGain(gain);
      final stored = Hive.box('SETTINGS').get(_eqBandsKey);
      final gains = stored is List
          ? List<double>.from(stored.map((e) => (e as num?)?.toDouble() ?? 0.0))
          : <double>[];
      if (gains.length != p.bands.length) {
        gains.length = p.bands.length;
        for (var i = 0; i < gains.length; i++) {
          gains[i] ??= 0.0;
        }
      }
      gains[index] = gain;
      await Hive.box('SETTINGS').put(_eqBandsKey, gains);
    } catch (_) {}
  }

  Future<void> resetEq() async {
    final p = _eqParams;
    if (p == null) return;
    try {
      for (final b in p.bands) {
        await b.setGain(0);
      }
      await Hive.box('SETTINGS').put(
          _eqBandsKey, List<double>.filled(p.bands.length, 0));
    } catch (_) {}
  }

  Future<void> _restoreEq() async {
    final eq = _eq;
    if (eq == null || !Platform.isAndroid) return;
    try {
      _eqParams ??= await eq.parameters;
      final p = _eqParams!;
      final box = Hive.box('SETTINGS');
      final enabled = box.get(_eqEnabledKey, defaultValue: false);
      if (enabled) await eq.setEnabled(true);
      final stored = box.get(_eqBandsKey);
      final gains = stored is List
          ? List<double>.from(stored.map((e) => (e as num?)?.toDouble() ?? 0.0))
          : <double>[];
      if (gains.length == p.bands.length) {
        for (var i = 0; i < gains.length; i++) {
          await p.bands[i].setGain(gains[i]);
        }
      }
    } catch (_) {}
  }
}

enum ButtonState { loading, paused, playing }

enum LoopState { off, all, one }

class ProgressBarState {
  Duration current;
  Duration buffered;
  Duration total;
  ProgressBarState(
      {this.current = Duration.zero,
        this.buffered = Duration.zero,
        this.total = Duration.zero});
}