class Song {
  final String id;
  final String title;
  final String artist;
  final String thumbnail;
  final Duration duration;
  final String? jiosaavnId;
  final String? jiosaavnStreamUrl;
  final String? audioType;
  final int? bitrateKbps;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.duration,
    this.jiosaavnId,
    this.jiosaavnStreamUrl,
    this.audioType,
    this.bitrateKbps,
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
    'audioType': audioType,
    'bitrateKbps': bitrateKbps,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'],
    title: json['title'],
    artist: json['artist'],
    thumbnail: json['thumbnail'],
    duration: Duration(seconds: json['duration']),
    jiosaavnId: json['jiosaavnId'],
    jiosaavnStreamUrl: json['jiosaavnStreamUrl'],
    audioType: json['audioType'] as String?,
    bitrateKbps: (json['bitrateKbps'] as num?)?.toInt(),
  );
}