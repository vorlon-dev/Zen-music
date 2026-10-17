// ZenMusic Desktop — ported from Echo Music (GPL-3.0), settings/appearance/appearance_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// REDESIGN v2: same design language as the settings home (zen_settings_kit).
// Same cubit, same AppearancePrefs / PlayerSkinPrefs wiring as before.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/screens/player/player_skins.dart';
import 'package:zenmusic/desktop/screens/settings/appearance/cubit/appearance_cubit.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/modals_extra.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppearanceCubit(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Appearance')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: BlocBuilder<AppearanceCubit, AppearanceState>(
              builder: (context, state) {
                final s = state as AppearanceLoaded;
                final cs = Theme.of(context).colorScheme;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                  children: [
                    // ── Theme ──
                    ZenSection(title: 'Theme', children: [
                      ZenRow(
                        icon: ZenIcons.themeMode,
                        title: 'Theme mode',
                        trailing: AdaptiveDropdownButton<ThemeMode>(
                          value: s.themeMode,
                          items: [
                            for (final m in ThemeMode.values)
                              AdaptiveDropdownMenuItem(
                                value: m,
                                child: Text(_cap(m.name)),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            context.read<AppearanceCubit>().setThemeMode(v);
                          },
                        ),
                      ),
                      ZenRow(
                        icon: ZenIcons.accent,
                        title: 'Accent color',
                        chevron: true,
                        trailing: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: s.accentColor ?? cs.primary,
                            border: Border.all(color: cs.outlineVariant),
                          ),
                        ),
                        onTap: () => AccentModals.showAccentSelector(context),
                      ),
                      ZenSwitchRow(
                        icon: ZenIcons.amoled,
                        title: 'Pure black background',
                        subtitle: 'Saves power on OLED screens',
                        value: s.amoledBlack,
                        onChanged: (v) =>
                            context.read<AppearanceCubit>().setAmoledBlack(v),
                      ),
                      ZenSwitchRow(
                        icon: ZenIcons.dynamicColor,
                        title: 'Dynamic colors',
                        subtitle: 'Take colors from the current song',
                        value: s.dynamicColors,
                        onChanged: (v) => context
                            .read<AppearanceCubit>()
                            .setDynamicColors(v),
                      ),
                    ]),

                    // ── Player ──
                    ZenSection(title: 'Player', children: [
                      ValueListenableBuilder<String>(
                        valueListenable: PlayerSkinPrefs.skin,
                        builder: (context, name, _) {
                          // Normalise unknown / legacy values so the
                          // dropdown always has a matching item.
                          final current = PlayerSkin.fromName(name).name;
                          return ZenRow(
                            icon: ZenIcons.playerScreen,
                            title: 'Player screen',
                            trailing: AdaptiveDropdownButton<String>(
                              value: current,
                              items: [
                                for (final p in PlayerSkin.values)
                                  AdaptiveDropdownMenuItem(
                                    value: p.name,
                                    child: Text(p.label),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) PlayerSkinPrefs.set(v);
                              },
                            ),
                          );
                        },
                      ),
                      ValueListenableBuilder<String>(
                        valueListenable: AppearancePrefs.sliderStyle,
                        builder: (context, style, _) {
                          // Legacy values ('slim'/'wavy'/'bar') -> valid name.
                          final current = ZenSliderStyle.fromName(style).name;
                          return ZenRow(
                            icon: ZenIcons.seekBar,
                            title: 'Seek bar',
                            trailing: AdaptiveDropdownButton<String>(
                              value: current,
                              items: [
                                for (final st in ZenSliderStyle.values)
                                  AdaptiveDropdownMenuItem(
                                    value: st.name,
                                    child: Text(st.label),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) AppearancePrefs.setSliderStyle(v);
                              },
                            ),
                          );
                        },
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.canvasEnabled,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.animatedBg,
                          title: 'Animated background',
                          subtitle: 'Moving backdrop on the player screen',
                          value: on,
                          onChanged: AppearancePrefs.setCanvasEnabled,
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.keepScreenOn,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.screenOn,
                          title: 'Keep screen on for lyrics',
                          value: on,
                          onChanged: AppearancePrefs.setKeepScreenOn,
                        ),
                      ),
                    ]),

                    // ── Lyrics ──
                    ZenSection(title: 'Lyrics', children: [
                      ValueListenableBuilder<double>(
                        valueListenable: AppearancePrefs.lyricsTextSize,
                        builder: (context, size, _) => ZenSliderRow(
                          icon: ZenIcons.textSize,
                          title: 'Text size',
                          valueLabel: '${size.round()}',
                          value: size,
                          min: 16,
                          max: 36,
                          divisions: 20,
                          onChanged: AppearancePrefs.setLyricsTextSize,
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: AppearancePrefs.lyricsLineSpacing,
                        builder: (context, gap, _) => ZenSliderRow(
                          icon: ZenIcons.lineSpacing,
                          title: 'Line spacing',
                          valueLabel: '${gap.toStringAsFixed(1)}×',
                          value: gap,
                          min: 1.0,
                          max: 4.0,
                          divisions: 30,
                          onChanged: AppearancePrefs.setLyricsLineSpacing,
                        ),
                      ),
                      ValueListenableBuilder<String>(
                        valueListenable: AppearancePrefs.lyricsPosition,
                        builder: (context, pos, _) => ZenRow(
                          icon: ZenIcons.alignment,
                          title: 'Alignment',
                          trailing: AdaptiveDropdownButton<String>(
                            value: pos,
                            items: const [
                              AdaptiveDropdownMenuItem(
                                  value: 'left', child: Text('Left')),
                              AdaptiveDropdownMenuItem(
                                  value: 'center', child: Text('Center')),
                              AdaptiveDropdownMenuItem(
                                  value: 'right', child: Text('Right')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                AppearancePrefs.setLyricsPosition(v);
                              }
                            },
                          ),
                        ),
                      ),
                    ]),

                    // ── Feedback ──
                    ZenSection(title: 'Feedback', children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.haptics,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.haptics,
                          title: 'Haptic feedback',
                          value: on,
                          onChanged: AppearancePrefs.setHaptics,
                        ),
                      ),
                    ]),
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