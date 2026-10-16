import 'package:bloc/bloc.dart';
import 'package:hive/hive.dart';
import 'package:meta/meta.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';
import 'package:zenmusic/desktop/services/jiosaavn_service.dart';
import 'package:zenmusic/desktop/spotify/spotify_search.dart';

part 'search_state.dart';

class SearchCubit extends Cubit<SearchState> {
  final YTMusic _ytmusic;
  Map<String, dynamic>? endpoint;
  SearchCubit(this._ytmusic, {this.endpoint}) : super(SearchLoading()) {
    if (endpoint != null) {
      search('');
    }
  }

  Future<void> search(String query) async {
    emit(const SearchLoading());
    try {
      if (Hive.box('SETTINGS').get('SEARCH_HISTORY', defaultValue: true)) {
        await Hive.box('SEARCH_HISTORY').delete(query.toLowerCase());
        await Hive.box('SEARCH_HISTORY').put(query.toLowerCase(), query);
      }
      final feed = await _ytmusic.search(query, endpoint: endpoint);

      // JioSaavn cross-source section (pure Dart — every platform).
      if (endpoint == null) {
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
      }

      // Spotify cross-source section (Stopify protocol). Silently skips
      // when there is no Spotify session — non-Spotify users see no change.
      // Playback routing for these rows lands in the next round.
      if (endpoint == null) {
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
    final current = state;
    if (current is! SearchSuccess) return;
    if (current.loadingMore || current.continuation == null) return;
    emit(current.copyWith(loadingMore: true));
    try {
      final feed = await _ytmusic.search('',
          endpoint: endpoint, additionalParams: current.continuation!);
      // FIXED (round after SP-2 smoke): result was constructed but never
      // emitted, so pagination stalled with loadingMore=true forever.
      emit(SearchSuccess(
        sections: [...current.sections, ...feed['sections']],
        continuation: feed['continuation'],
        loadingMore: false,
      ));
    } catch (e, st) {
      emit(SearchError(e.toString(), st.toString()));
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