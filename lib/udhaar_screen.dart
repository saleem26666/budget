import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'services/currency_service.dart';
import 'services/udhaar_service.dart';

/// Lend / borrow ledger (Phase 2). Does not modify existing wallet rows
/// except when the user opts to post new Income/Expense entries.
class UdhaarScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final List<String> peopleSuggestions;
  final VoidCallback onWalletChanged;

  const UdhaarScreen({
    super.key,
    required this.accounts,
    required this.peopleSuggestions,
    required this.onWalletChanged,
  });

  @override
  State<UdhaarScreen> createState() => _UdhaarScreenState();
}

class _UdhaarScreenState extends State<UdhaarScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Map<String, dynamic>> _entries = [];
  Map<String, double> _summary = const {
    'to_receive': 0,
    'to_pay': 0,
    'net': 0,
  };
  bool _loading = true;
  bool _showSettled = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await UdhaarService.instance.ensureUdhaarCategory();
    final rows = await DatabaseHelper.instance.getUdhaarEntries();
    final sum = await UdhaarService.instance.summary();
    if (!mounted) return;
    setState(() {
      _entries = rows;
      _summary = sum;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _filtered(String? direction) {
    return _entries.where((e) {
      if (!_showSettled && UdhaarService.statusOf(e) == 'settled') return false;
      if (direction == null) return true;
      return (e['direction'] ?? '') == direction;
    }).toList();
  }

  Future<void> _openAdd() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UdhaarEditorSheet(
        accounts: widget.accounts,
        peopleSuggestions: widget.peopleSuggestions,
      ),
    );
    if (ok == true) {
      await _reload();
      widget.onWalletChanged();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> entry) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _UdhaarDetailPage(
          entryId: entry['id'] as int,
          accounts: widget.accounts,
          onChanged: () {
            _reload();
            widget.onWalletChanged();
          },
        ),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Udhaar book'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'To receive'),
            Tab(text: 'To pay'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showSettled ? 'Hide settled' : 'Show settled',
            icon: Icon(_showSettled
                ? Icons.visibility_rounded
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showSettled = !_showSettled),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _SummaryStrip(summary: _summary),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _list(_filtered(null)),
                      _list(_filtered('lent')),
                      _list(_filtered('borrowed')),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _list(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.handshake_outlined,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text(
                'No udhaar yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Track money you lent or borrowed. Settlements can post to Wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final e = rows[i];
        final lent = (e['direction'] ?? '') == 'lent';
        final left = UdhaarService.remainingOf(e);
        final status = UdhaarService.statusOf(e);
        final color = lent ? AppTheme.income : AppTheme.expense;
        return Card(
          child: ListTile(
            onTap: () => _openDetail(e),
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(
                lent ? Icons.call_received_rounded : Icons.call_made_rounded,
                color: color,
              ),
            ),
            title: Text(
              e['person_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                UdhaarService.shortLabel(e['direction']?.toString()),
                if (status == 'partial') 'partial',
                if (status == 'settled') 'settled',
                if (e['due_date'] != null)
                  'due ${DateFormat('dd MMM').format(DateTime.tryParse(e['due_date'].toString()) ?? DateTime.now())}',
              ].join(' · '),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyService.fmt(left),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: status == 'settled' ? Colors.grey : color,
                  ),
                ),
                Text(
                  'of ${CurrencyService.fmt((e['amount'] ?? 0).toDouble())}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _SummaryStrip extends StatelessWidget {
  final Map<String, double> summary;
  const _SummaryStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _chip(context, 'To receive', summary['to_receive'] ?? 0, AppTheme.income),
          const SizedBox(width: 8),
          _chip(context, 'To pay', summary['to_pay'] ?? 0, AppTheme.expense),
          const SizedBox(width: 8),
          _chip(
            context,
            'Net',
            summary['net'] ?? 0,
            (summary['net'] ?? 0) >= 0 ? AppTheme.transfer : AppTheme.expense,
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              CurrencyService.fmt(value),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UdhaarEditorSheet extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final List<String> peopleSuggestions;
  const _UdhaarEditorSheet({
    required this.accounts,
    required this.peopleSuggestions,
  });

  @override
  State<_UdhaarEditorSheet> createState() => _UdhaarEditorSheetState();
}

class _UdhaarEditorSheetState extends State<_UdhaarEditorSheet> {
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _direction = 'lent';
  late String _account;
  DateTime? _due;
  bool _linkWallet = true;

  @override
  void initState() {
    super.initState();
    _account = widget.accounts.isNotEmpty
        ? widget.accounts.first['name'].toString()
        : '';
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await UdhaarService.instance.createEntry(
        personName: _person.text,
        direction: _direction,
        amount: double.tryParse(_amount.text.trim()) ?? 0,
        account: _account,
        note: _note.text.trim(),
        dueDate: _due,
        linkWallet: _linkWallet,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.accounts
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
              const Text('New udhaar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lent', label: Text('I lent')),
                  ButtonSegment(value: 'borrowed', label: Text('I borrowed')),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _person,
                decoration: const InputDecoration(
                  labelText: 'Person name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              if (widget.peopleSuggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: widget.peopleSuggestions.take(8).map((n) {
                    return ActionChip(
                      label: Text(n),
                      onPressed: () => setState(() => _person.text = n),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount (${CurrencyService.instance.code})',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
              if (names.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: names.contains(_account) ? _account : names.first,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: names
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: (v) => setState(() => _account = v ?? _account),
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due date (optional)'),
                subtitle: Text(_due == null
                    ? 'Not set'
                    : DateFormat('dd MMM yyyy').format(_due!)),
                trailing: const Icon(Icons.event),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _due ?? DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _due = picked);
                },
              ),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also post to Wallet'),
                subtitle: Text(_direction == 'lent'
                    ? 'Records as Expense when you give money'
                    : 'Records as Income when you take money'),
                value: _linkWallet,
                onChanged: (v) => setState(() => _linkWallet = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UdhaarDetailPage extends StatefulWidget {
  final int entryId;
  final List<Map<String, dynamic>> accounts;
  final VoidCallback onChanged;

  const _UdhaarDetailPage({
    required this.entryId,
    required this.accounts,
    required this.onChanged,
  });

  @override
  State<_UdhaarDetailPage> createState() => _UdhaarDetailPageState();
}

class _UdhaarDetailPageState extends State<_UdhaarDetailPage> {
  Map<String, dynamic>? _entry;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final all = await DatabaseHelper.instance.getUdhaarEntries();
    Map<String, dynamic>? found;
    for (final e in all) {
      if (e['id'] == widget.entryId) {
        found = e;
        break;
      }
    }
    final pays =
        await DatabaseHelper.instance.getUdhaarPayments(widget.entryId);
    if (!mounted) return;
    setState(() {
      _entry = found;
      _payments = pays;
      _loading = false;
    });
  }

  Future<void> _addPayment() async {
    final entry = _entry;
    if (entry == null) return;
    final left = UdhaarService.remainingOf(entry);
    if (left <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already settled')),
      );
      return;
    }
    final amountC = TextEditingController(
      text: left == left.roundToDouble()
          ? left.round().toString()
          : left.toStringAsFixed(2),
    );
    final noteC = TextEditingController();
    var account = widget.accounts.isNotEmpty
        ? widget.accounts.first['name'].toString()
        : '';
    var postWallet = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Record payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                if (widget.accounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: account,
                    decoration: const InputDecoration(labelText: 'Account'),
                    items: widget.accounts
                        .map((a) => DropdownMenuItem(
                              value: a['name'].toString(),
                              child: Text(a['name'].toString()),
                            ))
                        .toList(),
                    onChanged: (v) => setSt(() => account = v ?? account),
                  ),
                TextField(
                  controller: noteC,
                  decoration:
                      const InputDecoration(labelText: 'Note (optional)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Post to Wallet'),
                  value: postWallet,
                  onChanged: (v) => setSt(() => postWallet = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await UdhaarService.instance.addPayment(
        entryId: widget.entryId,
        amount: double.tryParse(amountC.text.trim()) ?? 0,
        account: account,
        note: noteC.text.trim(),
        postToWallet: postWallet,
      );
      widget.onChanged();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete udhaar?'),
        content: const Text(
          'Removes this record and its payments. Wallet transactions already posted stay.',
        ),
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
    await DatabaseHelper.instance.deleteUdhaarEntry(widget.entryId);
    widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    return Scaffold(
      appBar: AppBar(
        title: Text(e?['person_name']?.toString() ?? 'Udhaar'),
        actions: [
          if (e != null && UdhaarService.statusOf(e) != 'settled')
            IconButton(
              tooltip: 'Payment',
              icon: const Icon(Icons.payment_rounded),
              onPressed: _addPayment,
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: _loading || e == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          UdhaarService.directionLabel(
                              e['direction']?.toString()),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Remaining ${CurrencyService.fmt(UdhaarService.remainingOf(e))}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total ${CurrencyService.fmt((e['amount'] ?? 0).toDouble())}'
                          ' · Paid ${CurrencyService.fmt((e['paid_amount'] ?? 0).toDouble())}'
                          ' · ${UdhaarService.statusOf(e)}',
                        ),
                        if ((e['note'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(e['note'].toString()),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Payments',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (UdhaarService.statusOf(e) != 'settled')
                      TextButton.icon(
                        onPressed: _addPayment,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                  ],
                ),
                if (_payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No payments yet')),
                  )
                else
                  ..._payments.map((p) {
                    final d = DateTime.tryParse(p['date']?.toString() ?? '');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(CurrencyService.fmt(
                          (p['amount'] ?? 0).toDouble())),
                      subtitle: Text([
                        if (d != null) DateFormat('dd MMM yyyy').format(d),
                        p['account']?.toString() ?? '',
                        p['note']?.toString() ?? '',
                      ].where((s) => s.toString().trim().isNotEmpty).join(' · ')),
                    );
                  }),
              ],
            ),
    );
  }
}
