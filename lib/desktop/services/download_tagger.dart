// Saves the album cover next to a finished download (same name, .jpg), which
// most players (Android gallery/music apps, VLC, Poweramp, etc.) pick up
// automatically. Pure Dart, no native packages, so no dependency conflicts.
// Never throws: a failure must not break a finished download.
import 'dart:io';

import 'package:http/http.dart' as http;

class DownloadTagger {
  static Future<void> tag(String audioPath, Map song) async {
    try {
      final thumbs = song['thumbnails'];
      if (thumbs is! List || thumbs.isEmpty) return;
      final url = (thumbs.last['url'] ?? '')
          .toString()
          .replaceAll(RegExp(r'=w\d+-h\d+.*$'), '=w600-h600');
      if (!url.startsWith('http')) return;
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return;
      final dot = audioPath.lastIndexOf('.');
      final base = dot > audioPath.lastIndexOf(Platform.pathSeparator)
          ? audioPath.substring(0, dot)
          : audioPath;
      await File('$base.jpg').writeAsBytes(r.bodyBytes, flush: true);
    } catch (_) {}
  }
}
