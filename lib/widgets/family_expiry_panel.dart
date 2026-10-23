import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';
import '../app_theme.dart';

class FamilyExpiryItem {
  final String memberName;
  final String docType;
  final DateTime expiry;
  final String status; // expired | soon | today | ok
  final String kind; // expiry | birthday | reminder

  FamilyExpiryItem({
    required this.memberName,
    required this.docType,
    required this.expiry,
    required this.status,
    this.kind = 'expiry',
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
        docType: () {
          final t = (d['title'] ?? '').toString().trim();
          if (t.isNotEmpty) return t;
          return (d['doc_type'] ?? 'Document').toString();
        }(),
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

    try {
      final birthdays = await DatabaseHelper.instance.getVaultBirthdays();
      final today = DateTime(now.year, now.month, now.day);
      for (final b in birthdays) {
        final raw = b['birth_date']?.toString() ?? '';
        final birth = DateTime.tryParse(raw);
        if (birth == null) continue;
        var next = DateTime(today.year, birth.month, birth.day);
        if (next.isBefore(today)) {
          next = DateTime(today.year + 1, birth.month, birth.day);
        }
        final remindDays = int.tryParse('${b['remind_days'] ?? 7}') ?? 7;
        final days = next.difference(today).inDays;
        if (days > remindDays && days > 0) continue;
        items.add(FamilyExpiryItem(
          memberName: (b['name'] ?? 'Someone').toString(),
          docType: days == 0 ? 'Birthday today' : 'Birthday in $days days',
          expiry: next,
          status: days == 0 ? 'today' : 'soon',
          kind: 'birthday',
        ));
      }
    } catch (_) {}

    try {
      final anniversaries =
          await DatabaseHelper.instance.getVaultAnniversaries();
      final today = DateTime(now.year, now.month, now.day);
      for (final a in anniversaries) {
        final raw = a['marriage_date']?.toString() ?? '';
        final married = DateTime.tryParse(raw);
        if (married == null) continue;
        var next = DateTime(today.year, married.month, married.day);
        if (next.isBefore(today)) {
          next = DateTime(today.year + 1, married.month, married.day);
        }
        final remindDays = int.tryParse('${a['remind_days'] ?? 7}') ?? 7;
        final days = next.difference(today).inDays;
        if (days > remindDays && days > 0) continue;
        items.add(FamilyExpiryItem(
          memberName: (a['name'] ?? 'Anniversary').toString(),
          docType: days == 0
              ? 'Anniversary today'
              : 'Anniversary in $days days',
          expiry: next,
          status: days == 0 ? 'today' : 'soon',
          kind: 'anniversary',
        ));
      }
    } catch (_) {}

    try {
      final reminders = await DatabaseHelper.instance.getVaultReminders();
      final horizon = now.add(const Duration(days: 7));
      for (final r in reminders) {
        if ((r['done'] ?? 0) == 1) continue;
        final when = DateTime.tryParse(r['remind_at']?.toString() ?? '');
        if (when == null) continue;
        if (when.isAfter(horizon)) continue;
        final overdue = when.isBefore(now);
        items.add(FamilyExpiryItem(
          memberName: (r['title'] ?? 'Reminder').toString(),
          docType: overdue ? 'Reminder overdue' : 'Reminder',
          expiry: when,
          status: overdue ? 'expired' : 'soon',
          kind: 'reminder',
        ));
      }
    } catch (_) {}

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
                const Text('Vault alerts',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'Expiries, birthdays and reminders',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No upcoming alerts — you are clear ✅'),
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
                            : (it.status == 'today'
                                ? const Color(0xFFEC4899)
                                : Colors.orange.shade800);
                        IconData icon = Icons.schedule_rounded;
                        if (it.kind == 'birthday') {
                          icon = Icons.cake_rounded;
                        } else if (it.kind == 'anniversary') {
                          icon = Icons.favorite_rounded;
                        } else if (it.kind == 'reminder') {
                          icon = it.status == 'expired'
                              ? Icons.notification_important_rounded
                              : Icons.notifications_active_rounded;
                        } else if (it.status == 'expired') {
                          icon = Icons.error_rounded;
                        }
                        String whenLabel;
                        if (it.kind == 'birthday' || it.kind == 'anniversary') {
                          whenLabel = it.status == 'today'
                              ? 'Today'
                              : DateFormat('dd MMM').format(it.expiry);
                        } else if (it.kind == 'reminder') {
                          whenLabel = DateFormat('dd MMM · HH:mm').format(it.expiry);
                        } else {
                          whenLabel =
                              '${it.status == 'expired' ? 'Expired' : 'Due'} ${DateFormat('dd MMM yyyy').format(it.expiry)}';
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(icon, color: color),
                          title: Text('${it.memberName} · ${it.docType}'),
                          subtitle: Text(
                            whenLabel,
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
