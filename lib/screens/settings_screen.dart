import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/listening_stats_service.dart';
import '../services/spotify_bridge.dart';
import '../theme/spotify_theme.dart';
import 'equalizer_screen.dart';
import 'import_spotify_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _spotifyConnected;
  int _cacheCount = 0;
  int _historyCount = 0;
  String _audioQuality = 'high';
  bool _offlineMode = false;
  bool _checkUpdates = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final connected = await SpotifyBridge.hasCachedCredentials();
    final cache = await storage.getUrlCacheSize();
    final history = storage.getPlayedHistory().length;
    if (!mounted) return;
    setState(() {
      _spotifyConnected = connected;
      _cacheCount = cache;
      _historyCount = history;
      _audioQuality = storage.getAudioQuality();
      _offlineMode = storage.getOfflineMode();
      _checkUpdates = storage.getCheckUpdates();
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _confirm(
      String title,
      String message,
      VoidCallback onYes, {
        bool dangerous = false,
      }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        title: Text(title,
            style: TextStyle(
                color:
                dangerous ? Colors.redAccent : SpotifyColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text(message,
            style:
            const TextStyle(color: SpotifyColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                onYes();
              },
              child: Text(dangerous ? 'Delete' : 'Yes',
                  style: TextStyle(
                      color:
                      dangerous ? Colors.redAccent : SpotifyColors.green))),
        ],
      ),
    );
  }

  // ── Backup / Restore ──

  Future<void> _backupData() async {
    try {
      final liked = storage.getLikedSongs().map((s) => s.toJson()).toList();
      final playlists = <Map<String, dynamic>>[];
      for (final p in storage.getUserPlaylists()) {
        playlists.add({
          'name': p.name,
          'songs':
          storage.getUserPlaylistSongs(p.id).map((s) => s.toJson()).toList(),
        });
      }

      final backup = {
        'app': 'zenmusic',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'likedSongs': liked,
        'playlists': playlists,
      };

      final result = await FilePicker.saveFile(
        fileName:
        'zenmusic_backup_${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(jsonEncode(backup)),
      );
      if (result == null) {
        _toast('Backup cancelled');
        return;
      }

      _toast('Backup saved ✔');
    } catch (e) {
      _toast('Backup failed: $e');
    }
  }

  Future<void> _restoreData() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) {
        _toast('Could not read the file');
        return;
      }

      final raw = await File(path).readAsString();
      final data = jsonDecode(raw);
      if (data is! Map || data['app'] != 'zenmusic') {
        _toast('Not a ZenMusic backup file');
        return;
      }

      final liked = (data['likedSongs'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((m) => Song.fromJson(Map<String, dynamic>.from(m)));
      for (final song in liked) {
        await storage.setLiked(song, true);
      }

      for (final p in (data['playlists'] as List<dynamic>? ?? [])) {
        if (p is! Map) continue;
        final name = p['name']?.toString() ?? 'Restored playlist';
        final songs = (p['songs'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => Song.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        final id = await storage.createUserPlaylist(name);
        await storage.addUserPlaylistSongs(id, songs);
      }

      _toast('Restored ✔ — check Library');
      _load();
    } catch (e) {
      _toast('Restore failed: $e');
    }
  }

  // ── Audio quality picker ──

  void _showQualityPicker() {
    const qualities = ['low', 'medium', 'high'];
    const names = [
      'Low (≤96 kbps)',
      'Medium (≤160 kbps)',
      'High (best available)'
    ];
    const icons = [
      Icons.speaker_outlined,
      Icons.speaker_rounded,
      Icons.speaker_group_rounded,
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: 3,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(icons[i], color: SpotifyColors.textSecondary),
            title: Text(names[i],
                style: const TextStyle(color: SpotifyColors.textPrimary)),
            trailing: _audioQuality == qualities[i]
                ? const Icon(Icons.check_rounded, color: SpotifyColors.green)
                : null,
            onTap: () {
              storage.setAudioQuality(qualities[i]);
              setState(() => _audioQuality = qualities[i]);
              audioHandler.setAudioQualitySetting(qualities[i]);
              _toast('Audio quality: ${qualities[i]}');
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _group('Playback', Icons.tune_rounded, [
            _tile(FluentIcons.options_24_regular, 'Equalizer',
                'Bass, treble & presets', () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const EqualizerScreen()));
                }),
            _tile(FluentIcons.speaker_2_24_regular, 'Audio quality',
                _audioQuality == 'high'
                    ? 'High (best available)'
                    : _audioQuality == 'medium'
                    ? 'Medium (≤160 kbps)'
                    : 'Low (≤96 kbps)', () {
                  _showQualityPicker();
                }),
            _statsToggle(),
            SwitchListTile(
              secondary: const Icon(FluentIcons.cloud_off_24_regular,
                  color: SpotifyColors.textSecondary),
              activeColor: SpotifyColors.green,
              title: const Text('Offline mode',
                  style: TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Only cached/local content — skips network lookups',
                  style:
                  TextStyle(color: SpotifyColors.textSecondary, fontSize: 12)),
              value: _offlineMode,
              onChanged: (v) async {
                await storage.setOfflineMode(v);
                setState(() => _offlineMode = v);
                _toast(v ? 'Offline mode on' : 'Offline mode off');
              },
            ),
          ]),
          _group('Spotify', Icons.music_note_rounded, [
            _tile(
              FluentIcons.music_note_2_24_regular,
              'Spotify account',
              _spotifyConnected == null
                  ? 'Checking...'
                  : (_spotifyConnected!
                  ? 'Connected — tap to disconnect'
                  : 'Not connected — engine parked'),
              _spotifyConnected == null
                  ? null
                  : () {
                if (_spotifyConnected!) {
                  _confirm('Disconnect Spotify',
                      'Remove stored Spotify credentials?', () async {
                        await SpotifyBridge.logout();
                        _toast('Spotify disconnected');
                        _load();
                      });
                } else {
                  _toast('Spotify streaming is parked — connect later');
                }
              },
            ),
            _tile(FluentIcons.arrow_upload_24_regular,
                'Import Spotify playlist', 'From a CSV export', () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ImportSpotifyScreen()));
                }),
          ]),
          _group('Data & Storage', Icons.storage_rounded, [
            _tile(
              FluentIcons.delete_24_regular,
              'Clear audio URL cache',
              _cacheCount > 0 ? '$_cacheCount cached streams' : 'Empty',
              _cacheCount == 0
                  ? null
                  : () => _confirm('Clear cache',
                  'Delete cached stream URLs? They re-fetch on next play.',
                      () async {
                    await storage.clearUrlCache();
                    _toast('Cache cleared');
                    _load();
                  }),
            ),
            _tile(FluentIcons.history_24_regular, 'Clear recently played',
              _historyCount > 0 ? '$_historyCount songs' : 'Empty',
              _historyCount == 0
                  ? null
                  : () => _confirm('Clear recently played',
                  'Delete your play history?', () async {
                    await storage.clearHistory();
                    _toast('History cleared');
                    _load();
                  }),
            ),
            _tile(FluentIcons.search_24_regular, 'Clear search history',
                'Removes recent searches', () {
                  _confirm('Clear searches', 'Delete recent searches?', () async {
                    await storage.clearQueries();
                    _toast('Search history cleared');
                  });
                }),
            _tile(FluentIcons.data_trending_24_regular,
                'Clear listening stats', 'Resets minutes and play counts',
                    () {
                  _confirm('Clear listening stats',
                      'Delete all listening stats? This cannot be undone.',
                          () async {
                        await listeningStatsService.clearStats();
                        _toast('Listening stats cleared');
                      }, dangerous: true);
                }, dangerous: true),
          ]),
          _group('Backup', Icons.cloud_sync_rounded, [
            _tile(FluentIcons.cloud_sync_24_regular, 'Backup your data',
                'Liked songs & playlists → JSON file', _backupData),
            _tile(FluentIcons.cloud_add_24_regular, 'Restore from backup',
                'Import a ZenMusic backup file', _restoreData),
          ]),
          _group('About', Icons.info_rounded, [
            SwitchListTile(
              secondary: const Icon(FluentIcons.arrow_sync_24_regular,
                  color: SpotifyColors.textSecondary),
              activeColor: SpotifyColors.green,
              title: const Text('Automatic update checks',
                  style: TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              subtitle: const Text('Check for new versions on launch',
                  style:
                  TextStyle(color: SpotifyColors.textSecondary, fontSize: 12)),
              value: _checkUpdates,
              onChanged: (v) async {
                await storage.setCheckUpdates(v);
                setState(() => _checkUpdates = v);
              },
            ),
            const ListTile(
              leading: Icon(FluentIcons.info_24_regular,
                  color: SpotifyColors.textSecondary),
              title: Text('ZenMusic',
                  style: TextStyle(
                      color: SpotifyColors.textPrimary, fontSize: 15)),
              subtitle: Text('Version 1.0.0',
                  style: TextStyle(
                      color: SpotifyColors.textSecondary, fontSize: 12)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Listening stats toggle (flush + reload like the source) ──

  Widget _statsToggle() {
    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (context, value, _) => SwitchListTile(
        secondary: const Icon(FluentIcons.data_trending_24_regular,
            color: SpotifyColors.textSecondary),
        activeColor: SpotifyColors.green,
        title: const Text('Listening stats',
            style: TextStyle(
                color: SpotifyColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        subtitle: const Text('Track listening time for monthly recap',
            style:
            TextStyle(color: SpotifyColors.textSecondary, fontSize: 12)),
        value: value,
        onChanged: (v) async {
          if (!v) {
            listeningStatsService.finishListeningSession(
                countCurrentTick: true, flushStats: false);
            await listeningStatsService.flush();
          }
          await setWrappedEnabled(v);
          listeningStatsService.reload();
          _toast(v ? 'Listening stats on' : 'Listening stats off');
        },
      ),
    );
  }

  Widget _group(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Icon(icon, size: 15, color: SpotifyColors.textSecondary),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: SpotifyColors.textSecondary)),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String subtitle,
      VoidCallback? onTap,
      {bool dangerous = false}) {
    return ListTile(
      leading: Icon(icon,
          color: dangerous ? Colors.redAccent : SpotifyColors.textSecondary),
      title: Text(title,
          style: TextStyle(
              color:
              dangerous ? Colors.redAccent : SpotifyColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle,
          style:
          const TextStyle(color: SpotifyColors.textSecondary, fontSize: 12)),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded,
          color: SpotifyColors.textTertiary),
      onTap: onTap,
    );
  }
}