import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/yt_music_service.dart';
import '../theme/spotify_theme.dart';

class ImportSpotifyScreen extends StatefulWidget {
  const ImportSpotifyScreen({super.key});

  @override
  State<ImportSpotifyScreen> createState() => _ImportSpotifyScreenState();
}

class _ImportSpotifyScreenState extends State<ImportSpotifyScreen> {
  static bool _importRunning = false;
  static const _batchSize = 12;
  static const _batchPause = Duration(milliseconds: 150);

  final _csvController = TextEditingController();
  final _playlistNameController = TextEditingController();
  bool _isImporting = false;
  String? _fileName;
  int _processedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _csvController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _chooseFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (files.isEmpty || !mounted) return;

    final file = files.first;
    final path = file.path;
    if (path == null) {
      _toast('Could not read the selected file');
      return;
    }
    _csvController.text = await File(path).readAsString();
    if (!mounted) return;
    setState(() => _fileName = file.name);
  }

  Future<void> _importPlaylist() async {
    if (_isImporting) return;
    if (_importRunning) {
      _toast('An import is already running');
      return;
    }
    final playlistName = _playlistNameController.text.trim();
    if (playlistName.isEmpty) {
      _toast('Enter a playlist name first');
      return;
    }
    final records = _parseCsv(_csvController.text);
    if (records.length < 2) {
      _toast('Playlist CSV is empty');
      return;
    }

    final headers = records.first
        .map((h) => h.replaceFirst('\ufeff', '').trim().toLowerCase())
        .toList();
    bool isNameColumn(String h) =>
        !h.contains('id') &&
            !h.contains('uri') &&
            !h.contains('url') &&
            !h.contains('genre');
    final songIndex = headers.indexWhere(
          (h) => (h.contains('song') || h.contains('track')) && isNameColumn(h),
    );
    final artistIndex =
    headers.indexWhere((h) => h.contains('artist') && isNameColumn(h));
    if (songIndex == -1 || artistIndex == -1) {
      _toast('CSV must contain song and artist columns');
      return;
    }

    final rows = <({int index, String title, String artist})>[];
    var rowIndex = 0;
    for (final row in records.skip(1)) {
      if (row.length > songIndex &&
          row.length > artistIndex &&
          row[songIndex].trim().isNotEmpty) {
        rows.add((
        index: rowIndex++,
        title: row[songIndex].trim(),
        artist: row[artistIndex].trim(),
        ));
      }
    }
    if (rows.isEmpty) {
      _toast('No songs found in the CSV');
      return;
    }

    _importRunning = true;
    setState(() {
      _isImporting = true;
      _processedCount = 0;
      _totalCount = rows.length;
    });

    final foundByIndex = <int, Song>{};
    var missingRows = <({int index, String title, String artist})>[];
    var rateLimited = false;
    try {
      final firstPass = await _searchBatch(rows, (n) {
        if (mounted) setState(() => _processedCount += n);
      });
      foundByIndex.addAll(firstPass.found);
      missingRows = firstPass.missing;
      rateLimited = firstPass.rateLimited;

      if (!rateLimited && missingRows.isNotEmpty) {
        if (mounted) setState(() => _totalCount += missingRows.length);
        final retryPass = await _searchBatch(missingRows, (n) {
          if (mounted) setState(() => _processedCount += n);
        });
        foundByIndex.addAll(retryPass.found);
        missingRows = retryPass.missing;
        rateLimited = retryPass.rateLimited;
      }
    } finally {
      _importRunning = false;
    }

    final foundSongs = [
      for (final row in rows)
        if (foundByIndex[row.index] != null) foundByIndex[row.index]!,
    ];

    final playlistId = await storage.createUserPlaylist(playlistName);
    await storage.addUserPlaylistSongs(playlistId, foundSongs);

    if (!mounted) return;
    setState(() => _isImporting = false);

    final resultText = rateLimited
        ? 'Import stopped early (rate limited)\n'
        'Found ${foundSongs.length} of ${rows.length} songs'
        : 'Found ${foundSongs.length} of ${rows.length} songs';

    if (missingRows.isNotEmpty) {
      final missingText = missingRows
          .map((r) => '${r.title} - ${r.artist}')
          .join('\n');
      await Clipboard.setData(ClipboardData(text: missingText));
      _toast('$resultText\nMissing list copied to clipboard');
    } else {
      _toast(resultText);
    }
  }

  Future<({
  Map<int, Song> found,
  List<({int index, String title, String artist})> missing,
  bool rateLimited,
  })> _searchBatch(
      List<({int index, String title, String artist})> rows,
      void Function(int) onProgress,
      ) async {
    final found = <int, Song>{};
    final missing = <({int index, String title, String artist})>[];
    for (var i = 0; i < rows.length; i += _batchSize) {
      final batch = rows.skip(i).take(_batchSize).toList();
      final results = await Future.wait(
        batch.map((row) async {
          final song = await _findSongWithRetry(
            '${row.title} ${row.artist}',
            expectedArtist: row.artist,
            expectedTitle: row.title,
          );
          return (row, song);
        }),
      );
      var batchRateLimited = false;
      for (final (row, song) in results) {
        if (YtMusicService.lastSearchRateLimited) batchRateLimited = true;
        if (song == null) {
          missing.add(row);
        } else {
          found[row.index] = song;
        }
      }
      onProgress(batch.length);
      if (batchRateLimited) {
        missing.addAll(rows.skip(i + _batchSize));
        return (found: found, missing: missing, rateLimited: true);
      }
      await Future.delayed(_batchPause);
    }
    return (found: found, missing: missing, rateLimited: false);
  }

  Future<Song?> _findSongWithRetry(
      String query, {
        String? expectedArtist,
        String? expectedTitle,
      }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final song = await YtMusicService().searchSongMatch(
        query,
        expectedArtist: expectedArtist,
        expectedTitle: expectedTitle,
      );
      if (song != null) return song;
      if (YtMusicService.lastSearchRateLimited) return null;
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    return null;
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;

    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (character == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(character);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (row.any((v) => v.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Import Spotify playlist',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: SpotifyColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Export your Spotify playlist as CSV (e.g. from '
                  'chosic.com or tunemymusic.com), then import it here. '
                  'Every track is matched on YouTube Music and saved as a '
                  'playlist in your library.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: SpotifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: SpotifyColors.textPrimary,
                side: BorderSide(
                  color: SpotifyColors.textTertiary.withOpacity(0.35),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _toast(
                  'Open chosic.com or tunemymusic.com in a browser to '
                      'export your playlist as CSV'),
              icon: const Icon(FluentIcons.open_24_regular, size: 18),
              label: const Text('How to get the CSV'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: SpotifyColors.textPrimary,
                side: BorderSide(
                  color: SpotifyColors.textTertiary.withOpacity(0.35),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _isImporting ? null : _chooseFile,
              icon: const Icon(FluentIcons.document_add_24_regular, size: 18),
              label: Text(_fileName ?? 'Choose CSV file'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playlistNameController,
              enabled: !_isImporting,
              style: const TextStyle(color: SpotifyColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Playlist name *',
                labelStyle:
                const TextStyle(color: SpotifyColors.textSecondary),
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _csvController,
              enabled: !_isImporting,
              minLines: 8,
              maxLines: 16,
              style: const TextStyle(
                  fontSize: 12, color: SpotifyColors.textPrimary),
              decoration: InputDecoration(
                labelText: '...or paste the CSV here',
                labelStyle:
                const TextStyle(color: SpotifyColors.textSecondary),
                alignLabelWithHint: true,
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: SpotifyColors.green,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isImporting ? null : _importPlaylist,
              icon: _isImporting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
                  : const Icon(FluentIcons.arrow_upload_24_regular),
              label: Text(
                _isImporting ? 'Importing...' : 'Import playlist',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_isImporting && _totalCount > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _processedCount / _totalCount,
                  backgroundColor: SpotifyColors.surface,
                  color: SpotifyColors.green,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_processedCount / $_totalCount matched',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: SpotifyColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}