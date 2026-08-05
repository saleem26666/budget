import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class DocumentOcrResult {
  final String fullText;
  final String? cnic;
  final String? amountHint;
  /// Best guess for a business-card main heading (name / company).
  final String? heading;
  final List<String> lines;

  const DocumentOcrResult({
    required this.fullText,
    this.cnic,
    this.amountHint,
    this.heading,
    this.lines = const [],
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
      final lines = _collectLines(recognized);
      return DocumentOcrResult(
        fullText: text,
        cnic: _findCnic(text),
        amountHint: _findAmount(text),
        heading: suggestBusinessCardHeading(lines),
        lines: lines,
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static List<String> _collectLines(RecognizedText recognized) {
    final out = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final t = line.text.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    if (out.isEmpty) {
      for (final part in recognized.text.split(RegExp(r'[\r\n]+'))) {
        final t = part.trim();
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  /// Picks the main heading (usually person / company name) from OCR lines.
  static String? suggestBusinessCardHeading(List<String> lines) {
    if (lines.isEmpty) return null;

    String? best;
    var bestScore = -1.0;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i].trim();
      if (raw.length < 2 || raw.length > 60) continue;
      if (_looksLikeContactOrNoise(raw)) continue;

      var score = 40.0 - (i * 2.5); // prefer top lines
      score += (raw.length.clamp(3, 28)) * 0.6;

      if (RegExp(r'^(Dr\.?|Prof\.?|Mr\.?|Mrs\.?|Ms\.?|Engr\.?|Sir)\b',
              caseSensitive: false)
          .hasMatch(raw)) {
        score += 28;
      }
      if (raw == raw.toUpperCase() &&
          RegExp(r'[A-Za-z]').hasMatch(raw) &&
          raw.length <= 36) {
        score += 12;
      }
      // Title-ish: few digits
      final digits = RegExp(r'\d').allMatches(raw).length;
      if (digits == 0) score += 8;
      if (digits > 4) score -= 15;

      // Prefer multi-word person names
      final words = raw.split(RegExp(r'\s+'));
      if (words.length >= 2 && words.length <= 5) score += 10;

      if (score > bestScore) {
        bestScore = score;
        best = raw;
      }
    }

    return best;
  }

  static bool _looksLikeContactOrNoise(String t) {
    final lower = t.toLowerCase();
    if (lower.contains('@') || lower.contains('www.') || lower.contains('http')) {
      return true;
    }
    if (RegExp(r'\b(email|phone|tel|fax|mobile|cell|whatsapp|address|street|'
            r'road|city|pakistan|pk|llc|pvt|ltd|inc)\b',
            caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    // Mostly a phone number
    final digits = RegExp(r'\d').allMatches(t).length;
    if (digits >= 7 && digits >= t.replaceAll(RegExp(r'\s'), '').length * 0.5) {
      return true;
    }
    // CNIC-like
    if (RegExp(r'\b\d{5}[-\s]?\d{7}[-\s]?\d\b').hasMatch(t)) return true;
    return false;
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
