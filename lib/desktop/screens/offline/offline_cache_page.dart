// ZenMusic Desktop — offline cache manager page.
//
// Companion UI for the song cache (song_cache_service.dart):
//   • total cache size at a glance (songs + bytes)
//   • per-song art, codec badge, size, duration, cache date
//   • delete one song / wipe the whole cache (both confirmed)
//   • shows the on-disk folder so power users can find the files
//
// SELF-CONTAINED: imports only flutter/material, dart:io and
// song_cache_service.dart. No MediaPlayer access, no router deps —
// zero impact on existing screens (the Saved page already opens it).
//
// R5 print policy: no prints needed here (the service logs [yt_cache]).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/song_cache_service.dart';

class OfflineCachePage extends StatefulWidget {
  const OfflineCachePage({super.key});

  @override
  State<OfflineCachePage> createState() => _OfflineCachePageState();
}

class _OfflineCachePageState extends State<OfflineCachePage> {
  List<CachedSong>? _recs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final recs = await SongCache.all();
    if (!mounted) return;
    setState(() => _recs = recs);
  }

  int get _totalBytes => _recs?.fold<int>(0, (t, r) => t + r.bytes) ?? 0;

  Future<bool> _confirm(String title, String body, String action) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _deleteOne(CachedSong rec) async {
    final ok = await _confirm(
      'Remove from cache?',
      '"${rec.title.isEmpty ? rec.videoId : rec.title}" will be deleted from '
          'disk. It will be downloaded again the next time you play it online.',
      'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await SongCache.delete(rec.videoId);
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
  }

  Future<void> _wipeAll() async {
    final recs = _recs;
    if (recs == null || recs.isEmpty) return;
    final ok = await _confirm(
      'Clear offline cache?',
      '${recs.length} song${recs.length == 1 ? '' : 's'} '
          '(${_fmtBytes(_totalBytes)}) will be deleted from disk.',
      'Clear all',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    for (final r in recs) {
      await SongCache.delete(r.videoId);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _reload();
  }

  static String _fmtBytes(int b) {
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  static String _fmtDur(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  static String _fmtDate(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Widget _art(CachedSong r) {
    Widget fallback() => Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.music_note,
        size: 24,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
    final art = r.artPath;
    if (art.isEmpty || !File(art).existsSync()) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Image.file(
          File(art),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recs = _recs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline cache'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Clear all',
            onPressed: (_busy || recs == null || recs.isEmpty)
                ? null
                : _wipeAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(recs)),
        ],
      ),
    );
  }

  Widget _body(List<CachedSong>? recs) {
    if (recs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (recs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.offline_pin_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing cached yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Songs you play are saved automatically\nfor offline listening.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final folder = File(recs.first.filePath).parent.path;
    return Scrollbar(
      thumbVisibility: true,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '${recs.length} song${recs.length == 1 ? '' : 's'} • '
                  '${_fmtBytes(_totalBytes)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              folder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Divider(height: 1),
          for (final r in recs)
            ListTile(
              leading: _art(r),
              title: Text(
                r.title.isEmpty ? r.videoId : r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (r.author.isNotEmpty) r.author,
                  if (r.codec.isNotEmpty) r.codec.toUpperCase(),
                  _fmtBytes(r.bytes),
                  if (_fmtDur(r.durationMs).isNotEmpty)
                    _fmtDur(r.durationMs),
                  if (_fmtDate(r.cachedAt).isNotEmpty)
                    _fmtDate(r.cachedAt),
                ].join('  •  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy ? null : () => _deleteOne(r),
              ),
            ),
        ],
      ),
    );
  }
}