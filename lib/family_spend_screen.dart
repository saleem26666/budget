import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'services/currency_service.dart';
import 'utils/category_ledger.dart';

class FamilyMemberSpend {
  final String name;
  final double expense;
  final double income;
  final int txCount;

  const FamilyMemberSpend({
    required this.name,
    required this.expense,
    required this.income,
    required this.txCount,
  });

  double get net => income - expense;
}

/// Monthly spend breakdown by Vault family member tag on transactions.
class FamilySpendScreen extends StatefulWidget {
  final List<Map<String, dynamic>> transactions;

  const FamilySpendScreen({super.key, required this.transactions});

  @override
  State<FamilySpendScreen> createState() => _FamilySpendScreenState();
}

class _FamilySpendScreenState extends State<FamilySpendScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  List<FamilyMemberSpend> _compute() {
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
    final map = <String, FamilyMemberSpend>{};

    for (final tx in widget.transactions) {
      final member = (tx['member_name'] ?? '').toString().trim();
      if (member.isEmpty) continue;
      final date = DateTime.tryParse(tx['date']?.toString() ?? '');
      if (date == null) continue;
      if (date.isBefore(start) || date.isAfter(end)) continue;

      final type = (tx['type'] ?? '').toString();
      final amount = (tx['amount'] ?? 0).toDouble();
      final prev = map[member] ??
          FamilyMemberSpend(name: member, expense: 0, income: 0, txCount: 0);

      double expense = prev.expense;
      double income = prev.income;
      if (type == 'Expense') {
        expense += amount;
      } else if (type == 'Income') {
        income += amount;
      } else if (type == 'Transfer') {
        // Count budget-impacting transfers toward the tagged member.
        final contrib = CategoryLedger.budgetSpentContribution(tx);
        if (contrib > 0) expense += contrib;
        if (contrib < 0) income += -contrib;
      }

      map[member] = FamilyMemberSpend(
        name: member,
        expense: expense,
        income: income,
        txCount: prev.txCount + 1,
      );
    }

    final list = map.values.toList()
      ..sort((a, b) => b.expense.compareTo(a.expense));
    return list;
  }

  double get _untaggedExpense {
    final start = _month;
    final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
    double total = 0;
    for (final tx in widget.transactions) {
      final member = (tx['member_name'] ?? '').toString().trim();
      if (member.isNotEmpty) continue;
      if ((tx['type'] ?? '') != 'Expense') continue;
      final date = DateTime.tryParse(tx['date']?.toString() ?? '');
      if (date == null) continue;
      if (date.isBefore(start) || date.isAfter(end)) continue;
      total += (tx['amount'] ?? 0).toDouble();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _compute();
    final maxExpense = rows.isEmpty
        ? 1.0
        : rows.map((e) => e.expense).fold<double>(0, (a, b) => a > b ? a : b);
    final taggedTotal =
        rows.fold<double>(0, (s, e) => s + e.expense);
    final untagged = _untaggedExpense;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Family spend'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: _statCard(
                    context,
                    'Tagged spend',
                    CurrencyService.fmt(taggedTotal),
                    AppTheme.expense,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statCard(
                    context,
                    'Untagged',
                    CurrencyService.fmt(untagged),
                    Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Uses Family member tags on Wallet transactions. Tag spending when you add income/expense.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.family_restroom_rounded,
                              size: 56,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 12),
                          const Text(
                            'No tagged spending this month',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'In New Transaction, pick a Family member from Vault to see their share here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: rows.length,
                    itemBuilder: (_, i) {
                      final m = rows[i];
                      final pct =
                          maxExpense <= 0 ? 0.0 : m.expense / maxExpense;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.primary
                                        .withValues(alpha: 0.12),
                                    child: Text(
                                      m.name.isNotEmpty
                                          ? m.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${m.txCount} transaction${m.txCount == 1 ? '' : 's'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    CurrencyService.fmt(m.expense),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.expense,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: pct.clamp(0.0, 1.0),
                                  minHeight: 8,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  color: AppTheme.expense,
                                ),
                              ),
                              if (m.income > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Income tagged: ${CurrencyService.fmt(m.income)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.income,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
      BuildContext context, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
