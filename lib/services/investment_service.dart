import 'package:flutter/material.dart';

/// Portfolio calculations & asset-type metadata.
class InvestmentService {
  InvestmentService._();

  static const assetTypes = [
    'Stocks',
    'Mutual Fund',
    'Gold',
    'Crypto',
    'Bonds',
    'Property',
    'Other',
  ];

  static double qty(Map<String, dynamic> h) =>
      (h['quantity'] ?? 0).toDouble();

  static double avgBuy(Map<String, dynamic> h) =>
      (h['avg_buy_price'] ?? 0).toDouble();

  static double currentPrice(Map<String, dynamic> h) =>
      (h['current_price'] ?? h['avg_buy_price'] ?? 0).toDouble();

  static double invested(Map<String, dynamic> h) => qty(h) * avgBuy(h);

  static double marketValue(Map<String, dynamic> h) => qty(h) * currentPrice(h);

  static double gainLoss(Map<String, dynamic> h) =>
      marketValue(h) - invested(h);

  static double gainPct(Map<String, dynamic> h) {
    final inv = invested(h);
    if (inv <= 0) return 0;
    return (gainLoss(h) / inv) * 100;
  }

  static Map<String, double> allocationByType(
      List<Map<String, dynamic>> holdings) {
    final map = <String, double>{};
    for (final h in holdings) {
      final type = (h['asset_type'] ?? 'Other').toString();
      map[type] = (map[type] ?? 0) + marketValue(h);
    }
    return map;
  }

  static Map<String, dynamic> portfolioSummary(
      List<Map<String, dynamic>> holdings) {
    double investedTotal = 0;
    double valueTotal = 0;
    for (final h in holdings) {
      investedTotal += invested(h);
      valueTotal += marketValue(h);
    }
    final gl = valueTotal - investedTotal;
    final pct = investedTotal <= 0 ? 0.0 : (gl / investedTotal) * 100;
    return {
      'invested': investedTotal,
      'value': valueTotal,
      'gainLoss': gl,
      'gainPct': pct,
      'count': holdings.length,
    };
  }

  static IconData iconForType(String type) {
    switch (type) {
      case 'Stocks':
        return Icons.show_chart_rounded;
      case 'Mutual Fund':
        return Icons.pie_chart_rounded;
      case 'Gold':
        return Icons.monetization_on_rounded;
      case 'Crypto':
        return Icons.currency_bitcoin_rounded;
      case 'Bonds':
        return Icons.account_balance_rounded;
      case 'Property':
        return Icons.home_work_rounded;
      default:
        return Icons.savings_rounded;
    }
  }

  static Color colorForType(String type) {
    switch (type) {
      case 'Stocks':
        return const Color(0xFF3B82F6);
      case 'Mutual Fund':
        return const Color(0xFF8B5CF6);
      case 'Gold':
        return const Color(0xFFF59E0B);
      case 'Crypto':
        return const Color(0xFFF97316);
      case 'Bonds':
        return const Color(0xFF0D9488);
      case 'Property':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF64748B);
    }
  }
}
