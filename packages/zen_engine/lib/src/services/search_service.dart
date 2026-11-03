import '../models/song_model.dart';
import '../jiosaavn/jiosaavn_service.dart';
import '../ytmusic/yt_engine.dart';

/// Unified Search Engine combining JioSaavn and YouTube Music
class SearchEngine {
  SearchEngine({
    JioSaavnService? jioSaavn,
    YouTubeEngine? youtube,
  })  : _jioSaavn = jioSaavn ?? JioSaavnService(),
        _youtube = youtube ?? YouTubeEngine();

  final JioSaavnService _jioSaavn;
  final YouTubeEngine _youtube;

  /// Search across all sources with automatic deduplication and prioritization
  Future<List<ZenSong>> search(String query, {int limit = 20}) async {
    final futures = await Future.wait([
      _jioSaavn.search(query, limit: limit),
      _youtube.search(query, limit: limit),
    ]);

    final saavnResults = futures[0];
    final ytResults = futures[1];

    final combined = <ZenSong>[];
    final seenTitles = <String>{};

    void addSong(ZenSong song) {
      final key = '${song.title.toLowerCase().trim()} - ${song.artist.toLowerCase().trim()}';
      if (!seenTitles.contains(key)) {
        seenTitles.add(key);
        combined.add(song);
      }
    }

    // Interleave or prioritize JioSaavn (320kbps AAC quality)
    for (var i = 0; i < limit; i++) {
      if (i < saavnResults.length) addSong(saavnResults[i]);
      if (i < ytResults.length) addSong(ytResults[i]);
    }

    return combined;
  }

  /// Search specifically on JioSaavn
  Future<List<ZenSong>> searchJioSaavn(String query, {int limit = 20}) =>
      _jioSaavn.search(query, limit: limit);

  /// Search specifically on YouTube Music
  Future<List<ZenSong>> searchYouTube(String query, {int limit = 20}) =>
      _youtube.search(query, limit: limit);
}
