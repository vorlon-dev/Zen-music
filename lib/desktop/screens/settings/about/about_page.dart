// ZenMusic Desktop — About page.
// Same design language as the settings screens (zen_settings_kit):
// inset grouped lists, neutral platform icons, sentence-case titles.

import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';

const _repo = 'https://github.com/vorlon-dev/Zen-music';

/// Icons that only this page needs, resolved per platform.
class _I {
  _I._();
  static final bool _a = Platform.isIOS || Platform.isMacOS;
  static IconData get code =>
      _a ? CupertinoIcons.chevron_left_slash_chevron_right : Icons.code;
  static IconData get bug =>
      _a ? CupertinoIcons.ant : Icons.bug_report_outlined;
  static IconData get license =>
      _a ? CupertinoIcons.doc_text : Icons.description_outlined;
  static IconData get copy =>
      _a ? CupertinoIcons.doc_on_doc : Icons.copy_outlined;
  static IconData get package =>
      _a ? CupertinoIcons.cube_box : Icons.inventory_2_outlined;
  static IconData get tag =>
      _a ? CupertinoIcons.tag : Icons.sell_outlined;
  static IconData get device =>
      _a ? CupertinoIcons.device_laptop : Icons.devices_outlined;
  static IconData get people =>
      _a ? CupertinoIcons.person_2 : Icons.group_outlined;
  static IconData get library =>
      _a ? CupertinoIcons.book : Icons.menu_book_outlined;
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  String get _version => _info?.version ?? '…';
  String get _build => _info?.buildNumber ?? '…';
  String get _platform =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$label copied'),
        duration: const Duration(seconds: 2),
      ));
  }

  String get _report => 'ZenMusic $_version ($_build)\n$_platform';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/icon/logo.png',
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 88,
                        height: 88,
                        color: cs.surfaceContainerHigh,
                        child: Icon(Icons.music_note,
                            size: 44, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('ZenMusic',
                      style: tt.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Version $_version ($_build)',
                      style: tt.bodyMedium
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  Text(
                    'A music player for YouTube Music and Spotify, '
                        'on desktop and mobile.',
                    textAlign: TextAlign.center,
                    style:
                    tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ]),
              ),

              // ── Links ──
              ZenSection(title: 'Project', children: [
                ZenRow(
                  icon: _I.code,
                  title: 'Source code',
                  subtitle: 'github.com/vorlon-dev/Zen-music',
                  trailing: Icon(ZenIcons.openExternal,
                      size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _open(_repo),
                ),
                ZenRow(
                  icon: ZenIcons.update,
                  title: 'Releases',
                  subtitle: 'Download the latest version',
                  trailing: Icon(ZenIcons.openExternal,
                      size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _open('$_repo/releases'),
                ),
                ZenRow(
                  icon: _I.bug,
                  title: 'Report a problem',
                  subtitle: 'Open an issue on GitHub',
                  trailing: Icon(ZenIcons.openExternal,
                      size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _open('$_repo/issues'),
                ),
              ]),

              // ── App info ──
              ZenSection(title: 'App info', children: [
                ZenRow(
                  icon: _I.tag,
                  title: 'Version',
                  subtitle: '$_version ($_build)',
                  trailing: Icon(_I.copy, size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _copy('Version', '$_version+$_build'),
                ),
                if (_info != null)
                  ZenRow(
                    icon: _I.package,
                    title: 'Package',
                    subtitle: _info!.packageName,
                    trailing:
                    Icon(_I.copy, size: 18, color: cs.onSurfaceVariant),
                    onTap: () => _copy('Package name', _info!.packageName),
                  ),
                ZenRow(
                  icon: _I.device,
                  title: 'Platform',
                  subtitle: _platform,
                  trailing: Icon(_I.copy, size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _copy('Platform', _platform),
                ),
                ZenRow(
                  icon: _I.copy,
                  title: 'Copy details for a bug report',
                  subtitle: 'Version, build and platform',
                  onTap: () => _copy('App details', _report),
                ),
              ]),

              // ── Credits and licenses ──
              ZenSection(title: 'Credits and licenses', children: [
                ZenRow(
                  icon: _I.people,
                  title: 'Educational and research use',
                  subtitle: 'ZenMusic is made for educational and research '
                      'purposes only.',
                ),
                ZenRow(
                  icon: _I.license,
                  title: 'GPL-3.0 license',
                  subtitle: 'ZenMusic is free software. Read the license.',
                  trailing: Icon(ZenIcons.openExternal,
                      size: 18, color: cs.onSurfaceVariant),
                  onTap: () => _open('$_repo/blob/main/LICENSE'),
                ),
                ZenRow(
                  icon: _I.library,
                  title: 'Open-source libraries',
                  subtitle: 'Licenses of the packages ZenMusic uses',
                  chevron: true,
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'ZenMusic',
                    applicationVersion: '$_version ($_build)',
                  ),
                ),
              ]),

              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Built with Flutter.',
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}