import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:zenmusic/desktop/core/widgets/section_item.dart';
import 'package:zenmusic/desktop/screens/library/history/cubit/history_cubit.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HistoryCubit()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          centerTitle: true,
        ),
        body: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            return switch (state) {
              HistoryLoading() => const Center(child: AdaptiveProgressRing()),
              HistoryError(:final message) => Center(child: Text(message)),
              HistoryLoaded(:final songs, :final spotify) =>
                  _HistoryBody(songs: songs, spotify: spotify),
            };
          },
        ),
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.songs, required this.spotify});

  final List songs;
  final List spotify;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty && spotify.isEmpty) {
      return const Center(
        child: Text("No History Found"),
      );
    }

    // Bounded content (history box + capped Spotify section) — plain
    // children list keeps the section logic simple and readable.
    final children = <Widget>[];

    if (spotify.isNotEmpty) {
      children.add(_SectionLabel('Spotify'));
      for (final song in spotify) {
        children.add(SongTile(song: song));
      }
    }
    if (songs.isNotEmpty) {
      // Label the local list only when the Spotify section is present,
      // so a logged-out history page looks exactly as before.
      if (spotify.isNotEmpty) {
        children.add(const SizedBox(height: 12));
        children.add(_SectionLabel('On this device'));
      }
      for (final song in songs) {
        children.add(SwipeActionCell(
          backgroundColor: Colors.transparent,
          key: ObjectKey(song['videoId']),
          trailingActions: [
            SwipeAction(
              title: 'Remove',
              color: Colors.red,
              onTap: (handler) async {
                final confirm = await Modals.showConfirmBottomModal(
                  context,
                  message: 'Remove this song from your history?',
                  isDanger: true,
                );

                if (confirm && context.mounted) {
                  context.read<HistoryCubit>().remove(song['videoId']);
                }
              },
            ),
          ],
          child: SongTile(song: song),
        ));
      }
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1000),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListView(children: children),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}