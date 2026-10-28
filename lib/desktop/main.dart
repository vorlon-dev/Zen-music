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
import 'package:zenmusic/desktop/liquid/glass_panel.dart' show kUsePackageGlass; // SP-54
import 'package:zenmusic/desktop/liquid/liquid_backdrop.dart'; // SP-54
import 'package:zenmusic/desktop/liquid/liquid_bridge.dart'; // SP-54
import 'package:zenmusic/desktop/liquid/liquid_theme.dart'; // SP-54
import 'package:zenmusic/desktop/material3/m3_bridge.dart'; // SP-58
import 'package:zenmusic/desktop/material3/m3_palette.dart'; // SP-58
import 'package:zenmusic/desktop/material3/m3_theme.dart'; // SP-58
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart'; // SP-54 (Windows shader glass)
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

  // SP-54: pre-warm the liquid_glass_widgets shaders (Windows). This is
  // async disk-to-RAM I/O only — no GPU work, no window-present delay — and
  // unconditionally calling it means the theme can be toggled ON later
  // without an app restart.
  if (Platform.isWindows) {
    await LiquidGlassWidgets.initialize();
  }
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

  // SP-58: pull the native Material 3 palette (res/values/
  // material3_tokens.xml → Material3Tokens.kt) once at boot. Failure-soft;
  // identical Dart fallbacks make this invisible when absent.
  unawaited(loadM3Tokens());

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

  // SP-62: YouTube Music account — restore the device-OAuth session (or the
  // pasted-cookie fallback) so the home feed is personalized from boot.
  // YtmAuth resolves through the ytmusic.dart barrel (SP-62.1 re-export).
  YtmAuth.instance.load();

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
    // ── SP-54: Liquid Glass — whole-app theme switch ──
    // One flag flips EVERYTHING: ThemeData (translucent glass surfaces),
    // the root surface (aurora backdrop instead of opaque colour) and, on
    // Windows, the shader-glass provider wrapping the app.
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
        // SP-58: three whole-app themes — Classic / Liquid Glass /
        // Material 3 (the PixelMusic design system). Each branch re-skins
        // every screen through ThemeData alone.
        theme: switch (settings.uiTheme) {
          'm3' => ZenM3Theme.light(primary: settings.accentColor), // SP-58
          'liquid' =>
            ZenLiquidTheme.light(primary: settings.accentColor), // SP-54
          _ => AppTheme.light(primary: Colors.black),
        },
        darkTheme: switch (settings.uiTheme) {
          'm3' => ZenM3Theme.dark(primary: settings.accentColor), // SP-58
          'liquid' =>
            ZenLiquidTheme.dark(primary: settings.accentColor), // SP-54
          _ => AppTheme.dark(primary: Colors.white),
        },
        builder: (context, child) {
          // SP-56: the app (Router/Navigator) sits in a PERMANENT Stack slot
          // and only the decorative backdrop layer swaps widget type below
          // it. The pre-SP-56 builder wrapped `child` IN the backdrop, so
          // the first Liquid Glass toggle replaced ColoredBox with
          // LiquidBackdrop — a different runtimeType at the same slot —
          // which destroyed and re-inflated the ENTIRE navigator element
          // tree (every page State wiped) in the same frame the first
          // platform views were born. The backdrop is purely decorative;
          // the type swap now happens where nothing stateful lives.
          //
          // SP-57 (Android): ZERO platform views — the warm-up view is
          // GONE. The SP-56 field logcat showed the 1×1 warm-up view
          // itself being torn down at the exact moment the toggle created
          // the first glass panel view: real devices churn the
          // platform-view set mid-session even with the pipeline primed at
          // boot, and still drop every page plane. glass_panel.dart now
          // renders its surfaces in Dart (frosted glass), so a Liquid
          // Glass toggle changes NOTHING in the Android compositor — the
          // blank-page bug is structurally impossible. The stable slot
          // below is still worth keeping: page state survives the theme
          // flip on every platform.
          return Stack(
            fit: StackFit.expand,
            children: [
              if (liquid)
                // SP-54: the animated aurora IS the backdrop — glass
                // surfaces (and every translucent colorScheme surface)
                // read through it. SP-56: decorative layer only; the app
                // lives in the stable slot above.
                LiquidBackdrop(
                  dark: dark,
                  accent: settings.accentColor,
                  child: const SizedBox.expand(),
                )
              else
                // Classic mode (pre-SP-54): opaque backdrop. Echo paints
                // scaffold backgrounds transparent (acrylic-desktop look);
                // over Flutter's default that renders black, which light
                // mode exposes. SP-58: Material 3 paints PixelMusic's
                // exact background anchors (deep purple dark / tinted
                // white light) instead.
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
          );
        },
      ),
    );

    // SP-54 (Windows only): shader glass provider — adaptiveQuality
    // benchmarks the GPU and degrades gracefully (premium → standard →
    // minimal) under load, which is the low-end safety net here.
    // brightnessResolver is REQUIRED for MaterialApp users so glass
    // widgets honour themeMode instead of raw OS brightness.
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
  await Hive.openBox('SETTINGS');
  await Hive.openBox('LIBRARY');
  await Hive.openBox('SEARCH_HISTORY');
  await Hive.openBox('SONG_HISTORY');
  await Hive.openBox('FAVOURITES');
  await Hive.openBox('DOWNLOADS');
}