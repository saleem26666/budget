import 'package:translator/translator.dart';

/// Translates spoken text (Urdu / Roman Urdu) into English.
class VoiceTranslateHelper {
  static final GoogleTranslator _translator = GoogleTranslator();

  static bool looksUrdu(String text) =>
      RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  static Future<String> translateTo(
    String text, {
    required String targetLang,
    String from = 'auto',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    try {
      final result = await _translator.translate(
        trimmed,
        from: from,
        to: targetLang,
      );
      return result.text.trim().isEmpty ? trimmed : result.text;
    } catch (_) {
      return trimmed;
    }
  }

  /// Urdu speech → English text for diary / notes.
  static Future<String> urduToEnglish(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    const attempts = <(String, String)>[
      ('ur', 'en'),
      ('hi', 'en'),
      ('auto', 'en'),
    ];

    for (final (from, to) in attempts) {
      try {
        final result = await _translator.translate(trimmed, from: from, to: to);
        final out = result.text.trim();
        if (out.isEmpty) continue;
        if (out != trimmed && !looksUrdu(out)) return out;
        if (!_looksMostlySame(out, trimmed)) return out;
      } catch (_) {}
    }
    return trimmed;
  }

  static bool _looksMostlySame(String a, String b) =>
      a.toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ==
      b.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
