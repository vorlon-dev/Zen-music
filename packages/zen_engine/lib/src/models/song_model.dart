/// Represents an audio track in the ZenEngine ecosystem.
class ZenSong {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final String? thumbnailUrl;
  final String? streamUrl;
  final ZenSongSource source;
  final Map<String, dynamic> raw;

  const ZenSong({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.duration = Duration.zero,
    this.thumbnailUrl,
    this.streamUrl,
    this.source = ZenSongSource.youtube,
    this.raw = const {},
  });

  static const _entities = {
    '&quot;': '"',
    '&amp;': '&',
    '&#039;': "'",
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
  };

  static String decodeEntities(String input) {
    var out = input;
    _entities.forEach((entity, char) {
      out = out.replaceAll(entity, char);
    });
    return out;
  }

  factory ZenSong.fromJioSaavn(Map<String, dynamic> json) {
    final id = json['videoId'] as String? ?? json['id'] as String? ?? '';
    final rawTitle = json['title'] as String? ?? json['name'] as String? ?? 'Unknown';
    final rawArtist = json['artist'] as String? ?? json['primaryArtists'] as String? ?? 'Unknown';
    final album = json['album'] is Map ? json['album']['name'] as String? : json['album'] as String?;

    String? thumb;
    if (json['thumbnails'] is List && (json['thumbnails'] as List).isNotEmpty) {
      thumb = json['thumbnails'][0]['url'] as String?;
    } else if (json['image'] is List && (json['image'] as List).isNotEmpty) {
      thumb = (json['image'] as List).last['url'] as String?;
    }

    Duration duration = Duration.zero;
    if (json['duration'] is Duration) {
      duration = json['duration'] as Duration;
    } else if (json['duration'] is num) {
      duration = Duration(seconds: (json['duration'] as num).toInt());
    }

    return ZenSong(
      id: id,
      title: decodeEntities(rawTitle),
      artist: decodeEntities(rawArtist),
      album: album != null ? decodeEntities(album) : null,
      duration: duration,
      thumbnailUrl: thumb,
      streamUrl: json['jiosaavnStreamUrl'] as String?,
      source: ZenSongSource.jiosaavn,
      raw: json,
    );
  }

  factory ZenSong.fromYouTube(Map<String, dynamic> json) {
    final id = json['videoId'] as String? ?? json['id'] as String? ?? '';
    final title = json['title'] as String? ?? 'Unknown';
    final artist = json['artist'] as String? ??
        (json['artists'] is List && (json['artists'] as List).isNotEmpty
            ? (json['artists'] as List).map((a) => a['name']).join(', ')
            : 'Unknown');
    final album = json['album'] is Map ? json['album']['name'] as String? : json['album'] as String?;

    String? thumb;
    if (json['thumbnails'] is List && (json['thumbnails'] as List).isNotEmpty) {
      thumb = json['thumbnails'][0]['url'] as String?;
    }

    Duration duration = Duration.zero;
    if (json['duration'] is Duration) {
      duration = json['duration'] as Duration;
    } else if (json['duration'] is num) {
      duration = Duration(seconds: (json['duration'] as num).toInt());
    } else if (json['duration'] is String) {
      final parts = (json['duration'] as String).split(':').map(int.tryParse).toList();
      if (parts.length == 2 && parts[0] != null && parts[1] != null) {
        duration = Duration(minutes: parts[0]!, seconds: parts[1]!);
      } else if (parts.length == 3 && parts[0] != null && parts[1] != null && parts[2] != null) {
        duration = Duration(hours: parts[0]!, minutes: parts[1]!, seconds: parts[2]!);
      }
    }

    return ZenSong(
      id: id,
      title: decodeEntities(title),
      artist: decodeEntities(artist),
      album: album != null ? decodeEntities(album) : null,
      duration: duration,
      thumbnailUrl: thumb,
      streamUrl: null,
      source: ZenSongSource.youtube,
      raw: json,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'videoId': id,
      'id': id,
      'title': title,
      'artist': artist,
      'album': album != null ? {'name': album} : null,
      'duration': duration.inSeconds,
      'thumbnails': [
        if (thumbnailUrl != null) {'url': thumbnailUrl}
      ],
      'jiosaavnStreamUrl': streamUrl,
      'type': source == ZenSongSource.jiosaavn ? 'JIOSAAVN' : 'YOUTUBE',
      ...raw,
    };
  }

  ZenSong copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? thumbnailUrl,
    String? streamUrl,
    ZenSongSource? source,
    Map<String, dynamic>? raw,
  }) {
    return ZenSong(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      source: source ?? this.source,
      raw: raw ?? this.raw,
    );
  }
}

enum ZenSongSource {
  jiosaavn,
  youtube,
  spotify,
  local,
}
