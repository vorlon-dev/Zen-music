import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:zenmusic/desktop/spotify/spotify_history.dart';

part 'history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  late final Box _box;
  late final VoidCallback _listener;

  HistoryCubit() : super(const HistoryLoading()) {
    _box = Hive.box('SONG_HISTORY');

    _listener = () {
      if (!isClosed) {
        _emitState();
      }
    };

    _box.listenable().addListener(_listener);
  }

  void load() {
    _emitState();
    _loadSpotify();
  }

  // Spotify recents (Stopify recents query, remote-only). Best-effort:
  // silent skip when logged out / offline — the page is unchanged then.
  Future<void> _loadSpotify() async {
    try {
      final tracks = await SpotifyHistory.instance.recentlyPlayed(limit: 30);
      if (isClosed || tracks.isEmpty) return;
      final current = state;
      if (current is HistoryLoaded) {
        emit(HistoryLoaded(current.songs, spotify: tracks));
      }
    } catch (_) {
      // Section stays empty; never let Spotify telemetry break history.
    }
  }

  void _emitState() {
    if (isClosed) return;

    try {
      final songs = _box.values.toList();

      songs.sort(
            (a, b) => (b['updatedAt'] ?? 0).compareTo(a['updatedAt'] ?? 0),
      );

      // Preserve already-fetched Spotify rows across box re-emits
      // (e.g. after a swipe-remove) so the section doesn't flicker away.
      final prev = state;
      final spotify = prev is HistoryLoaded ? prev.spotify : const [];

      emit(HistoryLoaded(songs, spotify: spotify));
    } catch (e) {
      if (!isClosed) {
        emit(HistoryError(e.toString()));
      }
    }
  }

  Future<void> remove(dynamic videoId) async {
    await _box.delete(videoId);
    // listener will re-emit safely
  }

  @override
  Future<void> close() {
    _box.listenable().removeListener(_listener);
    return super.close();
  }
}