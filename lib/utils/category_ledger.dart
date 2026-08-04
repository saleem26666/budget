/// Category ledger math shared by Reports and budget alerts.
/// Income → +, Expense → −, Transfer uses [category_effect] (+ or −).
class CategoryLedger {
  CategoryLedger._();

  /// Returns '+' / '-' or null if transfer should not affect category.
  static String? normalizeEffect(dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    if (s == '+' || s.toLowerCase() == 'plus' || s.toLowerCase() == 'add') {
      return '+';
    }
    // ASCII hyphen, Unicode minus (U+2212), en-dash
    if (s == '-' ||
        s == '−' ||
        s == '–' ||
        s.toLowerCase() == 'minus' ||
        s.toLowerCase() == 'sub') {
      return '-';
    }
    return null;
  }

  static bool categoryEquals(dynamic a, dynamic b) =>
      (a?.toString().trim() ?? '') == (b?.toString().trim() ?? '');

  static double amountOf(Map<String, dynamic> t) =>
      (t['amount'] ?? 0).toDouble();

  /// Signed change to a category balance for one transaction.
  /// [onlyForCategory] null = any category (caller already filtered).
  static double signedChange(
    Map<String, dynamic> t, {
    String? onlyForCategory,
  }) {
    if (onlyForCategory != null &&
        !categoryEquals(t['category'], onlyForCategory)) {
      return 0;
    }
    final amt = amountOf(t);
    final type = (t['type'] ?? '').toString().trim();
    if (type == 'Income') return amt;
    if (type == 'Expense') return -amt;
    if (type == 'Transfer') {
      final effect = normalizeEffect(t['category_effect']);
      if (effect == '+') return amt;
      if (effect == '-') return -amt;
      return 0;
    }
    return 0;
  }

  /// Amount that counts as "spent" against a category budget this month.
  /// Expense and Transfer(−) increase spent; Income and Transfer(+) reduce it.
  static double budgetSpentContribution(Map<String, dynamic> t) {
    final change = signedChange(t);
    // spent increases when category balance goes down
    return -change;
  }
}
