import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import '../data/radio_stations_db.dart';
import '../main.dart';
import '../models/radio_station.dart';
import '../theme/spotify_theme.dart';
import '../widgets/wave_spinner.dart';

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> {
  String _search = '';

  List<RadioStation> get _stations {
    if (_search.isEmpty) return radioStationsDB;
    return radioStationsDB
        .where((s) =>
    s.name.toLowerCase().contains(_search) ||
        (s.genre?.toLowerCase().contains(_search) ?? false))
        .toList();
  }

  Future<void> _play(RadioStation station) async {
    final ok = await audioHandler.playRadioStream(
      id: station.id,
      name: station.name,
      streamUrl: station.streamUrl,
      image: station.image,
      genre: station.genre,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '▶ ${station.name}' : 'Failed to play station'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotifyColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Radio stations',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: SpotifyColors.textPrimary)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              style: const TextStyle(color: SpotifyColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search stations or genres...',
                hintStyle: const TextStyle(color: SpotifyColors.textTertiary),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: SpotifyColors.textSecondary),
                filled: true,
                fillColor: SpotifyColors.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: _stations.isEmpty
                ? const Center(
                child: Text('No stations found',
                    style: TextStyle(color: SpotifyColors.textSecondary)))
                : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: _stations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = _stations[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _play(s),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SpotifyColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            s.image,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            loadingBuilder:
                                (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: 56,
                                height: 56,
                                color: SpotifyColors.surfaceLight,
                                child: const Center(
                                  child: WaveSpinner(
                                      size: 18, strokeWidth: 2),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              width: 56,
                              height: 56,
                              color: SpotifyColors.surfaceLight,
                              child: const Icon(Icons.radio_rounded,
                                  color: SpotifyColors.textTertiary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: SpotifyColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14)),
                              if (s.genre != null)
                                Text(s.genre!,
                                    style: const TextStyle(
                                        color: SpotifyColors
                                            .textSecondary,
                                        fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(FluentIcons.speaker_2_24_filled,
                            size: 20, color: SpotifyColors.green),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}