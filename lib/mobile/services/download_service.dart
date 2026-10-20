import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

class DownloadService {
  /// Downloads a file and lets the user pick the folder via the native
  /// Android/iOS system dialog.
  static Future<String?> downloadToFolder({
    required String url,
    required String fileName,
  }) async {
    try {
      // 1. Download the file to a temporary cache directory
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      // 2. Open the native "Save As" folder picker
      final params = SaveFileDialogParams(
        sourceFilePath: tempFile.path,
        fileName: fileName,
      );
      final savedPath = await FlutterFileDialog.saveFile(params: params);

      // 3. Clean up the temp file
      if (tempFile.existsSync()) tempFile.deleteSync();

      return savedPath;
    } catch (e) {
      print('[download-service] error: $e');
      return null;
    }
  }
}