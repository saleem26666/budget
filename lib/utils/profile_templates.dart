import 'dart:convert';

import '../database_helper.dart';

/// Starter accounts/categories for new profiles (Personal / Shop / Pharmacy).
class ProfileTemplates {
  static const List<String> choices = [
    'Personal',
    'Shop',
    'Pharmacy',
    'Empty',
  ];

  static Future<void> apply(String templateLabel) async {
    final key = templateLabel.toLowerCase();
    if (key == 'empty' || key == 'personal') return;

    final db = DatabaseHelper.instance;
    if (key == 'shop' || key == 'pharmacy') {
      final accounts = await db.getAccounts();
      final names = accounts.map((a) => a['name'].toString()).toSet();
      Future<void> ensureAcc(String name) async {
        if (!names.contains(name)) {
          await db.addAccount({'name': name, 'initial_balance': 0.0});
          names.add(name);
        }
      }

      await ensureAcc('JazzCash');
      await ensureAcc('EasyPaisa');
      await ensureAcc('Bank');
      if (key == 'shop') {
        await ensureAcc('Shop Till');
      } else {
        await ensureAcc('Pharmacy Counter');
      }

      Future<void> ensureCat(String name, List<String> subs) async {
        final cats = await db.getCategories();
        if (cats.any((c) => c['name'].toString() == name)) return;
        await db.addCategory({
          'name': name,
          'budget': 0.0,
          'sub_categories': jsonEncode(subs),
        });
      }

      if (key == 'shop') {
        await ensureCat('Sales', ['Retail', 'Wholesale', 'Online']);
        await ensureCat('Stock Purchase', ['Supplier', 'Returns']);
        await ensureCat('Shop Expenses', ['Rent', 'Utilities', 'Staff']);
      } else {
        await ensureCat('Medicine Sales', ['OTC', 'Prescription']);
        await ensureCat('Stock / Supplier', ['Purchase', 'Expiry write-off']);
        await ensureCat('Clinic Expenses', ['Rent', 'Staff', 'Utilities']);
      }
    }
  }
}
