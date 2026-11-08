// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/services/lyrics_romanizer.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/lyric_motion.dart';
import 'package:zenmusic/desktop/services/lyric_styles.dart';
import 'package:zenmusic/desktop/services/lyric_translation.dart';
import 'package:zenmusic/desktop/services/lyrics_translator.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:zenmusic/desktop/backdrop/windows_backdrop_service.dart';
import 'package:zenmusic/desktop/screens/library/crossfade_page.dart';
import 'package:zenmusic/desktop/screens/player/player_skins.dart';
import 'package:zenmusic/desktop/screens/settings/appearance/cubit/appearance_cubit.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/lyrics_overlay_bridge.dart';
import 'package:zenmusic/desktop/services/mini_player_bridge.dart';
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
        appBar: AppBar(title: Text('Appearance'.tr)),
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
                    ZenSection(title: 'Theme'.tr, children: [
                      ZenRow(
                        icon: ZenIcons.themeMode,
                        title: 'Theme mode'.tr,
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
                        title: 'Accent color'.tr,
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
                        title: 'Pure black background'.tr,
                        subtitle: 'Saves power on OLED screens'.tr,
                        value: s.amoledBlack,
                        onChanged: (v) =>
                            context.read<AppearanceCubit>().setAmoledBlack(v),
                      ),
                      ZenSwitchRow(
                        icon: ZenIcons.dynamicColor,
                        title: 'Dynamic colors'.tr,
                        subtitle: 'Take colors from the current song'.tr,
                        value: s.dynamicColors,
                        onChanged: (v) => context
                            .read<AppearanceCubit>()
                            .setDynamicColors(v),
                      ),
                      ZenRow(
                        icon: ZenIcons.themeMode,
                        title: 'UI theme'.tr,
                        trailing: AdaptiveDropdownButton<String>(
                          value: s.uiTheme,
                          items: [
                            AdaptiveDropdownMenuItem(
                                value: 'classic', child: Text('Classic'.tr)),
                            AdaptiveDropdownMenuItem(
                                value: 'liquid',
                                child: Text('Liquid Glass'.tr)),
                            AdaptiveDropdownMenuItem(
                                value: 'm3', child: Text('Material 3'.tr)),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            context.read<AppearanceCubit>().setUiTheme(v);
                          },
                        ),
                      ),
                    ]),

                    ZenSection(title: 'Player'.tr, children: [
                      ValueListenableBuilder<String>(
                        valueListenable: PlayerSkinPrefs.skin,
                        builder: (context, name, _) {
                          // Normalise unknown / legacy values so the
                          // dropdown always has a matching item.
                          final current = PlayerSkin.fromName(name).name;
                          return ZenRow(
                            icon: ZenIcons.playerScreen,
                            title: 'Player screen'.tr,
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
                            title: 'Seek bar'.tr,
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
                      ZenRow(
                        icon: Icons.compare_arrows,
                        title: 'Crossfade'.tr,
                        subtitle: 'Smooth volume fade between tracks'.tr,
                        chevron: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CrossfadePage()),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.canvasEnabled,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.animatedBg,
                          title: 'Song backdrop'.tr,
                          subtitle:
                              'Video behind the player · 9:16 mobile · 16:9 desktop',
                          value: on,
                          onChanged: (v) {
                            AppearancePrefs.setCanvasEnabled(v);
                            if (Platform.isWindows) {
                              WindowsBackdropService.instance.setEnabled(v);
                            }
                          },
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.keepScreenOn,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.screenOn,
                          title: 'Keep screen on for lyrics'.tr,
                          value: on,
                          onChanged: AppearancePrefs.setKeepScreenOn,
                        ),
                      ),
                    ]),

                    if (Platform.isWindows)
                      ZenSection(title: 'Desktop'.tr, children: [
                        ZenRow(
                          icon: Icons.picture_in_picture_alt,
                          title: 'Mini player'.tr,
                          subtitle: 'Float the controls in a small window'.tr,
                          chevron: false,
                          onTap: () =>
                              MiniPlayerBridge.instance.openMiniPlayer(),
                        ),
                        ZenRow(
                          icon: Icons.lyrics,
                          title: 'Lyrics overlay'.tr,
                          subtitle: 'Pinned always-on-top sing-along window'.tr,
                          chevron: false,
                          onTap: () =>
                              LyricsOverlayBridge.instance.openOverlay(),
                        ),
                      ]),

                    ZenSection(title: 'Lyrics'.tr, children: [
                      ValueListenableBuilder<LyricStyle>(
                        valueListenable: LyricStylePrefs.style,
                        builder: (context, st, _) => ZenRow(
                          icon: Icons.style,
                          title: 'Lyric style'.tr,
                          trailing: AdaptiveDropdownButton<LyricStyle>(
                            value: st,
                            items: [
                              for (final s in LyricStyle.values)
                                AdaptiveDropdownMenuItem(
                                    value: s, child: Text(s.label)),
                            ],
                            onChanged: (v) {
                              if (v != null) LyricStylePrefs.set(v);
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: LyricsRomanizer.instance.mode,
                        builder: (context, m, _) => ZenRow(
                          icon: Icons.sort_by_alpha,
                          title: 'Romanize lyrics'.tr,
                          trailing: AdaptiveDropdownButton<int>(
                            value: m,
                            items: [
                              AdaptiveDropdownMenuItem(value: 0, child: Text('Off'.tr)),
                              AdaptiveDropdownMenuItem(
                                  value: 1, child: Text('Under the line'.tr)),
                              AdaptiveDropdownMenuItem(
                                  value: 2, child: Text('Replace the line'.tr)),
                            ],
                            onChanged: (v) {
                              if (v != null) LyricsRomanizer.instance.set(v);
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: LyricsTranslation.instance.enabled,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: Icons.translate,
                          title: 'Show lyrics translation'.tr,
                          subtitle: 'Translated line under each lyric',
                          value: on,
                          onChanged: LyricsTranslation.instance.setEnabled,
                        ),
                      ),
                      ValueListenableBuilder<LyricMotion>(
                        valueListenable: LyricMotionPrefs.motion,
                        builder: (context, m, _) => ZenRow(
                          icon: Icons.animation,
                          title: 'Lyric animation'.tr,
                          trailing: AdaptiveDropdownButton<LyricMotion>(
                            value: m,
                            items: [
                              for (final x in LyricMotion.values)
                                AdaptiveDropdownMenuItem(
                                    value: x, child: Text(x.label)),
                            ],
                            onChanged: (v) {
                              if (v != null) LyricMotionPrefs.set(v);
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: LyricsTranslation.instance.version,
                        builder: (context, _, __) => ZenRow(
                          icon: Icons.translate,
                          title: 'Translate lyrics to'.tr,
                          trailing: AdaptiveDropdownButton<String>(
                            value: LyricsTranslator.targetLang,
                            items: [
                              for (final e in kAppLanguages.entries)
                                AdaptiveDropdownMenuItem(
                                    value: e.key, child: Text(e.value)),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                LyricsTranslation.instance.setLang(v);
                              }
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: AppearancePrefs.lyricsTextSize,
                        builder: (context, size, _) => ZenSliderRow(
                          icon: ZenIcons.textSize,
                          title: 'Text size'.tr,
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
                          title: 'Line spacing'.tr,
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
                          title: 'Alignment'.tr,
                          trailing: AdaptiveDropdownButton<String>(
                            value: pos,
                            items: [
                              AdaptiveDropdownMenuItem(
                                  value: 'left', child: Text('Left'.tr)),
                              AdaptiveDropdownMenuItem(
                                  value: 'center', child: Text('Center'.tr)),
                              AdaptiveDropdownMenuItem(
                                  value: 'right', child: Text('Right'.tr)),
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

                    ZenSection(title: 'Feedback'.tr, children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: AppearancePrefs.haptics,
                        builder: (context, on, _) => ZenSwitchRow(
                          icon: ZenIcons.haptics,
                          title: 'Haptic feedback'.tr,
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
