import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio/zen_audio_handler.dart';
import 'models/song.dart';
import 'screens/home_screen.dart';
import 'services/storage_service.dart';
import 'services/youtube_service.dart';
import 'theme/spotify_theme.dart';

late ZenAudioHandler audioHandler;
late StorageService storage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive storage
  storage = StorageService();
  await storage.init();

  // yt_downloader needs no initialization — video mode is always available.
  YoutubeService.videoEnabled = true;

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

class ZenMusicApp extends StatelessWidget {
  const ZenMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PlayerController(),
      child: MaterialApp(
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