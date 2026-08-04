import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Fetches and caches FX rates (open.er-api.com). Convert any supported
/// currency into the profile home currency for transaction entry.
class ExchangeRateService extends ChangeNotifier {
  ExchangeRateService._();
  static final ExchangeRateService instance = ExchangeRateService._();

  static const _cacheKeyPrefix = 'fx_rates_';
  static const _cacheTimePrefix = 'fx_rates_time_';
  static const Duration staleAfter = Duration(hours: 24);

  String? _base;
  Map<String, double> _rates = {};
  DateTime? _lastUpdated;
  bool _loading = false;
  String? _lastError;

  String? get base => _base;
  Map<String, double> get rates => Map.unmodifiable(_rates);
  DateTime? get lastUpdated => _lastUpdated;
  bool get loading => _loading;
  String? get lastError => _lastError;

  bool get isStale {
    if (_lastUpdated == null) return true;
    return DateTime.now().difference(_lastUpdated!) > staleAfter;
  }

  Future<void> ensureRates(String homeCurrency, {bool forceRefresh = false}) async {
    final base = homeCurrency.toUpperCase();
    if (!forceRefresh &&
        _base == base &&
        _rates.isNotEmpty &&
        !isStale) {
      return;
    }
    await _loadCache(base);
    if (!forceRefresh && _rates.isNotEmpty && !isStale) {
      notifyListeners();
      return;
    }
    await refresh(base);
  }

  Future<void> refresh(String homeCurrency) async {
    final base = homeCurrency.toUpperCase();
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final uri = Uri.parse('https://open.er-api.com/v6/latest/$base');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw 'HTTP ${res.statusCode}';
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (map['result']?.toString() != 'success') {
        throw map['error-type']?.toString() ?? 'Rate fetch failed';
      }
      final raw = map['rates'];
      if (raw is! Map) throw 'Invalid rates payload';
      final parsed = <String, double>{};
      raw.forEach((k, v) {
        final n = (v is num) ? v.toDouble() : double.tryParse('$v');
        if (n != null && n > 0) parsed[k.toString().toUpperCase()] = n;
      });
      parsed[base] = 1.0;
      _base = base;
      _rates = parsed;
      _lastUpdated = DateTime.now();
      await _saveCache(base);
    } catch (e) {
      _lastError = e.toString();
      if (_rates.isEmpty) {
        await _loadCache(base);
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Rate: 1 [from] = ? [to] (home usually = [to]).
  double? rate({required String from, required String to}) {
    final f = from.toUpperCase();
    final t = to.toUpperCase();
    if (f == t) return 1.0;
    if (_base == null || _rates.isEmpty) return null;

    // API returns rates with _base as 1.0 → other currencies.
    // amount_in_base = amount_from / rates[from]
    // amount_to = amount_in_base * rates[to]
    // so 1 from → to = rates[to] / rates[from]
    final rf = f == _base ? 1.0 : _rates[f];
    final rt = t == _base ? 1.0 : _rates[t];
    if (rf == null || rt == null || rf <= 0) return null;
    return rt / rf;
  }

  double? convert({
    required String from,
    required String to,
    required double amount,
    double? manualRate,
  }) {
    if (manualRate != null && manualRate > 0) {
      return amount * manualRate;
    }
    final r = rate(from: from, to: to);
    if (r == null) return null;
    return amount * r;
  }

  Future<void> _loadCache(String base) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('$_cacheKeyPrefix$base');
    final timeMs = prefs.getInt('$_cacheTimePrefix$base');
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final parsed = <String, double>{};
      map.forEach((k, v) {
        final n = (v is num) ? v.toDouble() : double.tryParse('$v');
        if (n != null && n > 0) parsed[k.toUpperCase()] = n;
      });
      if (parsed.isEmpty) return;
      _base = base;
      _rates = parsed;
      if (timeMs != null) {
        _lastUpdated = DateTime.fromMillisecondsSinceEpoch(timeMs);
      }
    } catch (_) {}
  }

  Future<void> _saveCache(String base) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cacheKeyPrefix$base', jsonEncode(_rates));
    await prefs.setInt(
      '$_cacheTimePrefix$base',
      (_lastUpdated ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }
}
