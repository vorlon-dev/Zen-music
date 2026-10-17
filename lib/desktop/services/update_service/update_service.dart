import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:zenmusic/desktop/services/update_service/models/update_info.dart';

class UpdateService {
  // Using GitHub Releases API for your repo
  static const String _apiUrl = 'https://api.github.com/repos/vorlon-dev/Zen-music/releases/latest';

  // Local DB key to store the version the user clicked "Later" on
  static const String _ignoredVersionKey = 'IGNORED_UPDATE_VERSION';

  /// Checks GitHub for a new release.
  /// Returns UpdateInfo if a newer version is available, otherwise null.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // tag_name is usually like "v14.10.2026+4" or "14.10.2026"
      final String rawTag = data['tag_name']?.toString() ?? '';
      final String versionStr = rawTag.replaceAll('v', '').trim();

      // Parse versions
      final remoteVersion = Version.parse(versionStr);
      final packageInfo = await PackageInfo.fromPlatform();
      // Flutter version can be like "14.10.2026+4"
      final localVersion = Version.parse(packageInfo.version);

      // Check if remote is strictly newer
      if (remoteVersion > localVersion) {

        // Check local DB: Did user ignore this version?
        final box = Hive.box('SETTINGS');
        final ignoredVersion = box.get(_ignoredVersionKey) as String?;

        if (ignoredVersion == remoteVersion.toString()) {
          return null; // User clicked 'Later' for this version
        }

        return UpdateInfo(
          version: remoteVersion,
          name: data['name']?.toString() ?? 'New Update',
          body: data['body']?.toString() ?? '',
          publishedAt: data['published_at']?.toString() ?? '',
          downloadUrl: data['html_url']?.toString() ?? 'https://github.com/vorlon-dev/Zen-music/releases',
        );
      }
    } catch (e) {
      print('[update-service] Check failed: $e');
    }
    return null;
  }

  /// Call this when the user clicks "Later" in the dialog
  static Future<void> ignoreVersion(String version) async {
    final box = Hive.box('SETTINGS');
    await box.put(_ignoredVersionKey, version);
  }
}