/// ZenEngine: The complete, plug-and-play music brain for Flutter.
///
/// Provides built-in InnerTube API with poToken support, JavaScript challenge solver,
/// YouTube Explode extraction, multi-source search (JioSaavn & YouTube),
/// high-fidelity lossless stream resolution, synced LRC lyrics (LRCLIB & Kugou),
/// background-ready audio playback & queue controller, offline downloads, and synchronized
/// Listen Together rooms.
library;

// Re-export youtube_explode_dart
export 'package:youtube_explode_dart/youtube_explode_dart.dart';

// Core Facade
export 'src/zen_engine_facade.dart';

// Models
export 'src/models/song_model.dart';
export 'src/player/player_state.dart';
export 'src/lyrics/lyrics_model.dart';
export 'src/lossless/lossless_engine.dart' show LosslessQuality;
export 'src/downloads/download_engine.dart' show DownloadTask, DownloadStatus;
export 'src/jam/jam_engine.dart' show JamRole;

// Controllers & Services
export 'src/player/player_controller.dart';
export 'src/services/search_service.dart';
export 'src/jiosaavn/jiosaavn_service.dart';
export 'src/ytmusic/yt_engine.dart';
export 'src/ytmusic/innertube_service.dart';
export 'src/ytmusic/potoken_service.dart';
export 'src/ytmusic/js_solver.dart';
export 'src/lyrics/lyrics_engine.dart';
export 'src/lossless/lossless_engine.dart';
export 'src/downloads/download_engine.dart';
export 'src/jam/jam_engine.dart';
export 'src/spotify/spotify_service.dart';
