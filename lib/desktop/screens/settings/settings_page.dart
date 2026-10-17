// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/settings/settings_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
//
// REDESIGN v2: quiet, platform-native settings list.
//  * Inset grouped lists, one neutral icon colour, platform icon sets
//    (see utils/zen_icons.dart), sentence-case section titles.
//  * Search filters every row (title, subtitle, keywords).
//  * Single column (max 640) on phones / tablets, two columns of sections
//    on wide desktop windows (>= 1000 px).
//  * Same routes, same cubit, same Spotify logic as before.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/screens/player/player_skins.dart';
import 'package:zenmusic/desktop/screens/settings/cubit/settings_system_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/seek_bar_page.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';
import 'package:zenmusic/desktop/utils/zen_slider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsSystemCubit()..load(),
      child: AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: Text('Settings', style: appBarTitleStyle()),
          automaticallyImplyLeading: false,
        ),
        body: const _SettingsBody(),
      ),
    );
  }
}

// ── Data ─────────────────────────────────────────────────────────────

class _Entry {
  const _Entry({
    this.icon,
    this.title = '',
    this.subtitle,
    this.keywords = const [],
    this.onTap,
    this.trailing,
    this.builder,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final List<String> keywords;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Fully custom row (seek bar preview, Spotify).
  final WidgetBuilder? builder;

  bool matches(String q) {
    if (q.isEmpty) return true;
    final hay = '$title ${subtitle ?? ''} ${keywords.join(' ')}'.toLowerCase();
    return hay.contains(q);
  }

  Widget build(BuildContext context) =>
      builder?.call(context) ??
          ZenRow(
            icon: icon!,
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            chevron: trailing == null,
            onTap: onTap,
          );
}

class _Group {
  const _Group(this.title, this.entries);
  final String title;
  final List<_Entry> entries;
}

// ── Body ─────────────────────────────────────────────────────────────

class _SettingsBody extends StatefulWidget {
  const _SettingsBody();

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  String _query = '';

  List<_Group> _groups(BuildContext context) {
    return [
      _Group('General', [
        _Entry(
          icon: ZenIcons.appearance,
          title: 'Appearance',
          subtitle: 'Theme, colors and lyrics',
          keywords: const ['theme', 'dark', 'color', 'material', 'lyrics'],
          onTap: () => context.go('/settings/appearance'),
        ),
        _Entry(
          icon: ZenIcons.player,
          title: 'Player',
          subtitle: 'Playback, equalizer and queue',
          keywords: const ['equalizer', 'eq', 'audio', 'playback'],
          onTap: () => context.go('/settings/player'),
        ),
      ]),
      _Group('Personalization', [
        _Entry(
          title: 'Seek bar',
          keywords: const ['slider', 'progress', 'wave', 'style'],
          builder: (ctx) => ValueListenableBuilder<String>(
            valueListenable: AppearancePrefs.sliderStyle,
            builder: (ctx, name, _) {
              final s = ZenSliderStyle.fromName(name);
              return ZenRow(
                icon: ZenIcons.seekBar,
                title: 'Seek bar',
                subtitle: s.label,
                chevron: true,
                trailing: SizedBox(
                  width: 88,
                  height: 28,
                  child: IgnorePointer(
                    child: ZenSlider(
                      style: s,
                      value: 0.45,
                      isPlaying: false,
                      height: 28,
                      onChanged: (_) {},
                    ),
                  ),
                ),
                onTap: () => Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => const SeekBarPage()),
                ),
              );
            },
          ),
        ),
        _Entry(
          title: 'Player screen',
          keywords: const ['skin', 'layout', 'ui', 'player'],
          builder: (ctx) => ValueListenableBuilder<String>(
            valueListenable: PlayerSkinPrefs.skin,
            builder: (ctx, name, _) => ZenRow(
              icon: ZenIcons.playerScreen,
              title: 'Player screen',
              subtitle: PlayerSkin.fromName(name).label,
              chevron: true,
              onTap: () => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => const PlayerSkinPage()),
              ),
            ),
          ),
        ),
      ]),
      _Group('Services', [
        _Entry(
          icon: ZenIcons.youtube,
          title: 'YouTube Music',
          subtitle: 'Account, region and content',
          keywords: const ['youtube', 'ytmusic', 'login'],
          onTap: () => context.go('/settings/services/ytmusic'),
        ),
        const _Entry(
          title: 'Spotify',
          keywords: ['spotify', 'login', 'account', 'cookie'],
          builder: _spotifyBuilder,
        ),
      ]),
      _Group('Storage and privacy', [
        _Entry(
          icon: ZenIcons.backup,
          title: 'Backup and storage',
          subtitle: 'Back up, restore and manage space',
          keywords: const ['export', 'import', 'cache', 'downloads'],
          onTap: () => context.go('/settings/backup_storage'),
        ),
        _Entry(
          icon: ZenIcons.privacy,
          title: 'Privacy',
          subtitle: 'History and data controls',
          keywords: const ['history', 'data'],
          onTap: () => context.go('/settings/privacy'),
        ),
      ]),
      _Group('About', [
        _Entry(
          icon: ZenIcons.about,
          title: 'About',
          subtitle: 'Version, licenses and credits',
          keywords: const ['version', 'license', 'credits'],
          onTap: () => context.go('/settings/about'),
        ),
        _Entry(
          icon: ZenIcons.update,
          title: 'Check for updates',
          subtitle: 'Opens the releases page',
          keywords: const ['github', 'release', 'download'],
          trailing: Icon(ZenIcons.openExternal,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onTap: () async {
            final uri =
            Uri.parse('https://github.com/vorlon-dev/Zen-music/releases');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ]),
    ];
  }

  static Widget _spotifyBuilder(BuildContext context) => const _SpotifyTile();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsSystemCubit, SettingsSystemState>(
      builder: (context, state) {
        final bool? batteryDisabled = state is SettingsSystemLoaded
            ? state.isBatteryOptimizationDisabled
            : null;
        final showBattery = Platform.isAndroid && batteryDisabled != true;

        final q = _query.trim().toLowerCase();
        final groups = <_Group>[];
        for (final g in _groups(context)) {
          final list = g.entries.where((e) => e.matches(q)).toList();
          if (list.isNotEmpty) groups.add(_Group(g.title, list));
        }

        return LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 1000;

            Widget section(_Group g) => ZenSection(
              title: g.title,
              children: [for (final e in g.entries) e.build(context)],
            );

            Widget content;
            if (groups.isEmpty) {
              content = _NoResults(query: _query);
            } else if (twoCol) {
              final left = <Widget>[];
              final right = <Widget>[];
              for (var i = 0; i < groups.length; i++) {
                (i.isEven ? left : right).add(section(groups[i]));
              }
              content = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: left)),
                  const SizedBox(width: 24),
                  Expanded(child: Column(children: right)),
                ],
              );
            } else {
              content = Column(children: [for (final g in groups) section(g)]);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: twoCol ? 1040 : 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ZenSearchField(
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 20),
                        if (showBattery && q.isEmpty)
                          ZenSection(children: [
                            ZenRow(
                              icon: ZenIcons.battery,
                              iconColor: Theme.of(context).colorScheme.error,
                              title: 'Battery optimisation is on',
                              subtitle:
                              'Turn it off so music keeps playing in the background.',
                              chevron: true,
                              onTap: () => context
                                  .read<SettingsSystemCubit>()
                                  .requestBatteryOptimizationIgnore(),
                            ),
                          ]),
                        content,
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Text(
          'No settings match "$query"',
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ── Spotify ──────────────────────────────────────────────────────────
// Same logic as before: "Log in" opens the embedded login page
// (/spotify-login); the cookie paste is the advanced fallback.

class _SpotifyTile extends StatefulWidget {
  const _SpotifyTile();

  @override
  State<_SpotifyTile> createState() => _SpotifyTileState();
}

class _SpotifyTileState extends State<_SpotifyTile> {
  final _ctrl = TextEditingController();
  bool _showPaste = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    SpotifyAuth.instance.load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _openEmbeddedLogin() async {
    await context.push('/spotify-login');
    await SpotifyAuth.instance.load();
    if (mounted) setState(() {});
  }

  Future<void> _loginPaste() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await SpotifyAuth.instance.login(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) _ctrl.clear();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _ctrl.text = data!.text!;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: SpotifyAuth.instance.loggedIn,
      builder: (context, loggedIn, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZenRow(
              icon: loggedIn ? ZenIcons.connected : ZenIcons.disconnected,
              title: 'Spotify',
              subtitle: loggedIn ? 'Connected' : 'Not connected',
              trailing: loggedIn
                  ? OutlinedButton(
                onPressed: () => SpotifyAuth.instance.logout(),
                child: const Text('Log out'),
              )
                  : FilledButton.tonal(
                onPressed: _openEmbeddedLogin,
                child: const Text('Log in'),
              ),
            ),
            if (!loggedIn)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _showPaste
                    ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _ctrl,
                        maxLines: _hide ? 1 : 3,
                        obscureText: _hide,
                        decoration: InputDecoration(
                          hintText:
                          'Paste sp_dc cookie or cookies.txt content',
                          prefixIcon: Icon(ZenIcons.key, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Paste',
                                icon: Icon(ZenIcons.paste, size: 18),
                                onPressed: _pasteFromClipboard,
                              ),
                              IconButton(
                                tooltip: _hide ? 'Show' : 'Hide',
                                icon: Icon(
                                    _hide ? ZenIcons.eye : ZenIcons.eyeOff,
                                    size: 18),
                                onPressed: () =>
                                    setState(() => _hide = !_hide),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(ZenIcons.error,
                                  size: 16, color: cs.error),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(_error!,
                                    style: TextStyle(
                                        fontSize: 13, color: cs.error)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _showPaste = false),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: _busy ? null : _loginPaste,
                            child: _busy
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                                : const Text('Log in with cookie'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                    : Padding(
                  padding: const EdgeInsets.only(left: 54, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _showPaste = true),
                      child: const Text('Use a cookie instead'),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}