// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/settings/player/ai_remix_page.dart';
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

                  /// Spatial audio (6D / 16D) — Android audio pipeline only.
                  if (singShown)
                    ({required bool first, required bool last}) =>
                        _SpatialTile(
                          mode: s.spatialMode,
                          first: first,
                          last: last,
                          onChanged: (v) => context
                              .read<PlayerSettingsCubit>()
                              .setSpatialMode(v),
                        ),

                  /// Sound vibes: Slowed + Reverb / Nightcore (Android).
                  if (singShown)
                    ({required bool first, required bool last}) => _VibeTile(
                          preset: s.vibe,
                          speed: s.vibeSpeed,
                          first: first,
                          last: last,
                          onPreset: (v) =>
                              context.read<PlayerSettingsCubit>().setVibe(v),
                          onSpeed: (v) => context
                              .read<PlayerSettingsCubit>()
                              .setVibeSpeed(v),
                        ),

                  /// AI remix models — offline ONNX model manager +
                  /// on-device track scanner (SP-78).
                  ({required bool first, required bool last}) =>
                      SettingTile(
                        title: 'AI Remix Models'.tr,
                        subtitle:
                            'Download an offline model and scan tracks'
                                .tr,
                        leading: const Icon(Icons.psychology),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AiRemixPage(),
                            ),
                          );
                        },
                        isFirst: first,
                        isLast: last,
                      ),
                ];

                // On phones the mini player and bottom bar float over the page;
                // without this the last tile (AI Remix Models) could not be
                // scrolled into view or tapped.
                final floatingBottom =
                    (Platform.isAndroid || Platform.isIOS)
                        ? MediaQuery.paddingOf(context).bottom + 200
                        : 8.0;
                return ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, floatingBottom),
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


/// Spatial audio picker: Off · 6D · 8D · 16D · 18D · Surround, with a short
/// explanation and a headphones tip.
class _SpatialTile extends StatelessWidget {
  const _SpatialTile({
    required this.mode,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  final int mode;
  final bool first;
  final bool last;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final desc = switch (mode) {
      6 => '6D: the sound slowly circles around your head with a light sense of room.',
      8 => '8D: the classic wide pan that sweeps from ear to ear.',
      16 => '16D: a faster orbit with front-and-back depth and a bigger room.',
      18 => '18D: the most intense orbit, with deep front-and-back movement and a large room.',
      100 => 'Surround: the music sounds far away on a big stage, like a real concert hall.',
      _ => 'Make music feel like it moves around you or plays in a real space.',
    };
    final labels = <int, String>{
      0: 'Off'.tr,
      6: '6D',
      8: '8D',
      16: '16D',
      18: '18D',
      100: 'Surround'.tr,
    };
    final scheme = Theme.of(context).colorScheme;
    return SettingEmptyTile(
      isFirst: first,
      isLast: last,
      leading: const Icon(Icons.surround_sound_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spatial Audio'.tr,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          // Fixed 3 x 2 grid: the selected chip never grows or wraps, so the
          // tile keeps one height whichever mode is picked.
          for (final row in const [
            [0, 6, 8],
            [16, 18, 100],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        showCheckmark: false,
                        label: SizedBox(
                          width: double.infinity,
                          child: Text(
                            labels[row[i]]!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        selected: mode == row[i],
                        onSelected: (_) => onChanged(row[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(desc.tr, style: Theme.of(context).textTheme.labelLarge),
          if (mode != 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.headphones_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use headphones or earphones to feel the full effect.'.tr,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Slowed + Reverb / Nightcore: two Material 3 tonal cards and a speed slider.
class _VibeTile extends StatelessWidget {
  const _VibeTile({
    required this.preset,
    required this.speed,
    required this.first,
    required this.last,
    required this.onPreset,
    required this.onSpeed,
  });

  final int preset;
  final double speed;
  final bool first;
  final bool last;
  final ValueChanged<int> onPreset;
  final ValueChanged<double> onSpeed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final range = switch (preset) {
      1 => (0.65, 0.95),
      2 => (1.05, 1.5),
      _ => (1.0, 1.0),
    };

    Widget card(int value, IconData icon, String title, String sub) {
      final on = preset == value;
      return Expanded(
        child: Material(
          color: on ? scheme.secondaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => onPreset(on ? 0 : value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: on ? scheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: on ? scheme.primary : scheme.surfaceContainerLow,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon,
                        size: 22,
                        color: on ? scheme.onPrimary : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  Text(title.tr,
                      maxLines: 2,
                      style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: on
                              ? scheme.onSecondaryContainer
                              : scheme.onSurface)),
                  const SizedBox(height: 2),
                  Text(sub.tr,
                      maxLines: 2,
                      style: text.labelMedium?.copyWith(
                          color: on
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SettingEmptyTile(
      isFirst: first,
      isLast: last,
      leading: const Icon(Icons.auto_awesome_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sound Vibes'.tr,
              style: text.bodyLarge
                  ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text('One-tap styles that change speed, pitch and feel.'.tr,
              style: text.labelLarge),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                card(1, Icons.slow_motion_video_rounded, 'Slowed + Reverb',
                    'Slower, deeper, in a big room'),
                const SizedBox(width: 10),
                card(2, Icons.bolt_rounded, 'Nightcore',
                    'Faster and higher, full energy'),
              ],
            ),
          ),
          if (preset != 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Speed'.tr, style: text.labelLarge),
                const Spacer(),
                Text('${speed.toStringAsFixed(2)}×', style: text.labelLarge),
              ],
            ),
            Slider(
              value: speed.clamp(range.$1, range.$2),
              min: range.$1,
              max: range.$2,
              divisions: ((range.$2 - range.$1) / 0.05).round(),
              label: '${speed.toStringAsFixed(2)}×',
              onChanged: onSpeed,
            ),
          ],
        ],
      ),
    );
  }
}
