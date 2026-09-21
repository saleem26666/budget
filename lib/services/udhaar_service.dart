import '../database_helper.dart';

/// Helpers for lend/borrow (udhaar) bookkeeping.
class UdhaarService {
  UdhaarService._();
  static final UdhaarService instance = UdhaarService._();

  /// `lent` = I gave money (they owe me). `borrowed` = I took (I owe them).
  static const directions = ['lent', 'borrowed'];

  static String directionLabel(String? d) {
    switch ((d ?? '').toLowerCase()) {
      case 'lent':
        return 'I lent (they owe me)';
      case 'borrowed':
        return 'I borrowed (I owe)';
      default:
        return 'Udhaar';
    }
  }

  static String shortLabel(String? d) {
    switch ((d ?? '').toLowerCase()) {
      case 'lent':
        return 'To receive';
      case 'borrowed':
        return 'To pay';
      default:
        return 'Udhaar';
    }
  }

  static double remainingOf(Map<String, dynamic> entry) {
    final total = (entry['amount'] ?? 0).toDouble();
    final paid = (entry['paid_amount'] ?? 0).toDouble();
    final left = total - paid;
    return left < 0 ? 0 : left;
  }

  static String statusOf(Map<String, dynamic> entry) {
    final total = (entry['amount'] ?? 0).toDouble();
    final paid = (entry['paid_amount'] ?? 0).toDouble();
    if (paid <= 0) return 'open';
    if (paid + 0.0001 >= total) return 'settled';
    return 'partial';
  }

  Future<Map<String, double>> summary() async {
    final rows = await DatabaseHelper.instance.getUdhaarEntries();
    double toReceive = 0;
    double toPay = 0;
    for (final e in rows) {
      if (statusOf(e) == 'settled') continue;
      final left = remainingOf(e);
      if ((e['direction'] ?? '') == 'lent') {
        toReceive += left;
      } else {
        toPay += left;
      }
    }
    return {
      'to_receive': toReceive,
      'to_pay': toPay,
      'net': toReceive - toPay,
    };
  }

  /// Adds a payment and updates paid_amount / status.
  /// Optionally posts a wallet Income (repayment of lend) or Expense (repay borrow).
  Future<void> addPayment({
    required int entryId,
    required double amount,
    required String account,
    String note = '',
    DateTime? date,
    bool postToWallet = true,
  }) async {
    if (amount <= 0) throw 'Enter a valid amount';
    final entries = await DatabaseHelper.instance.getUdhaarEntries();
    Map<String, dynamic>? entry;
    for (final e in entries) {
      if (e['id'] == entryId) {
        entry = e;
        break;
      }
    }
    if (entry == null) throw 'Entry not found';

    final left = remainingOf(entry);
    if (amount > left + 0.01) throw 'Amount is more than remaining';

    final when = date ?? DateTime.now();
    int? txId;
    if (postToWallet && account.trim().isNotEmpty) {
      final direction = (entry['direction'] ?? 'lent').toString();
      final person = (entry['person_name'] ?? 'Someone').toString();
      final isLent = direction == 'lent';
      txId = await DatabaseHelper.instance.addTransaction({
        'title': isLent ? 'Udhaar received · $person' : 'Udhaar paid · $person',
        'desc': note.isEmpty ? 'From udhaar book' : note,
        'amount': amount,
        'type': isLent ? 'Income' : 'Expense',
        'account': account,
        'toAccount': '',
        'category': 'Udhaar',
        'sub_category': isLent ? 'Received' : 'Paid',
        'category_effect': '',
        'date': when.toIso8601String(),
        'imgs': '[]',
        'member_name': '',
      });
    }

    await DatabaseHelper.instance.addUdhaarPayment({
      'entry_id': entryId,
      'amount': amount,
      'account': account,
      'note': note,
      'date': when.toIso8601String(),
      'transaction_id': txId,
      'created_at': DateTime.now().toIso8601String(),
    });

    final newPaid = (entry['paid_amount'] ?? 0).toDouble() + amount;
    final total = (entry['amount'] ?? 0).toDouble();
    final status =
        newPaid + 0.0001 >= total ? 'settled' : (newPaid > 0 ? 'partial' : 'open');
    await DatabaseHelper.instance.updateUdhaarEntry(entryId, {
      'paid_amount': newPaid,
      'status': status,
    });
  }

  Future<int> createEntry({
    required String personName,
    required String direction,
    required double amount,
    required String account,
    String note = '',
    DateTime? startDate,
    DateTime? dueDate,
    bool linkWallet = true,
  }) async {
    if (personName.trim().isEmpty) throw 'Enter person name';
    if (amount <= 0) throw 'Enter a valid amount';
    final dir = directions.contains(direction) ? direction : 'lent';
    final when = startDate ?? DateTime.now();

    if (linkWallet && account.trim().isNotEmpty) {
      final isLent = dir == 'lent';
      await DatabaseHelper.instance.addTransaction({
        'title': isLent
            ? 'Udhaar given · ${personName.trim()}'
            : 'Udhaar taken · ${personName.trim()}',
        'desc': note.isEmpty ? 'Opened in udhaar book' : note,
        'amount': amount,
        'type': isLent ? 'Expense' : 'Income',
        'account': account,
        'toAccount': '',
        'category': 'Udhaar',
        'sub_category': isLent ? 'Given' : 'Taken',
        'category_effect': '',
        'date': when.toIso8601String(),
        'imgs': '[]',
        'member_name': '',
      });
    }

    return DatabaseHelper.instance.addUdhaarEntry({
      'person_name': personName.trim(),
      'direction': dir,
      'amount': amount,
      'paid_amount': 0.0,
      'account': account,
      'note': note,
      'start_date': when.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'status': 'open',
      'link_wallet': linkWallet ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Ensures an "Udhaar" category exists so wallet posts stay tidy.
  Future<void> ensureUdhaarCategory() async {
    final cats = await DatabaseHelper.instance.getCategories();
    if (cats.any((c) => (c['name'] ?? '').toString() == 'Udhaar')) return;
    await DatabaseHelper.instance.addCategory({
      'name': 'Udhaar',
      'budget': 0.0,
      'sub_categories':
          '["Given","Taken","Received","Paid"]',
    });
  }
}
