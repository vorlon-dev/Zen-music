// ZenMusic · vorlon-dev
//
// Real stream format of the track that is playing right now, read from the
// ExoPlayer decoder on Android (codec, declared bitrate, sample rate,
// channels, PCM depth) through the `zen.audio_format` channel that the
// just_audio fork exposes. Other platforms have no such channel and simply
// keep the metadata-based estimate.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class RealAudioFormat {
  RealAudioFormat._();
  static final RealAudioFormat instance = RealAudioFormat._();

  static const MethodChannel _ch = MethodChannel('zen.audio_format');

  /// Bumped whenever a fresh format arrives (UI rebuild trigger).
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Map<String, dynamic>? _current;
  String? _forId;
  bool _attached = false;
  bool _unsupported = false;

  /// Format of [songId] if it is the track we last measured, else null.
  Map<String, dynamic>? forSong(String songId) =>
      (_forId == songId) ? _current : null;

  void attach(AudioPlayer player) {
    if (_attached || _unsupported) return;
    _attached = true;
    player.currentIndexStream.listen((_) => _schedule(player));
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.ready) _schedule(player, quick: true);
    });
    _schedule(player);
  }

  Timer? _t1, _t2;

  void _schedule(AudioPlayer player, {bool quick = false}) {
    _t1?.cancel();
    _t2?.cancel();
    _t1 = Timer(const Duration(milliseconds: 350), () => refresh(player));
    if (!quick) {
      _t2 = Timer(const Duration(milliseconds: 1500), () => refresh(player));
    }
  }

  Future<void> refresh(AudioPlayer player) async {
    if (_unsupported) return;
    try {
      final tag = player.sequenceState?.currentSource?.tag;
      final id = tag is MediaItem ? tag.id : null;
      final raw = await _ch.invokeMethod<Map>('get');
      if (raw == null || id == null) return;
      final m = Map<String, dynamic>.from(raw);
      if (_forId == id && mapEquals(_current, m)) return;
      _forId = id;
      _current = m;
      revision.value++;
    } on MissingPluginException {
      _unsupported = true;
    } catch (_) {}
  }
}
