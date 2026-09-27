import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../theme/spotify_theme.dart';

/// OTA update checker + in-app installer, backed by GitHub Releases.
///
/// Flow: launch/manual check → compares latest release tag with the
/// installed version → dialog with changelog → "Update" downloads the
/// APK matching this device's ABI (universal fallback) with a progress
/// dialog, then launches the system installer. No browser.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Your repo, "owner/name".
  static const _repo = 'vorlon-dev/Zen-music';

  static bool _checkedThisSession = false;
  final http.Client _client = http.Client();
  static const _channel = MethodChannel('com.zen.music.install_apk');

  File? _downloadedApk;
  String? _downloadedVersion;

  /// Called on app launch. Runs AFTER the welcome dialog. Respects the
  /// "Automatic update checks" toggle in Settings → About.
  Future<void> checkOnLaunch(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    if (!storage.getCheckUpdates()) return;
    final update = await checkForUpdate();
    if (update == null) return;
    if (!context.mounted) return;
    _showUpdateDialog(context, update);
  }

  /// Manual check (Settings → About).
  Future<String> manualCheck(BuildContext context) async {
    _UpdateInfo? update;
    try {
      update = await checkForUpdate();
    } catch (_) {
      update = null;
    }
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
      final installed = pkg.version;

      final uri = Uri.parse(
          'https://api.github.com/repos/$_repo/releases/latest');
      final r = await _client.get(uri, headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ZenMusic',
      }).timeout(const Duration(seconds: 12));
      if (r.statusCode == 404) return null; // no releases yet
      if (r.statusCode != 200) return null;

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final tagName = (body['tag_name'] as String?) ?? '';
      final latest = tagName.replaceFirst(RegExp('^[vV]'), '');
      if (latest.isEmpty) return null;

      if (_compare(installed, latest) >= 0) return null;

      // Device ABI list — primary ABI first.
      final abis = await _deviceAbis();

      // Collect all APK assets and pick the best one for this device.
      final assets = body['assets'] as List? ?? [];
      String? downloadUrl;
      int bestScore = -1;
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] as String? ?? '');
        final url = (a['browser_download_url'] as String? ?? '');
        if (url.isEmpty || !name.endsWith('.apk')) continue;
        final score = _abiScore(name, abis);
        if (score > bestScore) {
          bestScore = score;
          downloadUrl = url;
        }
      }
      downloadUrl ??= body['html_url'] as String? ?? '';

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

  /// Device ABI list via device_info_plus — primary ABI first.
  Future<List<String>> _deviceAbis() async {
    try {
      if (!Platform.isAndroid) return const ['universal'];
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      final abis = android.supportedAbis;
      return abis.isNotEmpty ? abis : const ['arm64-v8a'];
    } catch (_) {
      return const ['arm64-v8a']; // sane modern default
    }
  }

  /// Scores an APK asset name against the device's ABI list.
  /// 3 = exact primary ABI match, 2 = supported ABI, 1 = universal,
  /// -1 = incompatible.
  static int _abiScore(String apkName, List<String> abis) {
    final n = apkName.toLowerCase();
    if (n.contains('universal')) return 1;
    for (var i = 0; i < abis.length; i++) {
      if (n.contains(abis[i].toLowerCase())) {
        return i == 0 ? 3 : 2;
      }
    }
    return -1;
  }

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

  // ═══════════════════════════════════════════
  // IN-APP DOWNLOAD + INSTALL
  // ═══════════════════════════════════════════

  /// Downloads the APK with progress UI, then launches the system
  /// installer. Returns a snackbar-ready result string.
  Future<String> downloadAndInstall(
      BuildContext context, _UpdateInfo info) async {
    // Already downloaded this version? Skip straight to install.
    if (_downloadedApk != null &&
        _downloadedVersion == info.latestVersion &&
        _downloadedApk!.existsSync()) {
      await _launchInstaller(_downloadedApk!);
      return 'Installer opened — confirm to install v${info.latestVersion}';
    }

    if (!info.downloadUrl.endsWith('.apk')) {
      // No APK asset in the release — fall back to the browser.
      await _open(info.downloadUrl);
      return 'Opened release page — download from there';
    }

    // Progress dialog.
    var progress = 0;
    var cancelled = false;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SpotifyColors.surface,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Downloading update',
              style: TextStyle(
                  color: SpotifyColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('v${info.latestVersion}',
                  style: const TextStyle(
                      color: SpotifyColors.green,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 8,
                  backgroundColor: SpotifyColors.surfaceLighter,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      SpotifyColors.green),
                ),
              ),
              const SizedBox(height: 8),
              Text('$progress%',
                  style: const TextStyle(
                      color: SpotifyColors.textSecondary, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Cancel',
                    style: TextStyle(color: SpotifyColors.textSecondary))),
          ],
        ),
      ),
    ));

    try {
      final dir = await Directory.systemTemp.createTemp('zen_update');
      final file = File('${dir.path}/zenmusic-${info.latestVersion}.apk');
      final uri = Uri.parse(info.downloadUrl);
      final request = http.Request('GET', uri);
      final response =
      await _client.send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        return 'Download failed (${response.statusCode})';
      }

      final totalBytes = response.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;

      await for (final chunk in response.stream) {
        if (cancelled) {
          await sink.close();
          if (await file.exists()) await file.delete();
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          return 'Download cancelled';
        }
        received += chunk.length;
        await sink.addStream(Stream.value(chunk));
        if (totalBytes > 0) {
          final pct = received * 100 ~/ totalBytes;
          if (pct != progress) {
            progress = pct;
          }
        }
      }
      await sink.close();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      _downloadedApk = file;
      _downloadedVersion = info.latestVersion;
      await _launchInstaller(file);
      return 'Installer opened — confirm to install v${info.latestVersion}';
    } catch (e) {
      if (context.mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
      return 'Download failed: $e';
    }
  }

  /// Launches the system APK installer via the FileProvider channel.
  Future<void> _launchInstaller(File apk) async {
    try {
      await _channel.invokeMethod('install', {'path': apk.path});
    } catch (e) {
      print('In-app install failed: $e');
      await _open(
          'https://github.com/vorlon-dev/Zen-music/releases/latest');
    }
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showUpdateDialog(BuildContext context, _UpdateInfo info) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SpotifyColors.surface,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.system_update_alt_rounded,
                color: SpotifyColors.green, size: 22),
            SizedBox(width: 10),
            Expanded(
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
                downloadAndInstall(context, info).then((result) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result)));
                  }
                });
              },
              child: const Text('Update',
                  style: TextStyle(
                      color: SpotifyColors.green,
                      fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// Internal update description.
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