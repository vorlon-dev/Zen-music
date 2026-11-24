// ZenMusic · vorlon-dev
//
// SP-78 · On-device tempo source for the remix brain.
//
// Implements the TempoSource seam the engines already expose: when a
// local file matching (title, artist) exists, it runs the offline
// analyzer (downloaded ONNX model, or the built-in DSP autocorrelation
// when no model is installed) through the zen/ai_remix channel and
// returns the tempo. If anything fails it falls back to the existing
// keyless Deezer lookup, so beat haptics / automix never stall.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:zenmusic/desktop/services/ai_remix_models.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart'
    show BpmCache, DeezerTempoSource, TempoSource;
import 'package:zenmusic/desktop/services/file_storage.dart';

class AiTempoSource implements TempoSource {
  static const MethodChannel _ch = MethodChannel('zen/ai_remix');

  final DeezerTempoSource _web = DeezerTempoSource();

  /// Last result, exposed so the AI remix page can show what the engine
  /// actually used (model vs DSP fallback).
  final ValueHolder lastSource = ValueHolder();

  Directory? _musicDirCache;

  @override
  Future<double?> tempoFor(String title, String artist) async {
    // 1. Offline on-device analysis over the user's own audio files.
    final file = await _findLocalFile(title, artist);
    if (file != null) {
      final bpm = await analyzeFile(file.path);
      if (bpm != null && bpm > 0) return bpm;
    }
    // 2. Studio tempo from the existing keyless lookup.
    return _web.tempoFor(title, artist);
  }

  /// Run the analyzer over one audio file. Returns null when neither a
  /// model nor the DSP fallback could produce a tempo (e.g. unsupported
  /// format) — callers treat that as "no answer", never an error.
  Future<double?> analyzeFile(String path) async {
    try {
      final spec = await AiRemixModels.instance.activeSpec();
      final args = <String, Object>{'path': path};
      if (spec != null) {
        args['modelPath'] = (await AiRemixModels.instance.fileFor(spec))!.path;
        args['contract'] = spec.contractMap();
      }
      final result = await _ch
          .invokeMethod('analyze', args)
          .timeout(const Duration(seconds: 90));
      if (result is! Map) return null;
      lastSource.value = (result['source'] ?? '').toString();
      final bpm = (result['bpm'] as num?)?.toDouble();
      if (bpm == null || bpm <= 0 || bpm > 400) return null;
      return bpm;
    } catch (_) {
      // Channel absent (desktop) or decode failed — no on-device answer.
      lastSource.value = '';
      return null;
    }
  }

  /// Bounded recursive search of the music folder for a file whose name
  /// matches the track. Normalized substring scoring, ≤ 4000 files, no
  /// blocking of the UI thread beyond directory walking in microtasks.
  Future<File?> _findLocalFile(String title, String artist) async {
    final dir = await _musicDir();
    if (dir == null) return null;
    final t = _norm(title);
    final a = _norm(artist);
    if (t.isEmpty && a.isEmpty) return null;

    File? best;
    int bestScore = 0;
    int visited = 0;
    final stack = <Directory>[dir];
    try {
      while (stack.isNotEmpty && visited < 4000) {
        final d = stack.removeLast();
        await for (final entity in d.list(followLinks: false)) {
          if (visited >= 4000) break;
          if (entity is Directory) {
            stack.add(entity);
            continue;
          }
          if (entity is! File) continue;
          final ext = entity.path.toLowerCase();
          if (!(ext.endsWith('.mp3') ||
              ext.endsWith('.flac') ||
              ext.endsWith('.m4a') ||
              ext.endsWith('.wav') ||
              ext.endsWith('.ogg') ||
              ext.endsWith('.opus'))) {
            continue;
          }
          visited++;
          final name = _norm(entity.path.split(Platform.pathSeparator).last);
          if (name.isEmpty) continue;
          int score = 0;
          if (t.isNotEmpty && name.contains(t)) score += 2;
          if (a.isNotEmpty && name.contains(a)) score += 2;
          if (score == 4 && t.isNotEmpty && a.isNotEmpty) {
            // Both matched — prefer the shortest (least extra junk).
            score += 3;
          }
          if (score > bestScore) {
            bestScore = score;
            best = entity;
            if (score >= 7) break;
          }
        }
        if (bestScore >= 7) break;
      }
    } catch (_) {
      // Permission or IO issue — no local answer.
      return null;
    }
    return bestScore >= 2 ? best : null;
  }

  Future<Directory?> _musicDir() async {
    final cached = _musicDirCache;
    if (cached != null) return cached;
    try {
      final storage = FileStorage();
      final d = Directory(storage.storagePaths.musicPath);
      if (d.existsSync()) {
        _musicDirCache = d;
        return d;
      }
    } catch (_) {
      // FileStorage not initialised (headless) — try documents fallback.
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory(
          '${docs.path}${Platform.pathSeparator}Music');
      if (d.existsSync()) {
        _musicDirCache = d;
        return d;
      }
    } catch (_) {}
    return null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// Persist a scanned tempo so every engine (which reads [BpmCache]
  /// first) picks it up on the next session without re-analyzing.
  static Future<void> saveToCache(
      String title, String artist, double bpm) {
    return BpmCache().put(title, artist, bpm);
  }
}

/// Tiny mutable holder — avoids pulling in another ValueNotifier when a
/// plain "last note" is enough.
class ValueHolder {
  String value = '';
}
