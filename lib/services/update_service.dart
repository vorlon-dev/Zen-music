import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../theme/spotify_theme.dart';

/// OTA update checker backed by GitHub Releases.
///
/// Flow: you push a tag (v1.0.1) → the release workflow builds the APK
/// and creates a GitHub Release → this service compares the latest
/// release tag with the installed version (from pubspec via
/// package_info_plus) and offers the update.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();


  static const _repo = 'vorlon-dev/Zen-music';

  static bool _checkedThisSession = false;
  final http.Client _client = http.Client();

  /// Called on app launch. Respects the "Automatic update checks"
  /// toggle in Settings → About (storage.getCheckUpdates()).
  Future<void> checkOnLaunch(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    if (!storage.getCheckUpdates()) return;
    final update = await checkForUpdate();
    if (update == null) return;
    if (!context.mounted) return;
    _showUpdateDialog(context, update);
  }

  /// Manual check (Settings row). Returns the result for a snackbar.
  Future<String> manualCheck(BuildContext context) async {
    final update = await checkForUpdate();
    if (!context.mounted) return 'Check failed — no connection?';
    if (update == null) {
      return 'You\'re on the latest version';
    }
    _showUpdateDialog(context, update);
    return 'Update available: ${update.latestVersion}';
  }

  Future<_UpdateInfo?> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final installed = pkg.version; // from pubspec version:

      final uri = Uri.parse(
          'https://api.github.com/repos/$_repo/releases/latest');
      final r = await _client
          .get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ZenMusic',
      })
          .timeout(const Duration(seconds: 12));
      if (r.statusCode == 404) return null; // no releases yet
      if (r.statusCode != 200) return null;

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final tagName = (body['tag_name'] as String?) ?? '';
      final latest = tagName.replaceFirst(RegExp('^[vV]'), '');
      if (latest.isEmpty) return null;

      if (_compare(installed, latest) >= 0) return null; // up to date

      // Prefer a .apk asset; fall back to the release page.
      String downloadUrl = body['html_url'] as String? ?? '';
      final assets = body['assets'] as List? ?? [];
      for (final a in assets) {
        if (a is Map && (a['name'] as String? ?? '').endsWith('.apk')) {
          downloadUrl = a['browser_download_url'] as String;
          break;
        }
      }

      return _UpdateInfo(
        installedVersion: installed,
        latestVersion: latest,
        changelog: (body['body'] as String?) ?? '',
        downloadUrl: downloadUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// -1 if a < b, 0 equal, 1 if a > b. Compares numeric dot segments.
  static int _compare(String a, String b) {
    final pa =
    a.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pb =
    b.split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  void _showUpdateDialog(BuildContext context, _UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt_rounded,
                color: SpotifyColors.green, size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Update available',
                  style: TextStyle(
                      color: SpotifyColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v${info.installedVersion}  →  v${info.latestVersion}',
                style: const TextStyle(
                    color: SpotifyColors.green,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            if (info.changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SpotifyColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Text(info.changelog,
                      style: const TextStyle(
                          color: SpotifyColors.textSecondary,
                          fontSize: 13,
                          height: 1.4)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later',
                  style: TextStyle(color: SpotifyColors.textSecondary))),
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _open(info.downloadUrl);
              },
              child: const Text('Download update',
                  style: TextStyle(
                      color: SpotifyColors.green,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}

class _UpdateInfo {
  const _UpdateInfo({
    required this.installedVersion,
    required this.latestVersion,
    required this.changelog,
    required this.downloadUrl,
  });
  final String installedVersion;
  final String latestVersion;
  final String changelog;
  final String downloadUrl;
}