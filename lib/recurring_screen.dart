import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'services/currency_service.dart';
import 'services/notification_service.dart';
import 'services/recurring_service.dart';
import 'utils/category_utils.dart';

class RecurringScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<String> familyMembers;
  final VoidCallback onChanged;

  const RecurringScreen({
    super.key,
    required this.accounts,
    required this.categories,
    required this.familyMembers,
    required this.onChanged,
  });

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await DatabaseHelper.instance.getRecurringTransactions();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openEditor({Map<String, dynamic>? edit}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringEditorSheet(
        accounts: widget.accounts,
        categories: widget.categories,
        familyMembers: widget.familyMembers,
        edit: edit,
      ),
    );
    if (saved == true) {
      await _reload();
      widget.onChanged();
      await NotificationService.instance.rescheduleActiveProfile();
    }
  }

  Future<void> _toggle(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id is! int) return;
    await DatabaseHelper.instance.updateRecurringTransaction(id, {
      'enabled': (row['enabled'] ?? 1) == 1 ? 0 : 1,
    });
    await _reload();
    widget.onChanged();
    await NotificationService.instance.rescheduleActiveProfile();
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id is! int) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recurring?'),
        content: const Text(
            'Stops future repeats. Past wallet transactions stay.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteRecurringTransaction(id);
    await _reload();
    widget.onChanged();
    await NotificationService.instance.rescheduleActiveProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Rent, salary, school fee…\nAdd a repeating payment here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final row = _rows[i];
                    final enabled = (row['enabled'] ?? 1) == 1;
                    final due =
                        DateTime.tryParse(row['next_due']?.toString() ?? '');
                    final amount = (row['amount'] ?? 0).toDouble();
                    final type = (row['type'] ?? 'Expense').toString();
                    final color = type == 'Income'
                        ? AppTheme.income
                        : (type == 'Transfer'
                            ? AppTheme.transfer
                            : AppTheme.expense);
                    return Card(
                      child: ListTile(
                        onTap: () => _openEditor(edit: row),
                        onLongPress: () => _delete(row),
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.15),
                          child: Icon(Icons.repeat_rounded, color: color),
                        ),
                        title: Text(row['title']?.toString() ?? '',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text([
                          RecurringService.labelFor(
                              (row['frequency'] ?? 'monthly').toString()),
                          if (due != null)
                            'next ${DateFormat('dd MMM').format(due)}',
                          if (!enabled) 'paused',
                        ].join(' · ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(CurrencyService.fmt(amount),
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                            Switch(
                                value: enabled,
                                onChanged: (_) => _toggle(row)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _RecurringEditorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<String> familyMembers;
  final Map<String, dynamic>? edit;

  const _RecurringEditorSheet({
    required this.accounts,
    required this.categories,
    required this.familyMembers,
    this.edit,
  });

  @override
  State<_RecurringEditorSheet> createState() => _RecurringEditorSheetState();
}

class _RecurringEditorSheetState extends State<_RecurringEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _amount;
  late String _type;
  late String _account;
  late String _toAccount;
  late String _category;
  String? _subCategory;
  late String _frequency;
  late DateTime _start;
  bool _autoPost = true;
  bool _notify = true;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _title = TextEditingController(text: e?['title']?.toString() ?? '');
    _amount = TextEditingController(
        text: e?['amount'] != null ? e!['amount'].toString() : '');
    _type = e?['type']?.toString() ?? 'Expense';
    _account = e?['account']?.toString() ??
        (widget.accounts.isNotEmpty
            ? widget.accounts.first['name'].toString()
            : '');
    _toAccount = e?['toAccount']?.toString() ??
        (widget.accounts.length > 1
            ? widget.accounts[1]['name'].toString()
            : '');
    _category = e?['category']?.toString() ??
        (widget.categories.isNotEmpty
            ? widget.categories.first['name'].toString()
            : 'General');
    _subCategory = e?['sub_category']?.toString();
    if (_subCategory != null && _subCategory!.isEmpty) _subCategory = null;
    _frequency = e?['frequency']?.toString() ?? 'monthly';
    _start = DateTime.tryParse(e?['start_date']?.toString() ?? '') ??
        DateTime.now();
    _autoPost = (e?['auto_post'] ?? 1) == 1;
    _notify = (e?['notify'] ?? 1) == 1;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return;
    final start = RecurringService.instance.dateOnly(_start);
    final next =
        RecurringService.instance.firstDueOnOrAfter(start, _frequency);
    final data = {
      'title': _title.text.trim(),
      'desc': '',
      'amount': amount,
      'type': _type,
      'account': _account,
      'toAccount': _type == 'Transfer' ? _toAccount : '',
      'category': _category,
      'sub_category': _subCategory ?? '',
      'category_effect': '',
      'member_name': '',
      'frequency': _frequency,
      'interval_n': 1,
      'start_date': start.toIso8601String(),
      'next_due': next.toIso8601String(),
      'enabled': 1,
      'auto_post': _autoPost ? 1 : 0,
      'notify': _notify ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    };
    if (widget.edit == null) {
      await DatabaseHelper.instance.addRecurringTransaction(data);
    } else {
      await DatabaseHelper.instance
          .updateRecurringTransaction(widget.edit!['id'], data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    List<String> subs = [];
    try {
      final catObj =
          widget.categories.firstWhere((e) => e['name'] == _category);
      subs = parseSubCategories(catObj['sub_categories']);
    } catch (_) {}
    final accounts = widget.accounts
        .map((e) => e['name'].toString())
        .where((n) => n.isNotEmpty)
        .toList();
    final cats = widget.categories
        .map((e) => e['name'].toString())
        .where((n) => n.isNotEmpty)
        .toList();
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.edit == null ? 'New recurring' : 'Edit recurring',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Expense', label: Text('Expense')),
                  ButtonSegment(value: 'Income', label: Text('Income')),
                  ButtonSegment(value: 'Transfer', label: Text('Transfer')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                      labelText: 'Title (Rent, Salary…)')),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Amount (${CurrencyService.instance.code})'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: RecurringService.frequencies.contains(_frequency)
                    ? _frequency
                    : 'monthly',
                decoration: const InputDecoration(labelText: 'Repeat'),
                items: RecurringService.frequencies
                    .map((f) => DropdownMenuItem(
                        value: f, child: Text(RecurringService.labelFor(f))))
                    .toList(),
                onChanged: (v) => setState(() => _frequency = v ?? 'monthly'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('First / next date'),
                subtitle: Text(DateFormat('dd MMM yyyy').format(_start)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _start,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _start = picked);
                },
              ),
              if (accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: accounts.contains(_account) ? _account : accounts.first,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: accounts
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setState(() => _account = v ?? _account),
                ),
              if (_type == 'Transfer' && accounts.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: accounts.contains(_toAccount)
                      ? _toAccount
                      : accounts.last,
                  decoration: const InputDecoration(labelText: 'To account'),
                  items: accounts
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _toAccount = v ?? _toAccount),
                ),
              ],
              if (cats.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: cats.contains(_category) ? _category : cats.first,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: cats
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v ?? _category;
                    _subCategory = null;
                  }),
                ),
              ],
              if (subs.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _subCategory != null && subs.contains(_subCategory)
                      ? _subCategory
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Sub-category (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    ...subs.map(
                        (n) => DropdownMenuItem(value: n, child: Text(n))),
                  ],
                  onChanged: (v) => setState(() => _subCategory = v),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add to wallet automatically'),
                value: _autoPost,
                onChanged: (v) => setState(() => _autoPost = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Phone reminder'),
                value: _notify,
                onChanged: (v) => setState(() => _notify = v),
              ),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
