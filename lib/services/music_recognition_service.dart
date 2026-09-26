import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'shazam_service.dart';
import 'shazam_signature_generator.dart';

enum RecognitionPhase { idle, listening, processing, success, noMatch, error }

class RecognitionState {
  const RecognitionState._(this.phase, {this.result, this.message});
  const RecognitionState.idle() : this._(RecognitionPhase.idle);
  const RecognitionState.listening() : this._(RecognitionPhase.listening);
  const RecognitionState.processing() : this._(RecognitionPhase.processing);
  const RecognitionState.success(ShazamResult r)
      : this._(RecognitionPhase.success, result: r);
  const RecognitionState.noMatch([String msg = 'No matches found'])
      : this._(RecognitionPhase.noMatch, message: msg);
  const RecognitionState.error(String msg)
      : this._(RecognitionPhase.error, message: msg);

  final RecognitionPhase phase;
  final ShazamResult? result;
  final String? message;
}

/// Mic → fingerprint → Shazam. Records directly at the fingerprinter's
/// 16 kHz requirement, so no resampling stage is needed (Echo resamples
/// from 44.1 kHz; the record package captures at 16 kHz natively).
class MusicRecognitionService {
  MusicRecognitionService._();
  static final MusicRecognitionService instance = MusicRecognitionService._();

  static const _sampleRate = 16000; // ShazamSignatureGenerator.sampleRate
  static const _recordMs = 10000;

  final AudioRecorder _recorder = AudioRecorder();
  final ValueNotifier<RecognitionState> state =
  ValueNotifier<RecognitionState>(const RecognitionState.idle());

  bool _busy = false;
  bool _cancelled = false;

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> recognize() async {
    if (_busy) return;
    _busy = true;
    _cancelled = false;
    state.value = const RecognitionState.listening();
    try {
      final pcm = await _recordPcm();
      if (_cancelled) return;
      state.value = const RecognitionState.processing();

      final signature = ShazamSignatureGenerator.fromI16(pcm);
      final durationMs = (pcm.length ~/ 2) * 1000 ~/ _sampleRate;
      final result =
      await ShazamService.instance.recognize(signature, durationMs);
      if (_cancelled) return;
      state.value = RecognitionState.success(result);
    } catch (e) {
      if (_cancelled) return;
      final msg = e.toString();
      if (msg.contains('No match')) {
        state.value =
        const RecognitionState.noMatch('No matches found. Try again with clearer audio.');
      } else {
        state.value = RecognitionState.error(
            msg.replaceFirst('Exception: ', '').trim());
      }
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List> _recordPcm() async {
    final chunks = BytesBuilder();
    final completer = Completer<Uint8List>();
    final deadline =
    DateTime.now().add(const Duration(milliseconds: _recordMs));

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: 1,
    ));

    StreamSubscription<Uint8List>? sub;
    sub = stream.listen((data) {
      if (_cancelled) return;
      chunks.add(data);
      if (!completer.isCompleted &&
          DateTime.now().isAfter(deadline)) {
        completer.complete(chunks.takeBytes());
      }
    }, onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!completer.isCompleted) {
        if (_cancelled) {
          completer.completeError(StateError('cancelled'));
        } else {
          // Recorder stopped early — use whatever we captured.
          completer.complete(chunks.takeBytes());
        }
      }
    });

    try {
      return await completer.future;
    } finally {
      await sub.cancel();
      try {
        await _recorder.stop();
      } catch (_) {}
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await _recorder.stop();
    } catch (_) {}
    state.value = const RecognitionState.idle();
    _busy = false;
  }

  void reset() {
    if (state.value.phase == RecognitionPhase.listening) return;
    state.value = const RecognitionState.idle();
  }
}