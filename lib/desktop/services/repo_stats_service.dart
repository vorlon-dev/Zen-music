// ZenMusic · vorlon-dev
//
// Live numbers for the About page, straight from the GitHub API:
// total downloads across all release assets (the same number the
// shields.io "downloads total" badge shows), latest release, stars.
// Cached for 30 minutes (and kept offline) in shared_preferences.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RepoStats {
  const RepoStats({
    required this.totalDownloads,
    required this.releaseCount,
    required this.stars,
    required this.fetchedAt,
    this.latestTag,
    this.latestDownloads = 0,
    this.latestDate,
  });

  final int totalDownloads;
  final int releaseCount;
  final int stars;
  final String? latestTag;
  final int latestDownloads;
  final DateTime? latestDate;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'total': totalDownloads,
        'releases': releaseCount,
        'stars': stars,
        'latestTag': latestTag,
        'latestDownloads': latestDownloads,
        'latestDate': latestDate?.toIso8601String(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  static RepoStats? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final fetched = DateTime.tryParse('${raw['fetchedAt']}');
    if (fetched == null) return null;
    return RepoStats(
      totalDownloads: (raw['total'] as num?)?.toInt() ?? 0,
      releaseCount: (raw['releases'] as num?)?.toInt() ?? 0,
      stars: (raw['stars'] as num?)?.toInt() ?? 0,
      latestTag: raw['latestTag'] as String?,
      latestDownloads: (raw['latestDownloads'] as num?)?.toInt() ?? 0,
      latestDate: DateTime.tryParse('${raw['latestDate']}'),
      fetchedAt: fetched,
    );
  }
}

class RepoStatsResult {
  const RepoStatsResult(this.stats, {this.failed = false});

  /// Fresh numbers, or the saved ones when the request failed (may be null).
  final RepoStats? stats;

  /// True when the live request failed.
  final bool failed;
}

class RepoStatsService {
  RepoStatsService._();
  static final RepoStatsService instance = RepoStatsService._();

  static const String _owner = 'vorlon-dev';
  static const String _repo = 'Zen-music';
  static const String _prefKey = 'about_repo_stats_v1';
  static const Duration _fresh = Duration(minutes: 30);
  static const Duration _timeout = Duration(seconds: 12);
  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  RepoStats? _mem;

  /// Saved numbers (no network) so the page can show something instantly.
  Future<RepoStats?> peek() async {
    if (_mem != null) return _mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == null) return null;
      _mem = RepoStats.fromJson(jsonDecode(saved));
    } catch (_) {}
    return _mem;
  }

  Future<RepoStatsResult> load({bool force = false}) async {
    final saved = await peek();
    if (!force &&
        saved != null &&
        DateTime.now().difference(saved.fetchedAt) < _fresh) {
      return RepoStatsResult(saved);
    }
    try {
      final fresh = await _fetch();
      _mem = fresh;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKey, jsonEncode(fresh.toJson()));
      } catch (_) {}
      return RepoStatsResult(fresh);
    } catch (e) {
      print('[about] repo stats failed: $e');
      return RepoStatsResult(saved, failed: true);
    }
  }

  Future<RepoStats> _fetch() async {
    var total = 0;
    var count = 0;
    String? latestTag;
    var latestDownloads = 0;
    DateTime? latestDate;

    for (var page = 1; page <= 5; page++) {
      final res = await http
          .get(
              Uri.https('api.github.com', '/repos/$_owner/$_repo/releases',
                  {'per_page': '100', 'page': '$page'}),
              headers: _headers)
          .timeout(_timeout);
      if (res.statusCode != 200) {
        throw Exception('GitHub HTTP ${res.statusCode}');
      }
      final list = jsonDecode(res.body) as List;
      for (final r in list) {
        if (r is! Map || r['draft'] == true) continue;
        var dl = 0;
        for (final a in (r['assets'] as List? ?? const [])) {
          if (a is Map) dl += (a['download_count'] as num?)?.toInt() ?? 0;
        }
        total += dl;
        count++;
        if (latestTag == null) {
          latestTag = r['tag_name']?.toString();
          latestDownloads = dl;
          latestDate = DateTime.tryParse('${r['published_at']}');
        }
      }
      if (list.length < 100) break;
    }

    var stars = 0;
    try {
      final res = await http
          .get(Uri.https('api.github.com', '/repos/$_owner/$_repo'),
              headers: _headers)
          .timeout(_timeout);
      if (res.statusCode == 200) {
        stars =
            ((jsonDecode(res.body) as Map)['stargazers_count'] as num?)?.toInt() ??
                0;
      }
    } catch (_) {}

    return RepoStats(
      totalDownloads: total,
      releaseCount: count,
      stars: stars,
      latestTag: latestTag,
      latestDownloads: latestDownloads,
      latestDate: latestDate,
      fetchedAt: DateTime.now(),
    );
  }
}
