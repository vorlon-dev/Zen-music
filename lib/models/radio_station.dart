class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.image,
    required this.streamUrl,
    this.genre,
    this.description,
  });

  factory RadioStation.fromMap(Map<String, dynamic> map) => RadioStation(
    id: map['id'] as String,
    name: map['name'] as String,
    image: map['image'] as String,
    streamUrl: map['streamUrl'] as String,
    genre: map['genre'] as String?,
    description: map['description'] as String?,
  );

  final String id;
  final String name;
  final String image;
  final String streamUrl;
  final String? genre;
  final String? description;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'image': image,
    'streamUrl': streamUrl,
    'genre': genre,
    'description': description,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is RadioStation && other.id == id);

  @override
  int get hashCode => id.hashCode;
}