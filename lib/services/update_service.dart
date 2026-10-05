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
/// installed version (semantic parts AND build code) → dialog with a
/// parsed "What's new" changelog → "Update" downloads the APK matching
/// this device's ABI with a live progress dialog, then launches the
/// system installer.
///
/// DOWNLOADED UPDATES PERSIST: the APK is stored under a
/// deterministic path (cache/zen_updates/zenmusic-<version>.apk).
/// Once a version is downloaded, every later launch shows
/// "Ready to install" with a direct Install button — no re-download,
/// until a NEWER release appears.
///
/// NO BROWSER TRAP: a failed install surfaces its REAL error in the
/// snackbar and keeps the cached APK for instant retry. The browser
/// opens ONLY when the release has no .apk assets at all.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Your repo, "owner/name".
  static const _repo = 'vorlon-dev/Zen-music';

  static bool _checkedThisSession = false;
  final http.Client _client = http.Client();
  static const _channel = MethodChannel('com.zen.music.install_apk');

  // ═══════════════════════════════════════════
  // PERSISTED DOWNLOAD CACHE
  // ═══════════════════════════════════════════

  /// Stable updates directory inside the app cache. The OS may clear
  /// it under storage pressure — that only costs one re-download.
  Directory _updatesDir() {
    final dir = Directory('${Directory.systemTemp.path}/zen_updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Versions come from git tags — keep the filename safe.
  static String _sanitizeVersion(String v) =>
      v.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  File _cachedApkFor(String version) => File(
      '${_updatesDir().path}/zenmusic-${_sanitizeVersion(version)}.apk');

  /// Deletes every cached APK except [keepVersion].
  void _cleanupUpdatesDir({String? keepVersion}) {
    try {
      final keepName = keepVersion == null
          ? null
          : _sanitizeVersion(keepVersion);
      for (final f in _updatesDir().listSync()) {
        if (f is! File) continue;
        final n = f.uri.pathSegments.last;
        if (!n.startsWith('zenmusic-') || !n.endsWith('.apk')) continue;
        if (keepName != null && n == 'zenmusic-$keepName.apk') continue;
        f.deleteSync();
      }
    } catch (_) {
      // Cache cleanup is best-effort only.
    }
  }

  /// Called on app launch. Runs AFTER the welcome dialog. Respects the
  /// "Automatic update checks" toggle in Settings → About.
  Future<void> checkOnLaunch(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    if (!storage.getCheckUpdates()) {
      debugPrint('Update: launch check skipped (toggle off)');
      return;
    }
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
    } catch (e) {
      debugPrint('Update: manual check threw: $e');
      update = null;
    }
    if (!context.mounted) return 'Check failed — no connection?';
    if (update == null) {
      return 'You\'re on the latest version';
    }
    _showUpdateDialog(context, update);
    return update.readyToInstall
        ? 'Update ready to install: ${update.latestVersion}'
        : 'Update available: ${update.latestVersion}';
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
      if (r.statusCode == 404) {
        debugPrint('Update: /releases/latest returned 404');
        return null;
      }
      if (r.statusCode != 200) {
        debugPrint('Update: GitHub API status ${r.statusCode}');
        return null;
      }

      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final tagName = (body['tag_name'] as String?) ?? '';
      if (tagName.isEmpty) {
        debugPrint('Update: release has empty tag_name');
        return null;
      }

      final m = RegExp(r'v?(\d+(?:\.\d+)+)(?:\+(\d+))?')
          .firstMatch(tagName);
      if (m == null) {
        debugPrint('Update: tag "$tagName" has no parsable version');
        return null;
      }
      final latestParts = _versionParts(m.group(1)!);
      if (m.group(2) != null) {
        latestParts.add(int.tryParse(m.group(2)!) ?? 0);
      }

      final installedParts = _versionParts(installed);
      if (_compare(installedParts, latestParts) >= 0) {
        debugPrint('Update: up to date '
            '(installed $installed vs tag $tagName)');
        _cleanupUpdatesDir();
        return null;
      }
      debugPrint('Update: $installed → $tagName available');

      final latestVersion = tagName.replaceFirst(RegExp('^[vV]'), '');
      final cached = _cachedApkFor(latestVersion);
      final readyToInstall = cached.existsSync();
      debugPrint('Update: cached APK for $latestVersion '
          '${readyToInstall ? "PRESENT — ready to install" : "absent"}');

      final abis = await _deviceAbis();
      debugPrint('Update: device ABIs $abis');

      final assets = body['assets'] as List? ?? [];
      String? downloadUrl;
      final apkAssets = <({String name, String url})>[];
      for (final a in assets) {
        if (a is! Map) continue;
        final name = (a['name'] as String? ?? '');
        final url = (a['browser_download_url'] as String? ?? '');
        if (url.isEmpty || !name.toLowerCase().endsWith('.apk')) continue;
        apkAssets.add((name: name, url: url));
        final score = _abiScore(name, abis);
        debugPrint('Update: asset "$name" → score $score');
        if (score > 0 && downloadUrl == null) {
          downloadUrl = url;
        }
      }

      if (downloadUrl == null && apkAssets.isNotEmpty) {
        debugPrint('Update: no ABI/universal match — '
            'falling back to any APK asset');
        final ({String name, String url}) pick;
        if (apkAssets.length == 1) {
          pick = apkAssets.first;
        } else {
          pick = apkAssets.firstWhere(
                (e) => e.name.toLowerCase().contains('arm64'),
            orElse: () => apkAssets.first,
          );
        }
        debugPrint('Update: fallback pick "${pick.name}"');
        downloadUrl = pick.url;
      }

      if (downloadUrl == null) {
        debugPrint('Update: release has NO .apk assets — '
            'browser fallback is unavoidable');
      }
      downloadUrl ??= body['html_url'] as String? ?? '';
      debugPrint('Update: download source: $downloadUrl');

      return _UpdateInfo(
        installedVersion: installed,
        latestVersion: latestVersion,
        changelog: (body['body'] as String?) ?? '',
        downloadUrl: downloadUrl,
        readyToInstall: readyToInstall,
      );
    } catch (e) {
      debugPrint('Update: check failed: $e');
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
      return const ['arm64-v8a'];
    }
  }

  static const _abiAliases = <String, List<String>>{
    'arm64-v8a': ['arm64-v8a', 'arm64'],
    'armeabi-v7a': ['armeabi-v7a', 'armeabi', 'v7a'],
    'x86_64': ['x86_64', 'x64'],
    'x86': ['x86'],
  };

  static int _abiScore(String apkName, List<String> abis) {
    final n = apkName.toLowerCase();
    if (n.contains('universal')) return 1;
    for (var i = 0; i < abis.length; i++) {
      final aliases = _abiAliases[abis[i]] ?? [abis[i].toLowerCase()];
      for (final alias in aliases) {
        if (n.contains(alias)) {
          return i == 0 ? 3 : 2;
        }
      }
    }
    return -1;
  }

  /// "1.0.2+2" → [1, 0, 2, 2]; "1.0.3" → [1, 0, 3, 0].
  static List<int> _versionParts(String version) {
    final plus = version.split('+');
    final sem = plus.first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final build = plus.length > 1 ? (int.tryParse(plus[1]) ?? 0) : 0;
    return [...sem, build];
  }

  static int _compare(List<int> a, List<int> b) {
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final va = i < a.length ? a[i] : 0;
      final vb = i < b.length ? b[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  // ═══════════════════════════════════════════
  // IN-APP DOWNLOAD + INSTALL
  // ═══════════════════════════════════════════

  Future<String> downloadAndInstall(
      BuildContext context, _UpdateInfo info) async {
    final cached = _cachedApkFor(info.latestVersion);
    if (cached.existsSync()) {
      debugPrint('Update: installing persisted APK ${cached.path}');
      return _launchInstaller(cached);
    }

    if (!info.downloadUrl.endsWith('.apk')) {
      await _open(info.downloadUrl);
      return 'Opened release page — download from there';
    }

    var progress = 0;
    var cancelled = false;
    var dialogOpen = false;
    StateSetter? setDownloadProgress;

    void closeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          setDownloadProgress = setDialogState;
          return WillPopScope(
            onWillPop: () async {
              dialogOpen = false;
              cancelled = true;
              return true;
            },
            child: AlertDialog(
              backgroundColor: SpotifyColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
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
                          color: SpotifyColors.textSecondary,
                          fontSize: 12)),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () {
                      cancelled = true;
                      dialogOpen = false;
                      Navigator.pop(ctx);
                    },
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: SpotifyColors.textSecondary))),
              ],
            ),
          );
        },
      ),
    ));
    dialogOpen = true;

    final partFile = File('${cached.path}.part');

    try {
      final uri = Uri.parse(info.downloadUrl);
      final request = http.Request('GET', uri);
      final response =
      await _client.send(request).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        closeDialog();
        return 'Download failed (${response.statusCode})';
      }

      final totalBytes = response.contentLength ?? 0;
      debugPrint('Update: downloading ${info.latestVersion} '
          '($totalBytes bytes)');
      final sink = partFile.openWrite();
      var received = 0;

      await for (final chunk in response.stream) {
        if (cancelled) {
          await sink.close();
          if (await partFile.exists()) await partFile.delete();
          closeDialog();
          return 'Download cancelled';
        }
        received += chunk.length;
        await sink.addStream(Stream.value(chunk));
        if (totalBytes > 0) {
          final pct = received * 100 ~/ totalBytes;
          if (pct != progress) {
            progress = pct;
            try {
              setDownloadProgress?.call(() {});
            } catch (_) {
              setDownloadProgress = null;
            }
          }
        }
      }
      await sink.close();
      closeDialog();
      debugPrint('Update: download complete (${received} bytes) — '
          'caching and launching installer');

      partFile.renameSync(cached.path);
      _cleanupUpdatesDir(keepVersion: info.latestVersion);

      return _launchInstaller(cached);
    } catch (e) {
      closeDialog();
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      return 'Download failed: $e';
    }
  }

  /// Launches the system APK installer via the FileProvider channel.
  /// NO browser fallback — failures surface their real error text.
  Future<String> _launchInstaller(File apk) async {
    if (!apk.existsSync()) {
      debugPrint('Update: APK vanished before install: ${apk.path}');
      return 'Cached update missing — tap Update to download again';
    }
    debugPrint('Update: launching installer for ${apk.path} '
        '(${apk.lengthSync()} bytes)');
    try {
      final ok = await _channel.invokeMethod<bool>(
          'install', {'path': apk.path});
      if (ok == false) {
        return 'Allow "Install unknown apps" for ZenMusic in the '
            'screen that opened, then tap Install again';
      }
      return 'Installer opened — confirm the install';
    } catch (e) {
      debugPrint('Update: install channel failed: $e');
      final msg = e is PlatformException
          ? '${e.code}: ${e.message ?? e.details ?? ''}'
          : '$e';
      return 'Install failed — $msg';
    }
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  // UPDATE DIALOG — modern layout + section-aware changelog
  // ═══════════════════════════════════════════

  void _showUpdateDialog(BuildContext context, _UpdateInfo info) {
    final ready = info.readyToInstall;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        child: Container(
          decoration: BoxDecoration(
            color: SpotifyColors.surface,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: icon badge + title + version subtitle ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: SpotifyColors.green.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        ready
                            ? Icons.download_done_rounded
                            : Icons.system_update_alt_rounded,
                        color: SpotifyColors.green,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ready
                                ? 'Ready to install'
                                : 'Update available',
                            style: const TextStyle(
                                color: SpotifyColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            ready
                                ? 'Version ${info.latestVersion} · '
                                'already downloaded'
                                : 'Version ${info.latestVersion}',
                            style: const TextStyle(
                                color: SpotifyColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── WHAT'S NEW label ──
              const Padding(
                padding: EdgeInsets.fromLTRB(22, 18, 22, 10),
                child: Text(
                  'WHAT\'S NEW',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: SpotifyColors.textTertiary),
                ),
              ),

              // ── Changelog card: parsed, scrollable ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: SpotifyColors.surfaceLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ConstrainedBox(
                    constraints:
                    const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                        _changelogContent(info.changelog),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Actions: stadium pills ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          shape: const StadiumBorder(
                              side: BorderSide(
                                  color: SpotifyColors.surfaceLighter)),
                        ),
                        child: const Text('Later',
                            style: TextStyle(
                                color: SpotifyColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          downloadAndInstall(context, info)
                              .then((result) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                  SnackBar(
                                      content: Text(result)));
                            }
                          });
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: SpotifyColors.green,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(ready ? 'Install' : 'Update',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Changelog parsing ─────────────────────────────────────────

  static const _clBase = TextStyle(
      fontSize: 13.5, height: 1.45, color: SpotifyColors.textSecondary);

  static const _clHeading = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w700,
      height: 1.35, color: SpotifyColors.textPrimary);

  /// Headings that introduce actual change notes.
  static const _changelogHeadings = [
    "what's new", "what's changed", 'changes', 'changelog',
    'release notes', 'highlights', 'new', 'features',
    'improvements', 'fixes', 'bug fixes', 'fixed',
  ];

  /// Headings that are setup boilerplate, never change notes.
  static const _skipHeadings = [
    'downloads', 'download', 'install', 'installation',
    'install instructions', 'how to install', 'checksums',
    'assets', 'verification', 'upgrade',
  ];

  static String _normHeading(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();

  static bool _headingMatches(String norm, List<String> keys) {
    for (final k in keys) {
      final kn = _normHeading(k);
      if (norm == kn || norm.startsWith('$kn ')) return true;
    }
    return false;
  }

  /// GitHub release body → widget list, section-aware:
  ///
  /// - If the body contains a changelog heading ("What's new",
  ///   "Fixes", …), ONLY those sections are rendered — Downloads
  ///   tables, install instructions and checksums disappear.
  /// - If it has none, everything renders EXCEPT recognized
  ///   boilerplate sections — so a release body that is all setup
  ///   notes falls back to a clean one-liner instead of an install
  ///   manual.
  /// - Always filtered: GitHub's "Full Changelog: vX...vY" footer,
  ///   horizontal rules, redundant "What's new" heading (the card
  ///   label already says it).
  /// - Markdown tables render as joined rows instead of raw pipes.
  List<Widget> _changelogContent(String body) {
    if (body.trim().isEmpty) {
      return const [
        Text('Bug fixes and improvements.', style: _clBase),
      ];
    }

    final lines = body.replaceAll('\r\n', '\n').split('\n');
    final headingRe = RegExp(r'^(#{1,6})\s+(.*)');

    // Pass 1: does the body have explicit changelog sections?
    var hasChangelogSection = false;
    for (final raw in lines) {
      final h = headingRe.firstMatch(raw.trim());
      if (h == null) continue;
      if (_headingMatches(_normHeading(h.group(2)!),
          _changelogHeadings)) {
        hasChangelogSection = true;
        break;
      }
    }

    final widgets = <Widget>[];
    var keep = true;

    for (final raw in lines) {
      final t = raw.trim();

      // Headings switch the active section.
      final h = headingRe.firstMatch(t);
      if (h != null) {
        final text = h.group(2)!.trim();
        final norm = _normHeading(text);
        keep = hasChangelogSection
            ? _headingMatches(norm, _changelogHeadings)
            : !_headingMatches(norm, _skipHeadings);
        if (!keep) continue;
        // "What's new/Changed/Fixed" as a heading is redundant — the
        // card label already says it.
        if (RegExp(r'^whats (new|changed|fixed)$').hasMatch(norm)) {
          continue;
        }
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text.rich(
            TextSpan(children: _mdSpans(text, base: _clHeading)),
            style: _clHeading,
          ),
        ));
        continue;
      }

      if (t.isEmpty) {
        if (widgets.isNotEmpty && widgets.last is! SizedBox) {
          widgets.add(const SizedBox(height: 6));
        }
        continue;
      }

      // Horizontal rules and GitHub's auto changelog footer.
      if (RegExp(r'^(-{3,}|\*{3,}|_{3,})$').hasMatch(t)) continue;
      if (RegExp(r'^\*{0,2}\s*full changelog',
          caseSensitive: false).hasMatch(t)) {
        continue;
      }

      if (!keep) continue;

      // Markdown table row → joined cells (separator rows skipped).
      if (t.startsWith('|')) {
        final cells = t
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        if (cells.isEmpty) continue;
        final isSeparator = cells.every(
                (c) => RegExp(r'^:?-{2,}:?$').hasMatch(c));
        if (isSeparator) continue;
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(children: _mdSpans(cells.join('  —  '))),
            style: _clBase,
          ),
        ));
        continue;
      }

      // Bullet (- / * / •)
      final bullet = RegExp(r'^[-*•]\s+(.*)').firstMatch(t);
      if (bullet != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7),
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: SpotifyColors.green,
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                      children: _mdSpans(bullet.group(1)!)),
                  style: _clBase,
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // Numbered item (1. / 2) ...)
      final numbered = RegExp(r'^(\d+)[.)]\s+(.*)').firstMatch(t);
      if (numbered != null) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text('${numbered.group(1)}.',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: SpotifyColors.green)),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                      children: _mdSpans(numbered.group(2)!)),
                  style: _clBase,
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      // Plain paragraph.
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(
          TextSpan(children: _mdSpans(t)),
          style: _clBase,
        ),
      ));
    }

    if (widgets.isEmpty) {
      return const [
        Text('Bug fixes and improvements.', style: _clBase),
      ];
    }
    return widgets;
  }

  /// Inline Markdown cleanup: [text](url) → text, **bold** → bold
  /// spans, backticks stripped. Uses replaceAllMapped — Dart has NO
  /// regex backreferences in replaceAll ('$1' is a parse error).
  List<InlineSpan> _mdSpans(String text, {TextStyle? base}) {
    final b = base ?? _clBase;
    final clean = text
        .replaceAllMapped(
      RegExp(r'!?\[([^\]]*)\]\(([^)]*)\)'),
          (m) => m.group(1) ?? '',
    )
        .replaceAll('`', '');
    final spans = <InlineSpan>[];
    final parts = clean.split('**');
    final emphasis = b.merge(const TextStyle(
        fontWeight: FontWeight.w700,
        color: SpotifyColors.textPrimary));
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i].trim();
      if (seg.isEmpty) continue;
      spans.add(TextSpan(
          text: seg, style: i.isOdd ? emphasis : b));
    }
    if (spans.isEmpty) {
      spans.add(const TextSpan(text: ''));
    }
    return spans;
  }
}

/// Internal update description.
class _UpdateInfo {
  const _UpdateInfo({
    required this.installedVersion,
    required this.latestVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.readyToInstall,
  });
  final String installedVersion;
  final String latestVersion;
  final String changelog;
  final String downloadUrl;

  /// True when this version's APK is already on disk — the dialog
  /// offers a direct install with no download.
  final bool readyToInstall;
}