// ZenMusic Desktop — screens/mini_player_page.dart (GPL-3.0).
//
// SP-26: the UI that runs INSIDE the floating mini-player window.
//
// Deliberately dependency-free — no Hive, no GetIt, no app services, no
// image plugins. The mini window is a second Flutter engine; it only
// mirrors the state the main window pushes through mini_player_bridge.dart
// and sends transport commands back. Everything is driven by
// ValueListenableBuilder so the bar updates the instant a push arrives.

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/mini_player_bridge.dart';

/// Root widget of the mini window's engine (run from the bridge).
class MiniPlayerApp extends StatelessWidget {
  const MiniPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const MiniPlayerPage(),
    );
  }
}

class MiniPlayerPage extends StatelessWidget {
  const MiniPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141416),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: <Widget>[
            const _Art(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const <Widget>[
                  _Titles(),
                  SizedBox(height: 6),
                  _ProgressRow(),
                  SizedBox(height: 2),
                  _Controls(),
                ],
              ),
            ),
            const _CloseButton(),
          ],
        ),
      ),
    );
  }
}

// ── artwork ──────────────────────────────────────────────────────────────

class _Art extends StatelessWidget {
  const _Art();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniTrack?>(
      valueListenable: MiniPlayerBridge.instance.miniTrack,
      builder: (BuildContext context, MiniTrack? track, _) {
        return Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0x12FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: _artChild(track?.artUri),
        );
      },
    );
  }

  Widget _artChild(String? artUri) {
    final ImageProvider? provider = _providerFor(artUri);
    if (provider == null) {
      return const Icon(Icons.music_note, size: 30, color: Colors.white24);
    }
    return Image(
      image: provider,
      fit: BoxFit.cover,
      width: 84,
      height: 84,
      gaplessPlayback: true,
      errorBuilder: (BuildContext context, Object e, StackTrace? s) =>
          const Icon(Icons.music_note, size: 30, color: Colors.white24),
    );
  }

  // The mini engine deliberately uses NO image plugins: plain NetworkImage
  // (dart:io under the hood) for remote art, FileImage as insurance for
  // local paths, and a note glyph when there is nothing usable.
  ImageProvider? _providerFor(String? artUri) {
    if (artUri == null || artUri.isEmpty) return null;
    if (artUri.startsWith('http://') || artUri.startsWith('https://')) {
      return NetworkImage(artUri);
    }
    try {
      final Uri uri = Uri.parse(artUri);
      if (uri.scheme == 'file') return FileImage(File.fromUri(uri));
      if (uri.scheme.isEmpty) return FileImage(File(artUri));
    } catch (_) {}
    return null;
  }
}

// ── title / artist ───────────────────────────────────────────────────────

class _Titles extends StatelessWidget {
  const _Titles();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MiniTrack?>(
      valueListenable: MiniPlayerBridge.instance.miniTrack,
      builder: (BuildContext context, MiniTrack? track, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              track?.title ?? 'Nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              (track == null || track.artist.isEmpty)
                  ? 'Play something in ZenMusic'
                  : track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        );
      },
    );
  }
}

// ── progress + times ─────────────────────────────────────────────────────

class _ProgressRow extends StatelessWidget {
  const _ProgressRow();

  @override
  Widget build(BuildContext context) {
    final MiniPlayerBridge bridge = MiniPlayerBridge.instance;
    return ListenableBuilder(
      listenable: Listenable.merge(
          <Listenable?>[bridge.miniPosition, bridge.miniDuration]),
      builder: (BuildContext context, _) {
        final Duration total = bridge.miniDuration.value;
        final Duration current = bridge.miniPosition.value;
        final double value = total <= Duration.zero
            ? 0.0
            : (current.inMilliseconds / total.inMilliseconds)
                .clamp(0.0, 1.0);
        return Row(
          children: <Widget>[
            Text(_fmt(current),
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.white38,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF1DB954)),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(_fmt(total),
                style: const TextStyle(
                    fontSize: 10.5,
                    color: Colors.white38,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()])),
          ],
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final int m = d.inMinutes.remainder(60) + d.inHours * 60;
    final int s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ── transport buttons ────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _iconButton(Icons.skip_previous, 24,
            () => MiniPlayerBridge.sendCommand('previous')),
        const SizedBox(width: 4),
        ValueListenableBuilder<bool>(
          valueListenable: MiniPlayerBridge.instance.miniPlaying,
          builder: (BuildContext context, bool playing, _) => _iconButton(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            32,
            () => MiniPlayerBridge.sendCommand('toggle'),
          ),
        ),
        const SizedBox(width: 4),
        _iconButton(Icons.skip_next, 24,
            () => MiniPlayerBridge.sendCommand('next')),
      ],
    );
  }

  Widget _iconButton(IconData icon, double size, VoidCallback onTap) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size, color: Colors.white),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => MiniPlayerBridge.sendCommand('close'),
      icon: const Icon(Icons.close, size: 16, color: Colors.white38),
      tooltip: 'Close mini player',
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
