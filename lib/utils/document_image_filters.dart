import 'dart:io';
import 'dart:isolate';
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

class _FilterJob {
  final String path;
  final String filterName;
  final String outPath;
  final int maxSide;

  const _FilterJob({
    required this.path,
    required this.filterName,
    required this.outPath,
    this.maxSide = 1280,
  });
}

/// Apply CamScanner-style filters using the `image` package.
class DocumentImageFilters {
  static Future<img.Image?> decodeFile(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return _decodeFast(bytes);
    } catch (_) {
      return null;
    }
  }

  static img.Image? _decodeFast(Uint8List bytes) {
    // JPEG path is much faster than generic decodeImage on phone scans.
    try {
      final jpg = img.decodeJpg(bytes);
      if (jpg != null) return jpg;
    } catch (_) {}
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static img.Image _downscale(img.Image source, int maxSide) {
    final longest = source.width > source.height ? source.width : source.height;
    if (longest <= maxSide) return source;
    final scale = maxSide / longest;
    return img.copyResize(
      source,
      width: (source.width * scale).round().clamp(1, maxSide),
      height: (source.height * scale).round().clamp(1, maxSide),
      // average is good quality/speed for docs; nearest is fastest but soft.
      interpolation: img.Interpolation.average,
    );
  }

  static img.Image apply(img.Image source, DocFilter filter) {
    switch (filter) {
      case DocFilter.original:
        return img.Image.from(source);
      case DocFilter.enhance:
        // No convolution — that was freezing phones for many seconds.
        return img.adjustColor(
          source,
          contrast: 1.22,
          brightness: 1.04,
          saturation: 1.06,
        );
      case DocFilter.grayscale:
        return img.grayscale(source);
      case DocFilter.contrast:
        return img.adjustColor(source, contrast: 1.4, brightness: 1.02);
      case DocFilter.magicBw:
        final gray = img.grayscale(source);
        return img.adjustColor(gray, contrast: 1.5, brightness: 1.05);
    }
  }

  static DocFilter _fromName(String name) {
    return DocFilter.values.firstWhere(
      (f) => f.name == name,
      orElse: () => DocFilter.original,
    );
  }

  /// Heavy decode/filter/encode — must stay off the UI isolate.
  static bool _processJob(_FilterJob job) {
    try {
      final bytes = File(job.path).readAsBytesSync();
      var decoded = _decodeFast(bytes);
      if (decoded == null) return false;
      decoded = _downscale(decoded, job.maxSide);
      final filter = _fromName(job.filterName);
      final out = apply(decoded, filter);
      final jpg = Uint8List.fromList(img.encodeJpg(out, quality: 82));
      File(job.outPath).writeAsBytesSync(jpg, flush: true);
      return true;
    } catch (_) {
      return false;
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
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/scan_${filter.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ok = await Isolate.run(
        () => _processJob(
          _FilterJob(
            path: path,
            filterName: filter.name,
            outPath: outPath,
            maxSide: 1280,
          ),
        ),
      );
      if (ok && await File(outPath).exists()) return outPath;
    } catch (_) {}
    return path;
  }
}
