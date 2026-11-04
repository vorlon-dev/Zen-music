// ZenMusic · vorlon-dev
//
// Web player data layer. Pure Dart (no dart:io), so it also runs in tests.

/// One playable track in the web player.
class WebSong {
  const WebSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.image,
    required this.streamUrl,
    required this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String image;
  final String streamUrl;
  final Duration duration;

  bool get playable => streamUrl.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'image': image,
        'streamUrl': streamUrl,
        'duration': duration.inSeconds,
      };

  /// Restores a song written by [toJson]. Returns null for malformed data.
  static WebSong? fromStored(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}';
    if (id.isEmpty) return null;
    return WebSong(
      id: id,
      title: '${raw['title'] ?? ''}',
      artist: '${raw['artist'] ?? ''}',
      album: '${raw['album'] ?? ''}',
      image: '${raw['image'] ?? ''}',
      streamUrl: '${raw['streamUrl'] ?? ''}',
      duration: Duration(seconds: int.tryParse('${raw['duration'] ?? ''}') ?? 0),
    );
  }

  /// Builds a song from one JioSaavn-style result object.
  factory WebSong.fromJson(Map<String, dynamic> map) {
    final rawArtists = map['artists'];
    Object? artists = rawArtists;
    if (rawArtists is Map) artists = rawArtists['primary'];
    final artistList = artists is List ? artists : const <Object?>[];
    final artistNames = artistList
        .whereType<Map>()
        .map((a) => unescapeHtml('${a['name'] ?? ''}'))
        .where((s) => s.isNotEmpty)
        .join(', ');

    final album = map['album'];
    final albumName = album is Map ? '${album['name'] ?? ''}' : '';

    return WebSong(
      id: '${map['id'] ?? ''}',
      title: unescapeHtml('${map['name'] ?? map['title'] ?? ''}'),
      artist: artistNames,
      album: unescapeHtml(albumName),
      image: _pickImage(map['image']),
      streamUrl: _pickStream(map['downloadUrl']),
      duration: Duration(
        seconds: int.tryParse('${map['duration'] ?? ''}') ?? 0,
      ),
    );
  }

  static int _quality(Object? q) =>
      int.tryParse('$q'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  static String pickImage(Object? raw) => _pickImage(raw);

  static String _pickImage(Object? raw) {
    if (raw is! List || raw.isEmpty) return '';
    String best = '';
    int bestSize = -1;
    for (final e in raw.whereType<Map>()) {
      final size = _quality(('${e['quality']}').split('x').first);
      if (size > bestSize) {
        bestSize = size;
        best = '${e['url'] ?? ''}';
      }
    }
    return _https(best);
  }

  static String _pickStream(Object? raw) {
    if (raw is! List || raw.isEmpty) return '';
    String best = '';
    int bestRate = -1;
    for (final e in raw.whereType<Map>()) {
      final rate = _quality(e['quality']);
      if (rate > bestRate) {
        bestRate = rate;
        best = '${e['url'] ?? ''}';
      }
    }
    return _https(best);
  }

  /// Browsers block plain-http media on an https page.
  static String _https(String url) =>
      url.startsWith('http://') ? 'https://${url.substring(7)}' : url;
}

/// Decodes the handful of HTML entities the upstream API returns in titles.
String unescapeHtml(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

/// One timed lyric line.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

/// Parses `[mm:ss.xx] text` LRC data. Lines without a timestamp are ignored;
/// several timestamps on one line produce several entries. Result is sorted.
List<LyricLine> parseLrc(String raw) {
  final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  final out = <LyricLine>[];
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final matches = stamp.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.substring(matches.last.end).trim();
    for (final m in matches) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      out.add(LyricLine(
        Duration(
          minutes: int.parse(m.group(1)!),
          seconds: int.parse(m.group(2)!),
          milliseconds: ms,
        ),
        text,
      ));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Index of the line being sung at [position], or -1 before the first line.
int activeLyricIndex(List<LyricLine> lines, Duration position) {
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].time <= position) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// m:ss or h:mm:ss.
String clock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}


/// An album or a playlist shown as a card.
class WebCollection {
  const WebCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
    required this.isAlbum,
  });

  final String id;
  final String title;
  final String subtitle;
  final String image;
  final bool isAlbum;

  factory WebCollection.fromJson(
    Map<String, dynamic> map, {
    required bool isAlbum,
  }) {
    return WebCollection(
      id: '${map['id'] ?? ''}',
      title: unescapeHtml('${map['name'] ?? map['title'] ?? ''}'),
      subtitle: unescapeHtml('${map['subtitle'] ?? map['description'] ?? ''}'),
      image: WebSong.pickImage(map['image']),
      isAlbum: isAlbum,
    );
  }
}

/// A collection together with its songs.
class WebDetail {
  const WebDetail(this.collection, this.songs);
  final WebCollection collection;
  final List<WebSong> songs;
}

enum WebRepeat { off, all, one }
