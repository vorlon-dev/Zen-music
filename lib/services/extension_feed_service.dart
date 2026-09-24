import 'dart:convert';

import 'package:flutter/services.dart';

/// A parsed home-feed shelf from the active extension.
class ExtShelf {
  ExtShelf({
    required this.kind,
    required this.title,
    this.subtitle,
    this.grid = false,
    this.items = const [],
    this.categories = const [],
    this.backgroundColor,
    this.imageUrl,
    this.imageHeaders = const {},
  });

  // 'items' | 'tracks' | 'categories' | 'item' | 'category'
  final String kind;
  final String title;
  final String? subtitle;
  final bool grid;
  final List<ExtMedia> items;
  final List<ExtCategory> categories;
  final String? backgroundColor;
  final String? imageUrl;
  final Map<String, String> imageHeaders;

  static ExtShelf? fromMap(Map map) {
    final type = (map['shelfType'] as String?) ?? '';
    final title = map['title']?.toString() ?? '';
    final subtitle = map['subtitle']?.toString();
    final layout = (map['type'] as String?) ?? '';

    if (type.endsWith('Lists.Items')) {
      final items = <ExtMedia>[];
      final rawList = map['list'];
      if (rawList is List) {
        for (final entry in rawList) {
          final media = ExtMedia.fromMap(entry);
          if (media != null) items.add(media);
        }
      }
      if (items.isEmpty) return null;
      return ExtShelf(
        kind: 'items',
        title: title,
        subtitle: subtitle,
        grid: layout == 'Grid',
        items: items,
      );
    }

    if (type.endsWith('Lists.Tracks')) {
      final items = <ExtMedia>[];
      final rawList = map['list'];
      if (rawList is List) {
        for (final entry in rawList) {
          // Entries of a Tracks shelf are Tracks by definition — their
          // JSON may omit the mediaItemType tag, so fall back to 'Track'.
          final media = ExtMedia.fromMap(entry, fallbackKind: 'Track');
          if (media != null) items.add(media);
        }
      }
      if (items.isEmpty) return null;
      return ExtShelf(
        kind: 'tracks',
        title: title,
        subtitle: subtitle,
        grid: layout == 'Grid',
        items: items,
      );
    }

    if (type.endsWith('Lists.Categories')) {
      final cats = <ExtCategory>[];
      final rawList = map['list'];
      if (rawList is List) {
        for (final entry in rawList) {
          if (entry is Map) cats.add(ExtCategory.fromMap(entry));
        }
      }
      if (cats.isEmpty) return null;
      return ExtShelf(
        kind: 'categories',
        title: title,
        subtitle: subtitle,
        categories: cats,
      );
    }

    if (type.endsWith('.Item')) {
      final media = ExtMedia.fromMap(map['media']);
      if (media == null) return null;
      return ExtShelf(kind: 'item', title: title, items: [media]);
    }

    if (type.endsWith('.Category')) {
      final image = _extractNetworkImage(map['image']);
      return ExtShelf(
        kind: 'category',
        title: title,
        subtitle: subtitle,
        backgroundColor: map['backgroundColor']?.toString(),
        imageUrl: image?.url,
        imageHeaders: image?.headers ?? const {},
      );
    }

    return null; // unknown shelf variant — skipped
  }
}

/// A parsed media item (track, album, artist, playlist, radio…).
class ExtMedia {
  ExtMedia({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.coverHeaders = const {},
    this.coverHex,
    this.durationMs,
    this.isVideo = false,
    this.trackType = '',
    required this.raw,
  });

  final String kind; // suffix of the media type, e.g. 'Track'
  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final Map<String, String> coverHeaders;
  final String? coverHex;
  final int? durationMs;
  final bool isVideo;
  final String trackType; // Track.type: Song | Podcast | Video | …
  final Map<dynamic, dynamic> raw; // kept for playback round-trip

  /// A song is a playable Track that is neither a podcast episode nor
  /// a video — the only kind that enters feeds and queues.
  bool get isSong =>
      kind == 'Track' && !isVideo && (trackType.isEmpty || trackType == 'Song');

