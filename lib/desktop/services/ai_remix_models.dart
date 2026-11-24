// ZenMusic · vorlon-dev
//
// SP-78 · Offline AI remix models.
//
// Small on-device models (ONNX) that power the remix brain: the native
// analyzer decodes a track, computes a mel front-end and runs the model
// fully offline. Models are NOT bundled with the app — the user downloads
// them (Hugging Face / Essentia model zoo) and the source URL is editable,
// so no server link is baked in. Downloads land in the app documents
// directory under zen_ai_models/ and are sha-256 checked when the spec
// carries an expected hash.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How a model's output tensor maps to a tempo.
enum AiModelOutputKind {
  /// Softmax over tempo bins: bpm = min + argmax * (max - min) / (bins - 1).
  softmaxBins,

  /// Direct scalar regression — take the first float of the output.
  regression,
}

/// Everything the native analyzer needs to run one model.
class AiRemixModelSpec {
  final String id;
  final String label;
  final String fileName;

  /// Prefilled download source. Editable per-user; never baked in stone.
  final String defaultUrl;

  final AiModelOutputKind outputKind;
  final int bins;
  final double minBpm;
  final double maxBpm;

  /// Front-end sample rate the model was trained at.
  final int sampleRate;

  /// 0 → derive from the ONNX session's declared input shape (auto).
  final int melBins;

  /// 0 → derive from the ONNX session's declared input shape (auto).
  final int frames;

  /// Analysis window cap (seconds) — bounds decode memory.
  final double maxSeconds;

  /// Optional integrity check (hex sha256). Empty string skips the check.
  final String expectedSha256;

  const AiRemixModelSpec({
    required this.id,
    required this.label,
    required this.fileName,
    required this.defaultUrl,
    this.outputKind = AiModelOutputKind.softmaxBins,
    this.bins = 256,
    this.minBpm = 30,
    this.maxBpm = 286,
    this.sampleRate = 16000,
    this.melBins = 0,
    this.frames = 0,
    this.maxSeconds = 45,
    this.expectedSha256 = '',
  });

  /// Contract handed to the native analyzer on every call.
  Map<String, Object> contractMap() => <String, Object>{
        'sampleRate': sampleRate,
        'melBins': melBins,
        'frames': frames,
        'outputKind': outputKind == AiModelOutputKind.softmaxBins
            ? 'softmax_bins'
            : 'regression',
        'bins': bins,
        'minBpm': minBpm,
        'maxBpm': maxBpm,
        'maxSeconds': maxSeconds,
      };
}

/// Per-model UI state. [progress] is null unless a download is running.
class AiRemixModelState {
  final bool downloaded;
  final double? progress;
  final String? error;
  final int bytes;

  const AiRemixModelState({
    required this.downloaded,
    this.progress,
    this.error,
    this.bytes = 0,
  });
}

class AiRemixModels {
  AiRemixModels._();

  static final AiRemixModels instance = AiRemixModels._();

  /// The catalog. TempoCNN (Essentia) is the default pick: tiny ONNX,
  /// softmax over tempo bins, built for exactly the automix use case.
  static const List<AiRemixModelSpec> catalog = <AiRemixModelSpec>[
    AiRemixModelSpec(
      id: 'tempocnn',
      label: 'TempoCNN (Essentia) · tempo',
      fileName: 'tempocnn.onnx',
      defaultUrl:
          'https://essentia.upf.edu/models/tempo/tempocnn/model2.onnx',
      outputKind: AiModelOutputKind.softmaxBins,
      bins: 256,
      minBpm: 30,
      maxBpm: 286,
      sampleRate: 16000,
      melBins: 0,
      frames: 0,
      maxSeconds: 45,
    ),
  ];

  static const String _modelsDirName = 'zen_ai_models';
  static const String _urlKeyPrefix = 'ai_model_url_';

  final ValueNotifier<Map<String, AiRemixModelState>> states =
      ValueNotifier<Map<String, AiRemixModelState>>(<String, AiRemixModelState>{});
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  http.Client? _client;

  Directory? _dirCache;

