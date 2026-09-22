import '../database_helper.dart';

class RecurringPostResult {
  final int postedCount;
  final List<String> titles;
  const RecurringPostResult({required this.postedCount, required this.titles});
}

class RecurringService {
  RecurringService._();
  static final RecurringService instance = RecurringService._();

  static const frequencies = ['daily', 'weekly', 'monthly', 'yearly'];

  static String labelFor(String frequency) {
    switch (frequency) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'yearly':
        return 'Yearly';
      default:
        return 'Monthly';
    }
  }

  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime nextAfter(DateTime from, String frequency, {int interval = 1}) {
    final n = interval < 1 ? 1 : interval;
    switch (frequency) {
      case 'daily':
        return from.add(Duration(days: n));
      case 'weekly':
        return from.add(Duration(days: 7 * n));
      case 'yearly':
        return DateTime(from.year + n, from.month, from.day);
      default:
        final total = from.month - 1 + n;
        final y = from.year + total ~/ 12;
        final m = total % 12 + 1;
        final lastDay = DateTime(y, m + 1, 0).day;
        final d = from.day > lastDay ? lastDay : from.day;
        return DateTime(y, m, d);
    }
  }

  DateTime firstDueOnOrAfter(DateTime start, String frequency,
      {int interval = 1, DateTime? today}) {
    var due = dateOnly(start);
    final now = dateOnly(today ?? DateTime.now());
    var guard = 0;
    while (due.isBefore(now) && guard < 400) {
      due = nextAfter(due, frequency, interval: interval);
      guard++;
    }
    return due;
  }

  Future<RecurringPostResult> processDue({DateTime? now}) async {
    final today = dateOnly(now ?? DateTime.now());
    List<Map<String, dynamic>> rows = [];
    try {
      rows = await DatabaseHelper.instance.getRecurringTransactions();
    } catch (_) {
      return const RecurringPostResult(postedCount: 0, titles: []);
    }

    final postedTitles = <String>[];
    for (final row in rows) {
      if ((row['enabled'] ?? 1) == 0) continue;
      if ((row['auto_post'] ?? 1) == 0) continue;

      final parsed = DateTime.tryParse(row['next_due']?.toString() ?? '') ??
          DateTime.tryParse(row['start_date']?.toString() ?? '');
      if (parsed == null) continue;
      var due = dateOnly(parsed);

      final end = DateTime.tryParse(row['end_date']?.toString() ?? '');
      final freq = (row['frequency'] ?? 'monthly').toString();
      final interval = int.tryParse('${row['interval_n'] ?? 1}') ?? 1;
      final id = row['id'];
      if (id is! int) continue;

      var postedHere = 0;
      while (!due.isAfter(today) && postedHere < 12) {
        if (end != null && due.isAfter(dateOnly(end))) break;
        await DatabaseHelper.instance.addTransaction({
          'title': row['title'],
          'desc': row['desc'],
          'amount': row['amount'],
          'type': row['type'] ?? 'Expense',
          'account': row['account'],
          'toAccount': row['toAccount'] ?? '',
          'category': row['category'],
          'sub_category': row['sub_category'],
          'category_effect': row['category_effect'] ?? '',
          'date':
              DateTime(due.year, due.month, due.day, 9, 0).toIso8601String(),
          'imgs': '[]',
          'member_name': row['member_name'] ?? '',
          'recurring_id': id,
        });
        postedTitles.add((row['title'] ?? 'Recurring').toString());
        postedHere++;
        due = nextAfter(due, freq, interval: interval);
      }

      if (postedHere > 0) {
        await DatabaseHelper.instance.updateRecurringTransaction(id, {
          'last_posted': today.toIso8601String(),
          'next_due': due.toIso8601String(),
          if (end != null && due.isAfter(dateOnly(end))) 'enabled': 0,
        });
      }
    }

    return RecurringPostResult(
      postedCount: postedTitles.length,
      titles: postedTitles,
    );
  }

  Future<int> addFromTransaction(
    Map<String, dynamic> tx,
    String frequency, {
    DateTime? start,
    int interval = 1,
  }) async {
    final startDay = dateOnly(start ??
        DateTime.tryParse(tx['date']?.toString() ?? '') ??
        DateTime.now());
    final freq = frequencies.contains(frequency) ? frequency : 'monthly';
    final next = nextAfter(startDay, freq, interval: interval);
    return DatabaseHelper.instance.addRecurringTransaction({
      'title': tx['title'],
      'desc': tx['desc'] ?? '',
      'amount': tx['amount'],
      'type': tx['type'] ?? 'Expense',
      'account': tx['account'],
      'toAccount': tx['toAccount'] ?? '',
      'category': tx['category'],
      'sub_category': tx['sub_category'],
      'category_effect': tx['category_effect'] ?? '',
      'member_name': tx['member_name'] ?? '',
      'frequency': freq,
      'interval_n': interval,
      'start_date': startDay.toIso8601String(),
      'next_due': next.toIso8601String(),
      'enabled': 1,
      'auto_post': 1,
      'notify': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
