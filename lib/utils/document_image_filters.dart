import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

enum DocFilter {
  original,
  enhance,
  grayscale,
  contrast,
  magicBw,
}

extension DocFilterLabel on DocFilter {
  String get label {
    switch (this) {
      case DocFilter.original:
        return 'Original';
      case DocFilter.enhance:
        return 'Enhance';
      case DocFilter.grayscale:
        return 'Grayscale';
      case DocFilter.contrast:
        return 'Contrast';
      case DocFilter.magicBw:
        return 'B&W doc';
    }
  }
}

/// Apply CamScanner-style filters using the `image` package.
class DocumentImageFilters {
  static Future<img.Image?> decodeFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static img.Image apply(img.Image source, DocFilter filter) {
    switch (filter) {
      case DocFilter.original:
        return img.Image.from(source);
      case DocFilter.enhance:
        var out = img.adjustColor(source, contrast: 1.15, saturation: 1.05);
        out = img.convolution(out, filter: const [
          0,
          -0.5,
          0,
          -0.5,
          3,
          -0.5,
          0,
          -0.5,
          0,
        ]);
        return out;
      case DocFilter.grayscale:
        return img.grayscale(source);
      case DocFilter.contrast:
        return img.adjustColor(source, contrast: 1.45, brightness: 1.02);
      case DocFilter.magicBw:
        final gray = img.grayscale(source);
        final punch = img.adjustColor(gray, contrast: 1.55, brightness: 1.04);
        return img.luminanceThreshold(punch, threshold: 0.48);
    }
  }

  static Future<String> saveJpeg(img.Image image, {String? prefix}) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${prefix ?? 'scan'}_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> applyAndSave(String path, DocFilter filter) async {
    if (filter == DocFilter.original) return path;
    final decoded = await decodeFile(path);
    if (decoded == null) return path;
    final out = apply(decoded, filter);
    return saveJpeg(out, prefix: 'scan_${filter.name}');
  }
}
