import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppCurrency {
  final String code;
  final String symbol;
  final String name;
  final int decimalDigits;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.name,
    this.decimalDigits = 0,
  });

  String get label => '$name ($code)';
}

/// Profile-wise currency preference + formatting for the whole app.
class CurrencyService extends ChangeNotifier {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  static const String defaultCode = 'PKR';

  static const List<AppCurrency> currencies = [
    AppCurrency(code: 'PKR', symbol: 'Rs', name: 'Pakistani Rupee'),
    AppCurrency(code: 'USD', symbol: r'$', name: 'US Dollar', decimalDigits: 2),
    AppCurrency(code: 'EUR', symbol: '€', name: 'Euro', decimalDigits: 2),
    AppCurrency(code: 'GBP', symbol: '£', name: 'British Pound', decimalDigits: 2),
    AppCurrency(code: 'AED', symbol: 'AED', name: 'UAE Dirham'),
    AppCurrency(code: 'SAR', symbol: 'SAR', name: 'Saudi Riyal'),
    AppCurrency(code: 'INR', symbol: '₹', name: 'Indian Rupee'),
    AppCurrency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka'),
    AppCurrency(code: 'CAD', symbol: r'C$', name: 'Canadian Dollar', decimalDigits: 2),
    AppCurrency(code: 'AUD', symbol: r'A$', name: 'Australian Dollar', decimalDigits: 2),
    AppCurrency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan'),
    AppCurrency(code: 'TRY', symbol: '₺', name: 'Turkish Lira'),
    AppCurrency(code: 'QAR', symbol: 'QAR', name: 'Qatari Riyal'),
    AppCurrency(code: 'KWD', symbol: 'KWD', name: 'Kuwaiti Dinar', decimalDigits: 3),
    AppCurrency(code: 'OMR', symbol: 'OMR', name: 'Omani Rial', decimalDigits: 3),
  ];

  String _code = defaultCode;
  String? _profileId;

  String get code => _code;

  AppCurrency get current =>
      currencies.firstWhere((c) => c.code == _code, orElse: () => currencies.first);

  String _prefKey(String profileId) => '${profileId}_currency_code';

  Future<void> loadForProfile(String profileId) async {
    _profileId = profileId;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey(profileId));
    _code = _isValidCode(saved) ? saved! : defaultCode;
    notifyListeners();
  }

  Future<void> setCurrency(String code, {String? profileId}) async {
    final pid = profileId ?? _profileId;
    if (pid == null || !_isValidCode(code)) return;
    _code = code;
    _profileId = pid;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(pid), code);
    notifyListeners();
  }

  bool _isValidCode(String? code) =>
      code != null && currencies.any((c) => c.code == code);

  String _patternFor(AppCurrency currency) {
    final digits = currency.decimalDigits;
    return digits > 0 ? '#,##0.${'0' * digits}' : '#,##0';
  }

  String _pattern() => _patternFor(current);

  String formatNumber(num amount) => NumberFormat(_pattern()).format(amount);

  /// Preview / format using a specific currency (not the active preference).
  String formatFor(AppCurrency currency, num amount, {bool compact = false}) {
    final formatted = NumberFormat(_patternFor(currency)).format(amount);
    if (compact) return '${currency.symbol} $formatted';
    return '${currency.code} $formatted';
  }

  String format(num amount, {bool compact = false}) =>
      formatFor(current, amount, compact: compact);

  String amountLabel() => 'Amount (${current.code})';

  String priceLabel([String kind = 'Price']) => '$kind (${current.code})';

  static String fmt(num amount) => instance.format(amount);
}
