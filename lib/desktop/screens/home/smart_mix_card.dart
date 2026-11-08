// ZenMusic · Home card: Smart Mix + weekly recap + Genre DNA + Discover.
// Hidden until you have some listening history.
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/screens/library/friends_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:zenmusic/desktop/services/media_player.dart';
import 'package:zenmusic/desktop/services/smart_mix_service.dart';

class SmartMixCard extends StatefulWidget {
  const SmartMixCard({super.key});
  @override
  State<SmartMixCard> createState() => _SmartMixCardState();
}

class _SmartMixCardState extends State<SmartMixCard> {
  Map? _recap;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    if (Hive.box('SONG_HISTORY').isNotEmpty) {
      SmartMixService.instance.weeklyRecap().then((r) {
        if (mounted) setState(() => _recap = r);
      });
    }
  }

  Future<void> _play() async {
    setState(() => _playing = true);
    final songs = await SmartMixService.instance.smartMix(size: 40);
    if (mounted) setState(() => _playing = false);
    if (songs.isNotEmpty) await GetIt.I<MediaPlayer>().playAll(songs);
  }

  void _sheet(String title, Future<Widget> body) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FutureBuilder<Widget>(
            future: body,
            builder: (c, s) => s.hasData
                ? s.data!
                : const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          ),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Hive.box('SONG_HISTORY').isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tops = ((_recap?['topArtists'] as List?) ?? const []).cast<Map>();
    final summary = _recap == null
        ? 'Made from what you play most'
        : '${_recap!['songs']} songs this week'
            '${tops.isEmpty ? '' : ' · top: ${tops.take(2).map((e) => e['name']).join(', ')}'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome, color: scheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Smart Mix'.tr,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onSecondaryContainer)),
                  Text(summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer.withOpacity(0.7))),
                ]),
              ),
              FilledButton.icon(
                onPressed: _playing ? null : _play,
                icon: _playing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text('Play'.tr),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.bar_chart, size: 18),
                label: Text('Genre DNA'.tr),
                onPressed: () => _sheet('Your genre DNA', _dna()),
              ),
              ActionChip(
                avatar: const Icon(Icons.group, size: 18),
                label: Text('Friends'.tr),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FriendsFeedPage()),
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.explore, size: 18),
                label: Text('Discover'.tr),
                onPressed: () => _sheet('Artists you may like', _discover()),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<Widget> _dna() async {
    final d = await SmartMixService.instance.genreDna();
    if (d.isEmpty) return Text('Not enough listening this week yet.'.tr);
    final e = d.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (final x in e.take(6))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 100, child: Text(x.key, overflow: TextOverflow.ellipsis)),
            Expanded(child: LinearProgressIndicator(value: x.value, minHeight: 8, borderRadius: BorderRadius.circular(4))),
            SizedBox(width: 44, child: Text('${(x.value * 100).round()}%', textAlign: TextAlign.end)),
          ]),
        ),
    ]);
  }

  Future<Widget> _discover() async {
    final a = await SmartMixService.instance.discoverArtists();
    if (a.isEmpty) return Text('Nothing new found right now. Check your connection.'.tr);
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final n in a) Chip(label: Text(n))]);
  }
}
