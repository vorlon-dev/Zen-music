// ZenMusic Desktop — ported from Echo Music (GPL-3.0), services/download_manager.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// PORT DEVIATIONS (stream resolution only — queue/progress/metadata logic is
// verbatim):
//  1. Echo's stream_client.dart (AudioStreamClient) is NOT ported. Byte fetch
//     uses the vendored fork's own API: videos.streams.get(info), which
//     auto-resolves the client-matched headers via HEAD probing.
//  2. Manifest resolution uses kYtClientPriority (visionOs -> ios -> android)
//     from yt_audio_stream.dart — Echo's androidVr is 403'd by YouTube since
//     2026-08-17 and would fail every download against this fork.
//  3. streamsClient -> streams (fork API surface); sortByBitrate (not exported
//     by the fork) -> inline sort.
//  4. The mp4-only container filter is dropped (desktop = libmpv, plays
//     mp4/webm/opus alike); saveMusic receives the true container extension.

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'file_storage.dart';
import 'settings_manager.dart';
import 'yt_audio_stream.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

Box _box = Hive.box('DOWNLOADS');

class DownloadManager {
  ValueNotifier<List<Map>> downloads = ValueNotifier([]);
  ValueNotifier<Map<String, Map>> downloadsByPlaylist = ValueNotifier({});
  final Map<String, ValueNotifier<double>> _activeDownloadProgress = {};
  static const String songsPlaylistId = 'songs';
  final int maxConcurrentDownloads = 3; // Limit concurrent downloads
  final Queue<String> _activeDownloads =
  Queue<String>(); // Currently active downloads
  final Queue<Map> _downloadQueue = Queue<Map>(); // Queue for pending downloads

  DownloadManager() {
    _refreshData();
    _cleanupDownloads();
    _box.listenable().addListener(() {
      _refreshData();
    });
  }

  void _cleanupDownloads() async {
    final activeIds = _activeDownloads.toSet();
    final queuedIds = _downloadQueue.map((e) => e['videoId']).toSet();
    for (Map song in downloads.value) {
      final id = song['videoId'];
      final status = song['status'];
      final isInvalidDownloading =
          status == 'DOWNLOADING' && !activeIds.contains(id);
      final isInvalidQueued = status == 'QUEUED' && !queuedIds.contains(id);
      if (isInvalidDownloading || isInvalidQueued) {
        await _updateSongMetadata(id, {'status': 'DELETED'});
      }
    }
  }

  void _refreshData() {
    downloads.value = _box.values.toList().cast<Map>();
    Map<String, Map> playlists = {};
    for (Map song in downloads.value) {
      final Map songPlaylists = song["playlists"];
      for (MapEntry entry in songPlaylists.entries) {
        String id = entry.key;
        String title = entry.value["title"];
        playlists
            .putIfAbsent(
            id,
                () => {
              "id": id,
              "title": title,
              "type": id == songsPlaylistId ? "SONGS" : "ALBUM",
              "songs": [],
            })['songs']
            .add({...song});
        if (playlists[id]!['type'] == "ALBUM" &&
            playlists[id]!['title'] != song["album"]?["name"]) {
          playlists[id]!['type'] = "PLAYLIST";
        }
      }
    }
    for (var playlist in playlists.values) {
      playlist['songs'].sort((a, b) =>
      (a["playlists"][playlist['id']]['timestamp'] ?? 0)
          .compareTo(b["playlists"][playlist['id']]['timestamp'] ?? 0)
      as int);
    }
    if (!DeepCollectionEquality()
        .equals(downloadsByPlaylist.value, playlists)) {
      downloadsByPlaylist.value = playlists;
    }
  }

  List<Map> getDownloadQueue() {
    return _downloadQueue.toList();
  }

  ValueNotifier<double>? getProgressNotifier(String videoId) {
    return _activeDownloadProgress[videoId];
  }

  void _startTrackingProgress(String videoId) {
    _activeDownloadProgress[videoId]?.dispose();
    _activeDownloadProgress[videoId] = ValueNotifier(0.0);
  }

  void _updateTrackingProgress(String videoId, double value) {
    _activeDownloadProgress[videoId]?.value = value;
  }

  void _stopTrackingProgress(String videoId) {
    if (_activeDownloadProgress.containsKey(videoId)) {
      _activeDownloadProgress[videoId]!.dispose();
      _activeDownloadProgress.remove(videoId);
    }
  }

  Future<void> restoreDownloads({List? songs}) async {
    final songsToRestore = songs ?? downloads.value;
    for (var song in songsToRestore) {
      if (_box.get(song['videoId']) != null) {
        final status = song['status'];
        final path = song['path'];
        final isFileMissing = status == 'DOWNLOADED' &&
            (path == null || !(await File(path).exists()));
        final isDeleted = status == 'DELETED';
        if (isDeleted || isFileMissing) {
          downloadSong(song);
        }
      }
    }
  }

  Future<void> downloadSong(Map songToDownaload) async {
    // Added "songs" playlist if needed
    final Map song = {
      ...songToDownaload,
      'playlists': songToDownaload['playlists'] ??
          {
            songsPlaylistId: {
              'title': 'Songs',
              'timestamp': DateTime.now().millisecondsSinceEpoch
            }
          }
    };
    // Check downloaded songs
    final Map? downloadSong = _box.get(song['videoId']);
    if (downloadSong != null) {
      if (_activeDownloads.contains(song['videoId'])) {
        // Already downloading, just update metadata
        await _updateSongMetadata(song['videoId'], {
          ...song,
        });
        _downloadNext();
        return;
      } else {
        final String? path = downloadSong['path'];
        if (path != null) {
          final file = File(path);
          final exists = await file.exists();
          if (exists) {
            // Already downloaded, just update metadata
            await _updateSongMetadata(song['videoId'], {
              ...song,
              'status': 'DOWNLOADED',
            });
            _downloadNext();
            return;
          }
        }
      }
    }
    // Execute download process
    if (!await _downloadStart(song)) return;
    await _downloadSong(song);
    _downloadEnd(song);
    _downloadNext();
  }

