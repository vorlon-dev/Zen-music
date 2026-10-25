import 'package:bloc/bloc.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/jiosaavn_service.dart';
import 'package:zenmusic/desktop/services/youtube_video_search.dart';
import 'package:zenmusic/desktop/spotify/spotify_search.dart';

part 'search_state.dart';

/// All = YT Music + YouTube videos preview + JioSaavn + Spotify.
/// Videos = YouTube videos only, with infinite scroll.
enum SearchFilter { all, videos }

/// YouTube serves the best thumbnail at i.ytimg.com/vi/<id>/<name>.jpg.
/// hqdefault (480x360) exists for every video; the search page tries
/// maxresdefault / hq720 first and falls back to this one.
String ytThumb(String videoId, {String name = 'hqdefault'}) =>
    'https://i.ytimg.com/vi/$videoId/$name.jpg';

/// Replaces the tiny thumbnails on YouTube video results with the
/// high-quality ones. Non-video rows (JioSaavn, Spotify, YT Music) are left
/// untouched.
List<Map<String, dynamic>> _hqVideos(Iterable items) {
  return items.map<Map<String, dynamic>>((e) {
    final m = Map<String, dynamic>.from(e as Map);
    final id = m['videoId']?.toString() ?? '';
    if (m['isYtVideo'] == true && id.length == 11) {
      m['thumbnails'] = [
        {'url': ytThumb(id), 'width': 480, 'height': 360},
      ];
    }
    return m;
  }).toList();
}

class SearchCubit extends Cubit<SearchState> {
  final YTMusic _ytmusic;
  Map<String, dynamic>? endpoint;

  String _query = '';
  SearchFilter _filter = SearchFilter.all;
  String? _videoToken;

  SearchFilter get filter => _filter;

  SearchCubit(this._ytmusic, {this.endpoint}) : super(SearchLoading()) {
    if (endpoint != null) {
      search('');
    } else {
      // SP-42 FIX (field report: "on search page that loader spin only no
      // data come ... deta should come ok like trending on search"). The
      // landing page never fetched anything: with endpoint == null the
      // constructor skipped search('') and the state stayed SearchLoading
      // forever — the page showed an eternal spinner (see screenshot).
      // The landing now loads the YTM home feed (the same trending shelves
      // the Home tab shows) so there is real data from the first paint.
      fetchTrending();
    }
  }

  /// Landing page content (no query yet): the trending feed. Sections keep
  /// their own titles and "More" buttons; a query replaces them via search().
  Future<void> fetchTrending() async {
    emit(const SearchLoading());
    try {
      final feed = await _ytmusic.browse();
      final List sections = (feed['sections'] as List?) ?? const [];
      // Keep the landing compact: the search page renders sections as
      // vertical lists (unlike the home shelves), so cap each section.
      final capped = sections.map<Map<String, dynamic>>((s) {
        final m = Map<String, dynamic>.from(s as Map);
        final contents = (m['contents'] as List?) ?? const [];
        if (contents.length > 10) m['contents'] = contents.take(10).toList();
        return m;
      }).toList();
      if (isClosed) return;
      emit(SearchSuccess(
          sections: capped, continuation: null, loadingMore: false));
    } catch (e, st) {
      if (isClosed) return; // page popped mid-load (SP-39f doctrine)
      print(e);
      print(st);
      emit(SearchError(e.toString(), st.toString()));
    }
  }

  /// Switch chip and re-run the last query (no extra history entry).
  Future<void> setFilter(SearchFilter f) async {
    if (f == _filter) return;
    _filter = f;
    if (_query.trim().isEmpty) return;
    await search(_query, saveHistory: false);
  }

