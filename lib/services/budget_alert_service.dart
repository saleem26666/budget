import '../utils/category_utils.dart';
import '../utils/category_ledger.dart';
import 'currency_service.dart';

class BudgetAlert {
  final String category;
  final String? subCategory;
  final double spent;
  final double budget;
  final double percent;
  final bool isOverBudget;
  final bool isNearLimit;

  BudgetAlert({
    required this.category,
    this.subCategory,
    required this.spent,
    required this.budget,
    required this.percent,
    required this.isOverBudget,
    required this.isNearLimit,
  });

  String get title => subCategory == null
      ? category
      : '$category › $subCategory';

  String get message {
    if (isOverBudget) {
      return 'Over budget by ${CurrencyService.fmt(spent - budget)}';
    }
    return '${percent.toStringAsFixed(0)}% used — ${CurrencyService.fmt(budget - spent)} left';
  }
}

class BudgetAlertService {
  static const double nearLimitThreshold = 0.85;

  static List<BudgetAlert> evaluate({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> categories,
  }) {
    final alerts = <BudgetAlert>[];
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    for (final cat in categories) {
      final catName = cat['name']?.toString() ?? '';
      final budget = (cat['budget'] ?? 0).toDouble();
      if (budget <= 0 || catName.isEmpty) continue;

      final spent = _monthCategorySpent(
        transactions: transactions,
        monthStart: monthStart,
        monthEnd: monthEnd,
        category: catName,
      );

      final percent = budget == 0 ? 0.0 : (spent / budget) * 100.0;
      if (percent >= nearLimitThreshold * 100) {
        alerts.add(BudgetAlert(
          category: catName,
          spent: spent,
          budget: budget,
          percent: percent,
          isOverBudget: spent > budget,
          isNearLimit: spent <= budget && percent >= nearLimitThreshold * 100,
        ));
      }

      for (final sub in parseSubCategories(cat['sub_categories'])) {
        final subSpent = _monthCategorySpent(
          transactions: transactions,
          monthStart: monthStart,
          monthEnd: monthEnd,
          category: catName,
          subCategory: sub,
        );
        if (subSpent <= 0) continue;
        final subBudget = budget / (parseSubCategories(cat['sub_categories']).length.clamp(1, 99));
        final subPercent = subBudget == 0 ? 0.0 : (subSpent / subBudget) * 100.0;
        if (subPercent >= nearLimitThreshold * 100) {
          alerts.add(BudgetAlert(
            category: catName,
            subCategory: sub,
            spent: subSpent,
            budget: subBudget,
            percent: subPercent,
            isOverBudget: subSpent > subBudget,
            isNearLimit: subSpent <= subBudget && subPercent >= nearLimitThreshold * 100,
          ));
        }
      }
    }

    alerts.sort((a, b) {
      if (a.isOverBudget != b.isOverBudget) return a.isOverBudget ? -1 : 1;
      return b.percent.compareTo(a.percent);
    });
    return alerts;
  }

  /// Expense + Transfer(−) raise spent; Income + Transfer(+) lower spent.
  static double _monthCategorySpent({
    required List<Map<String, dynamic>> transactions,
    required DateTime monthStart,
    required DateTime monthEnd,
    required String category,
    String? subCategory,
  }) {
    double total = 0;
    for (final tx in transactions) {
      if (!CategoryLedger.categoryEquals(tx['category'], category)) continue;
      if (subCategory != null &&
          (tx['sub_category'] ?? '').toString() != subCategory) {
        continue;
      }
      final date = DateTime.tryParse(tx['date']?.toString() ?? '');
      if (date == null) continue;
      if (date.isBefore(monthStart) || date.isAfter(monthEnd)) continue;
      total += CategoryLedger.budgetSpentContribution(tx);
    }
    return total < 0 ? 0 : total;
  }

  static Map<String, double> categoryExpenses(
    List<Map<String, dynamic>> transactions, {
    String type = 'Expense',
  }) {
    final map = <String, double>{};
    for (final tx in transactions) {
      if (tx['type'] != type) continue;
      final key = (tx['category'] ?? 'Other').toString();
      map[key] = (map[key] ?? 0) + (tx['amount'] ?? 0).toDouble();
    }
    return map;
  }

  static Map<String, double> subCategoryExpenses(
    List<Map<String, dynamic>> transactions, {
    String? forCategory,
  }) {
    final map = <String, double>{};
    for (final tx in transactions) {
      if (tx['type'] != 'Expense') continue;
      final cat = (tx['category'] ?? '').toString();
      if (forCategory != null && cat != forCategory) continue;

      final sub = (tx['sub_category'] ?? '').toString().trim();
      final key = forCategory != null
          ? (sub.isEmpty ? '(No sub-category)' : sub)
          : (sub.isEmpty ? '$cat › (No sub-category)' : '$cat › $sub');
      map[key] = (map[key] ?? 0) + (tx['amount'] ?? 0).toDouble();
    }
    return map;
  }

  /// Category → sub-category expense totals for reports.
  static Map<String, Map<String, double>> categorySubCategoryBreakdown(
    List<Map<String, dynamic>> transactions, {
    String? forCategory,
    List<Map<String, dynamic>>? categoryDefinitions,
  }) {
    final result = <String, Map<String, double>>{};

    void add(String cat, String sub, double amount) {
      if (forCategory != null && cat != forCategory) return;
      result.putIfAbsent(cat, () => {});
      result[cat]![sub] = (result[cat]![sub] ?? 0) + amount;
    }

    for (final tx in transactions) {
      if (tx['type'] != 'Expense') continue;
      final cat = (tx['category'] ?? 'Other').toString();
      final sub = (tx['sub_category'] ?? '').toString().trim();
      add(cat, sub.isEmpty ? '(No sub-category)' : sub, _txAmount(tx));
    }

    if (categoryDefinitions != null) {
      for (final cat in categoryDefinitions) {
        final catName = cat['name']?.toString() ?? '';
        if (catName.isEmpty) continue;
        if (forCategory != null && catName != forCategory) continue;
        result.putIfAbsent(catName, () => {});
        for (final sub in parseSubCategories(cat['sub_categories'])) {
          result[catName]!.putIfAbsent(sub, () => 0);
        }
      }
    }

    for (final subs in result.values) {
      final keys = subs.keys.toList()
        ..sort((a, b) {
          if (a == '(No sub-category)') return 1;
          if (b == '(No sub-category)') return -1;
          return a.compareTo(b);
        });
      final sorted = {for (final k in keys) k: subs[k]!};
      subs
        ..clear()
        ..addAll(sorted);
    }

    final ordered = Map.fromEntries(
      result.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    return ordered;
  }

  static double _txAmount(Map<String, dynamic> tx) =>
      (tx['amount'] ?? 0).toDouble();
}
