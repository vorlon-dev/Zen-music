// ZenMusic Desktop — entry point. ALWAYS run/build with an explicit target:
//   flutter run -d windows --no-enable-impeller -t lib/desktop/main.dart
//   flutter build windows -t lib/desktop/main.dart
// NEVER use the default entry on Windows: lib/main.dart is the MOBILE entry
// (Option B redesign) and lib/main.dart on Windows defaults to a crash
// (audio_service has no Windows implementation).
//
// Ported from Echo Music (GPL-3.0). Echo Music is Copyright (C) its authors;
// this port and ZenMusic remain GPL-3.0.
//
// SP-4 PROBE: RETIRED. The spike harness (sp4_probe.dart) is kept for future
// diagnostics but no longer auto-runs: it created its own UNMASKED WebView
// window at every launch — that was the cold-start "white tab for a few
// seconds" (SP-5b-stealth v4 only masks the ENGINE window, and v4 confirmed
// the engine itself never flashes). Flip kSp4SpikeEnabled to true to run the
// spike deliberately.

import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:zenmusic/desktop/core/app_theme.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/file_storage.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart';
import 'package:zenmusic/desktop/utils/router.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_desktop_engine.dart';
import 'package:zenmusic/desktop/spotify/sp4_probe.dart';
import 'package:zenmusic/hive/zen_duration_adapter.dart';

/// SP-4 spike harness gate. false = retired (normal builds). Flip to true
/// only when deliberately re-running the SP-4 diagnostic spike: it opens a
/// VISIBLE diagnostic WebView window, burns a real playback (CDN fetch +
/// two license POSTs) and prints the verdict, then closes.
const bool kSp4SpikeEnabled = false;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // desktop_webview_window: title-bar entry hook (documented requirement;
  // returns true only for its own subprocess, which must not run the app).
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  await initialiseHive();

  // PORT: Echo's desktop media_kit init, verbatim (title rebranded).
  // JustAudioBackground.init is intentionally NOT called — recorded crash path.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    JustAudioMediaKit.ensureInitialized();
    JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
    JustAudioMediaKit.title = 'ZenMusic';
    JustAudioMediaKit.prefetchPlaylist = true;
    JustAudioMediaKit.pitch = true;
  }

  // PORT: Echo calls FileStorage.initialise() here — creates the
  // Downloads/ZenMusic tree (Music + Back Up dirs) before any consumer.
  await FileStorage.initialise();
  await AppearancePrefs.load();
  // PORT: Echo's YTMusic construction, verbatim — Hive-backed visitorData.
  // First sendRequest with empty visitorData triggers resetVisitorId(), which
  // fetches a real VISITOR_DATA from music.youtube.com and persists it here
  // via onIdUpdate.
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

  // PORT: local audio stream server.
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

  // Spotify session: restore login state (Hive-backed). Cheap for token-only
  // sessions; mints a token for sp_dc sessions. No resolve, no dealer
  // connection at boot.
  unawaited(SpotifyAuth.instance.load());

  // SP-4 PROBE: retired — gated off. The spike opens its own VISIBLE
  // WebView window (no v4 masking) and burns a real playback per run;
  // auto-running it here was the cold-start white flash.
  if (kSp4SpikeEnabled && Platform.isWindows) {
    unawaited(runSp4Spike());
  }

  // SP-5b: pre-warm the engine WebView. Since SP-5b-stealth v4 the engine
  // window is BORN off-screen and masked, so warming at launch shows
  // nothing — and the first Spotify play skips the WebView2 + CDM spin-up.
  // (This call was present in the pre-SP-4 architecture and fell out during
  // manual edits; remove this block only if you dropped it deliberately.)
  if (Platform.isWindows) {
    unawaited(SpotifyDesktopEngine.instance.warm());
  }

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

class ZenDesktopApp extends StatelessWidget {
  const ZenDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp.router(
        title: 'ZenMusic Desktop',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: context.watch<SettingsManager>().themeMode,
        theme: AppTheme.light(primary: Colors.black),
        darkTheme: AppTheme.dark(primary: Colors.white),
        // Light-mode fix: an OPAQUE root surface. Echo paints scaffold
        // backgrounds transparent (acrylic-desktop look); over Flutter's
        // default that renders black, which light mode exposes. surfaceTint
        // resolves to a theme-correct opaque color in BOTH modes.
        builder: (context, child) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

Future<void> initialiseHive() async {
  String? applicationDataDirectoryPath;
  if (Platform.isWindows || Platform.isLinux) {
    applicationDataDirectoryPath =
    "${(await getApplicationSupportDirectory()).path}/database";
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  Hive.registerAdapter(ZenDurationAdapter());
  await Hive.openBox('SETTINGS');
  await Hive.openBox('LIBRARY');
  await Hive.openBox('SEARCH_HISTORY');
  await Hive.openBox('SONG_HISTORY');
  await Hive.openBox('FAVOURITES');
  await Hive.openBox('DOWNLOADS');
}