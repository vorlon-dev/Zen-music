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
import 'package:get_it/get_it.dart';
import 'package:zenmusic/desktop/services/settings_manager.dart';

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
            constraints: const BoxConstraints(maxWidth: 720),
            child: BlocBuilder<AppearanceCubit, AppearanceState>(
              builder: (context, state) {
                final s = state as AppearanceLoaded;
                final cs = Theme.of(context).colorScheme;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                  children: [
                    _ThemePreview(accent: s.accentColor),
                    const SizedBox(height: 16),
                    ZenSection(
                        title: 'Theme'.tr,
                        tint: const Color(0xFFB65CF0),
                        children: [
                          ZenCard(
                            padding: const EdgeInsets.all(12),
                            child: ZenSegmented<ThemeMode>(
                              value: s.themeMode,
                              options: [
                                (ThemeMode.system, 'System'.tr, Icons.brightness_auto_rounded),
                                (ThemeMode.light, 'Light'.tr, Icons.light_mode_rounded),
                                (ThemeMode.dark, 'Dark'.tr, Icons.dark_mode_rounded),
                              ],
                              onChanged: (v) =>
                                  context.read<AppearanceCubit>().setThemeMode(v),
                            ),
                          ),
                          ZenCard(
                            padding: const EdgeInsets.all(12),
                            child: ZenSegmented<String>(
                              value: s.uiTheme,
                              options: [
                                ('classic', 'Classic'.tr, null),
                                ('liquid', 'Liquid Glass'.tr, null),
                                ('m3', 'Material 3'.tr, null),
                              ],
                              onChanged: (v) =>
                                  context.read<AppearanceCubit>().setUiTheme(v),
                            ),
                          ),
                          ZenCard(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text('Accent color'.tr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(fontWeight: FontWeight.w500)),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        AccentModals.showAccentSelector(context),
                                    child: Text('More'.tr),
                                  ),
                                ]),
                                const SizedBox(height: 8),
                                Wrap(spacing: 10, runSpacing: 10, children: [
                                  _Swatch(
                                    color: null,
                                    selected: s.accentColor == null,
                                    label: 'Auto',
                                  ),
                                  for (final c in _kAccents)
                                    _Swatch(
                                      color: c,
                                      selected:
                                      s.accentColor?.toARGB32() == c.toARGB32(),
                                    ),
                                ]),
                              ],
                            ),
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
                        ]),

                    ZenSection(
                        tint: const Color(0xFF5B8DEF),
                        title: 'Player'.tr,
                        children: [
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
                                    for (final p in PlayerSkin.choosable)
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
                      ZenSection(
                          tint: const Color(0xFF2BB3A3),
                          title: 'Desktop'.tr,
                          children: [
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

                    ZenSection(
                        tint: const Color(0xFFE8604C),
                        title: 'Lyrics'.tr,
                        children: [
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

                    ZenSection(
                        tint: const Color(0xFFE5A100),
                        title: 'Feedback'.tr,
                        children: [
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

const _kAccents = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFF7C4DFF),
  Color(0xFFE91E63),
  Color(0xFFE8604C),
  Color(0xFFFF9800),
  Color(0xFFFFC107),
  Color(0xFF3FA66A),
  Color(0xFF00BFA5),
  Color(0xFF00B8D4),
];

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, this.label});
  final Color? color;
  final bool selected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => GetIt.I<SettingsManager>().accentColor = color,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? cs.surfaceContainerHighest,
          border: Border.all(
            color: selected ? cs.onSurface : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? Icon(Icons.check_rounded,
            size: 20,
            color: color == null
                ? cs.onSurface
                : (ThemeData.estimateBrightnessForColor(color!) ==
                Brightness.dark
                ? Colors.white
                : Colors.black))
            : (color == null
            ? Icon(Icons.auto_awesome_rounded,
            size: 18, color: cs.onSurfaceVariant)
            : null),
      ),
    );
  }
}

/// Live preview: a mock mini player drawn with the current theme.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.accent});
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer,
            Color.lerp(cs.primaryContainer, cs.surface, 0.55)!,
          ],
        ),
      ),
      child: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Preview'.tr,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 14),
        Container(
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: cs.outline.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: 0.62,
                  strokeWidth: 3,
                  strokeCap: StrokeCap.round,
                  backgroundColor: cs.outline.withValues(alpha: 0.2),
                ),
                CircleAvatar(
                    radius: 20, backgroundColor: cs.tertiaryContainer),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your song',
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  Text('Artist',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.skip_previous_rounded, color: cs.onSurface),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.primary,
              child: Icon(Icons.pause_rounded, color: cs.onPrimary),
            ),
            const SizedBox(width: 6),
            Icon(Icons.skip_next_rounded, color: cs.onSurface),
          ]),
        ),
      ]),
    );
  }
}