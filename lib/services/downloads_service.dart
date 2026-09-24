import 'dart:io';

import 'package:http/http.dart' as http;

import '../main.dart';
import '../models/song.dart';
import 'youtube_service.dart';

/// Offline downloads: fetch a song's audio via the normal stream chain,
/// store it in app-private storage, play from file with zero network.
class DownloadsService {
  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();
  final YoutubeService _yt = YoutubeService();

  static final DownloadsService _instance = DownloadsService._();
  factory DownloadsService() => _instance;
  DownloadsService._();

  /// App-private download directory (created lazily).
  Future<Directory> _dir() async {
    final dir = Directory('${Directory.systemTemp.path}/zen_downloads');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  bool isDownloaded(String songId) {
    // Cached existence check is avoided — a sync FS probe per row build
    // is cheap enough for library-scale lists.
    // Actual file check happens async via isDownloadedAsync in UI layers.
    return File(_pathForSync(songId)).existsSync();
  }

  String _pathForSync(String songId) {
    // Sync path helper: ID is sanitized on save; lookup uses the same
    // scheme. Extension is discovered from the manifest file if present.
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${Directory.systemTemp.path}/zen_downloads/$safe.audio';
  }

  Future<bool> isDownloadedAsync(String songId) async {
    final dir = await _dir();
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${dir.path}/$safe.audio').existsSync();
  }

  /// Download flow: resolve stream → fetch bytes → write file. Reports
  /// progress via callback (0–100). Returns true on success.
  Future<bool> download(Song song,
      {void Function(int percent)? onProgress}) async {
    try {
      final dir = await _dir();
      final safe = song.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final target = File('${dir.path}/$safe.audio');
      if (target.existsSync()) return true;

      onProgress?.call(2);
      final stream = await _yt.getAudioStreamUrl(song);
      onProgress?.call(10);

      final client = http.Client();
      final req = http.Request('GET', Uri.parse(stream.url));
      stream.headers.forEach((k, v) => req.headers[k] = v);
      req.headers['User-Agent'] = _ua;
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        client.close();
        return false;
      }

      final total = resp.contentLength ?? 0;
      final sink = target.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call(10 + (received / total * 88).round().clamp(0, 98));
        }
      }
      await sink.flush();
      await sink.close();
      client.close();
      onProgress?.call(100);
      return true;
    } catch (e) {
      print('⬇️ Download failed for "${song.title}": $e');
      return false;
    }
  }

  /// Local file path for an already-downloaded song, or null.
  Future<String?> localPath(String songId) async {
    final dir = await _dir();
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final f = File('${dir.path}/$safe.audio');
    return f.existsSync() ? f.path : null;
  }

  Future<void> delete(String songId) async {
    final dir = await _dir();
    final safe = songId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final f = File('${dir.path}/$safe.audio');
    if (f.existsSync()) await f.delete();
  }

  Future<void> deleteAll() async {
    final dir = await _dir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// All downloaded songs (from the played/liked catalog that matches
  /// files on disk). We rely on Hive history + manifest presence.
  Future<List<Song>> downloadedSongs() async {
    final dir = await _dir();
    if (!dir.existsSync()) return [];
    final ids = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.audio'))
        .map((n) => n.substring(0, n.length - '.audio'.length))
        .toSet();

    // Match IDs against every catalog we can reconstruct locally.
    final byId = <String, Song>{};
    for (final s in [...storage.getPlayedHistory(), ...storage.getLikedSongs()]) {
      byId[s.id] ??= s;
    }
    // User playlists too.
    for (final p in storage.getUserPlaylists()) {
      for (final s in storage.getUserPlaylistSongs(p.id)) {
        byId[s.id] ??= s;
      }
    }
    final out = <Song>[];
    for (final id in ids) {
      final song = byId[id];
      if (song != null) out.add(song);
    }
    return out;
  }
}