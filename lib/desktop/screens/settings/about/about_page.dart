// ZenMusic · vorlon-dev

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:zenmusic/desktop/core/widgets/zen_logo.dart';
import 'package:zenmusic/desktop/services/l10n.dart';
import 'package:zenmusic/desktop/services/repo_stats_service.dart';
import 'package:zenmusic/desktop/utils/zen_icons.dart';
import 'package:zenmusic/desktop/utils/zen_settings_kit.dart';

const _repo = 'https://github.com/vorlon-dev/Zen-music';
const _website = 'https://zenmusic-d6t.pages.dev/';
const _websiteLabel = 'zenmusic-d6t.pages.dev';
const _telegramUser = 'zenpratam';
const _telegramUrl = 'https://t.me/$_telegramUser';
const _telegramAsset = 'assets/brands/telegram_logo.png';
const _telegramBlue = Color(0xFF2AABEE);
const _commonsTelegram =
    'https://commons.wikimedia.org/wiki/File:Telegram_logo.svg';

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
  static IconData get tag => _a ? CupertinoIcons.tag : Icons.sell_outlined;
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

class _AboutPageState extends State<AboutPage>
    with SingleTickerProviderStateMixin {
  PackageInfo? _info;
  RepoStats? _stats;
  bool _loading = true;
  bool _failed = false;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
    // Saved numbers first (instant), then the live ones.
    RepoStatsService.instance.peek().then((s) {
      if (mounted && s != null && _stats == null) setState(() => _stats = s);
    });
    _loadStats();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Future<void> _loadStats({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final result = await RepoStatsService.instance.load(force: force);
    if (!mounted) return;
    setState(() {
      _stats = result.stats ?? _stats;
      _failed = result.failed;
      _loading = false;
    });
  }

  String get _version => _info?.version ?? '…';
  String get _build => _info?.buildNumber ?? '…';
  String get _platform =>
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
  String get _report => 'ZenMusic $_version ($_build)\n$_platform';

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _open(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) _snack('Could not open the link'.tr);
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget reveal(int i, Widget child) =>
        _Reveal(animation: _enter, index: i, child: child);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _loadStats(force: true),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar.large(title: Text('About'.tr)),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        reveal(0, _Hero(version: _version, buildNumber: _build)),
                        const SizedBox(height: 16),
                        reveal(
                          1,
                          _DownloadsCard(
                            stats: _stats,
                            loading: _loading,
                            failed: _failed,
                            onRefresh: () => _loadStats(force: true),
                            onDownload: () => _open('$_repo/releases/latest'),
                          ),
                        ),
                        const SizedBox(height: 28),
                        reveal(2, _SectionTitle('Get in touch'.tr)),
                        reveal(
                          3,
                          LayoutBuilder(builder: (context, c) {
                            final website = _ActionCard(
                              color: cs.secondaryContainer,
                              onColor: cs.onSecondaryContainer,
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: cs.onSecondaryContainer
                                      .withValues(alpha: 0.12),
                                ),
                                child: Icon(Icons.language_rounded,
                                    color: cs.onSecondaryContainer),
                              ),
                              title: 'Website'.tr,
                              subtitle: _websiteLabel,
                              hint: 'News, downloads and guides'.tr,
                              onTap: () => _open(_website),
                              onLongPress: () => _copy('Website link', _website),
                            );
                            final telegram = _ActionCard(
                              color: Color.alphaBlend(
                                _telegramBlue.withValues(alpha: 0.16),
                                cs.surfaceContainerHigh,
                              ),
                              onColor: cs.onSurface,
                              leading: Image.asset(
                                _telegramAsset,
                                width: 44,
                                height: 44,
                                filterQuality: FilterQuality.medium,
                              ),
                              title: 'Telegram',
                              subtitle: '@$_telegramUser',
                              hint: 'Tap to chat · hold to copy'.tr,
                              onTap: () => _open(_telegramUrl),
                              onLongPress: () =>
                                  _copy('Telegram handle', '@$_telegramUser'),
                            );
                            if (c.maxWidth >= 440) {
                              return IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: website),
                                    const SizedBox(width: 12),
                                    Expanded(child: telegram),
                                  ],
                                ),
                              );
                            }
                            return Column(children: [
                              website,
                              const SizedBox(height: 12),
                              telegram,
                            ]);
                          }),
                        ),
                        const SizedBox(height: 28),
                        reveal(
                          4,
                          ZenSection(title: 'Project'.tr, children: [
                            ZenRow(
                              icon: _I.code,
                              title: 'Source code'.tr,
                              subtitle: 'github.com/vorlon-dev/Zen-music',
                              trailing: Icon(ZenIcons.openExternal,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => _open(_repo),
                            ),
                            ZenRow(
                              icon: ZenIcons.update,
                              title: 'Releases'.tr,
                              subtitle: 'Download the latest version'.tr,
                              trailing: Icon(ZenIcons.openExternal,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => _open('$_repo/releases'),
                            ),
                            ZenRow(
                              icon: _I.bug,
                              title: 'Report a problem'.tr,
                              subtitle: 'Open an issue on GitHub'.tr,
                              trailing: Icon(ZenIcons.openExternal,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => _open('$_repo/issues'),
                            ),
                          ]),
                        ),
                        reveal(
                          5,
                          ZenSection(title: 'App info'.tr, children: [
                            ZenRow(
                              icon: _I.tag,
                              title: 'Version'.tr,
                              subtitle: '$_version ($_build)',
                              trailing: Icon(_I.copy,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => _copy('Version', '$_version+$_build'),
                            ),
                            if (_info != null)
                              ZenRow(
                                icon: _I.package,
                                title: 'Package'.tr,
                                subtitle: _info!.packageName,
                                trailing: Icon(_I.copy,
                                    size: 18, color: cs.onSurfaceVariant),
                                onTap: () =>
                                    _copy('Package name', _info!.packageName),
                              ),
                            ZenRow(
                              icon: _I.device,
                              title: 'Platform'.tr,
                              subtitle: _platform,
                              trailing: Icon(_I.copy,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => _copy('Platform', _platform),
                            ),
                            ZenRow(
                              icon: _I.copy,
                              title: 'Copy details for a bug report'.tr,
                              subtitle: 'Version, build and platform'.tr,
                              onTap: () => _copy('App details', _report),
                            ),
                          ]),
                        ),
                        reveal(
                          6,
                          ZenSection(
                              title: 'Credits and licenses'.tr,
                              children: [
                                ZenRow(
                                  icon: _I.people,
                                  title: 'Educational and research use'.tr,
                                  subtitle:
                                      'ZenMusic is made for educational and research '
                                      'purposes only.',
                                ),
                                ZenRow(
                                  icon: _I.license,
                                  title: 'GPL-3.0 license'.tr,
                                  subtitle:
                                      'ZenMusic is free software. Read the license.'
                                          .tr,
                                  trailing: Icon(ZenIcons.openExternal,
                                      size: 18, color: cs.onSurfaceVariant),
                                  onTap: () =>
                                      _open('$_repo/blob/main/LICENSE'),
                                ),
                                ZenRow(
                                  icon: _I.library,
                                  title: 'Open-source libraries'.tr,
                                  subtitle:
                                      'Licenses of the packages ZenMusic uses'
                                          .tr,
                                  chevron: true,
                                  onTap: () => showLicensePage(
                                    context: context,
                                    applicationName: 'ZenMusic',
                                    applicationVersion: '$_version ($_build)',
                                  ),
                                ),
                                ZenRow(
                                  icon: _I.license,
                                  leading: Image.asset(
                                    _telegramAsset,
                                    width: 22,
                                    height: 22,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                  title: 'Telegram logo'.tr,
                                  subtitle: 'Telegram Messenger LLP, Public '
                                      'domain, via Wikimedia Commons',
                                  trailing: Icon(ZenIcons.openExternal,
                                      size: 18, color: cs.onSurfaceVariant),
                                  onTap: () => _open(_commonsTelegram),
                                ),
                              ]),
                        ),
                        reveal(
                          7,
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Made with ',
                                      style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant)),
                                  Icon(Icons.favorite_rounded,
                                      size: 14, color: cs.error),
                                  Text(' by vorlon-dev',
                                      style: tt.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Built with Flutter.'.tr,
                                textAlign: TextAlign.center,
                                style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant
                                        .withValues(alpha: 0.7)),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── entrance

/// Fade + slide-up, staggered by [index].
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double start = (index * 0.08).clamp(0.0, 0.6).toDouble();
    final a = animation.drive(CurveTween(
      curve: Interval(start, math.min(start + 0.4, 1.0),
          curve: Curves.easeOutCubic),
    ));
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(a),
        child: child,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────── hero

class _Hero extends StatelessWidget {
  const _Hero({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      borderRadius: BorderRadius.circular(32),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.tertiaryContainer],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HeroPainter(
                    cs.onPrimaryContainer.withValues(alpha: 0.07)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.35),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const ZenLogoWidget(size: 96, borderRadius: 28),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'ZenMusic',
                    style: tt.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A music player for YouTube Music and Spotify, '
                    'on desktop and mobile.'.tr,
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(
                      color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(icon: Icons.sell_outlined, label: 'v$version'),
                      _Pill(icon: Icons.build_outlined, label: 'Build $buildNumber'),
                      const _Pill(icon: Icons.gavel_outlined, label: 'GPL-3.0'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onSurface),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final c1 = Offset(size.width * 0.94, size.height * 0.06);
    final c2 = Offset(size.width * 0.04, size.height * 0.96);
    for (var i = 1; i <= 6; i++) {
      canvas.drawCircle(c1, 30.0 * i, p);
      canvas.drawCircle(c2, 26.0 * i, p);
    }
  }

  @override
  bool shouldRepaint(_HeroPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────── downloads

final NumberFormat _full = NumberFormat.decimalPattern();
final NumberFormat _compact = NumberFormat.compact();

int _nextMilestone(int n) {
  const steps = [
    100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, //
    100000, 250000, 500000, 1000000,
  ];
  for (final s in steps) {
    if (n < s) return s;
  }
  return ((n ~/ 1000000) + 1) * 1000000;
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _DownloadsCard extends StatelessWidget {
  const _DownloadsCard({
    required this.stats,
    required this.loading,
    required this.failed,
    required this.onRefresh,
    required this.onDownload,
  });

  final RepoStats? stats;
  final bool loading;
  final bool failed;
  final VoidCallback onRefresh;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = stats;

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.download_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Total downloads'.tr,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh'.tr,
                  onPressed: loading ? null : onRefresh,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _body(context, s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, RepoStats? s) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (s == null) {
      if (loading) {
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Skeleton(width: 170, height: 52, radius: 16),
              const SizedBox(height: 16),
              _Skeleton(width: double.infinity, height: 10, radius: 8),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: cs.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Could not load the live numbers.'.tr,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            TextButton(onPressed: onRefresh, child: Text('Retry'.tr)),
          ],
        ),
      );
    }

    final total = s.totalDownloads;
    final milestone = _nextMilestone(total);
    final progress = (total / milestone).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: total.toDouble()),
          duration: const Duration(milliseconds: 1600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Text(
            _full.format(v.round()),
            style: tt.displayMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.primary,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Text(
          'across ${s.releaseCount} releases'.tr,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: progress),
          duration: const Duration(milliseconds: 1600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => LinearProgressIndicator(
            value: v,
            minHeight: 10,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_full.format(milestone - total)} more to reach ${_full.format(milestone)}',
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                icon: Icons.new_releases_outlined,
                label: 'Latest'.tr,
                value: s.latestTag ?? '—',
                sub: '${_compact.format(s.latestDownloads)} downloads',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStat(
                icon: Icons.star_rounded,
                label: 'Stars'.tr,
                value: _compact.format(s.stars),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MiniStat(
                icon: Icons.inventory_2_outlined,
                label: 'Releases'.tr,
                value: _full.format(s.releaseCount),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded),
            label: Text('Get the latest version'.tr),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              failed ? Icons.cloud_off_rounded : Icons.bolt_rounded,
              size: 14,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                failed
                    ? 'Offline, showing saved numbers (${_ago(s.fetchedAt)})'
                    : 'Live from GitHub, updated ${_ago(s.fetchedAt)}',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (sub != null)
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────── contact

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.color,
    required this.onColor,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.hint,
    this.onLongPress,
  });

  final Color color;
  final Color onColor;
  final Widget leading;
  final String title;
  final String subtitle;
  final String? hint;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  leading,
                  const Spacer(),
                  Icon(Icons.north_east_rounded,
                      size: 20, color: onColor.withValues(alpha: 0.7)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: onColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(
                  color: onColor.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (hint != null) ...[
                const SizedBox(height: 8),
                Text(
                  hint!,
                  style: tt.bodySmall
                      ?.copyWith(color: onColor.withValues(alpha: 0.65)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
