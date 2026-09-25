import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/appearance_prefs.dart';
import '../services/extension_bridge.dart';
import '../services/listening_stats_service.dart';
import '../services/spotify_bridge.dart';
import '../theme/spotify_theme.dart';
import '../utilities/zen_transitions.dart';
import '../widgets/source_picker_sheet.dart';
import 'equalizer_screen.dart';
import 'extensions_screen.dart';
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
  List<Map<String, dynamic>> _extensions = [];
  String? _activeSourceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _activeSourceName {
    if (_activeSourceId == null) return 'Default — built-in sources';
    for (final e in _extensions) {
      if (e['id']?.toString() == _activeSourceId) {
        return e['name']?.toString() ?? 'Extension';
      }
    }
    return 'Extension';
  }

  Future<void> _load() async {
    await AppearancePrefs.load();
    final connected = await SpotifyBridge.hasCachedCredentials();
    final cache = await storage.getUrlCacheSize();
    final history = storage.getPlayedHistory().length;
    final extensions = await ExtensionBridge.list();
    String? activeId;
    for (final e in extensions) {
      if (e['isActive'] == true) activeId = e['id']?.toString();
    }
    if (!mounted) return;
    setState(() {
      _spotifyConnected = connected;
      _cacheCount = cache;
      _historyCount = history;
      _audioQuality = storage.getAudioQuality();
      _offlineMode = storage.getOfflineMode();
      _checkUpdates = storage.getCheckUpdates();
      _extensions = extensions;
      _activeSourceId = activeId;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openSourcePicker() async {
    await showSourcePickerSheet(
      context: context,
      extensions: _extensions,
      activeId: _activeSourceId,
      onSelect: (id) async {
        final ok = id == null
            ? await ExtensionBridge.deselect()
            : await ExtensionBridge.select(id);
        if (!ok) {
          _toast('Could not switch source');
          return;
        }
        await _load();
        _toast('Source: ${_activeSourceName.split(' —').first}');
      },
      onOpenManager: () async {
        await pushSharedAxisY(context, const ExtensionsScreen());
        _load();
      },
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

  // ═══════════════════════════════════════════
  // APPEARANCE HELPERS — generic pickers & dialogs
  // ═══════════════════════════════════════════

  void _showPickerSheet({
    required String title,
    required List<({String value, String label, IconData icon})> items,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          itemCount: items.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
                child: Text(title,
                    style: const TextStyle(
                        color: SpotifyColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              );
            }
            final item = items[i - 1];
            return ListTile(
              leading:
              Icon(item.icon, color: SpotifyColors.textSecondary),
              title: Text(item.label,
                  style:
                  const TextStyle(color: SpotifyColors.textPrimary)),
              trailing: current == item.value
                  ? const Icon(Icons.check_rounded,
                  color: SpotifyColors.green)
                  : null,
              onTap: () {
                Navigator.pop(context);
                onSelect(item.value);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _showSliderPrefDialog({
    required String title,
    required double initial,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) label,
    double? resetTo,
    required ValueChanged<double> onOk,
  }) async {
    var temp = initial;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SpotifyColors.surface,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(title,
              style: const TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label(temp),
                  style: const TextStyle(
                      color: SpotifyColors.green,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Slider(
                value: temp.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                activeColor: SpotifyColors.green,
                onChanged: (v) => setDialogState(() => temp = v),
              ),
            ],
          ),
          // NOTE: never put Spacer/Expanded inside actions — actions renders
          // in an OverflowBar, and Flexible crashes there.
          actions: [
            if (resetTo != null)
              TextButton(
                  onPressed: () => setDialogState(() => temp = resetTo),
                  child: const Text('Reset',
                      style: TextStyle(color: SpotifyColors.textSecondary))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel',
                        style:
                        TextStyle(color: SpotifyColors.textSecondary))),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onOk(temp);
                    },
                    child: const Text('OK',
                        style: TextStyle(
                            color: SpotifyColors.green,
                            fontWeight: FontWeight.w700))),
              ],
            ),
          ],
          actionsAlignment: MainAxisAlignment.spaceBetween,
        ),
      ),
    );
  }

  // ── Appearance rows (read the live notifiers) ──

  Widget _appearanceCategory() {
    return _category(
        'Appearance & Player', Icons.palette_rounded, [
      _prefRow(
        Icons.gradient_rounded,
        'Player background',
        AppearancePrefs.playerBackground.value == 'gradient'
            ? 'Gradient'
            : AppearancePrefs.playerBackground.value == 'blur'
            ? 'Blurred artwork'
            : 'Solid black',
            () => _showPickerSheet(
          title: 'Player background',
          current: AppearancePrefs.playerBackground.value,
          items: const [
            (value: 'gradient', label: 'Gradient', icon: Icons.gradient_rounded),
            (value: 'solid', label: 'Solid black', icon: Icons.crop_square_rounded),
            (value: 'blur', label: 'Blurred artwork', icon: Icons.blur_on_rounded),
          ],
          onSelect: (v) async {
            await AppearancePrefs.setPlayerBackground(v);
            setState(() {});
          },
        ),
      ),
      _prefRow(
        Icons.linear_scale_rounded,
        'Slider style',
        switch (AppearancePrefs.sliderStyle.value) {
          'wavy' => 'Wavy',
          'bar' => 'Bar (Material)',
          _ => 'Slim',
        },
            () => _showPickerSheet(
          title: 'Progress slider style',
          current: AppearancePrefs.sliderStyle.value,
          // Exactly three styles — one entry each.
          items: const [
            (value: 'slim', label: 'Slim', icon: Icons.linear_scale_rounded),
            (value: 'wavy', label: 'Wavy', icon: Icons.waves_rounded),
            (value: 'bar', label: 'Bar (Material)', icon: Icons.align_horizontal_left_rounded),
          ],
          onSelect: (v) async {
            await AppearancePrefs.setSliderStyle(v);
            setState(() {});
          },
        ),
      ),
      _prefRow(
        Icons.picture_in_picture_rounded,
        'Mini-player background',
        AppearancePrefs.miniPlayerBackground.value == 'surface'
            ? 'Surface'
            : AppearancePrefs.miniPlayerBackground.value == 'blur'
            ? 'Blurred artwork'
            : 'Gradient',
            () => _showPickerSheet(
          title: 'Mini-player background',
          current: AppearancePrefs.miniPlayerBackground.value,
          items: const [
            (value: 'surface', label: 'Surface', icon: Icons.square_rounded),
            (value: 'blur', label: 'Blurred artwork', icon: Icons.blur_on_rounded),
            (value: 'gradient', label: 'Gradient', icon: Icons.gradient_rounded),
          ],
          onSelect: (v) async {
            await AppearancePrefs.setMiniPlayerBackground(v);
            setState(() {});
          },
        ),
      ),
      _prefRow(
        Icons.rounded_corner_rounded,
        'Thumbnail corner radius',
        '${AppearancePrefs.thumbRadius.value.round()}dp',
            () => _showSliderPrefDialog(
          title: 'Thumbnail corner radius',
          initial: AppearancePrefs.thumbRadius.value,
          min: 0,
          max: 24,
          divisions: 24,
          resetTo: 14,
          label: (v) => '${v.round()}dp',
          onOk: (v) async {
            await AppearancePrefs.setThumbRadius(v);
            setState(() {});
          },
        ),
      ),
      _switchRow(
        Icons.visibility_off_rounded,
        'Hide player thumbnail',
        'Player shows only text and controls',
        AppearancePrefs.hideThumbnail.value,
            (v) async {
          await AppearancePrefs.setHideThumbnail(v);
          setState(() {});
        },
      ),
      _switchRow(
        Icons.high_quality_rounded,
        'Show quality badge',
        'AAC / OPUS · bitrate on the player',
        AppearancePrefs.showQualityBadge.value,
            (v) async {
          await AppearancePrefs.setShowQualityBadge(v);
          setState(() {});
        },
      ),
      _prefRow(
        Icons.format_align_left_rounded,
        'Lyrics text position',
        AppearancePrefs.lyricsPosition.value == 'left'
            ? 'Left'
            : AppearancePrefs.lyricsPosition.value == 'center'
            ? 'Center'
            : 'Right',
            () => _showPickerSheet(
          title: 'Lyrics text position',
          current: AppearancePrefs.lyricsPosition.value,
          items: const [
            (value: 'left', label: 'Left', icon: Icons.format_align_left_rounded),
            (value: 'center', label: 'Center', icon: Icons.format_align_center_rounded),
            (value: 'right', label: 'Right', icon: Icons.format_align_right_rounded),
          ],
          onSelect: (v) async {
            await AppearancePrefs.setLyricsPosition(v);
            setState(() {});
          },
        ),
      ),
      _prefRow(
        Icons.format_size_rounded,
        'Lyrics text size',
        '${AppearancePrefs.lyricsTextSize.value.round()}sp',
            () => _showSliderPrefDialog(
          title: 'Lyrics text size',
          initial: AppearancePrefs.lyricsTextSize.value,
          min: 16,
          max: 36,
          divisions: 20,
          resetTo: 19,
          label: (v) => '${v.round()}sp',
          onOk: (v) async {
            await AppearancePrefs.setLyricsTextSize(v);
            setState(() {});
          },
        ),
      ),
      _prefRow(
        Icons.format_line_spacing_rounded,
        'Lyrics line spacing',
        '${AppearancePrefs.lyricsLineSpacing.value.toStringAsFixed(1)}x',
            () => _showSliderPrefDialog(
          title: 'Lyrics line spacing',
          initial: AppearancePrefs.lyricsLineSpacing.value,
          min: 1.0,
          max: 4.0,
          divisions: 30,
          resetTo: 1.3,
          label: (v) => '${v.toStringAsFixed(1)}x',
          onOk: (v) async {
            await AppearancePrefs.setLyricsLineSpacing(v);
            setState(() {});
          },
        ),
      ),
      _switchRow(
        Icons.fullscreen_rounded,
        'Hide status bar on lyrics',
        'Immersive lyrics view',
        AppearancePrefs.hideStatusBarOnLyrics.value,
            (v) async {
          await AppearancePrefs.setHideStatusBarOnLyrics(v);
          setState(() {});
        },
      ),
      _switchRow(
        Icons.screen_lock_portrait_rounded,
        'Keep screen on',
        'While the player is open',
        AppearancePrefs.keepScreenOn.value,
            (v) async {
          await AppearancePrefs.setKeepScreenOn(v);
          setState(() {});
        },
      ),
      _switchRow(
        Icons.vibration_rounded,
        'Haptics',
        'Subtle feedback on transport controls',
        AppearancePrefs.haptics.value,
            (v) async {
          await AppearancePrefs.setHaptics(v);
          setState(() {});
        },
      ),
      _prefRow(
        Icons.auto_awesome,
        'Ambient art scale',
        '${(AppearancePrefs.ambientArtScale.value * 100).round()}%',
            () => _showSliderPrefDialog(
          title: 'Ambient art scale',
          initial: AppearancePrefs.ambientArtScale.value,
          min: 0.4,
          max: 1.0,
          divisions: 12,
          resetTo: 0.85,
          label: (v) => '${(v * 100).round()}%',
          onOk: (v) async {
            await AppearancePrefs.setAmbientArtScale(v);
            setState(() {});
          },
        ),
      ),
      _switchRow(
        Icons.title_rounded,
        'Ambient: show title',
        'Song title under the artwork',
        AppearancePrefs.ambientShowTitle.value,
            (v) async {
          await AppearancePrefs.setAmbientShowTitle(v);
          setState(() {});
        },
      ),
      _switchRow(
        Icons.mic_rounded,
        'Ambient: show artist',
        'Artist name under the artwork',
        AppearancePrefs.ambientShowArtist.value,
            (v) async {
          await AppearancePrefs.setAmbientShowArtist(v);
          setState(() {});
        },
      ),
      _switchRow(
        Icons.lyrics_rounded,
        'Ambient: show lyrics',
        'Lyrics pane beside the artwork',
        AppearancePrefs.ambientShowLyrics.value,
            (v) async {
          await AppearancePrefs.setAmbientShowLyrics(v);
          setState(() {});
        },
      ),
      _prefRow(
        Icons.tab_rounded,
        'Default open tab',
        switch (AppearancePrefs.defaultTab.value) {
          1 => 'Search',
          2 => 'Library',
          _ => 'Home',
        },
            () => _showPickerSheet(
          title: 'Default open tab',
          current: '${AppearancePrefs.defaultTab.value}',
          items: const [
            (value: '0', label: 'Home', icon: Icons.home_rounded),
            (value: '1', label: 'Search', icon: Icons.search_rounded),
            (value: '2', label: 'Library', icon: Icons.library_music_rounded),
          ],
          onSelect: (v) async {
            await AppearancePrefs.setDefaultTab(int.tryParse(v) ?? 0);
            setState(() {});
            _toast('Applies on next app start');
          },
        ),
      ),
    ]);
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
          _appearanceCategory(),
          _category('Sources', Icons.extension_rounded, [
            _prefRow(
              Icons.music_note_rounded,
              'Music source',
              _activeSourceName,
              _openSourcePicker,
            ),
            _prefRow(
              Icons.extension_rounded,
              'Manage extensions',
              'Install & configure source extensions',
                  () async {
                await pushSharedAxisY(context, const ExtensionsScreen());
                _load();
              },
            ),
          ]),
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