// ZenMusic · vorlon-dev

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/charts_service.dart';
import 'package:zenmusic/desktop/services/chart_model.dart';

part 'home_state.dart';


class HomeCubit extends Cubit<HomeState> {
  final YTMusic _ytMusic;
  HomeCubit(this._ytMusic) : super(HomeLoading());

  Future<void> fetch() async {
    emit(const HomeLoading());
    try {
      emit(await _assemble());
    } catch (e, st) {
      emit(HomeError(e.toString(), st.toString()));
    }
  }

  Future<void> refresh() async {
    try {
      emit(await _assemble());
    } catch (e, st) {
      emit(HomeError(e.toString(), st.toString()));
    }
  }

  Future<HomeSuccess> _assemble() async {
    final authed = YtmAuth.instance.hasSession;

    // The account's play history — "last listening" — is fetched in
    // parallel with the feed. A history failure must never take the feed
    // down: it degrades to an empty list and the section is just absent.
    final historyFuture = authed
        ? _ytMusic.getHistory().catchError((_) => <dynamic>[])
        : Future<List<dynamic>>.value(const []);

    final responses = await Future.wait([
      _ytMusic.browse(),
      ChartsService().getChartsWithPreviews(),
      historyFuture,
    ]);

    final feed = responses[0] as Map<String, dynamic>;
    final charts = responses[1] as List<ChartURL>;
    final history = responses[2] as List;

    List sections = feed['sections'];
    final chartsSection = _createChartsSection(charts);

    if (authed) {
      final lastListening = _lastListeningSection(history);
      if (lastListening != null) sections.insert(0, lastListening);
      sections.add(chartsSection);
    } else {
      sections.insert(0, chartsSection);
    }

    return HomeSuccess(
      chips: feed['chips'] ?? [],
      sections: sections,
      continuation: feed['continuation'],
      loadingMore: false,
    );
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