  static ExtMedia? fromMap(dynamic data, {String? fallbackKind}) {
    if (data is! Map) return null;
    var typeRaw = (data['mediaItemType'] as String?) ?? '';
    if (typeRaw.isEmpty && fallbackKind != null) typeRaw = fallbackKind;
    if (typeRaw.isEmpty) return null;

    final trackType = (data['type'] as String?) ?? '';
    final duration = data['duration'];

    var subtitle = data['subtitleWithE']?.toString();
    if (subtitle == null || subtitle.isEmpty) {
      subtitle = data['subtitle']?.toString();
    }
    if ((subtitle == null || subtitle.isEmpty) && data['artists'] is List) {
      final names = (data['artists'] as List)
          .whereType<Map>()
          .map((a) => a['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) subtitle = names;
    }

    final cover = _extractNetworkImage(data['cover']);
    return ExtMedia(
      kind: typeRaw.split('.').last,
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      subtitle: subtitle,
      coverUrl: cover?.url,
      coverHeaders: cover?.headers ?? const {},
      coverHex: _extractHexImage(data['cover']),
      durationMs: duration is num ? duration.toInt() : null,
      isVideo: trackType == 'Video' ||
          trackType == 'VideoSong' ||
          trackType == 'HorizontalVideo',
      trackType: trackType,
      raw: data,
    );
  }
}

class ExtCategory {
  ExtCategory({
    required this.title,
    this.backgroundColor,
    this.imageUrl,
    this.imageHeaders = const {},
  });

  final String title;
  final String? backgroundColor;
  final String? imageUrl;
  final Map<String, String> imageHeaders;

  static ExtCategory fromMap(Map map) {
    final image = _extractNetworkImage(map['image']);
    return ExtCategory(
      title: map['title']?.toString() ?? '',
      backgroundColor: map['backgroundColor']?.toString(),
      imageUrl: image?.url,
      imageHeaders: image?.headers ?? const {},
    );
  }
}

/// Loaded detail page: the refreshed item, its tracks (album/playlist)
/// and/or its shelves (artist).
class ExtDetail {
  ExtDetail({this.item, this.tracks = const [], this.shelves = const []});

  final ExtMedia? item;
  final List<ExtMedia> tracks;
  final List<ExtShelf> shelves;
}

({String url, Map<String, String> headers})? _extractNetworkImage(
    dynamic cover) {
  if (cover is! Map) return null;
  final t = (cover['type'] as String?) ?? '';
  if (!t.endsWith('NetworkRequestImageHolder')) return null;
  final req = cover['request'];
  if (req is! Map) return null;
  var url = req['url']?.toString() ?? '';
  if (url.isEmpty) {
    for (final v in req.values) {
      if (v is String && v.startsWith('http')) {
        url = v;
        break;
      }
    }
  }
  if (url.isEmpty) return null;
  final headers = <String, String>{};
  final rawHeaders = req['headers'];
  if (rawHeaders is Map) {
    rawHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
  }
  return (url: url, headers: headers);
}

String? _extractHexImage(dynamic cover) {
  if (cover is! Map) return null;
  final t = (cover['type'] as String?) ?? '';
  if (!t.endsWith('HexColorImageHolder')) return null;
  return cover['hex']?.toString();
}

class ExtensionFeedService {
  static const _channel = MethodChannel('zen/extensions');

  /// Home shelves page-by-page. [continuation] null = first page.
  /// Returns the shelves plus the next continuation token (null = end).
  Future<({List<ExtShelf> shelves, String? continuation})>
  homeFeedPage(String? continuation) async {
    final raw = await _channel.invokeMethod<String>(
      'homeFeedPage',
      {'continuation': continuation},
    );
    if (raw == null || raw.isEmpty) {
      return (
      shelves: <ExtShelf>[],
      continuation: null,
      );
    }
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final shelves = <ExtShelf>[];
    final data = map['data'];
    if (data is List) {
      for (final entry in data) {
        if (entry is Map) {
          final shelf = ExtShelf.fromMap(entry);
          if (shelf != null) shelves.add(shelf);
        }
      }
    }
    return (
    shelves: shelves,
    continuation: map['continuation']?.toString(),
    );
  }

  /// Loads the detail page for an album / playlist / artist item.
  /// Throws with the native error — caller should catch and display.
  Future<ExtDetail> loadDetail(Map<String, dynamic> item) async {
    final raw = await _channel.invokeMethod<String>(
      'loadDetail',
      {'item': jsonEncode(item)},
    );
    if (raw == null) throw Exception('Detail load failed');
    final map = jsonDecode(raw) as Map<String, dynamic>;

    final tracks = <ExtMedia>[];
    final rawTracks = map['tracks'];
    if (rawTracks is List) {
      for (final t in rawTracks) {
        final m = ExtMedia.fromMap(t);
        if (m != null) tracks.add(m);
      }
    }
    final shelves = <ExtShelf>[];
    final rawShelves = map['shelves'];
    if (rawShelves is List) {
      for (final s in rawShelves) {
        if (s is Map) {
          final sh = ExtShelf.fromMap(s);
          if (sh != null) shelves.add(sh);
        }
      }
    }
    return ExtDetail(
      item: ExtMedia.fromMap(map['item']),
      tracks: tracks,
      shelves: shelves,
    );
  }
}