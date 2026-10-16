// ZenMusic Desktop — ported from Echo Music (GPL-3.0), settings/appearance/appearance_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// PORT: l10n -> literals; accent picker -> AccentModals (modals_extra).
// R+ : Player & Lyrics sections wired to AppearancePrefs.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'package:zenmusic/desktop/screens/settings/appearance/cubit/appearance_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/setting_item.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/modals_extra.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';


class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AppearanceCubit(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Appearance'),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: BlocBuilder<AppearanceCubit, AppearanceState>(
              builder: (context, state) {
                final s = state as AppearanceLoaded;

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    const GroupTitle(title: "Theme"),
                    SettingTile(
                      title: 'Theme Mode',
                      leading: const Icon(Icons.dark_mode),
                      isFirst: true,
                      trailing: AdaptiveDropdownButton<ThemeMode>(
                        value: s.themeMode,
                        items: ThemeMode.values
                            .map(
                              (e) => AdaptiveDropdownMenuItem(
                            value: e,
                            child: Text(
                              e.name.toUpperCase(),
                            ),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          context.read<AppearanceCubit>().setThemeMode(value);
                        },
                      ),
                    ),
                    SettingTile(
                      title: "AccentColor",
                      leading: const Icon(Icons.colorize_rounded),
                      trailing: CircleAvatar(
                        radius: 20,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Row(
                            children: [
                              Container(
                                color: s.accentColor ?? Colors.black,
                                width: 20,
                              ),
                              Container(
                                color: s.accentColor ?? Colors.white,
                                width: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      onTap: () => AccentModals.showAccentSelector(context),
                    ),
                    SettingSwitchTile(
                      title: 'Amoled Black',
                      leading: const Icon(Icons.mode_night_outlined),
                      value: s.amoledBlack,
                      onChanged: (value) {
                        context.read<AppearanceCubit>().setAmoledBlack(value);
                      },
                    ),
                    SettingSwitchTile(
                      title: 'Dynamic Colors',
                      leading: const Icon(Icons.color_lens_outlined),
                      isLast: true,
                      value: s.dynamicColors,
                      onChanged: (value) {
                        context.read<AppearanceCubit>().setDynamicColors(value);
                      },
                    ),

                    // ── PLAYER ──
                    const GroupTitle(title: "Player"),
                    ValueListenableBuilder<String>(
                      valueListenable: AppearancePrefs.sliderStyle,
                      builder: (context, style, _) {
                        // Normalize legacy values ('slim'/'wavy'/'bar') to a
                        // valid ZenSliderStyle name — the stored pref must
                        // always match one dropdown item or the widget
                        // asserts.
                        final current = ZenSliderStyle.fromName(style).name;
                        return SettingTile(
                          title:
                          'Seek Bar — ${ZenSliderStyle.fromName(current).label}',
                          leading: const Icon(Icons.waves_rounded),
                          isFirst: true,
                          trailing: AdaptiveDropdownButton<String>(
                            value: current,
                            items: [
                              for (final s in ZenSliderStyle.values)
                                AdaptiveDropdownMenuItem(
                                  value: s.name,
                                  child: Text(s.label.toUpperCase()),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                AppearancePrefs.setSliderStyle(v);
                              }
                            },
                          ),
                        );
                      },
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: AppearancePrefs.canvasEnabled,
                      builder: (context, canvas, _) => SettingSwitchTile(
                        title: 'Animated Player Background',
                        leading: const Icon(Icons.gradient_rounded),
                        value: canvas,
                        onChanged: (v) =>
                            AppearancePrefs.setCanvasEnabled(v),
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: AppearancePrefs.keepScreenOn,
                      builder: (context, keepOn, _) => SettingSwitchTile(
                        title: 'Keep Screen On (lyrics)',
                        leading: const Icon(Icons.screen_lock_portrait_rounded),
                        isLast: true,
                        value: keepOn,
                        onChanged: (v) => AppearancePrefs.setKeepScreenOn(v),
                      ),
                    ),

                    // ── LYRICS ──
                    const GroupTitle(title: "Lyrics"),
                    ValueListenableBuilder<double>(
                      valueListenable: AppearancePrefs.lyricsTextSize,
                      builder: (context, size, _) => SettingTile(
                        title: 'Text Size — ${size.round()}',
                        leading: const Icon(Icons.format_size_rounded),
                        isFirst: true,
                        trailing: SizedBox(
                          width: 160,
                          child: Slider(
                            value: size,
                            min: 16,
                            max: 36,
                            divisions: 20,
                            label: '${size.round()}',
                            onChanged: (v) =>
                                AppearancePrefs.setLyricsTextSize(v),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: AppearancePrefs.lyricsLineSpacing,
                      builder: (context, gap, _) => SettingTile(
                        title: 'Line Spacing — ${gap.toStringAsFixed(1)}×',
                        leading: const Icon(Icons.format_line_spacing_rounded),
                        trailing: SizedBox(
                          width: 160,
                          child: Slider(
                            value: gap,
                            min: 1.0,
                            max: 4.0,
                            divisions: 30,
                            label: gap.toStringAsFixed(1),
                            onChanged: (v) =>
                                AppearancePrefs.setLyricsLineSpacing(v),
                          ),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<String>(
                      valueListenable: AppearancePrefs.lyricsPosition,
                      builder: (context, pos, _) => SettingTile(
                        title: 'Alignment',
                        leading: const Icon(Icons.format_align_left_rounded),
                        isLast: true,
                        trailing: AdaptiveDropdownButton<String>(
                          value: pos,
                          items: const [
                            AdaptiveDropdownMenuItem(
                                value: 'left', child: Text('LEFT')),
                            AdaptiveDropdownMenuItem(
                                value: 'center', child: Text('CENTER')),
                            AdaptiveDropdownMenuItem(
                                value: 'right', child: Text('RIGHT')),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              AppearancePrefs.setLyricsPosition(v);
                            }
                          },
                        ),
                      ),
                    ),

                    // ── HAPTICS ──
                    const GroupTitle(title: "Feedback"),
                    ValueListenableBuilder<bool>(
                      valueListenable: AppearancePrefs.haptics,
                      builder: (context, haptics, _) => SettingSwitchTile(
                        title: 'Haptic Feedback',
                        leading: const Icon(Icons.vibration_rounded),
                        isFirst: true,
                        isLast: true,
                        value: haptics,
                        onChanged: (v) => AppearancePrefs.setHaptics(v),
                      ),
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