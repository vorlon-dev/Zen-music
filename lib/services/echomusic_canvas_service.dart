import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// echomusic canvas provider — Dart port of Echo's
/// echomusicCanvasProvider. A community-curated manifest at
/// canvas.echomusic.fun maps song+artist names to canvas video URLs.
/// Manifest cached for 1 minute (instant curated updates).
class EchomusicCanvasService {
  EchomusicCanvasService._();
  static final EchomusicCanvasService instance = EchomusicCanvasService._();

  static const _manifestUrl = 'https://canvas.echomusic.fun/canvas.json';
  static const _ttl = Duration(minutes: 1);

  final http.Client _client = http.Client();
  _CacheEntry? _cache;

  Future<_Manifest?> _fetchManifest() async {
    final cached = _cache;
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.manifest;
    }
    try {
      final resp = await _client
          .get(Uri.parse(_manifestUrl))
          .timeout(const Duration(seconds: 18));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return null;
      final itemsRaw = decoded['items'] as List? ?? [];
      final items = <_CanvasItem>[];
      for (final raw in itemsRaw) {
        if (raw is! Map) continue;
        final song = raw['song']?.toString() ?? '';
        final artist = raw['artist']?.toString() ?? '';
        final url = raw['url']?.toString() ?? '';
        if (song.isEmpty || artist.isEmpty || url.isEmpty) continue;
        items.add(_CanvasItem(song, artist, url));
      }
      final manifest = _Manifest(items);
      _cache = _CacheEntry(manifest, DateTime.now().add(_ttl));
      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// Looks up a canvas for [song] by [artist]. First entry where both
  /// song and artist mutually contain each other (Echo's matching).
  Future<EchomusicCanvas?> getBySongArtist(
      String song, String artist) async {
    if (song.trim().isEmpty || artist.trim().isEmpty) return null;

    final manifest = await _fetchManifest();
    if (manifest == null) return null;

    for (final item in manifest.items) {
      final matchSong = song.toLowerCase().contains(item.song.toLowerCase()) ||
          item.song.toLowerCase().contains(song.toLowerCase());
      final matchArtist =
          artist.toLowerCase().contains(item.artist.toLowerCase()) ||
              item.artist.toLowerCase().contains(artist.toLowerCase());
      if (matchSong && matchArtist) {
        return EchomusicCanvas(
          name: item.song,
          artist: item.artist,
          videoUrl: item.url,
        );
      }
    }
    return null;
  }

  void dispose() => _client.close();
}

class _CanvasItem {
  const _CanvasItem(this.song, this.artist, this.url);
  final String song;
  final String artist;
  final String url;
}

class _Manifest {
  const _Manifest(this.items);
  final List<_CanvasItem> items;
}

class _CacheEntry {
  const _CacheEntry(this.manifest, this.expires);
  final _Manifest manifest;
  final DateTime expires;
}

/// A matched echomusic canvas entry.
class EchomusicCanvas {
  const EchomusicCanvas({
    required this.name,
    required this.artist,
    required this.videoUrl,
  });
  final String name;
  final String artist;

  /// Direct video URL for the animated canvas.
  final String videoUrl;
}