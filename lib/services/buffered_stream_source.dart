import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

/// How long a read waits on bytes that never arrive before it gives up,
/// so a dead connection surfaces as a playback error instead of silence.
const _readStallTimeout = Duration(seconds: 30);

/// How often a read looks for bytes the download hasn't written yet.
const _readPollInterval = Duration(milliseconds: 50);

/// How much is handed to the player at a time.
const _readChunkSize = 64 * 1024;

/// ZenMusic's buffered streaming — Musify's BufferedStreamAudioSource
/// ported to the ZenMusic pipeline. Plays a song out of a file that
/// fills up as it plays: bytes are fetched in ranged chunks (which
/// YouTube serves far faster than the single long request the player
/// makes on its own), so the file runs ahead of playback within seconds
/// and a slow network moment stops being audible.
///
/// The buffer file is dropped as soon as another song takes over.
// just_audio still marks its byte-serving source API experimental. It is
// the only way to feed the player from something other than a URL or a
// finished file, so the warning is accepted here.
// ignore: experimental_member_use
class BufferedStreamAudioSource extends StreamAudioSource {
  BufferedStreamAudioSource({
    required this.songId,
    required this.streamUrl,
    required this.headers,
    required this.totalBytes,
  }) : bufferFile = File(
    '${Directory.systemTemp.path}/zen_buffer/$songId-${_nextBufferId++}.part',
  );

  /// The download feeding the song being played. Starting another one
  /// discards it: skipping through a queue would otherwise leave a
  /// download running per song passed through.
  static BufferedStreamAudioSource? _active;
  static int _nextBufferId = 0;

  final String songId;
  final String streamUrl;
  final Map<String, String> headers;
  final int totalBytes;
  final File bufferFile;

  Future<void>? _download;
  StreamIterator<List<int>>? _downloadIterator;
  RandomAccessFile? _writeHandle;
  int _downloadedBytes = 0;
  bool _downloadDone = false;
  bool _discarded = false;
  Object? _downloadError;

  final http.Client _client = http.Client();

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (_discarded) {
      throw StateError('Stream buffer for $songId was discarded');
    }
    _ensureDownloadStarted();

    final from = start ?? 0;
    final to = end ?? totalBytes;

    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: totalBytes,
      contentLength: to - from,
      offset: from,
      stream: _read(from, to),
      contentType: 'audio/mpeg',
    );
  }

  /// Stops the download and drops the buffer file. Called when another
  /// song takes over.
  Future<void> discard() async {
    if (_discarded) return;
    _discarded = true;

    await _downloadIterator?.cancel();
    await _download;

    try {
      await _writeHandle?.close();
    } catch (_) {}
    _writeHandle = null;

    try {
      if (await bufferFile.exists()) await bufferFile.delete();
    } catch (_) {}

    if (identical(_active, this)) _active = null;
  }

  void _ensureDownloadStarted() {
    if (_discarded) {
      throw StateError('Stream buffer for $songId was discarded');
    }
    if (_download != null) return;

    final previous = _active;
    if (previous != null && previous != this) {
      unawaited(previous.discard());
    }
    _active = this;

    _download = _runDownload();
  }

  Future<void> _runDownload() async {
    try {
      await Directory('${Directory.systemTemp.path}/zen_buffer')
          .create(recursive: true);
      if (_discarded) return;

      final handle = await bufferFile.open(mode: FileMode.write);
      _writeHandle = handle;
      if (_discarded) return;

      // Ranged download — the exact mechanism that makes YouTube serve
      // bytes faster than a single long request.
      var position = 0;
      while (position < totalBytes) {
        if (_discarded) return;
        final end = min(position + _readChunkSize * 8, totalBytes) - 1;
        final request = http.Request('GET', Uri.parse(streamUrl))
          ..headers.addAll({
            ...headers,
            'Range': 'bytes=$position-$end',
          });
        final response =
        await _client.send(request).timeout(const Duration(seconds: 15));

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception(
              'Buffered download failed: HTTP ${response.statusCode}');
        }

        final iterator = StreamIterator(response.stream);
        _downloadIterator = iterator;
        while (await iterator.moveNext()) {
          final chunk = iterator.current;
          if (_discarded) return;
          await handle.writeFrom(chunk);
          _downloadedBytes += chunk.length;
          position += chunk.length;
        }

        // If the server ignored the Range header and sent the whole
        // body, don't loop forever.
        if (response.statusCode == 200) break;
      }

      await handle.flush();
    } catch (e) {
      _downloadError = e;
      print('Buffered stream error for $songId: $e');
    } finally {
      _downloadIterator = null;
      _downloadDone = true;
      // The write handle stays open, and the file on disk: the song is
      // still playing out of it. Both go in discard().
    }
  }

  Stream<List<int>> _read(int from, int to) async* {
    var position = from;
    var waited = Duration.zero;
    RandomAccessFile? handle;

    try {
      while (position < to) {
        if (_discarded) return;
        if (_downloadError != null) {
          throw Exception('Stream buffer failed for $songId: $_downloadError');
        }

        final available = _downloadedBytes - position;
        if (available <= 0) {
          // Nothing more is coming: the player has everything there is.
          if (_downloadDone) return;
          if (waited >= _readStallTimeout) {
            throw TimeoutException('Stream buffer stalled for $songId');
          }
          await Future<void>.delayed(_readPollInterval);
          waited += _readPollInterval;
          continue;
        }

        waited = Duration.zero;
        handle ??= await bufferFile.open();
        await handle.setPosition(position);

        final bytes = await handle.read(
          min(min(available, to - position), _readChunkSize),
        );
        if (bytes.isEmpty) {
          await Future<void>.delayed(_readPollInterval);
          continue;
        }

        position += bytes.length;
        yield bytes;
      }
    } finally {
      try {
        await handle?.close();
      } catch (_) {}
    }
  }
}

/// Clears leftover buffers from a crash or kill mid-song.
Future<void> clearStreamBuffers() async {
  try {
    final dir = Directory('${Directory.systemTemp.path}/zen_buffer');
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  } catch (_) {}
}