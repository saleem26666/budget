import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/currency_service.dart';
import '../services/report_export_service.dart';
import '../services/report_translation_service.dart';
import '../utils/category_ledger.dart';
import '../utils/category_utils.dart';
import '../widgets/expense_charts.dart';

class AdvancedReports extends StatefulWidget {
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> diaryEntries;

  // نیا اضافہ: ایڈٹ فنکشن کا لنک
  final Function(Map)? onEditTransaction;

  const AdvancedReports({
    super.key,
    required this.transactions,
    required this.accounts,
    required this.categories,
    required this.diaryEntries,
    this.onEditTransaction, // نیا اضافہ
  });

  @override
  State<AdvancedReports> createState() => _AdvancedReportsState();
}

class _AdvancedReportsState extends State<AdvancedReports> {
  String _selectedAccount = "All Accounts";
  String _selectedCategory = "All Categories";
  String _selectedSubCategory = "All Sub-categories";
  DateTimeRange? _selectedDateRange;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  String _safeGetDescription(Map t) {
    return (t['desc'] ?? t['description'] ?? "").toString();
  }

  bool get _categoryFilterActive =>
      _selectedCategory != 'All Categories' && _selectedCategory.isNotEmpty;

  List<String> get _subCategoryOptions {
    if (!_categoryFilterActive) return const ['All Sub-categories'];
    final cat = widget.categories.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['name']?.toString() == _selectedCategory,
          orElse: () => null,
        );
    final subs = parseSubCategories(cat?['sub_categories']);
    return ['All Sub-categories', ...subs, '(No sub-category)'];
  }

  bool _subCategoryMatch(Map<String, dynamic> t) {
    if (_selectedSubCategory == 'All Sub-categories') return true;
    final sub = (t['sub_category'] ?? '').toString().trim();
    if (_selectedSubCategory == '(No sub-category)') return sub.isEmpty;
    return sub == _selectedSubCategory;
  }

  double _txAmount(Map<String, dynamic> t) => (t['amount'] ?? 0).toDouble();

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _txMatchesDateRange(Map<String, dynamic> t) {
    if (_selectedDateRange == null) return true;
    final txDay = _dateOnly(DateTime.parse(t['date'].toString()));
    final start = _dateOnly(_selectedDateRange!.start);
    final end = _dateOnly(_selectedDateRange!.end);
    return !txDay.isBefore(start) && !txDay.isAfter(end);
  }

  List<Map<String, dynamic>> _transactionsChronological() {
    final sorted = List<Map<String, dynamic>>.from(widget.transactions);
    sorted.sort((a, b) =>
        DateTime.parse(a['date'].toString())
            .compareTo(DateTime.parse(b['date'].toString())));
    return sorted;
  }

  /// Account balance after all transactions strictly before [day] (calendar day).
  double _balanceBeforeDay(DateTime day) {
    final cutoff = _dateOnly(day);
    double bal = _accountSetupInitial();
    for (final t in _transactionsChronological()) {
      final txDay = _dateOnly(DateTime.parse(t['date'].toString()));
      if (!txDay.isBefore(cutoff)) break;
      bal += _transactionBalanceChange(t);
    }
    return bal;
  }

  /// Account balance after all transactions on or before [day] (inclusive).
  double _balanceThroughDay(DateTime day) {
    final end = _dateOnly(day);
    double bal = _accountSetupInitial();
    for (final t in _transactionsChronological()) {
      final txDay = _dateOnly(DateTime.parse(t['date'].toString()));
      if (txDay.isAfter(end)) break;
      bal += _transactionBalanceChange(t);
    }
    return bal;
  }

  /// Signed effect of one transaction on the selected account view.
  /// Category-only ledger change (when a specific category is selected).
  double _categoryBalanceChange(Map<String, dynamic> t) {
    if (!_categoryFilterActive) return 0;
    if (!CategoryLedger.categoryEquals(t['category'], _selectedCategory)) {
      return 0;
    }
    if (t['type']?.toString() == 'Transfer') {
      if (_selectedAccount != "All Accounts" &&
          t['account'] != _selectedAccount &&
          t['toAccount'] != _selectedAccount) {
        return 0;
      }
    } else if (_selectedAccount != "All Accounts" &&
        t['account'] != _selectedAccount) {
      return 0;
    }
    return CategoryLedger.signedChange(t, onlyForCategory: _selectedCategory);
  }

  double _transactionBalanceChange(Map<String, dynamic> t) {
    final amt = (t['amount'] ?? 0).toDouble();
    if (_selectedAccount == "All Accounts") {
      if (t['type'] == 'Income') return amt;
      if (t['type'] == 'Expense') return -amt;
      return 0;
    }
    if (t['type'] == 'Income' && t['account'] == _selectedAccount) return amt;
    if (t['type'] == 'Expense' && t['account'] == _selectedAccount) {
      return -amt;
    }
    if (t['type'] == 'Transfer') {
      if (t['toAccount'] == _selectedAccount) return amt;
      if (t['account'] == _selectedAccount) return -amt;
    }
    return 0;
  }

  /// Balance in Settings is only the starting point; report opening = before first row.
  double _accountSetupInitial() {
    if (_selectedAccount == "All Accounts") {
      return widget.accounts.fold(
          0.0, (sum, acc) => sum + (acc['initial_balance'] ?? 0).toDouble());
    }
    final acc = widget.accounts.firstWhere(
      (a) => a['name'] == _selectedAccount,
      orElse: () => {'initial_balance': 0.0},
    );
    return (acc['initial_balance'] ?? 0).toDouble();
  }

  /// Category balance at end of the day before the report period starts
  /// (e.g. 31 March when period begins 1 April).
  double _openingCategoryBalance() {
    if (!_categoryFilterActive || _selectedDateRange == null) return 0;

    final periodStart = _dateOnly(_selectedDateRange!.start);
    double total = 0;

    for (final t in _transactionsChronological()) {
      final txDay = _dateOnly(DateTime.parse(t['date'].toString()));
      if (!txDay.isBefore(periodStart)) continue;

      final accountMatch = _selectedAccount == "All Accounts" ||
          t['account'] == _selectedAccount ||
          (t['type'] == 'Transfer' && t['toAccount'] == _selectedAccount);
      if (!accountMatch) continue;
      if (!CategoryLedger.categoryEquals(t['category'], _selectedCategory)) {
        continue;
      }
      if (!_subCategoryMatch(t)) continue;

      total += _categoryBalanceChange(t);
    }
    return total;
  }

  /// Opening at start of report period (cash ledger — not category-filtered).
  double _openingBalanceForReport(List<Map<String, dynamic>> filtered) {
    if (_categoryFilterActive) return 0;

    if (_selectedDateRange != null) {
      return _balanceBeforeDay(_selectedDateRange!.start);
    }

    if (filtered.isEmpty) return _accountSetupInitial();

    final oldest = filtered.last;
    final after = (oldest['running_balance'] as num).toDouble();
    return after - _transactionBalanceChange(oldest);
  }

  // ==================================================
  // نیا فیچر: ہر اکاؤنٹ کا لائیو بیلنس نکالنے کے لیے
  // ==================================================
  Map<String, double> _calculateAccountBalances() {
    Map<String, double> balances = {};
    double totalAll = 0.0;

    for (var acc in widget.accounts) {
      String name = acc['name'].toString();
      double init = (acc['initial_balance'] ?? 0.0).toDouble();
      balances[name] = init;
      totalAll += init;
    }

    for (var t in widget.transactions) {
      double amt = (t['amount'] ?? 0).toDouble();
      String type = (t['type'] ?? "").toString();
      String acc = (t['account'] ?? "").toString();
      String toAcc = (t['toAccount'] ?? "").toString();

      if (type == 'Income') {
        if (balances.containsKey(acc)) balances[acc] = balances[acc]! + amt;
        totalAll += amt;
      } else if (type == 'Expense') {
        if (balances.containsKey(acc)) balances[acc] = balances[acc]! - amt;
        totalAll -= amt;
      } else if (type == 'Transfer') {
        if (balances.containsKey(acc)) balances[acc] = balances[acc]! - amt;
        if (balances.containsKey(toAcc)) {
          balances[toAcc] = balances[toAcc]! + amt;
        }
      }
    }

    balances["All Accounts"] = totalAll;
    return balances;
  }

  List<Map<String, dynamic>> _getFilteredData() {
    List<Map<String, dynamic>> sortedAll = List.from(widget.transactions);
    sortedAll.sort((a, b) =>
        DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

    double runningBalance = 0;
    if (_selectedAccount == "All Accounts") {
      runningBalance = widget.accounts
          .fold(0.0, (sum, acc) => sum + (acc['initial_balance'] ?? 0.0));
    } else {
      var acc = widget.accounts.firstWhere((a) => a['name'] == _selectedAccount,
          orElse: () => {'initial_balance': 0.0});
      runningBalance = (acc['initial_balance'] ?? 0.0).toDouble();
    }

    List<Map<String, dynamic>> results = [];
    double categoryRunning = 0;

    for (var t in sortedAll) {
      final change = _transactionBalanceChange(t);
      runningBalance += change;

      bool accountMatch = _selectedAccount == "All Accounts" ||
          t['account'] == _selectedAccount ||
          (t['type'] == 'Transfer' && t['toAccount'] == _selectedAccount);
      bool categoryMatch = _selectedCategory == "All Categories" ||
          CategoryLedger.categoryEquals(t['category'], _selectedCategory);

      bool dateMatch = _txMatchesDateRange(t);

      if (_categoryFilterActive && accountMatch && dateMatch) {
        categoryRunning += _categoryBalanceChange(t);
      }

      Map<String, dynamic> tWithBal = Map.from(t);
      tWithBal['running_balance'] = runningBalance;
      if (_categoryFilterActive) {
        tWithBal['category_running_balance'] = categoryRunning;
      }

      String q = _searchQuery.trim().toLowerCase();
      bool searchMatch = true;
      if (q.isNotEmpty) {
        String title = (t['title'] ?? "").toString().toLowerCase();
        String dsc = _safeGetDescription(t).toLowerCase();
        String cat = (t['category'] ?? "").toString().toLowerCase();
        String accName = (t['account'] ?? "").toString().toLowerCase();
        String amt = (t['amount'] ?? "").toString();

        searchMatch = title.contains(q) ||
            dsc.contains(q) ||
            cat.contains(q) ||
            accName.contains(q) ||
            amt.contains(q);
      }

      if (accountMatch && categoryMatch && dateMatch && searchMatch &&
          _subCategoryMatch(t)) {
        results.add(tWithBal);
      }
    }
    return results.reversed.toList();
  }

  Map<String, dynamic> _calculateDetailedSummary(
      List<Map<String, dynamic>> filtered) {
    if (_categoryFilterActive) {
      // Category ledger: Income +, Expense −, Transfer uses category_effect (+/−).
      double totalIn = 0;
      double totalOut = 0;
      for (final t in filtered) {
        final change = _categoryBalanceChange(t);
        if (change > 0) {
          totalIn += change;
        } else if (change < 0) {
          totalOut += -change;
        }
      }
      final opening = _openingCategoryBalance();
      final periodNet = totalIn - totalOut;
      return {
        'initial': opening,
        'totalIn': totalIn,
        'totalOut': totalOut,
        'current': periodNet,
        'closing': opening + periodNet,
        'categoryOnly': true,
      };
    }

    double totalIn = 0;
    double totalOut = 0;

    for (var t in filtered) {
      if (_selectedAccount == "All Accounts") {
        if (t['type'] == 'Income') totalIn += _txAmount(t);
        if (t['type'] == 'Expense') totalOut += _txAmount(t);
      } else {
        if (t['type'] == 'Income' && t['account'] == _selectedAccount) {
          totalIn += _txAmount(t);
        } else if (t['type'] == 'Expense' &&
            t['account'] == _selectedAccount) {
          totalOut += _txAmount(t);
        } else if (t['type'] == 'Transfer') {
          if (t['toAccount'] == _selectedAccount) totalIn += _txAmount(t);
          if (t['account'] == _selectedAccount) totalOut += _txAmount(t);
        }
      }
    }

    final initial = _openingBalanceForReport(filtered);
    double current;
    if (_selectedDateRange != null) {
      current = _balanceThroughDay(_selectedDateRange!.end);
    } else if (filtered.isNotEmpty) {
      current = (filtered.first['running_balance'] as num).toDouble();
    } else {
      current = initial;
    }

    // Keep summary consistent: opening + flows = closing (within rounding).
    final reconciled = initial + totalIn - totalOut;
    if ((current - reconciled).abs() > 0.01) {
      current = reconciled;
    }

    return {
      'initial': initial,
      'totalIn': totalIn,
      'totalOut': totalOut,
      'current': current,
      'categoryOnly': false,
    };
  }

  Future<void> _shareSingleTransactionInUrdu(Map t) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          const Center(child: CircularProgressIndicator(color: Colors.green)),
    );

    try {
      String date = t['date'].split('T')[0];
      String title = (t['title'] ?? "No Title").toString();
      String desc = _safeGetDescription(t);
      String amtStr = t['amount'].toString();
      String typeInfo = t['type'] == 'Income'
          ? 'آمدنی'
          : (t['type'] == 'Expense' ? 'خرچ' : 'ٹرانسفر');

      String tTitle = await ReportTranslationService.toUrdu(title);
      String tDesc = await ReportTranslationService.toUrdu(desc);

      if (mounted) Navigator.pop(context);

      String shareText = "🧾 **رسید کی تفصیلات**\n";
      shareText += "------------------------\n";
      shareText += "📅 تاریخ: $date\n";
      shareText += "📌 عنوان: $tTitle\n";
      if (tDesc.isNotEmpty) {
        shareText += "📝 تفصیل: $tDesc\n";
      }
      shareText += "🔄 قسم: $typeInfo\n";
      shareText += "💵 رقم: $amtStr روپے\n";
      shareText += "------------------------\n";
      shareText += "ایپ: Budget Pro";

      Share.share(shareText);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ترجمہ کرنے میں مسئلہ ہوا: $e")));
    }
  }

  Future<void> _runExport(Future<void> Function() action, String label) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label failed: $e')),
        );
      }
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    var filteredData = _getFilteredData();
    var summary = _calculateDetailedSummary(filteredData);

    return Column(
      children: [
        _buildFilterHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                ExpenseCharts(
                  transactions: filteredData,
                  categories: widget.categories,
                  selectedCategory: _selectedCategory,
                  periodExpenseTotal: summary['totalOut'] as double,
                ),
                const SizedBox(height: 15),
                _buildSummaryCard(summary, "Statement Overview"),
                const SizedBox(height: 15),
                ...filteredData.map((t) => _buildTransactionCard(t)),
                const SizedBox(height: 15),
                _buildSummaryCard(summary, "Final Settlement Summary"),
                const SizedBox(height: 20),
                _buildActionButtons(filteredData, summary),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFilterHeader() {
    // لائیو بیلنس نکالیں
    Map<String, double> balances = _calculateAccountBalances();

    final accountOptions = [
      'All Accounts',
      ...widget.accounts.map((a) => a['name'].toString()).toSet(),
    ];
    final categoryOptions = [
      'All Categories',
      ...widget.categories.map((c) => c['name'].toString()).toSet(),
    ];
    final safeAccount = accountOptions.contains(_selectedAccount)
        ? _selectedAccount
        : 'All Accounts';
    final safeCategory = categoryOptions.contains(_selectedCategory)
        ? _selectedCategory
        : 'All Categories';
    final safeSubCategory = _subCategoryOptions.contains(_selectedSubCategory)
        ? _selectedSubCategory
        : 'All Sub-categories';

    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.indigo.withOpacity(0.1),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search Title, Description, Category, Amount...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // --- اکاؤنٹ ڈراپ ڈاؤن (Overflow Fix) ---
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: safeAccount,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Account",
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: accountOptions.map((e) {
                    double bal = balances[e] ?? 0.0;
                    String label = "$e (${CurrencyService.fmt(bal)})";

                    return DropdownMenuItem(
                      value: e,
                      child: Text(
                        label,
                        overflow: TextOverflow
                            .ellipsis, // اگر نام بڑا ہو تو ڈاٹ بن جائیں
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedAccount = v ?? 'All Accounts'),
                ),
              ),
              const SizedBox(width: 8),
              // --- کیٹیگری ڈراپ ڈاؤن (Overflow Fix) ---
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: safeCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Category",
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  items: categoryOptions
                      .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              e,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _selectedCategory = v ?? 'All Categories';
                    _selectedSubCategory = 'All Sub-categories';
                  }),
                ),
              ),
            ],
          ),
          if (_categoryFilterActive) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: safeSubCategory,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Sub-category",
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              items: _subCategoryOptions
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _selectedSubCategory = v ?? 'All Sub-categories'),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _selectedDateRange = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month,
                      color: Colors.indigo, size: 18),
                  label: Text(
                    _selectedDateRange == null
                        ? "Select Date Range"
                        : "${DateFormat('dd/MM').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM').format(_selectedDateRange!.end)}",
                    style: const TextStyle(color: Colors.indigo, fontSize: 11),
                  ),
                ),
              ),
              if (_selectedDateRange != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.red, size: 20),
                  onPressed: () => setState(() => _selectedDateRange = null),
                )
              ]
            ],
          ),
        ],
      ),
    );
  }

  String _categoryLine(Map<String, dynamic> t) {
    final date = t['date'].toString().split('T')[0];
    final cat = (t['category'] ?? '').toString();
    final sub = (t['sub_category'] ?? '').toString().trim();
    if (sub.isEmpty) return '$date | $cat';
    return '$date | $cat › $sub';
  }

  Widget _buildTransactionCard(Map<String, dynamic> t) {
    final bool isPlus;
    if (_categoryFilterActive) {
      final change = _categoryBalanceChange(t);
      isPlus = change >= 0;
    } else {
      isPlus = (t['type'] == 'Income' ||
          (t['type'] == 'Transfer' && t['toAccount'] == _selectedAccount));
    }
    String dsc = _safeGetDescription(t);

    final effect = CategoryLedger.normalizeEffect(t['category_effect']);
    final showEffect = t['type'] == 'Transfer' && effect != null;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _showTransactionDetail(t),
        title: Text(t['title'] ?? "No Title",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              showEffect
                  ? '${_categoryLine(t)} ($effect)'
                  : _categoryLine(t),
              style: const TextStyle(fontSize: 11, color: Colors.blue),
            ),
            if (dsc.isNotEmpty)
              Text(dsc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("${isPlus ? '+' : '-'} ${CurrencyService.instance.formatNumber((t['amount'] as num).toDouble())}",
                style: TextStyle(
                    color: isPlus ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            if (_categoryFilterActive && t['category_running_balance'] != null)
              Text(
                "Cat: ${CurrencyService.instance.formatNumber((t['category_running_balance'] as num).toDouble())}",
                style: const TextStyle(fontSize: 10, color: Colors.indigo),
              )
            else if (t['running_balance'] != null)
              Text(
                "Bal: ${CurrencyService.instance.formatNumber((t['running_balance'] as num).toDouble())}",
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDetail(Map t) {
    String dsc = _safeGetDescription(t);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t['title'] ?? "Detail"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Date", t['date'].replaceAll('T', ' ')),
              _detailRow("Type", t['type']),
              _detailRow("Account", t['account']),
              if (t['type'] == 'Transfer') _detailRow("To", t['toAccount']),
              _detailRow("Category", t['category']),
              const Divider(),
              const Text("DESCRIPTION:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.indigo)),
              const SizedBox(height: 5),
              Text(dsc.isNotEmpty ? dsc : "No description provided.",
                  style: const TextStyle(fontSize: 14)),
              const Divider(),
              _detailRow("Amount", CurrencyService.fmt((t['amount'] as num).toDouble()), isBold: true),
              if (_categoryFilterActive && t['category_running_balance'] != null)
                _detailRow(
                    "Category total",
                    CurrencyService.fmt(
                        (t['category_running_balance'] as num).toDouble()),
                    isBold: true),
              _detailRow(
                  "Wallet balance",
                  CurrencyService.fmt((t['running_balance'] as num).toDouble()),
                  isBold: true),
            ],
          ),
        ),
        actions: [
          // نیا اضافہ: ایڈٹ بٹن
          if (widget.onEditTransaction != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(c); // ڈائیلاگ بند کریں
                widget.onEditTransaction!(t); // ایڈٹ سکرین کھولیں
              },
              icon: const Icon(Icons.edit, color: Colors.blue),
              label: const Text("ایڈٹ کریں",
                  style: TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(c);
              _shareSingleTransactionInUrdu(t);
            },
            icon: const Icon(Icons.language, color: Colors.green),
            label: const Text("اردو میں شیئر کریں",
                style: TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text("Close")),
        ],
      ),
    );
  }

  Widget _detailRow(String l, String v, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(v,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  String _formatPeriodHint() {
    if (_selectedDateRange == null) return '';
    final start = DateFormat('dd MMM yyyy').format(_selectedDateRange!.start);
    final end = DateFormat('dd MMM yyyy').format(_selectedDateRange!.end);
    return '$start → $end';
  }

  Widget _buildSummaryCard(Map<String, dynamic> s, String title) {
    final walletNow = _calculateAccountBalances()[_selectedAccount] ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: title.contains("Final") ? Colors.blueGrey[900] : Colors.indigo,
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          if (s['categoryOnly'] == true && !title.contains("Final")) ...[
            const SizedBox(height: 6),
            Text(
              _selectedDateRange == null
                  ? '$_selectedCategory · all dates (no opening row)'
                  : '$_selectedCategory · ${_formatPeriodHint()}\n'
                      'Cat Open = balance before period · Cat Net = In − Out in period',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 9),
            ),
          ],
          const SizedBox(height: 10),
          if (s['categoryOnly'] == true) ...[
            if (_selectedDateRange != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _summaryItem("Cat Open", (s['initial'] as num).toDouble()),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem("Cat In", (s['totalIn'] as num).toDouble()),
                _summaryItem("Cat Out", (s['totalOut'] as num).toDouble()),
                _summaryItem("Cat Net", (s['current'] as num).toDouble()),
              ],
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem("Period Open", (s['initial'] as num).toDouble()),
                _summaryItem("Total In", (s['totalIn'] as num).toDouble()),
                _summaryItem("Total Out", (s['totalOut'] as num).toDouble()),
              ],
            ),
          if (s['categoryOnly'] == true && title.contains("Final")) ...[
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CAT CLOSE (OPEN + NET)",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                    CurrencyService.fmt(
                        (s['closing'] as num?)?.toDouble() ??
                            ((s['initial'] as num).toDouble() +
                                (s['current'] as num).toDouble())),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          if (s['categoryOnly'] == true && !title.contains("Final")) ...[
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("FULL WALLET NOW",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                Text(CurrencyService.fmt(walletNow),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          if (s['categoryOnly'] != true) ...[
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CURRENT BALANCE",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                Text(CurrencyService.fmt((s['current'] as num).toDouble()),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryItem(String l, double v) {
    return Column(children: [
      Text(l, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      Text(CurrencyService.instance.formatNumber(v),
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildActionButtons(
      List<Map<String, dynamic>> data, Map<String, dynamic> s) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _runExport(
                  () => ReportExportService.shareEnglishDocx(
                    data: data,
                    summary: s,
                    selectedAccount: _selectedAccount,
                    selectedCategory: _selectedCategory,
                    dateRange: _selectedDateRange,
                  ),
                  'Word export',
                ),
                icon: const Icon(Icons.description_outlined),
                label: const Text("HTML / Word",
                    style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _runExport(
                  () => ReportExportService.shareExcelXlsx(
                    data: data,
                    summary: s,
                    selectedAccount: _selectedAccount,
                    selectedCategory: _selectedCategory,
                    dateRange: _selectedDateRange,
                  ),
                  'Excel export',
                ),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text("Excel (.xlsx)",
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _runExport(
                  () => ReportExportService.shareEnglishPdf(
                    data: data,
                    summary: s,
                    selectedAccount: _selectedAccount,
                    selectedCategory: _selectedCategory,
                    dateRange: _selectedDateRange,
                  ),
                  'English PDF',
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text("PDF English",
                    style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _runExport(
                  () => ReportExportService.shareUrduPdf(
                    data: data,
                    summary: s,
                    selectedAccount: _selectedAccount,
                    selectedCategory: _selectedCategory,
                    dateRange: _selectedDateRange,
                  ),
                  'Urdu PDF',
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text("PDF اردو",
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
