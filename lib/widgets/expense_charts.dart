import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/budget_alert_service.dart';
import '../services/currency_service.dart';

class ExpenseCharts extends StatelessWidget {
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> categories;
  final String selectedCategory;
  /// Total Out from report summary (expenses in period) — shown for cross-check.
  final double? periodExpenseTotal;

  const ExpenseCharts({
    super.key,
    required this.transactions,
    this.categories = const [],
    this.selectedCategory = 'All Categories',
    this.periodExpenseTotal,
  });

  static const _colors = [
    AppTheme.primary,
    AppTheme.expense,
    AppTheme.income,
    AppTheme.transfer,
    AppTheme.accent,
    Color(0xFF8B5CF6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF0D9488),
  ];

  bool get _singleCategory =>
      selectedCategory != 'All Categories' && selectedCategory.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final Map<String, double> categoryData;
    if (_singleCategory) {
      final catTotal = BudgetAlertService.categoryExpenses(transactions)[
              selectedCategory] ??
          transactions
              .where((t) =>
                  t['type'] == 'Expense' &&
                  t['category'] == selectedCategory)
              .fold<double>(
                  0.0, (s, t) => s + (t['amount'] ?? 0).toDouble());
      categoryData = {selectedCategory: catTotal};
    } else {
      categoryData = BudgetAlertService.categoryExpenses(transactions);
    }

    final subData = BudgetAlertService.subCategoryExpenses(
      transactions,
      forCategory: _singleCategory ? selectedCategory : null,
    );
    final nestedBreakdown = BudgetAlertService.categorySubCategoryBreakdown(
      transactions,
      forCategory: _singleCategory ? selectedCategory : null,
      categoryDefinitions: categories,
    );

    if (categoryData.isEmpty && subData.isEmpty && nestedBreakdown.isEmpty) {
      return const SizedBox.shrink();
    }

    final categoryTotal =
        categoryData.values.fold(0.0, (a, b) => a + b);
    final subTotal = subData.values.fold(0.0, (a, b) => a + b);
    final reportOut = periodExpenseTotal;
    final showReconcile = reportOut != null &&
        !_singleCategory &&
        (reportOut - categoryTotal).abs() > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_singleCategory && categoryData.isNotEmpty) ...[
          _sectionTitle(context, 'Category expenses'),
          Text(
            'Total: ${CurrencyService.fmt(categoryTotal)}'
            '${reportOut != null ? '  •  Report expenses: ${CurrencyService.fmt(reportOut)}' : ''}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: showReconcile ? AppTheme.expense : Colors.grey.shade700,
            ),
          ),
          if (showReconcile)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Tip: Some expenses may use a category name not in Settings, or '
                'Income/Transfer rows are excluded from this chart.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 36,
                      sections: _pieSections(categoryData),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _legendWithAmounts(categoryData),
                ),
              ],
            ),
          ),
        ],
        if (_singleCategory && categoryTotal > 0) ...[
          _sectionTitle(context, '$selectedCategory — total'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.12),
                  AppTheme.accent.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
            ),
            child: Text(
              CurrencyService.fmt(categoryTotal),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
        if (subData.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionTitle(
            context,
            _singleCategory
                ? 'Sub-categories ($selectedCategory)'
                : 'Sub-category expenses',
          ),
          Text(
            'Sub-total: ${CurrencyService.fmt(subTotal)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ...subData.entries.map((e) => _subCategoryRow(e.key, e.value, subTotal)),
          const SizedBox(height: 12),
          SizedBox(
            height: (subData.length * 44.0).clamp(140, 320),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: subData.values.reduce((a, b) => a > b ? a : b) * 1.25,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final keys = subData.keys.toList();
                        final i = value.toInt();
                        if (i < 0 || i >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        final amt = subData[keys[i]]!;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            _shortAmount(amt),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final keys = subData.keys.toList();
                        final i = value.toInt();
                        if (i < 0 || i >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        final label = keys[i];
                        final short = label.length > 10
                            ? '${label.substring(0, 8)}…'
                            : label;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            short,
                            style: const TextStyle(fontSize: 9),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: subData.entries.toList().asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: _colors[e.key % _colors.length],
                        width: 18,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
        if (nestedBreakdown.isNotEmpty && !_singleCategory) ...[
          const SizedBox(height: 20),
          _sectionTitle(
            context,
            _singleCategory
                ? 'Sub-category report ($selectedCategory)'
                : 'Category & sub-category report',
          ),
          ...nestedBreakdown.entries.map(
            (catEntry) => _categorySubBlock(catEntry.key, catEntry.value),
          ),
        ],
      ],
    );
  }

  String _shortAmount(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _categorySubBlock(String category, Map<String, double> subs) {
    final catTotal = subs.values.fold(0.0, (a, b) => a + b);
    if (catTotal <= 0 && subs.values.every((v) => v == 0)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              Text(
                CurrencyService.fmt(catTotal),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...subs.entries
              .where((e) => e.value > 0)
              .map((e) => _subCategoryRow(e.key, e.value, catTotal)),
        ],
      ),
    );
  }

  Widget _subCategoryRow(String name, double amount, double total) {
    final pct = total == 0 ? 0.0 : (amount / total) * 100;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              CurrencyService.fmt(amount),
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  List<PieChartSectionData> _pieSections(Map<String, double> data) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    return data.entries.toList().asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final pct = total == 0 ? 0.0 : (e.value / total) * 100;
      return PieChartSectionData(
        value: e.value,
        title: '${pct.toStringAsFixed(0)}%',
        color: _colors[i % _colors.length],
        radius: 52,
        titleStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _legendWithAmounts(Map<String, double> data) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    return ListView(
      children: data.entries.toList().asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final pct = total == 0 ? 0.0 : (e.value / total) * 100;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _colors[i % _colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Text(
                  '${CurrencyService.fmt(e.value)} (${pct.toStringAsFixed(0)}%)',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
