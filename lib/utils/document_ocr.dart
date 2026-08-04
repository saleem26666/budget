import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DocumentOcrResult {
  final String fullText;
  final String? cnic;
  final String? amountHint;

  const DocumentOcrResult({
    required this.fullText,
    this.cnic,
    this.amountHint,
  });

  bool get hasHints =>
      (cnic != null && cnic!.isNotEmpty) ||
      (amountHint != null && amountHint!.isNotEmpty);
}

/// On-device OCR (Android/iOS). No-op friendly on desktop.
class DocumentOcr {
  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<DocumentOcrResult?> recognize(String imagePath) async {
    if (!isSupported) return null;
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final input = InputImage.fromFilePath(imagePath);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognized = await recognizer.processImage(input);
      final text = recognized.text.trim();
      if (text.isEmpty) {
        return const DocumentOcrResult(fullText: '');
      }
      return DocumentOcrResult(
        fullText: text,
        cnic: _findCnic(text),
        amountHint: _findAmount(text),
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  /// Pakistani CNIC: 12345-1234567-1
  static String? _findCnic(String text) {
    final re = RegExp(r'\b\d{5}[-\s]?\d{7}[-\s]?\d\b');
    final m = re.firstMatch(text.replaceAll('\n', ' '));
    if (m == null) return null;
    final raw = m.group(0)!.replaceAll(RegExp(r'\s'), '');
    if (raw.contains('-')) return raw;
    if (raw.length == 13) {
      return '${raw.substring(0, 5)}-${raw.substring(5, 12)}-${raw.substring(12)}';
    }
    return raw;
  }

  static String? _findAmount(String text) {
    final patterns = [
      RegExp(
          r'(?:PKR|Rs\.?|USD|AED|SAR|INR|Total|Amount|Paid)\s*[:.]?\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})|[0-9]+(?:\.[0-9]{1,2})?)',
          caseSensitive: false),
      RegExp(r'\b([0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{1,2})?)\b'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(text);
      if (m != null) {
        final g = m.groupCount >= 1 ? m.group(1) : m.group(0);
        if (g != null && g.trim().isNotEmpty) return g.trim();
      }
    }
    return null;
  }
}