  Future<void> _downloadSong(Map song) async {
    try {
      await _updateSongMetadata(song['videoId'], {
        ...song,
        'status': 'DOWNLOADING',
      });
      _startTrackingProgress(song['videoId']);

      if (!(await FileStorage.requestPermissions())) {
        throw Exception('Storage permissions not granted.');
      }

      AudioOnlyStreamInfo audioSource = await _getSongInfo(song['videoId'],
          quality:
          GetIt.I<SettingsManager>().downloadQuality.name.toLowerCase());

      int total = audioSource.size.totalBytes;
      BytesBuilder received = BytesBuilder();

      Stream<List<int>> stream = ytExplode.videos.streams.get(audioSource);

      await for (var data in stream) {
        received.add(data);
        _updateTrackingProgress(song['videoId'], received.length / total);
      }
      File? file = await GetIt.I<FileStorage>().saveMusic(
        received.takeBytes(),
        song,
        extension: audioSource.container.name,
      );
      if (file != null) {
        await _updateSongMetadata(song['videoId'], {
          'status': 'DOWNLOADED',
          'path': file.path,
        });
      } else {
        throw Exception("File saving failed");
      }
    } catch (e) {
      debugPrint("Error in _downloadSong: $e");
      await _updateSongMetadata(song['videoId'], {
        'status': 'DELETED',
      });
    } finally {
      _stopTrackingProgress(song['videoId']);
    }
  }

  Future<void> _updateSongMetadata(String key, Map newMetadata) async {
    Map? song = _box.get(key);
    if (song != null) {
      if (newMetadata.containsKey('playlists')) {
        Map<String, dynamic> mergedPlaylists = {};
        if (song['playlists'] != null) {
          (song['playlists'] as Map).forEach((k, v) {
            mergedPlaylists[k] = Map<String, dynamic>.from(v);
          });
        }
        (newMetadata['playlists'] as Map).forEach((k, v) {
          mergedPlaylists[k] = Map<String, dynamic>.from(v);
        });
        song['playlists'] = mergedPlaylists;
        newMetadata.remove('playlists');
      }
      await _box.put(key, {
        ...song,
        ...newMetadata,
      });
    } else {
      await _box.put(key, newMetadata);
    }
  }

  Future<bool> _downloadStart(Map song) async {
    if (_activeDownloads.length >= maxConcurrentDownloads) {
      _downloadQueue.add(song);
      await _updateSongMetadata(song['videoId'], {
        ...song,
        'status': 'QUEUED',
      });
      return false;
    }
    _activeDownloads.add(song['videoId']);
    return true;
  }

  void _downloadEnd(Map song) {
    if (_activeDownloads.isNotEmpty) {
      _activeDownloads.remove(song['videoId']);
    }
  }

  void _downloadNext() {
    if (_downloadQueue.isNotEmpty &&
        _activeDownloads.length < maxConcurrentDownloads) {
      downloadSong(_downloadQueue.removeFirst());
    }
  }

  Future<String> deleteSong({
    required String key,
    String playlistId = songsPlaylistId,
    String? path,
  }) async {
    Map? song = _box.get(key);
    if (song != null && song['playlists'].keys.contains(playlistId)) {
      song['playlists'].remove(playlistId);
      if (song['playlists'].isNotEmpty) {
        await _box.put(key, song);
      } else {
        await _box.delete(key);
        if (path != null && await File(path).exists()) {
          await File(path).delete();
        }
      }
    }
    return 'Song deleted successfully.';
  }

  Future<void> updateStatus(String key, String status) async {
    Map? song = _box.get(key);
    if (song != null) {
      song['status'] = status;
      await _box.put(key, song);
    }
  }

  Future<void> downloadPlaylist(Map playlist) async {
    List songs = playlist['isPredefined'] == false
        ? playlist['songs']
        : playlist['type'] == 'ARTIST'
        ? await GetIt.I<YTMusic>()
        .getNextSongList(playlistId: playlist['playlistId'])
        : await GetIt.I<YTMusic>().getPlaylistSongs(playlist['playlistId']);
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    for (Map song in songs) {
      downloadSong({
        ...song,
        'playlists': {
          playlist['playlistId']: {
            'title': playlist['title'],
            'timestamp': timestamp++,
          },
        },
      }); // Queue each song download
    }
  }

  Future<AudioOnlyStreamInfo> _getSongInfo(String videoId,
      {String quality = 'high'}) async {
    try {
      StreamManifest manifest = await ytExplode.videos.streams.getManifest(
          videoId,
          ytClients: kYtClientPriority);
      List<AudioOnlyStreamInfo> streamInfos = manifest.audioOnly
          .where((a) => a.url.host.isNotEmpty)
          .toList()
        ..sort((a, b) =>
            a.bitrate.bitsPerSecond.compareTo(b.bitrate.bitsPerSecond));
      return quality == 'low' ? streamInfos.first : streamInfos.last;
    } catch (e) {
      rethrow;
    }
  }
}