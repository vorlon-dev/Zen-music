// ZenMusic — MOBILE entry (Android). [Option B redesign]
// Boots the DESKTOP service stack on Android: same YTMusic client,
// MediaPlayer (just_audio -> ExoPlayer on Android), Hive services and the
// Echo-port UI as the Windows build. The legacy mobile stack
// (ZenAudioHandler + old screens) is retired on this branch — preserved on
// `main` and in history.
//
// Desktop entry: lib/desktop/main.dart (unchanged, Windows-only).
//
// PORT DEVIATION (mobile-only): FileStorage.initialise() can fail on Android
// before storage permission is granted — falls back to app-private storage
// (always writable); the user can switch folders later in Settings ->
// Backup and storage.
//
// ANDROID VIDEO: native extraction (zen/innertubex MethodChannel — Kotlin
// host untouched on this branch) warms at boot for the video watch page.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:zenmusic/desktop/main.dart' show ZenDesktopApp, initialiseHive;
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/file_storage.dart';
import 'package:zenmusic/desktop/services/innertubex_bridge.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initialiseHive();
  await AppearancePrefs.load();
  // Media notifications + background playback. just_audio_background is the
  // standard ANDROID path — the recorded audio_service crash was
  // Windows-only (audio_service has no Windows implementation; Android is
  // its home platform). The AndroidManifest already carries the
  // audio_service declarations from the legacy stack.
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
    // Storage not grantable yet (fresh install) — fall back to
    // app-private storage so the app always boots.
    final docs = await getApplicationDocumentsDirectory();
    await Hive.box('SETTINGS').put('APP_FOLDER', docs.path);
    await FileStorage.initialise();
  }

  // ANDROID VIDEO: warm the native extraction resolver (zen/innertubex) —
  // primes visitorData for the video watch page. No-op on other platforms
  // (bridge reports available=false).
  unawaited(InnertubexBridge.warm());

  // PORT: desktop service set, verbatim ordering.
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

  final libraryService = LibraryService();
  GetIt.I.registerSingleton<LibraryService>(libraryService);

  final fileStorage = FileStorage();
  GetIt.I.registerSingleton<FileStorage>(fileStorage);

  GetIt.I.registerSingleton<DownloadManager>(DownloadManager());

  GetIt.I.registerSingleton<LyricsService>(LyricsService());

  GetIt.I.registerSingleton<YTMusic>(ytMusic);

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