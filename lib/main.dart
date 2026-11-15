// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/lyrics_romanizer.dart';
import 'package:zenmusic/desktop/services/lyric_motion.dart';
import 'package:zenmusic/desktop/services/lyric_translation.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/lyric_styles.dart';
import 'package:zenmusic/desktop/services/sing_mode.dart';
import 'dart:async';
import 'dart:io' show Platform;

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
import 'package:zenmusic/desktop/services/discover_feed.dart';
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

  // First frame IMMEDIATELY. All initialisation used to run before runApp, so
  // a phone showed nothing and then stuttered for seconds/minutes while Hive,
  // the audio service, Discover, the YouTube bridge and the last session were
  // all loaded at the same moment. Now a splash is on screen at once, the
  // essential setup runs behind it in short steps (each step yields a frame so
  // the spinner keeps moving), and the heavy warm-ups start one after another
  // right after the UI is up - never all together.
  runApp(const _ZenBoot());
}

/// Let the engine draw one frame between boot steps.
Future<void> _yieldFrame() =>
    Future<void>.delayed(const Duration(milliseconds: 16));

class _ZenBoot extends StatefulWidget {
  const _ZenBoot();

  @override
  State<_ZenBoot> createState() => _ZenBootState();
}

class _ZenBootState extends State<_ZenBoot> {
  Widget? _app;

  @override
  void initState() {
    super.initState();
    // Start once the splash has been painted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final app = await _bootstrap();
    if (!mounted) return;
    setState(() => _app = app);
    _startBackgroundServices();
  }

  @override
  Widget build(BuildContext context) => _app ?? const _BootSplash();
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        child: Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: dark ? Colors.white : Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// Heavy warm-ups, staggered so no two land on the same frames.
void _startBackgroundServices() {
  void later(int ms, void Function() job) {
    Future<void>.delayed(Duration(milliseconds: ms), () {
      try {
        job();
      } catch (_) {}
    });
  }

  final mediaPlayer = GetIt.I<MediaPlayer>();
  later(500, () {
    GetIt.I<BeatHapticsEngine>().start();
    ZenWallService.instance.attach(mediaPlayer.currentSongNotifier);
  });
  later(900, () => unawaited(mediaPlayer.restoreLastSession()));
  later(1800, () => unawaited(InnertubexBridge.warm()));
  if (Platform.isAndroid || Platform.isIOS) {
    later(3000, () => unawaited(DiscoverFeed.instance.warm()));
  }
  later(4500, () => JamService.instance.start(mediaPlayer));
}

Future<Widget> _bootstrap() async {
  await initialiseHive();
  await _yieldFrame();

  // These do not depend on each other (only on Hive, which is ready), so run
  // them together.
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
  await _yieldFrame();
  // Feature pack prefs (need Hive/SETTINGS, so they run after the block above)
  await L10n.load();
  LyricStylePrefs.load();
  LyricMotionPrefs.load();
  LyricsTranslation.instance.load();
  LyricsRomanizer.instance.load();
  unawaited(SingMode.instance.restore());

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
  await _yieldFrame();

  final MediaPlayer mediaPlayer = MediaPlayer();
  GetIt.I.registerSingleton<MediaPlayer>(mediaPlayer);
  await _yieldFrame();

  // Registered now (the UI may look it up); started in
  // _startBackgroundServices().
  GetIt.I.registerSingleton<BeatHapticsEngine>(
      BeatHapticsEngine(mediaPlayer));

  unawaited(SpotifyAuth.instance.load());

  final libraryService = LibraryService();
  GetIt.I.registerSingleton<LibraryService>(libraryService);

  final fileStorage = FileStorage();
  GetIt.I.registerSingleton<FileStorage>(fileStorage);

  GetIt.I.registerSingleton<DownloadManager>(DownloadManager());

  GetIt.I.registerSingleton<LyricsService>(LyricsService());

  GetIt.I.registerSingleton<YTMusic>(ytMusic);

  YtmAuth.instance.load();
  await _yieldFrame();

  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => settingsManager),
      ChangeNotifierProvider(create: (_) => mediaPlayer),
      ChangeNotifierProvider(create: (_) => libraryService),
    ],
    child: const ZenDesktopApp(),
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
