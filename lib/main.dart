import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:zenmusic/desktop/main.dart' show ZenDesktopApp, initialiseHive;
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart'; // SP-78
import 'package:zenmusic/desktop/services/zen_wall_service.dart'; // SP-78
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/file_storage.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/jam_service.dart'; // SP-83: boot restored (SP-78 rewrite dropped it)
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart'; // SP-78

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initialiseHive();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.zen.music.zenmusic.audio',
    androidNotificationChannelName: 'ZenMusic Playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  // Appearance prefs (slider style, lyric size/alignment, etc.) — hydrate
  // before any UI mounts.
  await AppearancePrefs.load();

  // MOBILE DEVIATION: storage bootstrap (see header).
  try {
    await FileStorage.initialise();
  } catch (_) {

    final docs = await getApplicationDocumentsDirectory();
    await Hive.box('SETTINGS').put('APP_FOLDER', docs.path);
    await FileStorage.initialise();
  }

  unawaited(InnertubexBridge.warm());


  String? visitorId = await Hive.box('SETTINGS').get('VISITOR_ID');
  YTMusic ytMusic = YTMusic(
    config: YTConfig(
        visitorData: visitorId ?? '', language: 'en', location: 'IN'),
    onIdUpdate: (visitorId) async {
      await Hive.box('SETTINGS').put('VISITOR_ID', visitorId);
    },
  );

  final settingsManager = SettingsManager();
  GetIt.I.registerSingleton<SettingsManager>(settingsManager);

  final String audioStreamUrl = await createAudioStreamServer();
  GetIt.I.registerSingleton<String>(audioStreamUrl,
      instanceName: 'audioStreamUrl');

  final MediaPlayer mediaPlayer = MediaPlayer();
  GetIt.I.registerSingleton<MediaPlayer>(mediaPlayer);

  // SP-78: beat haptics + ZenWall — mobile-only features; both self-gate
  // (Android/iOS + their settings switches), so this wiring is inert
  // wherever they don't apply.
  GetIt.I.registerSingleton<BeatHapticsEngine>(
      BeatHapticsEngine(mediaPlayer));
  GetIt.I<BeatHapticsEngine>().start();
  ZenWallService.instance.attach(mediaPlayer.currentSongNotifier);

  // SP-78: restore the Spotify session at boot. The desktop main already
  // does this; the mobile entry never did, so canvas features (player
  // backdrop, ZenWall) came up logged-out until Settings was opened once.
  unawaited(SpotifyAuth.instance.load());

  // SP-11: Restore the last played queue/song from Hive cache
  unawaited(mediaPlayer.restoreLastSession());

  final libraryService = LibraryService();
  GetIt.I.registerSingleton<LibraryService>(libraryService);

  final fileStorage = FileStorage();
  GetIt.I.registerSingleton<FileStorage>(fileStorage);

  GetIt.I.registerSingleton<DownloadManager>(DownloadManager());

  GetIt.I.registerSingleton<LyricsService>(LyricsService());

  GetIt.I.registerSingleton<YTMusic>(ytMusic);

  // SP-83: LastWave Jam (listen together) boot is BACK. The SP-78 rewrite
  // of this file rebuilt it from a pre-SP-77 base and silently dropped the
  // start() call — rooms could never connect even when the page opened.
  // App-scoped controller + playback sync bridge; rooms survive navigation
  // and run for the app's lifetime.
  JamService.instance.start(mediaPlayer);

  // SP-62: YouTube Music account — restore the device-OAuth session (or the
  // pasted-cookie fallback) so the home feed is personalized from boot.
  YtmAuth.instance.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => settingsManager),
        ChangeNotifierProvider(create: (_) => mediaPlayer),
        ChangeNotifierProvider(create: (_) => libraryService),
      ],
      child: const ZenDesktopApp(),
    ),
  );
}