  Future<void> search(String query, {bool saveHistory = true}) async {
    // SP-42: an empty query on the landing page re-loads the trending feed
    // instead of hitting the search endpoint with no query.
    if (endpoint == null && query.trim().isEmpty) {
      await fetchTrending();
      return;
    }
    emit(const SearchLoading());
    try {
      if (saveHistory &&
          query.trim().isNotEmpty &&
          Hive.box('SETTINGS').get('SEARCH_HISTORY', defaultValue: true)) {
        await Hive.box('SEARCH_HISTORY').delete(query.toLowerCase());
        await Hive.box('SEARCH_HISTORY').put(query.toLowerCase(), query);
      }
      if (endpoint == null) _query = query;

      // ---- Videos chip: YouTube videos only -------------------------
      if (endpoint == null && _filter == SearchFilter.videos) {
        final page = await YouTubeVideoSearch.instance.search(query);
        _videoToken = page.token;
        emit(SearchSuccess(
          sections: [
            {'title': null, 'contents': _hqVideos(page.items)},
          ],
          continuation: null,
          loadingMore: false,
        ));
        return;
      }

      // ---- All chip -------------------------------------------------
      final feed = await _ytmusic.search(query, endpoint: endpoint);

      if (endpoint == null) {
        // YouTube videos preview (top results for the keyword).
        try {
          final page = await YouTubeVideoSearch.instance.search(query);
          if (page.items.isNotEmpty) {
            (feed['sections'] as List).add({
              'title': 'YouTube videos',
              'contents': _hqVideos(page.items.take(8)),
            });
          }
        } catch (_) {}

        // JioSaavn cross-source section (pure Dart — every platform).
        try {
          final saavnSongs =
          await JioSaavnService.instance.search(query, limit: 10);
          if (saavnSongs.isNotEmpty) {
            (feed['sections'] as List).add({
              'title': 'JioSaavn',
              'contents': saavnSongs,
            });
          }
        } catch (_) {}

        // Spotify cross-source section (Stopify protocol). Silently skips
        // when there is no Spotify session.
        try {
          final spotifySongs =
          await SpotifySearch.instance.search(query, limit: 10);
          if (spotifySongs.isNotEmpty) {
            (feed['sections'] as List).add({
              'title': 'Spotify',
              'contents': spotifySongs,
            });
          }
        } catch (e) {
          print('[spotify-search] section error: $e');
        }
      }

      emit(SearchSuccess(
          sections: feed['sections'],
          continuation: feed['continuation'],
          loadingMore: false));
    } catch (e, st) {
      print(e);
      print(st);
      emit(SearchError(e.toString(), st.toString()));
    }
  }

  Future<void> fetchNext() async {
    if (endpoint == null && _filter == SearchFilter.videos) {
      await _moreVideos();
      return;
    }
    final current = state;
    if (current is! SearchSuccess) return;
    if (current.loadingMore || current.continuation == null) return;
    emit(current.copyWith(loadingMore: true));
    try {
      final feed = await _ytmusic.search('',
          endpoint: endpoint, additionalParams: current.continuation!);
      emit(SearchSuccess(
        sections: [...current.sections, ...feed['sections']],
        continuation: feed['continuation'],
        loadingMore: false,
      ));
    } catch (e, st) {
      emit(SearchError(e.toString(), st.toString()));
    }
  }

  Future<void> _moreVideos() async {
    final current = state;
    if (current is! SearchSuccess) return;
    if (current.loadingMore || _videoToken == null) return;
    emit(current.copyWith(loadingMore: true));
    try {
      final page = await YouTubeVideoSearch.instance.more(_videoToken!);
      _videoToken = page.token;
      final existing = List<Map<String, dynamic>>.from(
          (current.sections.first['contents'] as List)
              .cast<Map<String, dynamic>>());
      final seen = existing.map((e) => e['videoId']).toSet();
      existing.addAll(
          _hqVideos(page.items.where((e) => !seen.contains(e['videoId']))));
      emit(SearchSuccess(
        sections: [
          {'title': null, 'contents': existing},
        ],
        continuation: null,
        loadingMore: false,
      ));
    } catch (_) {
      emit(current.copyWith(loadingMore: false));
    }
  }

  Future<List<Map<String, dynamic>>> getSuggestions(String query) async {
    try {
      List<Map<String, dynamic>> suggestions =
      await _ytmusic.getSearchSuggestions(query);
      return suggestions;
    } catch (e) {
      return [];
    }
  }
}