import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/song.dart';
import '../services/extension_bridge.dart';
import '../theme/spotify_theme.dart';
import '../widgets/song_row.dart';
import '../widgets/wave_spinner.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen> {
  List<Map<String, dynamic>> _extensions = [];
  String? _selectedId;
  bool _searching = false;
  bool _activating = false;
  bool _picking = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ExtensionBridge.list();
    if (!mounted) return;
    setState(() {
      _extensions = list;
      // Native is the source of truth for which one is active.
      _selectedId = list
          .where((e) => e['isActive'] == true)
          .map((e) => e['id']?.toString())
          .firstOrNull;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _install() async {
    // .eapk isn't a registered MIME type — pick any file, validate name.
    if (_picking) return;
    _picking = true;
    try {
      final files = await FilePicker.pickFiles(type: FileType.any);
      if (files.isEmpty) return;

      final file = files.first;
      final name = file.name.toLowerCase();
      if (!name.endsWith('.eapk') && !name.endsWith('.apk')) {
        _toast('Only .eapk files are supported');
        return;
      }

      final path = file.path;
      if (path == null) {
        _toast('Could not read the file');
        return;
      }

      final result = await ExtensionBridge.install(path);
      final extName = result?['name']?.toString() ?? 'Extension';
      _toast('Installed: $extName');
      _load();
    } on PlatformException catch (e) {
      if (e.code == 'already_active') return; // second tap — ignore
      _toast('Install failed: ${e.message ?? e.code}');
    } catch (e) {
      _toast('Install failed: $e');
    } finally {
      _picking = false;
    }
  }

  Future<void> _select(String id) async {
    if (_activating) return;
    setState(() => _activating = true);
    final ok = await ExtensionBridge.select(id);
    if (!mounted) return;
    setState(() {
      _activating = false;
      if (ok) _selectedId = id;
    });
    _toast(ok ? 'Extension activated' : 'Activation failed');
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty || _selectedId == null) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await ExtensionBridge.search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      _toast('Search failed: ${e.message ?? e.code}');
    }
  }

  void _playFromExtension(Map<String, dynamic> track) async {
    try {
      final stream = await ExtensionBridge.resolveStream(track);
      await audioHandler.playStream(
        url: stream.url,
        headers: stream.headers,
        id: track['id']?.toString() ?? 'ext_track',
        title: track['title']?.toString() ?? 'Extension track',
        artist: track['artist']?.toString() ?? 'Extension',
        image: track['thumbnail']?.toString(),
      );
    } catch (e) {
      _toast('Playback failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Extensions',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: SpotifyColors.green,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: _install,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Install extension (.eapk)',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),

          // ── Installed ──
          Text('Installed (${_extensions.length})',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: SpotifyColors.textSecondary)),
          const SizedBox(height: 8),
          if (_activating)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: WaveSpinner(size: 24, strokeWidth: 2.2),
              ),
            ),
          for (final ext in _extensions)
            ListTile(
              leading: const Icon(FluentIcons.puzzle_piece_20_regular,
                  color: SpotifyColors.textSecondary),
              title: Text(ext['name']?.toString() ?? '',
                  style: const TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'v${ext['version'] ?? ''} · ${ext['author'] ?? ''}',
                  style: const TextStyle(
                      color: SpotifyColors.textSecondary, fontSize: 12)),
              trailing: _selectedId == ext['id']
                  ? const Icon(Icons.check_circle_rounded,
                  color: SpotifyColors.green)
                  : TextButton(
                onPressed: () => _select(ext['id'].toString()),
                child: const Text('Activate',
                    style: TextStyle(
                        color: SpotifyColors.green, fontSize: 13)),
              ),
            ),

          const SizedBox(height: 16),

          // ── Search via the selected extension ──
          if (_selectedId != null) ...[
            TextField(
              style: const TextStyle(color: SpotifyColors.textPrimary),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search via extension...',
                hintStyle: const TextStyle(color: SpotifyColors.textTertiary),
                prefixIcon: _searching
                    ? Padding(
                  padding: const EdgeInsets.all(13),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: WaveSpinner(size: 20, strokeWidth: 2.2),
                  ),
                )
                    : const Icon(Icons.search_rounded,
                    color: SpotifyColors.textSecondary),
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (q) => _search(q),
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: WaveSpinner(size: 26)),
              )
            else
              for (final track in _searchResults)
                SongRow(
                  song: Song(
                    id: track['id']?.toString() ?? '',
                    title: track['title']?.toString() ?? 'Unknown',
                    artist: track['artist']?.toString() ?? 'Unknown',
                    thumbnail: track['thumbnail']?.toString() ?? '',
                    duration: Duration.zero,
                  ),
                  onTap: () => _playFromExtension(track),
                ),
          ],
        ],
      ),
    );
  }
}