import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';

import 'package:zenmusic/desktop/ytmusic/ytmusic.dart';

part 'browse_state.dart';

class BrowseCubit extends Cubit<BrowseState> {
  final YTMusic _ytMusic;
  final Map<String, dynamic> endpoint;
  BrowseCubit(this._ytMusic, {required this.endpoint}) : super(BrowseLoading());
  Future<void> fetch() async {
    emit(const BrowseLoading());
    try {
      final feed = await _ytMusic.browse(body: endpoint, limit: 2);
      // SP-39f: the cubit may have been closed while browse() was in
      // flight (route popped). Never emit on a closed cubit.
      if (isClosed) return;
      emit(BrowseSuccess(
        header: feed['header'] ?? {},
        sections: feed['sections'],
        continuation: feed['continuation'],
        loadingMore: false,
      ));
    } catch (e, st) {
      // SP-39f: guards the double-throw — on a closed cubit the success
      // emit above threw INTO this catch, and re-emitting here turned it
      // into the unhandled "Cannot emit new states after calling close".
      if (isClosed) return;
      emit(BrowseError(e.toString(), st.toString()));
    }
  }
}