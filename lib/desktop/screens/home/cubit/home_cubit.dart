// ZenMusic · vorlon-dev

import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:meta/meta.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/charts_service.dart';
import 'package:zenmusic/desktop/services/chart_model.dart';

part 'home_state.dart';


class HomeCubit extends Cubit<HomeState> {
  final YTMusic _ytMusic;
  HomeCubit(this._ytMusic) : super(HomeLoading());

  static const String _cacheKey = 'HOME_FEED_CACHE';

  /// Last known charts row (title / url / cover) — cached on disk too, so the
  /// cached feed paints COMPLETE and nothing jumps when the live data lands.
  List<ChartURL> _charts = const [];

  /// Shows the last home feed from disk at once, then refreshes it in the
  /// background. If the refresh fails the cached feed stays on screen.
  Future<void> fetch() async {
    final cached = _readCache();
    if (cached != null) {
      emit(cached);
      try {
        await _assemble();
      } catch (_) {/* keep showing the cached feed */}
      return;
    }
    emit(const HomeLoading());
    try {
      await _assemble();
    } catch (e, st) {
      emit(HomeError(e.toString(), st.toString()));
    }
  }

  Future<void> refresh() async {
    _ytMusic.clearRequestCache();
    try {
      await _assemble();
    } catch (e, st) {
      // A failed pull-to-refresh must not wipe a feed that is on screen.
      if (state is! HomeSuccess) emit(HomeError(e.toString(), st.toString()));
    }
  }

  HomeSuccess? _readCache() {
    try {
      final raw = Hive.box('SETTINGS').get(_cacheKey);
      if (raw is! String) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      // A feed cached while signed out must not show after signing in (and
      // the other way round): it is a different, personalised feed.
      final authed = YtmAuth.instance.hasSession;
      if (m['authed'] != authed) return null;
      final base = (m['sections'] as List?) ?? const [];
      if (base.isEmpty) return null;
      _charts = [
        for (final c in (m['charts'] as List?) ?? const [])
          if (c is Map && c['title'] != null && c['url'] != null)
            ChartURL(
              title: c['title'].toString(),
              url: c['url'].toString(),
              coverArt: c['coverArt']?.toString(),
            ),
      ];
      return HomeSuccess(
        chips: (m['chips'] as List?) ?? const [],
        sections: _compose(List<dynamic>.from(base), authed, null),
        continuation: m['continuation'],
        loadingMore: false,
      );
    } catch (_) {
      return null;
    }
  }

  void _writeCache(HomeSuccess s) {
    try {
      // Charts are stored separately (they hold model objects, not JSON).
      final sections = [
        for (final sec in s.sections)
          if (!(sec is Map && sec['title'] == 'Browse Charts')) sec,
      ];
      Hive.box('SETTINGS').put(
        _cacheKey,
        jsonEncode({
          'authed': YtmAuth.instance.hasSession,
          'chips': s.chips,
          'sections': sections,
          'charts': [
            for (final c in _charts)
              {'title': c.title, 'url': c.url, 'coverArt': c.coverArt},
          ],
          'continuation': s.continuation,
        }),
      );
    } catch (_) {}
  }

  /// Feed sections + (optional) history shelf + charts, in the order the app
  /// has always used: signed in → [last listening, …feed…, charts];
  /// signed out → [charts, …feed…].
  List<dynamic> _compose(List<dynamic> feed, bool authed, List? history) {
    // Pull any "Last listening" row out of the feed (a cached feed has one)
    // so it is re-inserted exactly once, at the top.
    Map<String, dynamic>? prev;
    final sections = <dynamic>[];
    for (final sec in feed) {
      if (sec is Map && sec['title'] == 'Last listening') {
        prev ??= Map<String, dynamic>.from(sec);
      } else {
        sections.add(sec);
      }
    }
    if (authed) {
      final last =
          history != null ? _lastListeningSection(history) : (prev ?? _onScreenLast());
      if (last != null) sections.insert(0, last);
    }
    if (_charts.isNotEmpty) {
      final c = _createChartsSection(_charts);
      if (authed) {
        sections.add(c);
      } else {
        sections.insert(0, c);
      }
    }
    return sections;
  }

