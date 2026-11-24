// ZenMusic · vorlon-dev

import 'package:zenmusic/desktop/screens/library/friends_feed_page.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zenmusic/desktop/core/widgets/zen_logo.dart';

import 'package:zenmusic/desktop/screens/library/backdrop_page.dart';
import 'package:zenmusic/desktop/screens/library/crossfade_page.dart';
import 'package:zenmusic/desktop/screens/settings/lyric_sources_page.dart';
import 'package:zenmusic/desktop/screens/library/lastfm_page.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality.dart';
import 'package:zenmusic/desktop/lossless/lossless_quality_page.dart';
import 'package:zenmusic/desktop/screens/offline/offline_cache_page.dart';
import 'package:zenmusic/desktop/screens/player/player_skins.dart';
import 'package:zenmusic/desktop/screens/settings/cubit/settings_system_cubit.dart';
import 'package:zenmusic/desktop/screens/settings/seek_bar_page.dart';
import 'package:zenmusic/desktop/core/widgets/brand_logos.dart';
import 'package:zenmusic/desktop/services/appearance_prefs.dart';
import 'package:zenmusic/desktop/services/lyrics_overlay_bridge.dart';
import 'package:zenmusic/desktop/services/mini_player_bridge.dart';
import 'package:zenmusic/desktop/spotify/spotify_auth.dart';
import 'package:zenmusic/desktop/ytmusic/ytm_auth.dart';
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
          title: Text('Settings'.tr, style: appBarTitleStyle()),
          automaticallyImplyLeading: false,
        ),
        body: const _SettingsBody(),
      ),
    );
  }
}


