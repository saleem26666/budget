import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'services/currency_service.dart';
import 'services/investment_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<Map<String, dynamic>> _holdings = [];
  String _filterType = 'All';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseHelper.instance.getInvestments();
    if (mounted) {
      setState(() {
        _holdings = rows;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filterType == 'All') return _holdings;
    return _holdings
        .where((h) => (h['asset_type'] ?? '').toString() == _filterType)
        .toList();
  }

  Future<void> _openForm({Map<String, dynamic>? edit}) async {
    final nameC =
        TextEditingController(text: edit?['name']?.toString() ?? '');
    final symbolC =
        TextEditingController(text: edit?['symbol']?.toString() ?? '');
    final qtyC = TextEditingController(
        text: edit != null ? InvestmentService.qty(edit).toString() : '');
    final buyC = TextEditingController(
        text: edit != null ? InvestmentService.avgBuy(edit).toString() : '');
    final curC = TextEditingController(
        text: edit != null
            ? InvestmentService.currentPrice(edit).toString()
            : '');
    final brokerC =
        TextEditingController(text: edit?['broker']?.toString() ?? '');
    final notesC =
        TextEditingController(text: edit?['notes']?.toString() ?? '');
    String assetType = edit?['asset_type']?.toString() ??
        InvestmentService.assetTypes.first;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  edit == null ? 'Add Investment' : 'Edit Holding',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    hintText: 'e.g. HBL Shares, Sui Gas, Gold',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: assetType,
                  decoration: const InputDecoration(labelText: 'Asset type'),
                  items: InvestmentService.assetTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) =>
                      setSheet(() => assetType = v ?? assetType),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: symbolC,
                  decoration: const InputDecoration(
                    labelText: 'Symbol / Code (optional)',
                    hintText: 'HBL, Meezan Fund, BTC',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: assetType == 'Gold'
                              ? 'Quantity (tola) *'
                              : 'Quantity *',
                          hintText: assetType == 'Gold'
                              ? 'e.g. 1.5 tola'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: buyC,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: assetType == 'Gold'
                              ? '${CurrencyService.instance.priceLabel('Buy / tola')} *'
                              : '${CurrencyService.instance.priceLabel('Buy price')} *',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: curC,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: assetType == 'Gold'
                        ? '${CurrencyService.instance.priceLabel('Current / tola')} *'
                        : '${CurrencyService.instance.priceLabel('Current price')} *',
                    hintText: assetType == 'Gold'
                        ? 'Paste today’s tola rate (Karachi/Lahore)'
                        : 'Update anytime for live P/L',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: brokerC,
                  decoration: const InputDecoration(
                    labelText: 'Broker / Platform',
                    hintText: 'PSX, CDC, Bank, Binance',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesC,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final name = nameC.text.trim();
                    final qty = double.tryParse(qtyC.text.trim()) ?? 0;
                    final buy = double.tryParse(buyC.text.trim()) ?? 0;
                    var cur = double.tryParse(curC.text.trim()) ?? buy;
                    if (name.isEmpty || qty <= 0 || buy <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Name, quantity & buy price required')),
                      );
                      return;
                    }
                    if (cur <= 0) cur = buy;
                    final now = DateTime.now().toIso8601String();
                    final row = {
                      'name': name,
                      'asset_type': assetType,
                      'symbol': symbolC.text.trim(),
                      'quantity': qty,
                      'avg_buy_price': buy,
                      'current_price': cur,
                      'broker': brokerC.text.trim(),
                      'notes': notesC.text.trim(),
                      'updated_date': now,
                    };
                    if (edit == null) {
                      row['created_date'] = now;
                      await DatabaseHelper.instance.addInvestment(row);
                    } else {
                      row['created_date'] =
                          edit['created_date']?.toString() ?? now;
                      await DatabaseHelper.instance.updateInvestment(
                          edit['id'] as int, row);
                    }
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  },
                  child: Text(edit == null ? 'Save Investment' : 'Update'),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );

    if (saved == true) await _load();
  }

  Future<void> _deleteHolding(Map<String, dynamic> h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove holding?'),
        content: Text('Delete "${h['name']}" from portfolio?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteInvestment(h['id'] as int);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final summary = InvestmentService.portfolioSummary(filtered);
    final allocation = InvestmentService.allocationByType(filtered);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'Add investment',
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                children: [
                  _summaryCard(summary),
                  if (allocation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _allocationSection(allocation),
                  ],
                  const SizedBox(height: 8),
                  _filterChips(),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.trending_up_rounded,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _holdings.isEmpty
                                ? 'No investments yet'
                                : 'No holdings in this category',
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap + to track stocks, funds, gold & more',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map(_holdingTile),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(Map<String, dynamic> s) {
    final gl = (s['gainLoss'] as num).toDouble();
    final positive = gl >= 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B21B6), Color(0xFF4F46E5), Color(0xFF3730A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: Colors.white70),
              const SizedBox(width: 8),
              const Text('Portfolio Value',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const Spacer(),
              Text('${s['count']} holdings',
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyService.fmt((s['value'] as num).toDouble()),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _miniStat('Invested',
                    CurrencyService.fmt((s['invested'] as num).toDouble())),
              ),
              Expanded(
                child: _miniStat(
                  'P/L',
                  '${positive ? '+' : ''}${gl.toStringAsFixed(0)}',
                  sub: '${(s['gainPct'] as num).toStringAsFixed(1)}%',
                  color: positive ? AppTheme.income : AppTheme.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value,
      {String? sub, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        if (sub != null)
          Text(sub,
              style: TextStyle(
                  color: color ?? Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _allocationSection(Map<String, double> data) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Asset allocation',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 28,
                        sections: data.entries.toList().asMap().entries.map((e) {
                          final i = e.key;
                          final entry = e.value;
                          final pct =
                              total == 0 ? 0.0 : (entry.value / total) * 100;
                          return PieChartSectionData(
                            value: entry.value,
                            title: '${pct.toStringAsFixed(0)}%',
                            color: InvestmentService.colorForType(entry.key),
                            radius: 44,
                            titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: data.entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: InvestmentService.colorForType(e.key),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(e.key,
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChips() {
    final types = ['All', ...InvestmentService.assetTypes];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: types.map((t) {
          final sel = _filterType == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(t, style: const TextStyle(fontSize: 12)),
              selected: sel,
              onSelected: (_) => setState(() => _filterType = t),
              selectedColor: AppTheme.primary.withValues(alpha: 0.15),
              checkmarkColor: AppTheme.primary,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _holdingTile(Map<String, dynamic> h) {
    final type = (h['asset_type'] ?? 'Other').toString();
    final gl = InvestmentService.gainLoss(h);
    final pct = InvestmentService.gainPct(h);
    final positive = gl >= 0;
    final symbol = h['symbol']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openForm(edit: h),
        onLongPress: () => _deleteHolding(h),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: InvestmentService.colorForType(type)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(InvestmentService.iconForType(type),
                    color: InvestmentService.colorForType(type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(h['name']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      '$type${symbol.isNotEmpty ? ' · $symbol' : ''} · '
                      'Qty ${InvestmentService.qty(h).toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600),
                    ),
                    if ((h['broker'] ?? '').toString().isNotEmpty)
                      Text(h['broker'].toString(),
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyService.fmt(InvestmentService.marketValue(h)),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    '${positive ? '+' : ''}${gl.toStringAsFixed(0)} '
                    '(${pct.toStringAsFixed(1)}%)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: positive ? AppTheme.income : AppTheme.expense,
                    ),
                  ),
                  Text(
                    'Cur ${InvestmentService.currentPrice(h).toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
