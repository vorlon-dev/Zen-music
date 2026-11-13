// ZenMusic · vorlon-dev
//
// Discover feed (mobile) — a Dart port of the "Music Flow" idea from
// Echo Music (https://github.com/EchoMusicApp/Echo-Music, GPL-3.0):
//   • seeds  = now playing + recent history + liked songs + Indian catalog
//   • each seed → YouTube Music radio → candidates
//   • filter (seen / hidden / recent / playlists & mixes) → rank
//     (source weight, liked-artist boost, "less like this", artist spacing)
//   • append-only list: a page index always maps to the same song
// Warmed once at app start so the Discover tab opens instantly.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

enum FlowSource { nowPlaying, history, liked, catalog, offline }

class FlowItem {
  final Map<String, dynamic> song;
  final FlowSource source;
  const FlowItem(this.song, this.source);

  String get id => (song['videoId'] ?? '').toString();
  String get title => (song['title'] ?? '').toString();

  List<Map> get artists {
    final a = song['artists'];
    if (a is List) return a.whereType<Map>().toList();
    return const [];
  }

  String get artist {
    final names = artists
        .map((e) => (e['name'] ?? '').toString())
        .where((e) => e.isNotEmpty);
    if (names.isNotEmpty) return names.join(', ');
    return (song['artist'] ?? '').toString();
  }

  String? get artistKey {
    final a = artists;
    if (a.isEmpty) return null;
    final id = a.first['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
    final n = (a.first['name'] ?? '').toString().toLowerCase();
    return n.isEmpty ? null : n;
  }

  String get trackKey => '${_norm(title)}|${_norm(artist)}';

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-෿]+'), '');
}

class DiscoverFeed extends ChangeNotifier {
  DiscoverFeed._();
  static final DiscoverFeed instance = DiscoverFeed._();

  // Indian-first catalog (Hindi / Punjabi / Tamil / Telugu).
  static const _catalogQueries = [
    'trending hindi songs',
    'new bollywood songs',
    'latest punjabi songs',
    'trending tamil songs',
    'new telugu songs',
    'arijit singh latest songs',
    'indian indie songs',
    'latest hindi songs 2026',
  ];

  static const _sourceWeight = {
    FlowSource.history: 0.6,
    FlowSource.liked: 0.8,
    FlowSource.catalog: 0.4,
    FlowSource.offline: 0.4,
  };
  static const _artistSpacing = 2;
  static const _likedBoost = 1.0;
  static const _lessLikePenalty = 2.5;
  static const _positionDecay = 0.02;

  static const _initialTarget = 12;
  static const _maxFetchesPerLoad = 3;
  static const _seedsPerBatch = 2;
  static const _seedLimit = 6;
  static const _maxFeedSize = 300;
  static const _recentExclusionLimit = 30;

  final List<FlowItem> items = [];
  bool isLoading = false;
  bool isLoadingMore = false;
  bool hasMore = true;
  bool failed = false;
  bool isOffline = false;

  final Set<String> _seenIds = {};
  final Set<String> _seenKeys = {};
  final Set<String> _hiddenIds = {};
  final Set<String> _lessLikeArtists = {};
  Set<String> _recentIds = {};
  Set<String> _likedArtists = {};
  List<FlowItem> _seeds = [];
  final List<FlowItem> _chainSeeds = [];
  Future<void>? _warming;

  bool get ready => items.isNotEmpty;

  /// Idempotent. Call at app start; the page awaits the same future.
  Future<void> warm({bool force = false}) {
    if (force) _warming = null;
    return _warming ??= _start();
  }

  Future<void> _start() async {
    isLoading = true;
    failed = false;
    isOffline = false;
    items.clear();
    _seenIds.clear();
    _seenKeys.clear();
    _chainSeeds.clear();
    hasMore = true;
    notifyListeners();
    try {
      _loadSignals();
      _seeds = await _buildSeeds();
      var fetches = 0;
      while (items.length < _initialTarget &&
          hasMore &&
          fetches < _maxFetchesPerLoad) {
        fetches++;
        final ok = await _fetchAndAppend();
        if (!ok) break;
      }
      if (items.isEmpty) _appendOffline();
      failed = items.isEmpty;
    } catch (e) {
      debugPrint('[discover] start failed: $e');
      failed = items.isEmpty;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Appends at most one bounded round. Returns true if anything was added.
  Future<bool> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || items.length >= _maxFeedSize) {
      return false;
    }
    isLoadingMore = true;
    final before = items.length;
    var fetches = 0;
    try {
      while (items.length == before && hasMore && fetches < _maxFetchesPerLoad) {
        fetches++;
        if (!await _fetchAndAppend()) break;
      }
    } finally {
      isLoadingMore = false;
      hasMore = hasMore && items.length < _maxFeedSize;
      notifyListeners();
    }
    return items.length > before;
  }

