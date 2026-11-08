// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/library/downloads/downloading/cubit/downloading_cubit.dart';
import 'package:zenmusic/desktop/screens/library/downloads/downloading/widgets/downloading_section_tile.dart';
import 'package:zenmusic/desktop/screens/library/downloads/downloading/widgets/downloading_song_tile.dart';

class DownloadingPage extends StatelessWidget {
  const DownloadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DownloadingCubit()..load(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('Downloading'.tr),
          centerTitle: true,
        ),
        body: BlocBuilder<DownloadingCubit, DownloadingState>(
          builder: (context, state) {
            return switch (state) {
              DownloadingLoading() =>
              const Center(child: CircularProgressIndicator()),
              DownloadingError(:final message) => Center(child: Text(message)),
              DownloadingLoaded(
                  :final downloading,
                  :final queued,
              ) =>
                  CustomScrollView(
                    slivers: [
                      if (downloading.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: DownloadingSectionTile(
                            title: 'In Progress'.tr,
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) => DownloadingSongTile(
                              song: downloading[index],
                            ),
                            childCount: downloading.length,
                          ),
                        ),
                      ],
                      if (queued.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: DownloadingSectionTile(
                            title: 'Queued (${queued.length})',
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                                (context, index) => DownloadingSongTile(
                              song: queued[index],
                            ),
                            childCount: queued.length,
                          ),
                        ),
                      ],
                    ],
                  ),
            };
          },
        ),
      ),
    );
  }
}
