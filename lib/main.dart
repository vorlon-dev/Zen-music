// ZenMusic · vorlon-dev

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:zenmusic/desktop/main.dart' show ZenDesktopApp, initialiseHive;
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart';
import 'package:zenmusic/desktop/services/zen_wall_service.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/file_storage.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/jam_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Phones: the default image cache (100 MB / 1000 images) is far too big for
  // a 2 GB device and makes the GC fight the UI thread. Keep it small.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 48 << 20
    ..maximumSize = 120;

  await initialiseHive();

  // These four do not depend on each other (only on Hive, which is ready), so
  // run them together instead of one after another: the first frame no longer
  // waits for the sum of all of them.
  final audioServerFuture = createAudioStreamServer();
  await Future.wait<void>([
    JustAudioBackground.init(
      androidNotificationChannelId: 'com.zen.music.zenmusic.audio',
      androidNotificationChannelName: 'ZenMusic Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
    // Appearance prefs (slider style, lyric size/alignment, etc.) — hydrate
    // before any UI mounts.
    AppearancePrefs.load(),
    _initFileStorage(),
  ]);

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

  final String audioStreamUrl = await audioServerFuture;
  GetIt.I.registerSingleton<String>(audioStreamUrl,
      instanceName: 'audioStreamUrl');

  final MediaPlayer mediaPlayer = MediaPlayer();
  GetIt.I.registerSingleton<MediaPlayer>(mediaPlayer);

  GetIt.I.registerSingleton<BeatHapticsEngine>(
      BeatHapticsEngine(mediaPlayer));
  GetIt.I<BeatHapticsEngine>().start();
  ZenWallService.instance.attach(mediaPlayer.currentSongNotifier);

  unawaited(SpotifyAuth.instance.load());

  unawaited(mediaPlayer.restoreLastSession());

  final libraryService = LibraryService();
  GetIt.I.registerSingleton<LibraryService>(libraryService);

  final fileStorage = FileStorage();
  GetIt.I.registerSingleton<FileStorage>(fileStorage);

  GetIt.I.registerSingleton<DownloadManager>(DownloadManager());

  GetIt.I.registerSingleton<LyricsService>(LyricsService());

  GetIt.I.registerSingleton<YTMusic>(ytMusic);

  JamService.instance.start(mediaPlayer);

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

Future<void> _initFileStorage() async {
  try {
    await FileStorage.initialise();
  } catch (_) {
    final docs = await getApplicationDocumentsDirectory();
    await Hive.box('SETTINGS').put('APP_FOLDER', docs.path);
    await FileStorage.initialise();
  }
}
