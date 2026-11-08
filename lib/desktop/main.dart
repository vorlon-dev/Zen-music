// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/lyrics_romanizer.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/lyric_motion.dart';
import 'package:zenmusic/desktop/services/lyric_styles.dart';
import 'package:zenmusic/desktop/services/lyric_translation.dart';
import 'package:zenmusic/desktop/services/sing_mode.dart';
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
import 'package:zenmusic/desktop/liquid/glass_panel.dart' show kUsePackageGlass;
import 'package:zenmusic/desktop/liquid/liquid_backdrop.dart';
import 'package:zenmusic/desktop/liquid/liquid_bridge.dart';
import 'package:zenmusic/desktop/liquid/liquid_theme.dart';
import 'package:zenmusic/desktop/material3/m3_bridge.dart';
import 'package:zenmusic/desktop/material3/m3_palette.dart';
import 'package:zenmusic/desktop/material3/m3_theme.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:zenmusic/desktop/services/download_manager.dart';
import 'package:zenmusic/desktop/services/file_storage.dart';
import 'package:zenmusic/desktop/services/jam_service.dart';
import 'package:zenmusic/desktop/services/library.dart';
import 'package:zenmusic/desktop/services/lyrics.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';
import 'package:zenmusic/desktop/services/yt_audio_stream.dart';
import 'package:zenmusic/desktop/utils/router.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/ytmusic/modals/yt_config.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart';
import 'package:zenmusic/desktop/services/zen_wall_service.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/spotify/spotify_desktop_engine.dart';
import 'package:zenmusic/desktop/spotify/sp4_probe.dart';
import 'package:zenmusic/hive/zen_duration_adapter.dart';

const bool kSp4SpikeEnabled = false;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // desktop_webview_window: title-bar entry hook (documented requirement;
  // returns true only for its own subprocess, which must not run the app).
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  await initialiseHive();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    JustAudioMediaKit.ensureInitialized();
    JustAudioMediaKit.bufferSize = 8 * 1024 * 1024;
    JustAudioMediaKit.title = 'ZenMusic';
    JustAudioMediaKit.prefetchPlaylist = true;
    JustAudioMediaKit.pitch = true;
  }

  await FileStorage.initialise();
  await AppearancePrefs.load();
  await L10n.load();
  LyricStylePrefs.load();
  LyricMotionPrefs.load();
  LyricsTranslation.instance.load();
  LyricsRomanizer.instance.load();
  unawaited(SingMode.instance.restore());

  if (Platform.isWindows) {
    await LiquidGlassWidgets.initialize();
  }
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

  unawaited(loadM3Tokens());

  final String audioStreamUrl = await createAudioStreamServer();
  GetIt.I.registerSingleton<String>(audioStreamUrl,
      instanceName: 'audioStreamUrl');

  final MediaPlayer mediaPlayer = MediaPlayer();
  GetIt.I.registerSingleton<MediaPlayer>(mediaPlayer);

  GetIt.I.registerSingleton<BeatHapticsEngine>(
      BeatHapticsEngine(mediaPlayer));
  GetIt.I<BeatHapticsEngine>().start();
  ZenWallService.instance.attach(mediaPlayer.currentSongNotifier);

  final libraryService = LibraryService();
  GetIt.I.registerSingleton<LibraryService>(libraryService);

  final fileStorage = FileStorage();
  GetIt.I.registerSingleton<FileStorage>(fileStorage);

  GetIt.I.registerSingleton<DownloadManager>(DownloadManager());

  GetIt.I.registerSingleton<LyricsService>(LyricsService());

  GetIt.I.registerSingleton<YTMusic>(ytMusic);

  JamService.instance.start(mediaPlayer);

  // Spotify session: restore login state (Hive-backed). Cheap for token-only
  // sessions; mints a token for sp_dc sessions. No resolve, no dealer
  // connection at boot.
  unawaited(SpotifyAuth.instance.load());

  YtmAuth.instance.load();

  if (kSp4SpikeEnabled && Platform.isWindows) {
    unawaited(runSp4Spike());
  }

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
    final settings = context.watch<SettingsManager>();
    final liquid = settings.liquidGlass;
    final dark = getDarkness(settings.themeModes.indexOf(settings.themeMode));

    // Keep the Kotlin glass engine in sync on Android (no-op on desktop).
    if (Platform.isAndroid) {
      LiquidGlassBridge.instance
          .sync(enabled: liquid, dark: dark, accent: settings.accentColor?.value);
      unawaited(LiquidGlassBridge.instance.warmUp());
    }

    Widget app = Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.select): const ActivateIntent(),
      },
      child: MaterialApp.router(
        title: 'ZenMusic Desktop',
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: settings.themeMode,
        theme: switch (settings.uiTheme) {
          'm3' => ZenM3Theme.light(primary: settings.accentColor),
          'liquid' =>
            ZenLiquidTheme.light(primary: settings.accentColor),
          _ => AppTheme.light(primary: Colors.black),
        },
        darkTheme: switch (settings.uiTheme) {
          'm3' => ZenM3Theme.dark(primary: settings.accentColor),
          'liquid' =>
            ZenLiquidTheme.dark(primary: settings.accentColor),
          _ => AppTheme.dark(primary: Colors.white),
        },
        builder: (context, child) {
          return Directionality(
            textDirection: L10n.isRtl ? TextDirection.rtl : TextDirection.ltr,
            child: Stack(
            fit: StackFit.expand,
            children: [
              if (liquid)
                LiquidBackdrop(
                  dark: dark,
                  accent: settings.accentColor,
                  child: const SizedBox.expand(),
                )
              else
                ColoredBox(
                  color: settings.uiTheme == 'm3'
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? ZenM3Palette.darkBackground
                          : ZenM3Palette.lightBackground)
                      : Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: const SizedBox.expand(),
                ),
              if (child != null) child!,
            ],
          ));
        },
      ),
    );

    if (liquid && Platform.isWindows && kUsePackageGlass) {
      app = LiquidGlassWidgets.wrap(
        child: app,
        brightnessResolver: Theme.maybeBrightnessOf,
        adaptiveQuality: true,
        theme: GlassThemeData.simple(
          blur: 12,
          thickness: 30,
          quality: GlassQuality.standard,
        ),
      );
    }

    return app;
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
  await Future.wait<void>([
    Hive.openBox('SETTINGS'),
    Hive.openBox('LIBRARY'),
    Hive.openBox('SEARCH_HISTORY'),
    Hive.openBox('SONG_HISTORY'),
    Hive.openBox('FAVOURITES'),
    Hive.openBox('DOWNLOADS'),
  ]);
}
