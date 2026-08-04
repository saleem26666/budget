import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

class ImageHelper {
  static Future<Directory> appImagesDir() async {
    final base = kIsWeb
        ? await getTemporaryDirectory()
        : (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            ? await getApplicationSupportDirectory()
            : await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/budget_pro_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<String> copyToAppStorage(String sourcePath, String prefix) async {
    if (kIsWeb) return sourcePath;
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;

    final dir = await appImagesDir();
    final name =
        '${prefix}_${DateTime.now().millisecondsSinceEpoch}_${source.uri.pathSegments.last}';
    final dest = File('${dir.path}/$name');
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<List<String>> persistPaths(
    List<String> paths,
    String prefix,
  ) async {
    final saved = <String>[];
    for (final path in paths) {
      if (path.isEmpty) continue;
      if (kIsWeb) {
        saved.add(path);
        continue;
      }
      final file = File(path);
      if (!await file.exists()) continue;
      final dir = await appImagesDir();
      if (path.startsWith(dir.path)) {
        saved.add(path);
      } else {
        saved.add(await copyToAppStorage(path, prefix));
      }
    }
    return saved;
  }

  static List<String> decodeImagePaths(dynamic raw) {
    if (raw == null) return [];
    final text = raw.toString().trim();
    if (text.isEmpty || text == '[]') return [];
    try {
      return List<String>.from(jsonDecode(text));
    } catch (_) {
      return [];
    }
  }
}
