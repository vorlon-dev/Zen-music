import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'audio/zen_audio_handler.dart';
import 'models/song.dart';
import 'screens/home_screen.dart';
import 'services/share_intent_service.dart';
import 'services/storage_service.dart';
import 'services/youtube_service.dart';
import 'theme/spotify_theme.dart';

late ZenAudioHandler audioHandler;
late StorageService storage;

/// Global navigator key — used by the share-intent service to push the
/// video watch page when a YouTube link is shared into the app.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive storage
  storage = StorageService();
  await storage.init();

  // yt_downloader needs no initialization — video mode is always available.
  YoutubeService.videoEnabled = true;

  // Full-screen app: hide the status bar and the 3-button nav bar
  // globally. Immersive-sticky re-hides them automatically after the
  // user swipes the edge, like the YouTube app.
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize audio service
  audioHandler = await AudioService.init(
    builder: () => ZenAudioHandler(storage: storage),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.zenmusic.audio',
      androidNotificationChannelName: 'ZenMusic Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(const ZenMusicApp());
}

class ZenMusicApp extends StatefulWidget {
  const ZenMusicApp({super.key});

  @override
  State<ZenMusicApp> createState() => _ZenMusicAppState();
}

class _ZenMusicAppState extends State<ZenMusicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Share-target: YouTube links shared from other apps open the video
    // watch page directly. Registered after the first frame so the
    // navigator exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        ShareIntentService.instance.init(nav);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ShareIntentService.instance.dispose();
    super.dispose();
  }

  // Re-assert immersive mode whenever the app resumes — the system can
  // restore system bars after dialogs, permission prompts, or the
  // in-app APK installer opens over us.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlayerController(),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'ZenMusic',
        debugShowCheckedModeBanner: false,
        theme: SpotifyTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}

class PlayerController extends ChangeNotifier {
  Song? currentSong;
  bool isPlaying = false;

  PlayerController() {
    audioHandler.currentSongStream.listen((song) {
      currentSong = song;
      notifyListeners();
    });
    audioHandler.playingStream.listen((playing) {
      isPlaying = playing;
      notifyListeners();
    });
  }
}