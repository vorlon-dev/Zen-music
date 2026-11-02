// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/settings/privacy/cubit/privacy_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/setting_item.dart';
import 'package:zenmusic/desktop/services/bottom_message.dart';
import 'package:zenmusic/desktop/utils/bottom_modals.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PrivacyCubit(),
      child: BlocListener<PrivacyCubit, PrivacyState>(
        listenWhen: (_, state) => state.lastAction != null,
        listener: (context, state) {
          final action = state.lastAction;
          if (action == null) return;

          if (action == PrivacyAction.playbackDeleted) {
            BottomMessage.showText(
              context,
              'Playback history deleted',
            );
          } else if (action == PrivacyAction.searchDeleted) {
            BottomMessage.showText(
              context,
              'Search history deleted',
            );
          }

          context.read<PrivacyCubit>().consumeAction();
        },
        child: const _PrivacyView(),
      ),
    );
  }
}

class _PrivacyView extends StatelessWidget {
  const _PrivacyView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Privacy"),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: BlocBuilder<PrivacyCubit, PrivacyState>(
            builder: (context, state) {
              final cubit = context.read<PrivacyCubit>();

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const GroupTitle(title: "Playback"),

                  /// PLAYBACK HISTORY ENABLE
                  SettingSwitchTile(
                    title: 'Enable Playback History',
                    leading: const Icon(Icons.manage_history_rounded),
                    isFirst: true,
                    value: state.playbackHistory,
                    onChanged: cubit.togglePlaybackHistory,
                  ),

                  /// DELETE PLAYBACK HISTORY
                  SettingTile(
                    title: 'Delete Playback History',
                    leading: const Icon(Icons.playlist_remove_rounded),
                    isLast: true,
                    onTap: () async {
                      final confirm = await Modals.showConfirmBottomModal(
                        context,
                        message:
                        'Delete your playback history? This cannot be undone.',
                        isDanger: true,
                      );

                      if (confirm == true) {
                        cubit.clearPlaybackHistory();
                      }
                    },
                  ),

                  const GroupTitle(title: "Search"),

                  /// SEARCH HISTORY ENABLE
                  SettingSwitchTile(
                    title: 'Enable Search History',
                    leading: const Icon(Icons.saved_search_rounded),
                    isFirst: true,
                    value: state.searchHistory,
                    onChanged: cubit.toggleSearchHistory,
                  ),

                  /// DELETE SEARCH HISTORY
                  SettingTile(
                    title: 'Delete Search History',
                    leading: const Icon(Icons.highlight_remove_sharp),
                    isLast: true,
                    onTap: () async {
                      final confirm = await Modals.showConfirmBottomModal(
                        context,
                        message:
                        'Delete your search history? This cannot be undone.',
                        isDanger: true,
                      );

                      if (confirm == true) {
                        cubit.clearSearchHistory();
                      }
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
