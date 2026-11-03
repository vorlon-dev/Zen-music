/// ZenEngine: The complete, plug-and-play music brain for Flutter.
///
/// Provides multi-source search (JioSaavn & YouTube), high-fidelity lossless
/// stream resolution, synced LRC lyrics (LRCLIB & Kugou), background-ready
/// audio playback & queue controller, offline downloads, and synchronized
/// Listen Together rooms.
library;

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
export 'src/lyrics/lyrics_engine.dart';
export 'src/lossless/lossless_engine.dart';
export 'src/downloads/download_engine.dart';
export 'src/jam/jam_engine.dart';
export 'src/spotify/spotify_service.dart';
