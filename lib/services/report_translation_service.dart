import 'package:translator/translator.dart';

/// Urdu report labels + reliable en→ur for user text.
class ReportTranslationService {
  static final GoogleTranslator _translator = GoogleTranslator();

  static const Map<String, String> fixedUrdu = {
    'All Accounts': 'تمام اکاؤنٹس',
    'All Categories': 'تمام کیٹگریز',
    'All Time': 'تمام وقت',
    'Income': 'آمدنی',
    'Expense': 'خرچ',
    'Transfer': 'ٹرانسفر',
    'No Title': 'بلا عنوان',
    'Cash': 'نقد',
    'Opening': 'ابتدائی',
    'Total In': 'کل آمدنی',
    'Total Out': 'کل خرچ',
    'CURRENT BALANCE': 'موجودہ بیلنس',
  };

  static bool hasUrduScript(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  static bool shouldSkipTranslate(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (double.tryParse(t.replaceAll(',', '')) != null) return true;
    if (RegExp(r'^[A-Z]{3}\s*[\d.,+-]+$').hasMatch(t)) return true;
    if (RegExp(r'^[\d.,+\-]+$').hasMatch(t)) return true;
    return false;
  }

  static String fixedOrSelf(String text) {
    final t = text.trim();
    return fixedUrdu[t] ?? t;
  }

  static Future<String> toUrdu(String text) async {
    final t = text.trim();
    if (t.isEmpty || shouldSkipTranslate(t)) return t;
    if (fixedUrdu.containsKey(t)) return fixedUrdu[t]!;
    if (hasUrduScript(t)) return t;

    try {
      final result = await _translator.translate(
        t,
        from: 'en',
        to: 'ur',
      );
      return result.text.trim().isEmpty ? t : result.text;
    } catch (_) {
      return t;
    }
  }

  static Future<String> typeLabelUrdu(String type, {String? account, String? toAccount, String? selectedAccount}) async {
    if (type == 'Income') return fixedUrdu['Income']!;
    if (type == 'Expense') return fixedUrdu['Expense']!;
    if (type == 'Transfer') {
      if (selectedAccount != null && toAccount == selectedAccount) {
        final from = await toUrdu((account ?? '').toString());
        return 'ٹرانسفر (وصول: $from سے)';
      }
      if (selectedAccount != null && account == selectedAccount) {
        final to = await toUrdu((toAccount ?? '').toString());
        return 'ٹرانسفر (بھیجا: $to کو)';
      }
      return fixedUrdu['Transfer']!;
    }
    return await toUrdu(type);
  }
}
