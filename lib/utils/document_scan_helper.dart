import 'dart:async';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/document_enhance_sheet.dart';
import 'platform_utils.dart';

/// Document scan (edge detect) vs normal camera/gallery photos.
class DocumentScanHelper {
  static final ImagePicker _picker = ImagePicker();
  static bool _scanInFlight = false;

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

  /// After a native Activity (ML Kit scanner) closes, Flutter's Android
  /// surface is often still paused — UI looks black until power-cycle.
  /// Wait for resume + a couple frames, then nudge system chrome.
  static Future<void> _waitForSurfaceReady(BuildContext context) async {
    final binding = WidgetsBinding.instance;

    if (binding.lifecycleState != AppLifecycleState.resumed) {
      final done = Completer<void>();
      late final AppLifecycleListener listener;
      listener = AppLifecycleListener(
        onResume: () {
          if (!done.isCompleted) done.complete();
          listener.dispose();
        },
      );
      await Future.any([
        done.future,
        Future<void>.delayed(const Duration(milliseconds: 900)),
      ]);
      try {
        listener.dispose();
      } catch (_) {}
    }

    // Let the engine paint at least two frames after resume.
    await Future<void>.delayed(const Duration(milliseconds: 180));
    binding.scheduleFrame();
    await binding.endOfFrame;
    if (!context.mounted) return;
    binding.scheduleFrame();
    await SchedulerBinding.instance.endOfFrame;

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  static Future<String?> _enhanceIfReady(
    BuildContext context,
    String? path,
  ) async {
    if (path == null || !context.mounted) return path;
    await _waitForSurfaceReady(context);
    if (!context.mounted) return path;
    return DocumentEnhanceSheet.show(context, imagePath: path);
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

    // Let the choice sheet finish closing before launching the native camera.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return null;

    String? path;
    if (choice == 'camera') {
      path = await _scan(source: ScannerSource.camera);
    } else if (choice == 'gallery_scan') {
      path = await _scan(source: ScannerSource.gallery);
    }
    return _enhanceIfReady(context, path);
  }

  /// Direct camera edge scan (Scan button shortcut).
  static Future<String?> scanDocumentDirect({BuildContext? context}) async {
    if (!isMobilePlatform) {
      final path = await pickNormalGallery();
      if (path == null || context == null || !context.mounted) return path;
      return DocumentEnhanceSheet.show(context, imagePath: path);
    }
    final path = await _scan(source: ScannerSource.camera);
    if (path == null || context == null) return path;
    return _enhanceIfReady(context, path);
  }

  /// Gallery → edge crop.
  static Future<String?> scanFromGallery(BuildContext context) async {
    String? path;
    if (isMobilePlatform) {
      path = await _scan(source: ScannerSource.gallery);
    }
    path ??= await pickNormalGallery();
    return _enhanceIfReady(context, path);
  }

  static Future<String?> _scan({
    required ScannerSource source,
    int noOfPages = 1,
  }) async {
    if (_scanInFlight) return null;
    _scanInFlight = true;
    try {
      final paths = await CunningDocumentScanner.getPictures(
        noOfPages: noOfPages,
        scannerSource: source,
        // base is lighter / more stable on many devices than full ML Kit UI.
        androidScannerMode: AndroidScannerMode.base,
      );
      if (paths != null && paths.isNotEmpty) return paths.first;
    } catch (_) {
      // Fallback to full mode if base is unavailable on this device.
      try {
        final paths = await CunningDocumentScanner.getPictures(
          noOfPages: noOfPages,
          scannerSource: source == ScannerSource.gallery
              ? ScannerSource.cameraAndGallery
              : source,
          androidScannerMode: AndroidScannerMode.full,
        );
        if (paths != null && paths.isNotEmpty) return paths.first;
      } catch (_) {}
    } finally {
      _scanInFlight = false;
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

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return [];

    List<String>? paths;
    if (_scanInFlight) return [];
    _scanInFlight = true;
    try {
      paths = await CunningDocumentScanner.getPictures(
        noOfPages: remaining.clamp(1, 10),
        scannerSource: choice == 'gallery_scan'
            ? ScannerSource.gallery
            : ScannerSource.camera,
        androidScannerMode: AndroidScannerMode.base,
      );
    } catch (_) {
      try {
        paths = await CunningDocumentScanner.getPictures(
          noOfPages: remaining.clamp(1, 10),
          scannerSource: choice == 'gallery_scan'
              ? ScannerSource.gallery
              : ScannerSource.camera,
          androidScannerMode: AndroidScannerMode.full,
        );
      } catch (_) {
        paths = null;
      }
    } finally {
      _scanInFlight = false;
    }

    if (paths == null || paths.isEmpty || !context.mounted) return [];

    await _waitForSurfaceReady(context);
    if (!context.mounted) return [];

    final out = <String>[];
    for (final p in paths.take(remaining)) {
      if (!context.mounted) break;
      final enhanced =
          await DocumentEnhanceSheet.show(context, imagePath: p);
      if (enhanced != null) out.add(enhanced);
      // Small gap so the next page open doesn't race the previous pop.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return out;
  }
}