  void hide(String id) => _hiddenIds.add(id);

  void lessLikeThis(FlowItem item) {
    final k = item.artistKey;
    if (k != null) _lessLikeArtists.add(k);
  }

  int indexOf(String? id) =>
      id == null ? -1 : items.indexWhere((e) => e.id == id);

  // ───────────────────────── signals & seeds ─────────────────────────

  void _loadSignals() {
    try {
      final hist = Hive.box('SONG_HISTORY')
          .values
          .whereType<Map>()
          .toList()
        ..sort((a, b) =>
            ((b['updatedAt'] ?? 0) as num).compareTo((a['updatedAt'] ?? 0) as num));
      final hideRecent =
          Hive.box('SETTINGS').get('DISCOVER_HIDE_RECENT', defaultValue: true);
      _recentIds = hideRecent == true
          ? hist
              .take(_recentExclusionLimit)
              .map((e) => (e['videoId'] ?? '').toString())
              .toSet()
          : <String>{};
      _likedArtists = Hive.box('FAVOURITES')
          .values
          .whereType<Map>()
          .map((e) => FlowItem(Map<String, dynamic>.from(e), FlowSource.liked))
          .map((e) => e.artistKey)
          .whereType<String>()
          .toSet();
    } catch (_) {
      _recentIds = {};
      _likedArtists = {};
    }
  }

  Future<List<FlowItem>> _buildSeeds() async {
    List<FlowItem> fromBox(String box, FlowSource s,
        {bool shuffle = false, int pool = 40, String sortKey = 'updatedAt'}) {
      try {
        final list = Hive.box(box).values.whereType<Map>().toList()
          ..sort((a, b) => ((b[sortKey] ?? 0) as num)
              .compareTo((a[sortKey] ?? 0) as num));
        var l = list.take(pool).toList();
        if (shuffle) l.shuffle();
        return l
            .take(_seedLimit)
            .map((e) => FlowItem(Map<String, dynamic>.from(e), s))
            .where((e) => e.id.length == 11)
            .toList();
      } catch (_) {
        return [];
      }
    }

    final recent = fromBox('SONG_HISTORY', FlowSource.history);
    final liked = fromBox('FAVOURITES', FlowSource.liked,
        shuffle: true, sortKey: 'createdAt');
    final catalog = await _catalogSeeds();

    // The catalog is ALSO shown directly, so the first swipe is already
    // Indian trending music even before any radio answers.
    for (final c in catalog.take(4)) {
      _appendRaw([c]);
    }
    final seeds = _interleave([recent, liked, catalog]);
    final seen = <String>{};
    return seeds.where((e) => seen.add(e.id)).toList();
  }

  Future<List<FlowItem>> _catalogSeeds() async {
    final q = [..._catalogQueries]..shuffle();
    final results = await Future.wait(q.take(3).map((s) => _search(s)));
    return _interleave(results)
        .where(_acceptable)
        .map((e) => FlowItem(e.song, FlowSource.catalog))
        .take(_seedLimit)
        .toList();
  }

