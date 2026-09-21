/// A JioSaavn collection — playlist or album — shown as a card on
/// Home and opened as a full track list (CollectionScreen).
class Collection {
  final String id; // JioSaavn numeric id
  final String title;
  final String subtitle; // "50 songs · Hindi" / artist / year
  final String imageUrl; // 500x500 when available
  final String type; // 'playlist' | 'album'

  const Collection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.type,
  });

  bool get isPlaylist => type == 'playlist';
  bool get isAlbum => type == 'album';

  factory Collection.fromPlaylistJson(Map<String, dynamic> json) =>
      Collection(
        id: json['id'] as String? ?? '',
        title: json['name'] as String? ?? 'Unknown playlist',
        subtitle: _playlistSubtitle(json),
        imageUrl: _pickImage(json['image']),
        type: 'playlist',
      );

  factory Collection.fromAlbumJson(Map<String, dynamic> json) => Collection(
    id: json['id'] as String? ?? '',
    title: json['name'] as String? ?? 'Unknown album',
    subtitle: _albumSubtitle(json),
    imageUrl: _pickImage(json['image']),
    type: 'album',
  );

  static String _playlistSubtitle(Map<String, dynamic> json) {
    final count = json['songCount'];
    final lang = json['language'];
    final parts = <String>[
      if (count != null) '$count songs',
      if (lang is String && lang.isNotEmpty) lang,
    ];
    return parts.join(' · ');
  }

  static String _albumSubtitle(Map<String, dynamic> json) {
    // Albums may carry artists.primary[] or primaryArtists — handled
    // defensively; finalized after the albums JSON arrives.
    final primary = json['primaryArtists'];
    if (primary is String && primary.isNotEmpty) return primary;
    final artists = json['artists']?['primary'] as List<dynamic>?;
    if (artists != null && artists.isNotEmpty) {
      final names = artists
          .map((a) => a is Map ? a['name'] as String? ?? '' : '')
          .where((s) => s.isNotEmpty)
          .join(', ');
      if (names.isNotEmpty) return names;
    }
    final year = json['year'];
    return year != null ? '$year' : '';
  }

  /// Same image[] quality-tier pattern as songs: prefer 500x500,
  /// fall back to the last entry.
  static String _pickImage(dynamic image) {
    if (image is! List || image.isEmpty) return '';
    String? fallback;
    for (final img in image) {
      if (img is! Map) continue;
      final url = img['url'] as String?;
      if (url == null || url.isEmpty) continue;
      if (img['quality'] == '500x500') return url;
      fallback ??= url;
    }
    return fallback ?? '';
  }
}