class Song {
  final String id;
  final String title;
  final String artist;
  final String thumbnail;
  final Duration duration;
  final String? jiosaavnId;
  /// Pre-fetched 320kbps URL — extracted directly from JioSaavn's search response.
  final String? jiosaavnStreamUrl;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.duration,
    this.jiosaavnId,
    this.jiosaavnStreamUrl,
  });

  bool get isFromJiosaavn => jiosaavnId != null;
  bool get hasHighQuality =>
      jiosaavnStreamUrl != null && jiosaavnStreamUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'thumbnail': thumbnail,
    'duration': duration.inSeconds,
    'jiosaavnId': jiosaavnId,
    'jiosaavnStreamUrl': jiosaavnStreamUrl,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'],
    title: json['title'],
    artist: json['artist'],
    thumbnail: json['thumbnail'],
    duration: Duration(seconds: json['duration']),
    jiosaavnId: json['jiosaavnId'],
    jiosaavnStreamUrl: json['jiosaavnStreamUrl'],
  );
}