  /// While history is still loading, keep the "Last listening" row that is
  /// already on screen so it does not blink out and back.
  Map<String, dynamic>? _onScreenLast() {
    final cur = state;
    if (cur is! HomeSuccess) return null;
    for (final sec in cur.sections) {
      if (sec is Map && sec['title'] == 'Last listening') {
        return Map<String, dynamic>.from(sec);
      }
    }
    return null;
  }

  /// Progressive load: the screen waits ONLY for the main feed. Charts and
  /// the play history are started at the same moment, in parallel, and are
  /// merged in (with a time limit) when they arrive.
  Future<void> _assemble() async {
    final authed = YtmAuth.instance.hasSession;

    final Future<List<ChartURL>> chartsF = ChartsService()
        .getChartsWithPreviews()
        .timeout(const Duration(seconds: 8),
        onTimeout: () => <ChartURL>[])
        .catchError((_) => <ChartURL>[]);
    final Future<List<dynamic>> historyF = authed
        ? _ytMusic
        .getHistory()
        .timeout(const Duration(seconds: 8),
        onTimeout: () => <dynamic>[])
        .catchError((_) => <dynamic>[])
        : Future<List<dynamic>>.value(const []);

    final feed = await _ytMusic.browse();
    final base = List<dynamic>.from(feed['sections'] as List);
    final chips = feed['chips'] ?? [];
    final continuation = feed['continuation'];

    // 1) First paint: the feed alone (keeps last charts / last listening).
    emit(HomeSuccess(
      chips: chips,
      sections: _compose(base, authed, null),
      continuation: continuation,
      loadingMore: false,
    ));

    // 2) Merge history + charts as they land.
    final history = await historyF;
    final charts = await chartsF;
    if (charts.isNotEmpty) _charts = charts;
    final result = HomeSuccess(
      chips: chips,
      sections: _compose(base, authed, history),
      continuation: continuation,
      loadingMore: false,
    );
    emit(result);
    _writeCache(result);
  }

  /// Merges the history shelves (Today / Yesterday / …) into one
  /// "Last listening" row — the account's most recent plays, the section
  /// YouTube Music itself fronts its home with. Repeats are dropped (the
  /// history loves replaying the same track), the row is capped so a
  /// heavy listener still gets a snappy horizontal scroll.
  Map<String, dynamic>? _lastListeningSection(List history) {
    final items = <dynamic>[];
    final seen = <String>{};
    for (final shelf in history) {
      final contents = shelf is Map ? shelf['contents'] : null;
      if (contents is! List) continue;
      for (final item in contents) {
        final id = item is Map ? item['videoId']?.toString() ?? '' : '';
        if (id.isNotEmpty && !seen.add(id)) continue;
        items.add(item);
      }
    }
    if (items.isEmpty) return null;
    return {
      'title': 'Last listening',
      'contents': items.take(32).toList(),
    };
  }

  Map<String, dynamic> _createChartsSection(List<ChartURL> charts) {
    return {
      'title': 'Browse Charts',
      'contents': charts.map((chart) => {
        'title': chart.title,
        'subtitle': 'Billboard Chart',
        'thumbnails': [{'url': chart.coverArt ?? 'https://www.billboard.com/wp-content/themes/vip/pmc-billboard-2021/assets/app/icons/icon-512x512.png', 'width': 500, 'height': 500}],
        'chartUrl': chart,
        'aspectRatio': 1.0, // Square cards
      }).toList(),
    };
  }

  Future<void> fetchNext() async {
    final current = state;
    if (current is! HomeSuccess) return;
    if (current.loadingMore || current.continuation == null) return;
    emit(current.copyWith(loadingMore: true));
    try {
      final feed = await _ytMusic.browseContinuation(
          additionalParams: current.continuation!);
      emit(
        HomeSuccess(
          chips: current.chips,
          sections: [...current.sections, ...feed['sections']],
          continuation: feed['continuation'],
          loadingMore: false,
        ),
      );
    } catch (e, st) {
      emit(HomeError(e.toString(), st.toString()));
    }
  }
}
