import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/document_enhance_sheet.dart';
import 'platform_utils.dart';

/// Document scan (edge detect) vs normal camera/gallery photos.
class DocumentScanHelper {
  static final ImagePicker _picker = ImagePicker();

  /// Normal phone camera — NO edge detection (for everyday photos).
  static Future<String?> pickNormalCamera() async {
    final img = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    return img?.path;
  }

  /// Normal gallery photo — NO edge detection.
  static Future<String?> pickNormalGallery() async {
    final img = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    return img?.path;
  }

  /// Scan only: camera or gallery WITH auto edge detect + improve filters.
  static Future<String?> pickDocumentImage(BuildContext context) async {
    if (!isMobilePlatform) {
      final path = await pickNormalGallery();
      if (path == null || !context.mounted) return path;
      return DocumentEnhanceSheet.show(context, imagePath: path);
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Scan document',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan with camera'),
              subtitle: const Text('Auto edge detect + crop'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.crop_free_rounded),
              title: const Text('Scan from gallery'),
              subtitle: const Text('Pick photo → edge crop'),
              onTap: () => Navigator.pop(ctx, 'gallery_scan'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || choice == null) return null;

    String? path;
    if (choice == 'camera') {
      path = await _scan(source: ScannerSource.camera);
    } else if (choice == 'gallery_scan') {
      path = await _scan(source: ScannerSource.gallery);
    }
    if (path == null || !context.mounted) return path;
    return DocumentEnhanceSheet.show(context, imagePath: path);
  }

  /// Direct camera edge scan (Scan button shortcut).
  static Future<String?> scanDocumentDirect({BuildContext? context}) async {
    if (!isMobilePlatform) {
      final path = await pickNormalGallery();
      if (path == null || context == null || !context.mounted) return path;
      return DocumentEnhanceSheet.show(context, imagePath: path);
    }
    final path = await _scan(source: ScannerSource.camera);
    if (path == null) return null;
    if (context != null && context.mounted) {
      return DocumentEnhanceSheet.show(context, imagePath: path);
    }
    return path;
  }

  /// Gallery → edge crop.
  static Future<String?> scanFromGallery(BuildContext context) async {
    String? path;
    if (isMobilePlatform) {
      path = await _scan(source: ScannerSource.gallery);
    }
    path ??= await pickNormalGallery();
    if (path == null || !context.mounted) return path;
    return DocumentEnhanceSheet.show(context, imagePath: path);
  }

  static Future<String?> _scan({
    required ScannerSource source,
    int noOfPages = 1,
  }) async {
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: noOfPages,
        scannerSource: source,
        androidScannerMode: AndroidScannerMode.full,
      );
      if (paths != null && paths.isNotEmpty) return paths.first;
    } catch (_) {
      if (source == ScannerSource.gallery) {
        try {
          final paths = await CunningDocumentScanner.getPictures(
            noOfPages: noOfPages,
            scannerSource: ScannerSource.cameraAndGallery,
            androidScannerMode: AndroidScannerMode.full,
          );
          if (paths != null && paths.isNotEmpty) return paths.first;
        } catch (_) {}
      }
    }
    return null;
  }

  static Future<List<String>> pickMultipleDocumentImages(
    BuildContext context, {
    required int maxCount,
    required int currentCount,
  }) async {
    if (currentCount >= maxCount) return [];
    final remaining = maxCount - currentCount;
    if (!isMobilePlatform) {
      final path = await pickDocumentImage(context);
      return path != null ? [path] : [];
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan with camera'),
              subtitle: Text('Edge detect · up to $remaining pages'),
              onTap: () => Navigator.pop(ctx, 'scan'),
            ),
            ListTile(
              leading: const Icon(Icons.crop_free_rounded),
              title: const Text('Scan from gallery'),
              subtitle: const Text('Edge crop'),
              onTap: () => Navigator.pop(ctx, 'gallery_scan'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return [];

    final out = <String>[];
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: remaining.clamp(1, 10),
        scannerSource: choice == 'gallery_scan'
            ? ScannerSource.gallery
            : ScannerSource.camera,
        androidScannerMode: AndroidScannerMode.full,
      );
      if (paths != null) {
        for (final p in paths.take(remaining)) {
          if (!context.mounted) break;
          final enhanced =
              await DocumentEnhanceSheet.show(context, imagePath: p);
          if (enhanced != null) out.add(enhanced);
        }
      }
    } catch (_) {}
    return out;
  }
}
