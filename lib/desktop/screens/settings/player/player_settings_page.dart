// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/settings/player/cubit/player_settings_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/setting_item.dart';

/// Signature for the group builders below — keeps the isFirst / isLast
/// corner radii correct no matter which tiles a given platform hides.
typedef _GroupTileBuilder = Widget Function({
  required bool first,
  required bool last,
});

class PlayerSettingsPage extends StatelessWidget {
  const PlayerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlayerSettingsCubit(),
      child: Scaffold(
        appBar: AppBar(
          title: Text("Player".tr),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: BlocBuilder<PlayerSettingsCubit, PlayerSettingsState>(
              builder: (context, state) {
                final s = state as PlayerSettingsLoaded;

                // Feature gates mirror the engines themselves:
                //  * the beat-haptics engine runs on Android / iOS only,
                //  * Sing mode vocal removal is Android-only (its
                //    MethodChannel lives in the Android lossless bridge).
                final beatShown = Platform.isAndroid || Platform.isIOS;
                final singShown = Platform.isAndroid;

                final group = <_GroupTileBuilder>[
                  /// Skip silence
                  if (!Platform.isWindows)
                    ({required bool first, required bool last}) =>
                        SettingSwitchTile(
                          title: 'Skip Silence'.tr,
                          leading: const Icon(
                            Icons.fast_forward,
                          ),
                          value: s.skipSilence,
                          onChanged: (value) {
                            context
                                .read<PlayerSettingsCubit>()
                                .setSkipSilence(value);
                          },
                          isFirst: first,
                          isLast: last,
                        ),

                  /// Haptic beats — engine: services/beat_haptics.dart.
                  /// Registered and started at boot, but until now it had
                  /// no switch anywhere in the app.
                  if (beatShown) ...[
                    ({required bool first, required bool last}) =>
                        SettingSwitchTile(
                          title: 'Haptic Beats'.tr,
                          subtitle: 'Vibrate with the rhythm of the song'.tr,
                          leading: const Icon(Icons.vibration),
                          value: s.beatHaptics,
                          onChanged: (value) {
                            context
                                .read<PlayerSettingsCubit>()
                                .setBeatHaptics(value);
                          },
                          isFirst: first,
                          isLast: last,
                        ),
                    if (s.beatHaptics)
                      ({required bool first, required bool last}) =>
                          _BeatStrengthTile(
                            strength: s.beatStrength,
                            first: first,
                            last: last,
                            onChanged: (v) => context
                                .read<PlayerSettingsCubit>()
                                .setBeatStrength(v),
                          ),
                  ],

                  /// Sing mode — engine: services/sing_mode.dart.
                  /// Restored at boot and applied through the Android
                  /// lossless bridge, but had no UI entry anywhere.
                  if (singShown) ...[
                    ({required bool first, required bool last}) =>
                        SettingSwitchTile(
                          title: 'Sing Mode'.tr,
                          subtitle: 'Dip the vocals so you can sing along'.tr,
                          leading: const Icon(Icons.mic),
                          value: s.singMode,
                          onChanged: (value) {
                            context
                                .read<PlayerSettingsCubit>()
                                .setSingMode(value);
                          },
                          isFirst: first,
                          isLast: last,
                        ),
                    if (s.singMode)
                      ({required bool first, required bool last}) =>
                          _SingVoiceTile(
                            level: s.singVoiceLevel,
                            first: first,
                            last: last,
                            onChanged: (v) => context
                                .read<PlayerSettingsCubit>()
                                .setSingVoiceLevel(v),
                          ),
                  ],
                ];

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    for (var i = 0; i < group.length; i++)
                      group[i](
                        first: i == 0,
                        last: i == group.length - 1,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Vibration strength for haptic beats — 0 light, 1 medium, 2 strong,
/// matching BeatStrength in services/beat_haptics.dart.
class _BeatStrengthTile extends StatelessWidget {
  const _BeatStrengthTile({
    required this.strength,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  final int strength;
  final bool first;
  final bool last;
  final ValueChanged<int> onChanged;

  static const _labels = <String>['Light', 'Medium', 'Strong'];

  @override
  Widget build(BuildContext context) {
    final sel = strength < 0 ? 0 : (strength > 2 ? 2 : strength);

    return SettingEmptyTile(
      isFirst: first,
      isLast: last,
      leading: const Icon(Icons.graphic_eq),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vibration Strength'.tr,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (var i = 0; i < _labels.length; i++)
                ButtonSegment<int>(value: i, label: Text(_labels[i].tr)),
            ],
            selected: <int>{sel},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> selection) {
              if (selection.isNotEmpty) onChanged(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

/// Voice level for Sing mode — how much of the singer's voice stays in
/// the mix (0 = full karaoke, 100 = untouched), matching voiceLevel in
/// services/sing_mode.dart.
class _SingVoiceTile extends StatelessWidget {
  const _SingVoiceTile({
    required this.level,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  final double level;
  final bool first;
  final bool last;
  final ValueChanged<double> onChanged;

  static double _clamp01(double v) => v < 0 ? 0.0 : (v > 1 ? 1.0 : v);

  @override
  Widget build(BuildContext context) {
    final v = _clamp01(level);
    final pct = '${(v * 100).round()}%';

    return SettingEmptyTile(
      isFirst: first,
      isLast: last,
      leading: const Icon(Icons.mic_none),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Voice Level'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              Text(
                pct,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          Slider(
            value: v,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: pct,
            onChanged: onChanged,
          ),
          Text(
            'How much of the vocals stays in the mix'.tr,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
