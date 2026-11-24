// ZenMusic · vorlon-dev
//
// SP-78 · AI Remix models page.
//
// Download a small offline ONNX model (Hugging Face / Essentia zoo),
// scan tracks on-device (model, or the built-in DSP autocorrelation
// fallback), and persist results into the shared tempo cache that the
// beat-haptics and automix engines read first.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/services/ai_remix_models.dart';
import 'package:zenmusic/desktop/services/ai_tempo_source.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/beat_haptics.dart' show BpmCache;

class AiRemixPage extends StatefulWidget {
  const AiRemixPage({super.key});

  @override
  State<AiRemixPage> createState() => _AiRemixPageState();
}

class _AiRemixPageState extends State<AiRemixPage> {
  static const String _hfBrowseUrl =
      'https://huggingface.co/models?other=onnx&pipeline_tag=audio-classification';

  final _analyzer = AiTempoSource();

  late final AiRemixModelSpec _spec = AiRemixModels.catalog.first;
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _artistCtrl = TextEditingController();

  bool _urlLoaded = false;
  String? _pickedPath;
  double? _scannedBpm;
  String _scanSource = '';
  bool _scanning = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    AiRemixModels.instance.refresh().then((_) async {
      _urlCtrl.text = await AiRemixModels.instance.urlFor(_spec);
      if (mounted) setState(() => _urlLoaded = true);
    });
    _prefillFromNowPlaying();
  }

  void _prefillFromNowPlaying() {
    try {
      final song = GetIt.I<MediaPlayer>().currentSongNotifier.value;
      if (song != null) {
        _titleCtrl.text = song.title;
        _artistCtrl.text = (song.artist ?? song.album ?? '').toString();
      }
    } catch (_) {
      // Player not up yet — fields stay editable by hand.
    }
  }

  Future<void> _download() async {
    await AiRemixModels.instance
        .setUrlOverride(_spec, _urlCtrl.text);
    setState(() {});
    await AiRemixModels.instance.download(_spec);
  }

  Future<void> _pickAndScan() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'mp3', 'wav', 'flac', 'm4a', 'ogg', 'opus', 'aac',
        ],
      );
      final path = picked?.path;
      if (path == null) return;
      setState(() {
        _pickedPath = path;
        _scannedBpm = null;
        _scanSource = '';
        _scanError = null;
        _scanning = true;
      });
      final bpm = await _analyzer.analyzeFile(path);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scannedBpm = bpm;
        _scanSource = _analyzer.lastSource.value;
        if (bpm == null) {
          _scanError =
              'Analysis failed — no tempo. Check the format or model.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _scanError = e.toString();
      });
    }
  }

  Future<void> _saveToCache() async {
    final bpm = _scannedBpm;
    if (bpm == null || bpm <= 0) return;
    await BpmCache().put(_titleCtrl.text, _artistCtrl.text, bpm);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Saved ${bpm.round()} BPM — engines will use it for this song'.tr),
      ),
    );
  }

  String _fmtBytes(int b) {
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
    return '$b B';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Remix Models'.tr)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _introCard(),
              const SizedBox(height: 12),
              _modelCard(),
              const SizedBox(height: 12),
              _scanCard(),
              const SizedBox(height: 12),
              _howItWorksCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _introCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.psychology),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Offline remix brain'.tr,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Download a small AI model once; after that it runs fully '
                      'offline and never sends your music anywhere.'
                  .tr,
              style: const TextStyle(height: 1.4),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    await launchUrl(Uri.parse(_hfBrowseUrl),
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('Browse models on Hugging Face'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelCard() {
    return ValueListenableBuilder<Map<String, AiRemixModelState>>(
      valueListenable: AiRemixModels.instance.states,
      builder: (BuildContext context, Map<String, AiRemixModelState> states,
          _) {
        final st = states[_spec.id] ??
            const AiRemixModelState(downloaded: false);
        final downloading = st.progress != null && !st.downloaded;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.model_training, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _spec.label.tr,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    _statusChip(st),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlCtrl,
                  enabled: _urlLoaded && !downloading,
                  decoration: InputDecoration(
                    labelText: 'Model URL'.tr,
                    hintText: _spec.defaultUrl,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: 'Reset to default'.tr,
                      onPressed: _urlLoaded && !downloading
                          ? () async {
                              await AiRemixModels.instance
                                  .setUrlOverride(_spec, '');
                              _urlCtrl.text = _spec.defaultUrl;
                              setState(() {});
                            }
                          : null,
                      icon: const Icon(Icons.restart_alt, size: 18),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                if (st.error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline,
                          size: 16, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          st.error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                if (st.downloaded) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    '${'On device'.tr}: ${_fmtBytes(st.bytes)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: downloading
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                LinearProgressIndicator(
                                    value: st.progress),
                                const SizedBox(height: 4),
                                Text(
                                  '${(st.progress! * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            )
                          : FilledButton.icon(
                              onPressed: _download,
                              icon: const Icon(Icons.download, size: 18),
                              label: Text(st.downloaded
                                  ? 'Re-download'.tr
                                  : 'Download model'.tr),
                            ),
                    ),
                    if (st.downloaded) ...<Widget>[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Delete model'.tr,
                        onPressed: () async {
                          await AiRemixModels.instance.delete(_spec);
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(AiRemixModelState st) {
    final downloading = st.progress != null && !st.downloaded;
    Color color;
    String label;
    if (downloading) {
      color = Theme.of(context).colorScheme.primary;
      label = 'Downloading'.tr;
    } else if (st.downloaded) {
      color = Colors.greenAccent.shade400;
      label = 'Ready'.tr;
    } else if (st.error != null) {
      color = Colors.redAccent;
      label = 'Failed'.tr;
    } else {
      color = Theme.of(context).hintColor;
      label = 'Not downloaded'.tr;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _scanCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.graphic_eq, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scan a track on-device'.tr,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Picks the tempo of any audio file with the downloaded model '
                      '(or the built-in DSP fallback), then the automix and '
                      'beat features reuse it.'
                  .tr,
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning ? null : _pickAndScan,
                    icon: const Icon(Icons.music_note, size: 18),
                    label: Text(
                      _pickedPath == null
                          ? 'Choose audio file'.tr
                          : _pickedPath!
                              .split(Platform.pathSeparator)
                              .last,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            if (_scanning) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_scanError != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _scanError!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12),
              ),
            ],
            if (_scannedBpm != null && !_scanning) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Text(
                    '${_scannedBpm!.round()} BPM',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _scanSource == 'model'
                        ? 'via model'.tr
                        : 'via DSP fallback'.tr,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).hintColor),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Title'.tr,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _artistCtrl,
                      decoration: InputDecoration(
                        labelText: 'Artist'.tr,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _saveToCache,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text('Save to tempo cache'.tr),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _howItWorksCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Good to know'.tr,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '• The analyzer never needs the network: the model file runs '
                      'on-device, and scanned tempos are stored in the shared '
                      'cache the beat and automix features read first.\n'
                      '• On-device analysis is available on Android; on '
                      'desktop you can manage models but scanning uses the '
                      'online lookup.\n'
                      '• If no model is installed the built-in DSP fallback '
                      'still estimates tempo offline from the audio itself.\n'
                      '• Model URL is editable — point it at any compatible '
                      'ONNX tempo model you prefer.'
                  .tr,
              style: const TextStyle(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
