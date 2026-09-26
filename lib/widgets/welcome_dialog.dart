import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/spotify_theme.dart';

/// First-launch welcome dialog — Echo Nightly port, trimmed to GitHub +
/// Instagram. Shows once (until cleared from Settings → About), on top
/// of the home screen after the first frame.
///
/// Fix: the "shown" flag is written ONLY after the dialog has actually
/// been dismissed. Writing it before (the old bug) meant any hiccup in
/// the dialog flow consumed the one-shot and the dialog never appeared.
class WelcomeDialog {
  WelcomeDialog._();

  // ⚠️ EDIT THESE — your links.
  static const _instagramUrl = 'https://instagram.com/neod.evx';
  static const _instagramHandle = '@neod.evx';
  static const _githubUrl = 'https://github.com/vorlon-dev';
  static const _repoUrl = 'https://github.com/vorlon-dev/Zen-music';

  static const _shownKey = 'welcome_shown_v1';

  /// Shows the dialog once ever (first app launch).
  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_shownKey) ?? false) return;
    if (!context.mounted) return;

    // Show FIRST; mark shown only after the user closes it.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _WelcomeBody(),
    );
    await prefs.setBool(_shownKey, true);
  }

  /// Re-show from Settings → About.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _WelcomeBody(),
    );
  }

  /// Reset the "shown" flag so the dialog shows again on next launch.
  static Future<void> resetShownFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, false);
  }
}

class _WelcomeBody extends StatefulWidget {
  const _WelcomeBody();

  @override
  State<_WelcomeBody> createState() => _WelcomeBodyState();
}

class _WelcomeBodyState extends State<_WelcomeBody> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform()
        .then((p) {
      if (!mounted) return;
      setState(() => _version = p.version);
    })
        .catchError((_) {});
  }

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: SpotifyColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerCard(),
                const SizedBox(height: 16),
                _section('Follow the developer', [
                  _actionRow(
                    Icons.photo_camera_outlined,
                    'Instagram',
                    WelcomeDialog._instagramHandle,
                        () => _open(WelcomeDialog._instagramUrl),
                  ),
                  _divider(),
                  _actionRow(
                    Icons.code_rounded,
                    'GitHub',
                    WelcomeDialog._githubUrl.replaceFirst('https://', ''),
                        () => _open(WelcomeDialog._githubUrl),
                  ),
                ]),
                const SizedBox(height: 16),
                // Star the repo.
                SizedBox(
                  height: 50,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: SpotifyColors.surfaceLight,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => _open(WelcomeDialog._repoUrl),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 20, color: SpotifyColors.textPrimary),
                        SizedBox(width: 8),
                        Text('Star the Repo',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: SpotifyColors.textPrimary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 50,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: SpotifyColors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header: app name, version badge, dev notice (no logo) ──

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: SpotifyColors.surfaceLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Text('ZenMusic',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.textPrimary)),
          const SizedBox(height: 8),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: SpotifyColors.green.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_version.isEmpty ? '…' : 'v$_version',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: SpotifyColors.green)),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.construction_rounded,
                    size: 18, color: Colors.orangeAccent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This app is still in development — features may '
                        'change and you may run into bugs.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: SpotifyColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // ── Echo's section card + action rows ──

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: SpotifyColors.green)),
        ),
        Container(
          decoration: BoxDecoration(
            color: SpotifyColors.surfaceLight,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _actionRow(IconData icon, String title, String? subtitle,
      VoidCallback onTap) {
    return _PressScaleRow(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: SpotifyColors.green.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: SpotifyColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: SpotifyColors.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: SpotifyColors.textSecondary
                                .withOpacity(0.8))),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 18,
                color: SpotifyColors.textTertiary.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 66, right: 20),
      child: Divider(
          thickness: 0.5,
          color: Colors.white.withOpacity(0.07)),
    );
  }
}

/// Echo's press-scale feedback on action rows.
class _PressScaleRow extends StatefulWidget {
  const _PressScaleRow({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressScaleRow> createState() => _PressScaleRowState();
}

class _PressScaleRowState extends State<_PressScaleRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}