  Future<List<FlowItem>> _search(String query) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await GetIt.I<YTMusic>().search(query, filter: 'songs');
        final sections = res['sections'] as List?;
        if (sections == null || sections.isEmpty) continue;
        final list = ((sections[0]['contents'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                FlowItem(Map<String, dynamic>.from(e), FlowSource.catalog))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    return [];
  }

  // ───────────────────────── radio fetch ─────────────────────────

  Future<bool> _fetchAndAppend() async {
    // Seeds exhausted → chain from the newest songs in the feed (endless).
    if (_seeds.isEmpty) {
      if (_chainSeeds.isEmpty) {
        _chainSeeds.addAll(items.reversed.take(4).toList());
      }
      _seeds = List.of(_chainSeeds);
      _chainSeeds.clear();
      if (_seeds.isEmpty) {
        hasMore = false;
        return false;
      }
    }
    final take = _seeds.take(_seedsPerBatch).toList();
    _seeds = _seeds.skip(take.length).toList();

    final batches = await Future.wait(take.map((seed) async {
      try {
        final songs = await GetIt.I<YTMusic>().getNextSongList(
            videoId: seed.id, playlistId: 'RDAMVM${seed.id}', limit: 25);
        return songs
            .whereType<Map>()
            .map((e) => FlowItem(Map<String, dynamic>.from(e), seed.source))
            .toList();
      } catch (_) {
        return <FlowItem>[];
      }
    }));
    final merged = _interleave(batches);
    if (merged.isEmpty) {
      // Network trouble or empty radios; keep trying other seeds.
      return _seeds.isNotEmpty;
    }
    _appendRaw(merged);
    return true;
  }

  // ───────────────────────── filter / rank / append ─────────────────────────

  static const _bad = [
    'playlist', 'jukebox', 'nonstop', 'non stop', 'mashup mix',
    'full album', 'hours', 'podcast', 'compilation',
  ];

  static int? _seconds(Map m) {
    final n = m['duration_seconds'];
    if (n is num) return n.toInt();
    final d = m['duration']?.toString();
    if (d == null || !d.contains(':')) return null;
    var total = 0;
    for (final p in d.split(':')) {
      final v = int.tryParse(p.trim());
      if (v == null) return null;
      total = total * 60 + v;
    }
    return total;
  }

  bool _acceptable(FlowItem e) {
    if (e.id.length != 11) return false;
    final t = e.title.toLowerCase();
    if (_bad.any(t.contains)) return false;
    final s = _seconds(e.song);
    if (s != null && (s < 45 || s > 600)) return false;
    return true;
  }

  void _appendRaw(List<FlowItem> raw) {
    final batchIds = <String>{};
    final batchKeys = <String>{};
    final candidates = raw.where((e) {
      final key = e.trackKey;
      return _acceptable(e) &&
          !_seenIds.contains(e.id) &&
          !_seenKeys.contains(key) &&
          !_hiddenIds.contains(e.id) &&
          !_recentIds.contains(e.id) &&
          batchIds.add(e.id) &&
          batchKeys.add(key);
    }).toList();
    final room = _maxFeedSize - items.length;
    if (room <= 0 || candidates.isEmpty) return;
    final ranked = _rank(
        candidates,
        items
            .skip(math.max(0, items.length - _artistSpacing))
            .map((e) => e.artistKey)
            .toList());
    for (final e in ranked.take(room)) {
      _seenIds.add(e.id);
      _seenKeys.add(e.trackKey);
      items.add(e);
    }
    notifyListeners();
  }

  List<FlowItem> _rank(List<FlowItem> candidates, List<String?> tail) {
    final scored = <MapEntry<FlowItem, double>>[];
    for (var i = 0; i < candidates.length; i++) {
      final item = candidates[i];
      final artist = item.artistKey;
      var score = _sourceWeight[item.source] ?? 0.0;
      score -= i * _positionDecay;
      if (artist != null && _likedArtists.contains(artist)) score += _likedBoost;
      if (artist != null && _lessLikeArtists.contains(artist)) {
        score -= _lessLikePenalty;
      }
      scored.add(MapEntry(item, score));
    }
    // Stable sort by score (ties keep original order).
    final indexed = scored.asMap().entries.toList()
      ..sort((a, b) {
        final c = b.value.value.compareTo(a.value.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    final pool = indexed.map((e) => e.value.key).toList();

    final recent = List<String?>.of(
        tail.skip(math.max(0, tail.length - _artistSpacing)));
    final out = <FlowItem>[];
    while (pool.isNotEmpty) {
      var pick = pool.indexWhere(
          (e) => e.artistKey == null || !recent.contains(e.artistKey));
      if (pick < 0) pick = 0;
      final picked = pool.removeAt(pick);
      out.add(picked);
      recent.add(picked.artistKey);
      while (recent.length > _artistSpacing) {
        recent.removeAt(0);
      }
    }
    return out;
  }

  void _appendOffline() {
    try {
      final songs = Hive.box('DOWNLOADS')
          .values
          .whereType<Map>()
          .where((e) => e['status'] == 'DOWNLOADED')
          .map((e) => FlowItem(Map<String, dynamic>.from(e), FlowSource.offline))
          .toList()
        ..shuffle();
      if (songs.isEmpty) return;
      _appendRaw(songs);
      isOffline = items.isNotEmpty;
      hasMore = false;
    } catch (_) {}
  }

  static List<FlowItem> _interleave(List<List<FlowItem>> lists) {
    final out = <FlowItem>[];
    final longest = lists.fold<int>(0, (m, l) => math.max(m, l.length));
    for (var i = 0; i < longest; i++) {
      for (final l in lists) {
        if (i < l.length) out.add(l[i]);
      }
    }
    return out;
  }
}
