import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';
import '../app_theme.dart';

class FamilyExpiryItem {
  final String memberName;
  final String docType;
  final DateTime expiry;
  final String status; // expired | soon | ok

  FamilyExpiryItem({
    required this.memberName,
    required this.docType,
    required this.expiry,
    required this.status,
  });
}

/// Loads family vault + card expiries due within [withinDays] or already expired.
class FamilyExpiryCenter {
  static Future<List<FamilyExpiryItem>> load({int withinDays = 30}) async {
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: withinDays));
    final items = <FamilyExpiryItem>[];

    final docs = await DatabaseHelper.instance.getFamilyVault();
    for (final d in docs) {
      final raw = d['expiry_date']?.toString() ?? '';
      final dt = DateTime.tryParse(raw);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final status = day.isBefore(DateTime(now.year, now.month, now.day))
          ? 'expired'
          : (day.isBefore(cutoff) || day.isAtSameMomentAs(cutoff)
              ? 'soon'
              : 'ok');
      if (status == 'ok') continue;
      items.add(FamilyExpiryItem(
        memberName: (d['member_name'] ?? 'Family').toString(),
        docType: (d['doc_type'] ?? 'Document').toString(),
        expiry: day,
        status: status,
      ));
    }

    final cards = await DatabaseHelper.instance.getCards();
    for (final c in cards) {
      final raw = c['expiry']?.toString() ?? '';
      // Cards may store MM/YY or ISO
      DateTime? dt = DateTime.tryParse(raw);
      if (dt == null && raw.contains('/')) {
        final parts = raw.split('/');
        if (parts.length >= 2) {
          final m = int.tryParse(parts[0].trim());
          var y = int.tryParse(parts[1].trim());
          if (m != null && y != null) {
            if (y < 100) y += 2000;
            dt = DateTime(y, m + 1, 0); // last day of month
          }
        }
      }
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      final status = day.isBefore(DateTime(now.year, now.month, now.day))
          ? 'expired'
          : (day.isBefore(cutoff) ? 'soon' : 'ok');
      if (status == 'ok') continue;
      final holder = (c['card_holder'] ?? 'Card').toString();
      final type = (c['card_type'] ?? 'Card').toString();
      items.add(FamilyExpiryItem(
        memberName: holder,
        docType: type,
        expiry: day,
        status: status,
      ));
    }

    items.sort((a, b) => a.expiry.compareTo(b.expiry));
    return items;
  }

  static Future<void> show(BuildContext context) async {
    final items = await load();
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Family expiry center',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'CNIC, passports, cards & docs expiring in 30 days',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No upcoming expiries — you are clear ✅'),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final color = it.status == 'expired'
                            ? AppTheme.expense
                            : Colors.orange.shade800;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            it.status == 'expired'
                                ? Icons.error_rounded
                                : Icons.schedule_rounded,
                            color: color,
                          ),
                          title: Text('${it.memberName} · ${it.docType}'),
                          subtitle: Text(
                            '${it.status == 'expired' ? 'Expired' : 'Due'} ${DateFormat('dd MMM yyyy').format(it.expiry)}',
                            style: TextStyle(color: color),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
