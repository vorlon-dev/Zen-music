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
import '../utilities/zen_transitions.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _category('Playback', FluentIcons.options_24_regular, [
            _prefRow(
              FluentIcons.options_24_regular,
              'Equalizer',
              'Bass, treble & presets',
                  () => pushSharedAxisY(context, const EqualizerScreen()),
            ),
            _prefRow(
              FluentIcons.speaker_2_24_regular,
              'Audio quality',
              _audioQuality == 'high'
                  ? 'High (best available)'
                  : _audioQuality == 'medium'
                  ? 'Medium (≤160 kbps)'
                  : 'Low (≤96 kbps)',
              _showQualityPicker,
            ),
            _statsToggle(),
            _switchRow(
              FluentIcons.cloud_off_24_regular,
              'Offline mode',
              'Only cached/local content — skips network lookups',
              _offlineMode,
                  (v) async {
                await storage.setOfflineMode(v);
                setState(() => _offlineMode = v);
                _toast(v ? 'Offline mode on' : 'Offline mode off');
              },
            ),
          ]),
          _category('Spotify', FluentIcons.music_note_2_24_regular, [
            _prefRow(
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
            _prefRow(
              FluentIcons.arrow_upload_24_regular,
              'Import Spotify playlist',
              'From a CSV export',
                  () => pushSharedAxisY(context, const ImportSpotifyScreen()),
            ),
          ]),
          _category('Data & Storage', FluentIcons.delete_24_regular, [
            _prefRow(
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
            _prefRow(
              FluentIcons.history_24_regular,
              'Clear recently played',
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
            _prefRow(
              FluentIcons.search_24_regular,
              'Clear search history',
              'Removes recent searches',
                  () {
                _confirm('Clear searches', 'Delete recent searches?',
                        () async {
                      await storage.clearQueries();
                      _toast('Search history cleared');
                    });
              },
            ),
            _prefRow(
              FluentIcons.data_trending_24_regular,
              'Clear listening stats',
              'Resets minutes and play counts',
                  () {
                _confirm('Clear listening stats',
                    'Delete all listening stats? This cannot be undone.',
                        () async {
                      await listeningStatsService.clearStats();
                      _toast('Listening stats cleared');
                    }, dangerous: true);
              },
              dangerous: true,
            ),
          ]),
          _category('Backup', FluentIcons.cloud_sync_24_regular, [
            _prefRow(
              FluentIcons.cloud_sync_24_regular,
              'Backup your data',
              'Liked songs & playlists → JSON file',
              _backupData,
            ),
            _prefRow(
              FluentIcons.cloud_add_24_regular,
              'Restore from backup',
              'Import a ZenMusic backup file',
              _restoreData,
            ),
          ]),
          _category('About', FluentIcons.info_24_regular, [
            _switchRow(
              FluentIcons.arrow_sync_24_regular,
              'Automatic update checks',
              'Check for new versions on launch',
              _checkUpdates,
                  (v) async {
                await storage.setCheckUpdates(v);
                setState(() => _checkUpdates = v);
              },
            ),
            _prefRow(
              FluentIcons.info_24_regular,
              'ZenMusic',
              'Version 1.0.0',
              null,
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
      builder: (context, value, _) => _switchRow(
        FluentIcons.data_trending_24_regular,
        'Listening stats',
        'Track listening time for monthly recap',
        value,
            (v) async {
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

  // ── Echo preference building blocks ──

  Widget _category(String title, IconData icon, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
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
        for (final row in rows) ...[
          row,
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Echo's OutlinedButton preference row: 64dp stadium pill, 24dp
  /// padding, leading icon, 16sp title with summary below.
  Widget _prefRow(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback? onTap,
      {
        bool dangerous = false,
      }) {
    final enabled = onTap != null;
    final contentColor = dangerous ? Colors.redAccent : SpotifyColors.textPrimary;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: SpotifyColors.surface,
        borderRadius: BorderRadius.circular(32),
        child: InkWell(
          borderRadius: BorderRadius.circular(32),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                Icon(icon,
                    size: 24,
                    color: dangerous
                        ? Colors.redAccent
                        : SpotifyColors.textSecondary),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: contentColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: SpotifyColors.textSecondary
                                    .withOpacity(0.66),
                                fontSize: 12)),
                    ],
                  ),
                ),
                if (enabled)
                  const Icon(Icons.chevron_right_rounded,
                      color: SpotifyColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Same pill with a trailing switch.
  Widget _switchRow(
      IconData icon,
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
      ) {
    return Material(
      color: SpotifyColors.surface,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 24, color: SpotifyColors.textSecondary),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: SpotifyColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: SpotifyColors.textSecondary
                                  .withOpacity(0.66),
                              fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: SpotifyColors.green,
                activeColor: SpotifyColors.background,
              ),
            ],
          ),
        ),
      ),
    );
  }
}