  Future<Directory> _modelsDir() async {
    final cached = _dirCache;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
        '${docs.path}${Platform.pathSeparator}$_modelsDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dirCache = dir;
    return dir;
  }

  /// URL the user may have edited (persisted); falls back to the default.
  Future<String> urlFor(AiRemixModelSpec spec) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('$_urlKeyPrefix${spec.id}') ?? spec.defaultUrl;
  }

  Future<void> setUrlOverride(AiRemixModelSpec spec, String url) async {
    final p = await SharedPreferences.getInstance();
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == spec.defaultUrl) {
      await p.remove('$_urlKeyPrefix${spec.id}');
    } else {
      await p.setString('$_urlKeyPrefix${spec.id}', trimmed);
    }
  }

  Future<File?> fileFor(AiRemixModelSpec spec) async {
    final dir = await _modelsDir();
    final f = File(
        '${dir.path}${Platform.pathSeparator}${spec.fileName}');
    return f.existsSync() ? f : null;
  }

  /// The spec whose model is downloaded and ready, if any.
  Future<AiRemixModelSpec?> activeSpec() async {
    for (final spec in catalog) {
      if (await fileFor(spec) != null) return spec;
    }
    return null;
  }

  Future<void> refresh() async {
    final map = <String, AiRemixModelState>{};
    for (final spec in catalog) {
      final f = await fileFor(spec);
      final prev = states.value[spec.id];
      map[spec.id] = AiRemixModelState(
        downloaded: f != null,
        progress: prev?.progress,
        error: prev?.error,
        bytes: f?.lengthSync() ?? 0,
      );
    }
    states.value = map;
  }

  /// Streamed download with live progress + optional sha256 verify.
  /// The URL comes from [urlFor] — user-editable, never a fixed link.
  Future<void> download(AiRemixModelSpec spec) async {
    if (busy.value) return;
    busy.value = true;
    _setState(spec,
        const AiRemixModelState(downloaded: false, progress: 0.0));
    http.Client? client;
    try {
      final url = await urlFor(spec);
      final dir = await _modelsDir();
      final target =
          File('${dir.path}${Platform.pathSeparator}${spec.fileName}');
      final tmp = File('${target.path}.part');

      client = http.Client();
      _client = client;
      final request = http.Request('GET', Uri.parse(url))
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers['User-Agent'] = 'ZenMusic/1.0';
      final response = await client.send(request).timeout(
            const Duration(minutes: 10),
          );
      if (response.statusCode != 200) {
        throw 'HTTP ${response.statusCode} — check the model URL';
      }

      final total = response.contentLength ?? 0;
      int received = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) {
            _setState(
              spec,
              AiRemixModelState(
                downloaded: false,
                progress: (received / total).clamp(0.0, 1.0).toDouble(),
                bytes: received,
              ),
            );
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Integrity: sha256 when the spec carries an expected digest.
      if (spec.expectedSha256.isNotEmpty) {
        final digest =
            sha256.convert(await tmp.readAsBytes()).toString();
        if (digest != spec.expectedSha256) {
          tmp.deleteSync();
          throw 'Checksum mismatch — download corrupted';
        }
      }
      if (tmp.lengthSync() < 64) {
        tmp.deleteSync();
        throw 'File too small to be a model — check the URL';
      }
      if (target.existsSync()) target.deleteSync();
      tmp.renameSync(target.path);

      _setState(spec, AiRemixModelState(downloaded: true, bytes: received));
    } catch (e) {
      _setState(spec,
          AiRemixModelState(downloaded: false, error: e.toString()));
    } finally {
      _client?.close();
      _client = null;
      busy.value = false;
      unawaited(refresh());
    }
  }

  Future<void> delete(AiRemixModelSpec spec) async {
    final f = await fileFor(spec);
    if (f != null) {
      try {
        await f.delete();
      } catch (_) {}
    }
    await refresh();
  }

  void _setState(AiRemixModelSpec spec, AiRemixModelState state) {
    final next = Map<String, AiRemixModelState>.from(states.value);
    next[spec.id] = state;
    states.value = next;
  }
}
