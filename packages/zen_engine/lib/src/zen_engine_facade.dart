import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'jiosaavn/jiosaavn_service.dart';
import 'ytmusic/yt_engine.dart';
import 'ytmusic/innertube_service.dart';
import 'ytmusic/potoken_service.dart';
import 'ytmusic/js_solver.dart';
import 'lossless/lossless_engine.dart';
import 'lyrics/lyrics_engine.dart';
import 'downloads/download_engine.dart';
import 'jam/jam_engine.dart';
import 'spotify/spotify_service.dart';
import 'services/search_service.dart';
import 'player/player_controller.dart';

/// The central entry point ("Brain") of the ZenEngine music system.
///
/// Simply initialize via:
/// ```dart
/// await ZenEngine.instance.init();
/// ```
class ZenEngine {
  ZenEngine._();

  static final ZenEngine _instance = ZenEngine._();
  static ZenEngine get instance => _instance;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  late final JioSaavnService _jioSaavn;
  late final YouTubeEngine _youtube;
  late final InnerTubeService _innertube;
  late final PoTokenService _poToken;
  late final ZenJSSolver _jsSolver;
  late final SearchEngine _search;
  late final LosslessEngine _lossless;
  late final LyricsEngine _lyrics;
  late final DownloadEngine _downloads;
  late final JamEngine _jam;
  late final SpotifyService _spotify;
  late final ZenPlayerController _player;

  /// JioSaavn streaming & catalog service
  static JioSaavnService get jioSaavn => _instance._jioSaavn;

  /// YouTube Explode extraction service
  static YouTubeEngine get youtube => _instance._youtube;

  /// InnerTube client with poToken support
  static InnerTubeService get innertube => _instance._innertube;

  /// Proof-of-Origin token solver & manager
  static PoTokenService get poToken => _instance._poToken;

  /// JavaScript challenge solver for signature cipher & n-parameter
  static ZenJSSolver get jsSolver => _instance._jsSolver;

  /// Multi-source unified Search engine
  static SearchEngine get search => _instance._search;

  /// Lossless multi-tier stream resolver (Hi-Res / FLAC / 320kbps)
  static LosslessEngine get lossless => _instance._lossless;

  /// LRCLIB and Kugou time-synced lyrics engine
  static LyricsEngine get lyrics => _instance._lyrics;

  /// Offline cache and file download manager
  static DownloadEngine get downloads => _instance._downloads;

  /// Real-time Listen Together room synchronization engine
  static JamEngine get jam => _instance._jam;

  /// Spotify metadata & search engine
  static SpotifyService get spotify => _instance._spotify;

  /// Complete queue and playback controller
  static ZenPlayerController get player => _instance._player;

  /// Initialize all ZenEngine subsystems, local Hive databases, and audio pipeline.
  Future<void> init({
    AudioPlayer? customAudioPlayer,
    YoutubeExplode? customYoutubeExplode,
    String? jamServerUrl,
    String? losslessEndpoint,
  }) async {
    if (_initialized) return;

    WidgetsFlutterBinding.ensureInitialized();
    await Hive.initFlutter();

    _poToken = PoTokenService();
    _jsSolver = ZenJSSolver();
    _innertube = InnerTubeService(poTokenService: _poToken);

    _youtube = YouTubeEngine(
      yt: customYoutubeExplode ?? YoutubeExplode(),
    );

    _jioSaavn = JioSaavnService();
    _lossless = LosslessEngine(
      endpoint: losslessEndpoint ?? 'https://jobfolw.antideploy.app/',
    );
    _lyrics = LyricsEngine();
    _downloads = DownloadEngine(
      lossless: _lossless,
      youtube: _youtube,
      jioSaavn: _jioSaavn,
    );
    await _downloads.init();

    _jam = JamEngine(
      serverUrl: jamServerUrl ?? 'wss://metroserver.up.railway.app',
    );
    _spotify = SpotifyService();
    _search = SearchEngine(jioSaavn: _jioSaavn, youtube: _youtube);

    _player = ZenPlayerController(
      audioPlayer: customAudioPlayer,
      lossless: _lossless,
      youtube: _youtube,
      jioSaavn: _jioSaavn,
      downloads: _downloads,
    );

    await _player.restoreSession();

    _initialized = true;
  }

  /// Cleanly dispose all engines and audio resources
  void dispose() {
    if (!_initialized) return;
    _player.dispose();
    _downloads.dispose();
    _jam.dispose();
    _lyrics.dispose();
    _youtube.dispose();
    _innertube.dispose();
    _poToken.dispose();
    _jsSolver.dispose();
    _jioSaavn.dispose();
    _spotify.dispose();
    _initialized = false;
  }
}