class _Entry {
  const _Entry({
    this.icon,
    this.title = '',
    this.subtitle,
    this.keywords = const [],
    this.onTap,
    this.trailing,
    this.chevron,
    this.builder,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final List<String> keywords;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Override the automatic chevron (action rows pass `false`).
  final bool? chevron;

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
            chevron: chevron ?? trailing == null,
            onTap: onTap,
          );
}

class _Group {
  const _Group(this.title, this.entries, [this.color]);
  final String title;
  final List<_Entry> entries;
  final Color? color;
}


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
          title: 'Appearance'.tr,
          subtitle: 'Theme, colors and lyrics'.tr,
          keywords: const ['theme', 'dark', 'color', 'material', 'lyrics'],
          onTap: () => context.go('/settings/appearance'),
        ),
        _Entry(
          icon: Icons.group,
          title: 'Friends feed'.tr,
          subtitle: 'What your Last.fm friends are playing'.tr,
          keywords: const ['friends', 'lastfm', 'social', 'scrobble'],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FriendsFeedPage()),
          ),
        ),
        _Entry(
          icon: Icons.language,
          title: 'Language'.tr,
          subtitle: kAppLanguages[L10n.lang.value] ?? 'English',
          keywords: const ['language', 'translate', 'hindi', 'spanish', 'arabic'],
          onTap: () => showLanguageDialog(context),
        ),
        _Entry(
          icon: ZenIcons.player,
          title: 'Player'.tr,
          subtitle: 'Playback, equalizer and queue'.tr,
          keywords: const ['equalizer', 'eq', 'audio', 'playback'],
          onTap: () => context.go('/settings/player'),
        ),
        _Entry(
          icon: Icons.equalizer_rounded,
          title: 'Equalizer'.tr,
          subtitle: '15 bands, presets and bass boost'.tr,
          keywords: const ['equalizer', 'eq', 'bass', 'treble', 'preset'],
          onTap: () => context.go('/settings/player/equalizer'),
        ),
        _Entry(
          icon: Icons.compare_arrows,
          title: 'Crossfade'.tr,
          subtitle: 'Fade between tracks'.tr,
          keywords: const ['crossfade', 'fade', 'transition', 'gapless'],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CrossfadePage()),
          ),
        ),
        _Entry(
          icon: Icons.lyrics,
          title: 'Lyric sources',
          subtitle: 'Choose and order where lyrics come from',
          keywords: const ['lyrics', 'sources', 'word sync', 'syllable'],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LyricSourcesPage()),
          ),
        ),
        _Entry(
          icon: Icons.high_quality,
          title: 'Song quality'.tr,
          subtitle: 'Lossless tier for YTM and JioSaavn'.tr,
          keywords: const [
            'quality',
            'lossless',
            'flac',
            'hifi',
            'hi-res',
            '320kbps',
            'bitrate',
            'cd',
          ],
          builder: (ctx) => ValueListenableBuilder<int>(
            valueListenable: LosslessPrefs.index,
            builder: (ctx, i, _) {
              final tiers = LosslessQuality.values;
              final tier = tiers[(i < 0)
                  ? 0
                  : (i >= tiers.length ? tiers.length - 1 : i)];
              return ZenRow(
                icon: Icons.high_quality,
                title: 'Song quality'.tr,
                subtitle: tier.label,
                chevron: true,
                onTap: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                      builder: (_) => const LosslessQualityPage()),
                ),
              );
            },
          ),
        ),
      ], const Color(0xFF5B8DEF)),
      _Group('Personalization', [
        if (Platform.isAndroid)
          _Entry(
            icon: Icons.image_outlined,
            title: 'Logo'.tr,
            subtitle: 'Pick the launcher icon'.tr,
            keywords: const ['logo', 'icon', 'launcher', 'app icon', 'theme'],
            builder: (ctx) => ZenRow(
              icon: Icons.image_outlined,
              title: 'Logo'.tr,
              subtitle: 'Pick the launcher icon'.tr,
              chevron: true,
              onTap: () => ctx.push('/logo'),
            ),
          ),
        _Entry(
          title: 'Seek bar'.tr,
          keywords: const ['slider', 'progress', 'wave', 'style'],
          builder: (ctx) => ValueListenableBuilder<String>(
            valueListenable: AppearancePrefs.sliderStyle,
            builder: (ctx, name, _) {
              final s = ZenSliderStyle.fromName(name);
              return ZenRow(
                icon: ZenIcons.seekBar,
                title: 'Seek bar'.tr,
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
          title: 'Player screen'.tr,
          keywords: const ['skin', 'layout', 'ui', 'player'],
          builder: (ctx) => ValueListenableBuilder<String>(
            valueListenable: PlayerSkinPrefs.skin,
            builder: (ctx, name, _) => ZenRow(
              icon: ZenIcons.playerScreen,
              title: 'Player screen'.tr,
              subtitle: PlayerSkin.fromName(name).label,
              chevron: true,
              onTap: () => Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => const PlayerSkinPage()),
              ),
            ),
          ),
        ),
      ], const Color(0xFFB65CF0)),
      if (Platform.isWindows)
        _Group('Desktop', [
          _Entry(
            icon: Icons.picture_in_picture_alt,
            title: 'Mini player'.tr,
            subtitle: 'Float the controls'.tr,
            keywords: const ['mini', 'player', 'floating', 'window'],
            chevron: false,
            onTap: () => MiniPlayerBridge.instance.openMiniPlayer(),
          ),
          _Entry(
            icon: Icons.lyrics,
            title: 'Lyrics overlay'.tr,
            subtitle: 'Floating sing-along'.tr,
            keywords: const ['lyrics', 'overlay', 'floating', 'sing'],
            chevron: false,
            onTap: () => LyricsOverlayBridge.instance.openOverlay(),
          ),
          _Entry(
            icon: Icons.smart_display,
            title: 'Video backdrop'.tr,
            subtitle: 'Song video behind the player'.tr,
            keywords: const ['backdrop', 'video', 'blur', 'background'],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BackdropPage()),
            ),
          ),
        ], const Color(0xFF2BB3A3)),
      _Group('Services', [
        _Entry(
          title: 'YouTube Music'.tr,
          subtitle: 'Account, region and content'.tr,
          keywords: [
            'youtube',
            'ytmusic',
            'login',
            'account',
            'google',
            'feed',
            'taste',
            'personalized',
          ],
          builder: _ytmBuilder,
        ),
        _Entry(
          icon: ZenIcons.youtube,
          title: 'Content and region'.tr,
          subtitle: 'Country, language and content type'.tr,
          keywords: const ['region', 'country', 'language', 'content'],
          onTap: () => context.go('/settings/services/ytmusic'),
        ),
        const _Entry(
          title: 'Spotify',
          keywords: ['spotify', 'login', 'account', 'cookie'],
          builder: _spotifyBuilder,
        ),
        _Entry(
          title: 'Last.fm',
          keywords: const ['lastfm', 'last.fm', 'scrobble', 'music'],
          builder: (ctx) => ZenRow(
            icon: Icons.graphic_eq,
            leading: const ZenBrandTile(ZenBrands.lastfm),
            title: 'Last.fm',
            subtitle: 'Scrobble your plays'.tr,
            chevron: true,
            onTap: () => Navigator.of(ctx).push(
              MaterialPageRoute(builder: (_) => const LastfmPage()),
            ),
          ),
        ),
      ], const Color(0xFFE8604C)),
      _Group('Storage and privacy', [
        _Entry(
          icon: ZenIcons.backup,
          title: 'Backup and storage'.tr,
          subtitle: 'Back up, restore and manage space'.tr,
          keywords: const ['export', 'import', 'cache', 'downloads'],
          onTap: () => context.go('/settings/backup_storage'),
        ),
        _Entry(
          icon: ZenIcons.privacy,
          title: 'Privacy'.tr,
          subtitle: 'History and data controls'.tr,
          keywords: const ['history', 'data'],
          onTap: () => context.go('/settings/privacy'),
        ),
        _Entry(
          icon: Icons.offline_pin_outlined,
          title: 'Offline cache'.tr,
          subtitle: 'Auto-cached songs'.tr,
          keywords: const ['offline', 'cache', 'download', 'space'],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OfflineCachePage()),
          ),
        ),
      ], const Color(0xFFE5A100)),
      _Group('About', [
        _Entry(
          icon: ZenIcons.about,
          title: 'About'.tr,
          subtitle: 'Version, licenses and credits'.tr,
          keywords: const ['version', 'license', 'credits'],
          onTap: () => context.go('/settings/about'),
        ),
        _Entry(
          icon: ZenIcons.update,
          title: 'Check for updates'.tr,
          subtitle: 'Opens the releases page'.tr,
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
      ], const Color(0xFF6B7A90)),
      _Group('Community', [
        _Entry(
          title: 'Source code'.tr,
          keywords: const ['github', 'code', 'repo', 'star'],
          builder: (ctx) => ZenRow(
            icon: Icons.code,
            leading: const ZenBrandTile(ZenBrands.github),
            title: 'Source code'.tr,
            subtitle: 'github.com/vorlon-dev/Zen-music',
            trailing: Icon(ZenIcons.openExternal,
                size: 18,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            onTap: () => _openUrl(_repoUrl),
          ),
        ),
        _Entry(
          icon: Icons.star_outline_rounded,
          title: 'Star on GitHub'.tr,
          subtitle: 'Support the project'.tr,
          keywords: const ['star', 'support', 'rate'],
          trailing: Icon(ZenIcons.openExternal,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onTap: () => _openUrl(_repoUrl),
        ),
        _Entry(
          icon: Icons.bug_report_outlined,
          title: 'Report a problem'.tr,
          subtitle: 'Open an issue on GitHub'.tr,
          keywords: const ['bug', 'issue', 'feedback', 'help'],
          trailing: Icon(ZenIcons.openExternal,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onTap: () => _openUrl('$_repoUrl/issues/new'),
        ),
        _Entry(
          icon: Icons.ios_share_rounded,
          title: 'Share ZenMusic'.tr,
          subtitle: 'Send the download link to a friend'.tr,
          keywords: const ['share', 'invite', 'friend'],
          chevron: false,
          onTap: () => SharePlus.instance.share(ShareParams(
            text: 'ZenMusic – YouTube Music and Spotify in one player: '
                '$_repoUrl/releases',
          )),
        ),
      ], const Color(0xFF3FA66A)),
    ];
  }

  static const _repoUrl = 'https://github.com/vorlon-dev/Zen-music';

  static Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Widget _spotifyBuilder(BuildContext context) => const _SpotifyTile();

  static Widget _ytmBuilder(BuildContext context) => const _YtmTile();

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
          if (list.isNotEmpty) groups.add(_Group(g.title, list, g.color));
        }

        return LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 1000;

            Widget section(_Group g) => ZenSection(
              title: g.title,
              tint: g.color,
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
                        if (q.isEmpty) ...[
                          const _Hero(),
                          const SizedBox(height: 12),
                          _QuickActions(),
                          const SizedBox(height: 20),
                        ],
                        ZenSearchField(
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: 20),
                        if (showBattery && q.isEmpty)
                          ZenSection(children: [
                            ZenRow(
                              icon: ZenIcons.battery,
                              iconColor: Theme.of(context).colorScheme.error,
                              title: 'Battery optimisation is on'.tr,
                              subtitle:
                              'Turn it off so music keeps playing in the background.'.tr,
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
              icon: ZenIcons.connected,
              leading: Opacity(
                opacity: loggedIn ? 1.0 : 0.4,
                child: const SpotifyLogo(size: 22),
              ),
              title: 'Spotify',
              subtitle: loggedIn
                  ? 'Connected — tap to open your library'
                  : 'Not connected',
              onTap: loggedIn
                  ? () => context.push('/saved/spotify_library')
                  : null,
              trailing: loggedIn
                  ? OutlinedButton(
                onPressed: () => SpotifyAuth.instance.logout(),
                child: Text('Log out'.tr),
              )
                  : FilledButton.tonal(
                onPressed: _openEmbeddedLogin,
                child: Text('Log in'.tr),
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
                                tooltip: 'Paste'.tr,
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
                            child: Text('Cancel'.tr),
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
                                : Text('Log in with cookie'.tr),
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
                      child: Text('Use a cookie instead'.tr),
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


class _YtmTile extends StatefulWidget {
  const _YtmTile();

  @override
  State<_YtmTile> createState() => _YtmTileState();
}

class _YtmTileState extends State<_YtmTile> {
  final _ctrl = TextEditingController();
  bool _showPaste = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    YtmAuth.instance.load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _openEmbeddedLogin() async {
    await context.push('/ytm-login');
    YtmAuth.instance.load();
    if (mounted) setState(() {});
  }

  Future<void> _loginPaste() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await YtmAuth.instance.loginWithCookies(_ctrl.text);
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
      valueListenable: YtmAuth.instance.loggedIn,
      builder: (context, loggedIn, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZenRow(
              icon: ZenIcons.connected,
              leading: Opacity(
                opacity: loggedIn ? 1.0 : 0.4,
                child: const YouTubeMusicLogo(size: 22),
              ),
              title: 'YouTube Music'.tr,
              subtitle: loggedIn
                  ? 'Connected — your home feed follows your taste'
                  : 'Not connected',
              // Connected: tap opens the region/content page (the row the
              // old entry used to be). Login/logout stay in the trailing.
              onTap: loggedIn
                  ? () => context.go('/settings/services/ytmusic')
                  : null,
              trailing: loggedIn
                  ? OutlinedButton(
                onPressed: () => YtmAuth.instance.logout(),
                child: Text('Log out'.tr),
              )
                  : FilledButton.tonal(
                onPressed: _openEmbeddedLogin,
                child: Text('Log in'.tr),
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
                          'Paste cookies.txt content or a cookie '
                              'header from music.youtube.com',
                          prefixIcon: Icon(ZenIcons.key, size: 18),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Paste'.tr,
                                icon: Icon(ZenIcons.paste, size: 18),
                                onPressed: _pasteFromClipboard,
                              ),
                              IconButton(
                                tooltip: _hide ? 'Show' : 'Hide',
                                icon: Icon(_hide
                                    ? ZenIcons.eye
                                    : ZenIcons.eyeOff,
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
                                        fontSize: 13,
                                        color: cs.error)),
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
                            child: Text('Cancel'.tr),
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
                                : Text('Log in with cookies'.tr),
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
                      onPressed: () =>
                          setState(() => _showPaste = true),
                      child: Text('Use cookies instead'.tr),
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


class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(children: [
        const ZenLogoWidget(size: 64, borderRadius: 18),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ZenMusic',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer)),
              const SizedBox(height: 2),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snap) => Text(
                  snap.hasData
                      ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})'
                      : 'Settings',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.75)),
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Check for updates'.tr,
          icon: Icon(ZenIcons.update),
          onPressed: () =>
              _SettingsBodyState._openUrl('${_SettingsBodyState._repoUrl}/releases'),
        ),
      ]),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget a(IconData i, String l, VoidCallback f) =>
        Expanded(child: ZenQuickAction(icon: i, label: l, onTap: f));
    return Row(children: [
      a(ZenIcons.appearance, 'Appearance'.tr,
              () => context.go('/settings/appearance')),
      const SizedBox(width: 8),
      a(Icons.equalizer_rounded, 'Equalizer'.tr,
              () => context.go('/settings/player/equalizer')),
      const SizedBox(width: 8),
      a(ZenIcons.player, 'Player'.tr, () => context.go('/settings/player')),
      const SizedBox(width: 8),
      a(Icons.language, 'Language'.tr, () => showLanguageDialog(context)),
    ]);
  }
}