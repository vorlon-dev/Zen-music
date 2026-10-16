// ZenMusic Desktop — ported from Echo Music (GPL-3.0), screens/settings/settings_page.dart.
// Echo Music is Copyright (C) the Echo Music authors; this port and ZenMusic
// remain GPL-3.0 (https://github.com/vorlon-dev/Zen-music).
// PORT: l10n -> literals. R8e sections (appearance, EQ). R+ additions:
// spotify login card (embedded login via /spotify-login, sp_dc paste as
// advanced fallback) driven by SpotifyAuth.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/screens/settings/appearance/appearance_page.dart';
import 'package:zenmusic/desktop/screens/settings/cubit/settings_system_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/player/equalizer_page.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/color_icon.dart';
import 'package:zenmusic/desktop/screens/settings/widgets/setting_item.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/themes/text_styles.dart';
import 'package:zenmusic/desktop/utils/adaptive_widgets/adaptive_widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SettingsSystemCubit()..load(),
      child: AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: Text(
            'Settings',
            style: appBarTitleStyle(),
          ),
          automaticallyImplyLeading: false,
        ),
        body: BlocBuilder<SettingsSystemCubit, SettingsSystemState>(
          builder: (context, state) {
            final bool? batteryDisabled = state is SettingsSystemLoaded
                ? state.isBatteryOptimizationDisabled
                : null;

            return Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    if (Platform.isAndroid && batteryDisabled != true)
                      _BatteryWarningTile(),
                    const GroupTitle(title: "General"),
                    SettingTile(
                      title: "Appearance",
                      leading: const Icon(Icons.palette_rounded),
                      isFirst: true,
                      onTap: () => context.go('/settings/appearance'),
                    ),
                    SettingTile(
                      title: "Player",
                      leading: const Icon(Icons.play_arrow_rounded),
                      isLast: true,
                      onTap: () => context.go('/settings/player'),
                    ),
                    const GroupTitle(title: "Services"),
                    SettingTile(
                      title: "Youtube Music",
                      leading: const Icon(Icons.play_circle_fill),
                      isFirst: true,
                      onTap: () => context.go('/settings/services/ytmusic'),
                    ),
                    const _SpotifyLoginCard(),
                    const GroupTitle(title: "Storage & Privacy"),
                    SettingTile(
                      title: "Backup and storage",
                      leading: const Icon(
                        Icons.cloud_upload_rounded,
                      ),
                      isFirst: true,
                      onTap: () => context.go(
                        '/settings/backup_storage',
                      ),
                    ),
                    SettingTile(
                      title: "Privacy",
                      leading: const Icon(Icons.privacy_tip),
                      isLast: true,
                      onTap: () => context.go('/settings/privacy'),
                    ),
                    const GroupTitle(title: "Updates & About"),
                    SettingTile(
                      title: 'About',
                      leading: const Icon(Icons.info_rounded),
                      isFirst: true,
                      onTap: () => context.go('/settings/about'),
                    ),
                    SettingTile(
                      title: 'Check For Update',
                      leading: const Icon(Icons.update_rounded),
                      onTap: () async {
                        final uri = Uri.parse(
                            'https://github.com/vorlon-dev/Zen-music/releases');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BatteryWarningTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: Theme.of(context).colorScheme.errorContainer.withAlpha(200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(25),
      ),
      leading: const ColorIcon(
        icon: Icons.battery_alert,
        color: Colors.red,
      ),
      title: Text(
        'Battery Optimisation',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      subtitle: Text(
        'Disable battery optimisation so playback continues in the background.',
        style: tinyTextStyle(context).copyWith(
          color: Theme.of(context)
              .colorScheme
              .onErrorContainer
              .withValues(alpha: 0.7),
        ),
      ),
      onTap: () {
        context.read<SettingsSystemCubit>().requestBatteryOptimizationIgnore();
      },
    );
  }
}

/// spotify login card (SP-1b): "Login" opens the embedded browser page
/// (/spotify-login) — the user logs in normally and the session is
/// captured automatically. Advanced fallback: paste sp_dc / cookies.txt.
class _SpotifyLoginCard extends StatefulWidget {
  const _SpotifyLoginCard();

  @override
  State<_SpotifyLoginCard> createState() => _SpotifyLoginCardState();
}

class _SpotifyLoginCardState extends State<_SpotifyLoginCard> {
  final _ctrl = TextEditingController();
  bool _showPaste = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Hydrate the auth state (token refresh happens in background on boot
    // via SpotifyAuth.load() in main; this reflects the stored session).
    SpotifyAuth.instance.load();
  }

  Future<void> _openEmbeddedLogin() async {
    await context.push('/spotify-login');
    // Returning from the login page = capture attempted; refresh state.
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SpotifyAuth.instance.loggedIn,
      builder: (context, loggedIn, _) {
        return Column(
          children: [
            SettingTile(
              title: loggedIn ? 'spotify — Logged in' : 'spotify',
              subtitle: loggedIn
                  ? 'Free account connected — playback enabled'
                  : 'Connect your spotify account (free works)',
              leading: Icon(
                loggedIn
                    ? Icons.verified_rounded
                    : Icons.music_off_rounded,
                color: loggedIn ? Colors.green : Colors.grey,
              ),
              isFirst: true,
              trailing: loggedIn
                  ? TextButton(
                onPressed: () {
                  SpotifyAuth.instance.logout();
                },
                child: const Text('Log out'),
              )
                  : FilledButton.icon(
                onPressed: _openEmbeddedLogin,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Login'),
              ),
            ),
            if (!loggedIn && _showPaste) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _ctrl,
                  maxLines: 3,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText:
                    'Advanced: paste sp_dc cookie or cookies.txt content',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
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
                              strokeWidth: 2))
                          : const Text('Login with cookie'),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
                ),
            ],
            if (!loggedIn && !_showPaste)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton(
                  onPressed: () => setState(() => _showPaste = true),
                  child: const Text('Advanced: paste cookie instead'),
                ),
              ),
          ],
        );
      },
    );
  }
}