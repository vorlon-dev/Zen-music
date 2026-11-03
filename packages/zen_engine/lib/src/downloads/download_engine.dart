import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:hive/hive.dart';
import '../models/song_model.dart';
import '../lossless/lossless_engine.dart';
import '../ytmusic/yt_engine.dart';
import '../jiosaavn/jiosaavn_service.dart';

enum DownloadStatus {
  idle,
  downloading,
  completed,
  failed,
}

class DownloadTask {
  final ZenSong song;
  final String filePath;
  final DownloadStatus status;
  final double progress;
  final String? error;

  const DownloadTask({
    required this.song,
    required this.filePath,
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.error,
  });

  DownloadTask copyWith({
    ZenSong? song,
    String? filePath,
    DownloadStatus? status,
    double? progress,
    String? error,
  }) {
    return DownloadTask(
      song: song ?? this.song,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

/// Headless offline download and cache manager.
class DownloadEngine {
  DownloadEngine({
    LosslessEngine? lossless,
    YouTubeEngine? youtube,
    JioSaavnService? jioSaavn,
  })  : _lossless = lossless ?? LosslessEngine(),
        _youtube = youtube ?? YouTubeEngine(),
        _jioSaavn = jioSaavn ?? JioSaavnService();

  final LosslessEngine _lossless;
  final YouTubeEngine _youtube;
  final JioSaavnService _jioSaavn;

  final Map<String, DownloadTask> _tasks = {};
  final StreamController<Map<String, DownloadTask>> _tasksController =
      StreamController<Map<String, DownloadTask>>.broadcast();

  Stream<Map<String, DownloadTask>> get tasksStream => _tasksController.stream;
  Map<String, DownloadTask> get tasks => Map.unmodifiable(_tasks);

  static const String _boxName = 'ZEN_DOWNLOADS';

  Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
  }

  /// Check if a song is downloaded offline
  bool isDownloaded(String songId) {
    if (!Hive.isBoxOpen(_boxName)) return false;
    final box = Hive.box(_boxName);
    final path = box.get(songId) as String?;
    if (path == null) return false;
    return File(path).existsSync();
  }

  /// Get local file path of a downloaded song
  String? getDownloadedPath(String songId) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final path = Hive.box(_boxName).get(songId) as String?;
    if (path != null && File(path).existsSync()) return path;
    return null;
  }

  /// Download a song with automatic stream resolution (Lossless / JioSaavn 320 / YouTube)
  Future<String?> download(ZenSong song) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'ZenDownloads'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final safeName = song.id.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final targetFile = File(p.join(dir.path, '$safeName.m4a'));

      if (targetFile.existsSync()) {
        _tasks[song.id] = DownloadTask(
          song: song,
          filePath: targetFile.path,
          status: DownloadStatus.completed,
          progress: 1.0,
        );
        _notify();
        return targetFile.path;
      }

      _tasks[song.id] = DownloadTask(
        song: song,
        filePath: targetFile.path,
        status: DownloadStatus.downloading,
        progress: 0.0,
      );
      _notify();

      // Resolve stream
      String? streamUrl;
      if (song.source == ZenSongSource.jiosaavn) {
        streamUrl = song.streamUrl ?? await _jioSaavn.fetchStreamUrl(song.id);
      } else {
        // Try lossless first
        streamUrl = await _lossless.resolveStreamUrl(song.id);
        // Fallback to youtube explode stream
        streamUrl ??= await _youtube.getAudioStreamUrl(song.id);
      }

      if (streamUrl == null) {
        throw Exception('Unable to resolve stream for download: ${song.id}');
      }

      // Download bytes
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(streamUrl));
      final res = await client.send(req);
      final total = res.contentLength ?? 0;
      int received = 0;

      final sink = targetFile.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = (received / total).clamp(0.0, 1.0);
          _tasks[song.id] = _tasks[song.id]!.copyWith(progress: progress);
          _notify();
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      // Save to Hive
      if (Hive.isBoxOpen(_boxName)) {
        await Hive.box(_boxName).put(song.id, targetFile.path);
      }

      _tasks[song.id] = _tasks[song.id]!.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
      );
      _notify();
      return targetFile.path;
    } catch (e) {
      _tasks[song.id] = (_tasks[song.id] ?? DownloadTask(song: song, filePath: ''))
          .copyWith(status: DownloadStatus.failed, error: e.toString());
      _notify();
      return null;
    }
  }

  void _notify() {
    if (!_tasksController.isClosed) {
      _tasksController.add(Map.unmodifiable(_tasks));
    }
  }

  void dispose() {
    _tasksController.close();
  }
}
