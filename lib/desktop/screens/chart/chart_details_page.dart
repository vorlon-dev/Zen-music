// ZenMusic Desktop — FRESH screen (not ported): Billboard / spotify chart
// detail page. Driven by ChartURL from the home "Browse Charts" section;
// data via ChartsService (scraped track lists), playback via the standard
// isChart search-and-play path already in SongTile. ZenMusic remains GPL-3.0.

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart' show SongTile;
import 'package:zenmusic/desktop/services/chart_model.dart';
import 'package:zenmusic/desktop/services/charts_service.dart';
import 'package:zenmusic/desktop/services/media_player.dart';

class ChartDetailsPage extends StatefulWidget {
  const ChartDetailsPage({super.key, required this.chart});
  final ChartURL chart;

  @override
  State<ChartDetailsPage> createState() => _ChartDetailsPageState();
}

class _ChartDetailsPageState extends State<ChartDetailsPage> {
  ChartModel? _chart;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final model = widget.chart.url.contains('spotify.com')
          ? await ChartsService().getSpotifyTop50Chart(widget.chart)
          : await ChartsService().getBillboardChart(widget.chart);
      if (!mounted) return;
      setState(() {
        _chart = model;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this chart. It may be blocked or offline.';
      });
    }
  }

  /// Converts chart rows to the section_item song shape (isChart: true) so
  /// tapping uses the established search-and-play path.
  List<Map<String, dynamic>> _chartSongs(ChartModel model) => [
    for (final item in model.chartItems ?? const <ChartItemModel>[])
      {
        'title': item.name ?? 'Unknown',
        'subtitle': item.subtitle ?? '',
        'isChart': true,
        'aspectRatio': 1.0,
        'thumbnails': [
          {'url': item.imageUrl ?? ''},
        ],
      },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chart.title),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      )
          : Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Builder(
            builder: (context) {
              final model = _chart!;
              final songs = _chartSongs(model);
              final playable = songs
                  .where((s) => (s['title'] as String).isNotEmpty)
                  .toList();

              return ListView(
                children: [
                  // Header with Play All
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  model.chartName ??
                                      widget.chart.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${playable.length} tracks · updated ${_lastUpdated(model)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: playable.isEmpty
                                ? null
                                : () => GetIt.I<MediaPlayer>()
                                .playAll(playable),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play All'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < playable.length; i++)
                    Stack(
                      children: [
                        SongTile(song: playable[i]),
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _lastUpdated(ChartModel model) {
    final d = model.lastUpdated;
    if (d == null) return 'recently';
    return '${d.day}/${d.month}';
  }
}