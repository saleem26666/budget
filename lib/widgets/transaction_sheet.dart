import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../services/currency_service.dart';
import '../services/exchange_rate_service.dart';
import '../utils/platform_utils.dart';
import '../utils/category_utils.dart';
import '../utils/document_scan_helper.dart';
import '../utils/image_helper.dart';
import 'full_screen_image.dart';

Future<void> showTransactionSheet({
  required BuildContext context,
  required List<Map<String, dynamic>> transactions,
  required List<Map<String, dynamic>> accounts,
  required List<Map<String, dynamic>> categories,
  required DateTime defaultDate,
  Map<String, dynamic>? editTx,
  List<String>? initialImages,
  List<String> familyMembers = const [],
  /// Create account in DB; return saved row (with name) or null on failure.
  Future<Map<String, dynamic>?> Function(String name, double openingBalance)?
      onCreateAccount,
  required Future<void> Function(Map<String, dynamic> data) onSave,
}) {
  final homeCode = CurrencyService.instance.code;
  final workingAccounts = List<Map<String, dynamic>>.from(accounts);
  const addAccountSentinel = '__add_new_account__';
  final titleC = TextEditingController(text: editTx?['title']?.toString() ?? '');
  final descC = TextEditingController(text: editTx?['desc']?.toString() ?? '');

  final editFxCurrency = editTx?['fx_currency']?.toString();
  final editFxAmount = editTx?['fx_amount'];
  final editFxRate = editTx?['fx_rate'];
  final bool editingFx = editFxCurrency != null &&
      editFxCurrency.isNotEmpty &&
      editFxAmount != null;

  final amountC = TextEditingController(
    text: editingFx
        ? editFxAmount.toString()
        : (editTx?['amount']?.toString() ?? ''),
  );
  final manualRateC = TextEditingController(
    text: editingFx &&
            editFxRate != null &&
            editFxCurrency.toUpperCase() != homeCode
        ? editFxRate.toString()
        : '',
  );

  String type = editTx?['type']?.toString() ?? 'Expense';
  String acc = editTx?['account']?.toString() ??
      (workingAccounts.isNotEmpty
          ? workingAccounts.first['name'].toString()
          : '');
  String toAcc = editTx?['toAccount']?.toString() ??
      (workingAccounts.length > 1
          ? workingAccounts[1]['name'].toString()
          : '');
  String cat = editTx?['category']?.toString() ??
      (categories.isNotEmpty ? categories.first['name'].toString() : 'General');
  String? subCat = editTx?['sub_category']?.toString();
  if (subCat != null && subCat.isEmpty) subCat = null;
  // Default: transfers do NOT affect category/budget unless user chooses +/-.
  String categoryEffect = editTx?['category_effect']?.toString() ?? '';
  if (categoryEffect != '+' &&
      categoryEffect != '-' &&
      categoryEffect != '') {
    categoryEffect = '';
  }
  String? memberName = editTx?['member_name']?.toString();
  if (memberName != null && memberName.isEmpty) memberName = null;

  String fxCurrency = editingFx ? editFxCurrency.toUpperCase() : homeCode;
  bool showManualRate = manualRateC.text.trim().isNotEmpty;
  bool ratesLoading = false;
  String? ratesError;
  bool ratesRequested = false;

  DateTime date = editTx != null
      ? DateTime.tryParse(editTx['date']?.toString() ?? '') ?? defaultDate
      : defaultDate;

  List<String> images = ImageHelper.decodeImagePaths(editTx?['imgs']);
  if (initialImages != null) {
    for (final p in initialImages) {
      if (p.isEmpty) continue;
      if (images.length >= 5) break;
      if (!images.contains(p)) images.add(p);
    }
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setSt) {
        if (!ratesRequested) {
          ratesRequested = true;
          Future.microtask(() async {
            setSt(() => ratesLoading = true);
            await ExchangeRateService.instance.ensureRates(homeCode);
            if (!context.mounted) return;
            setSt(() {
              ratesLoading = ExchangeRateService.instance.loading;
              ratesError = ExchangeRateService.instance.lastError;
            });
          });
        }

        final fxAmount = double.tryParse(amountC.text.trim()) ?? 0;
        final manualRate = double.tryParse(manualRateC.text.trim());
        final autoRate = ExchangeRateService.instance
            .rate(from: fxCurrency, to: homeCode);
        final effectiveRate = (fxCurrency == homeCode)
            ? 1.0
            : (manualRate != null && manualRate > 0
                ? manualRate
                : autoRate);
        final finalAmount = (effectiveRate == null)
            ? null
            : fxAmount * effectiveRate;
        final rateUpdated = ExchangeRateService.instance.lastUpdated;
        List<String> availableSubCats = [];
        try {
          final catObj = categories.firstWhere((e) => e['name'] == cat);
          availableSubCats = parseSubCategories(catObj['sub_categories']);
        } catch (_) {}
        if (subCat != null && !availableSubCats.contains(subCat)) {
          subCat = null;
        }

        final accountNames = workingAccounts
            .map((e) => e['name'].toString())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort(compareNames);
        final categoryNames = categories
            .map((e) => e['name'].toString())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList()
          ..sort(compareNames);
        availableSubCats.sort(compareNames);
        if (!accountNames.contains(acc) && accountNames.isNotEmpty) {
          acc = accountNames.first;
        }
        if (!categoryNames.contains(cat) && categoryNames.isNotEmpty) {
          cat = categoryNames.first;
        }

        Future<void> createAccountAndSelect(
            {required bool forToAccount}) async {
          if (onCreateAccount == null) return;
          final nameC = TextEditingController();
          final balC = TextEditingController(text: '0');
          final created = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (dCtx) => AlertDialog(
              title: const Text('New account'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameC,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Account name',
                      hintText: 'e.g. JazzCash, HBL',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: balC,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Opening balance',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = nameC.text.trim();
                    if (name.isEmpty) return;
                    final exists = workingAccounts.any((a) =>
                        a['name'].toString().toLowerCase() ==
                        name.toLowerCase());
                    if (exists) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Account "$name" already exists'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    final bal = double.tryParse(balC.text.trim()) ?? 0;
                    final row = await onCreateAccount(name, bal);
                    if (row != null && dCtx.mounted) {
                      Navigator.pop(dCtx, row);
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            ),
          );
          if (created == null) {
            setSt(() {}); // reset dropdown selection
            return;
          }
          setSt(() {
            workingAccounts.add(created);
            final name = created['name'].toString();
            if (forToAccount) {
              toAcc = name;
            } else {
              acc = name;
            }
          });
        }

        List<DropdownMenuItem<String>> accountMenuItems() => [
              ...accountNames.map(
                (e) => DropdownMenuItem(value: e, child: Text(e)),
              ),
              if (onCreateAccount != null)
                const DropdownMenuItem(
                  value: addAccountSentinel,
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline,
                          size: 20, color: AppTheme.primary),
                      SizedBox(width: 8),
                      Text(
                        'Add new account',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ];

        Future<void> pickReceiptScan() async {
          if (images.length >= 5) return;
          try {
            final path = await DocumentScanHelper.pickDocumentImage(context);
            if (path != null) setSt(() => images.add(path));
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not scan image: $e')),
              );
            }
          }
        }

        Future<void> pickFromCamera() async {
          if (images.length >= 5) return;
          try {
            final path = await DocumentScanHelper.pickNormalCamera();
            if (path != null) setSt(() => images.add(path));
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not take photo: $e')),
              );
            }
          }
        }

        Future<void> pickFromGallery() async {
          if (images.length >= 5) return;
          try {
            final path = await DocumentScanHelper.pickNormalGallery();
            if (path != null) setSt(() => images.add(path));
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not pick image: $e')),
              );
            }
          }
        }

        return Container(
          margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 12,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
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
                    editTx == null ? 'New Transaction' : 'Edit Transaction',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'Expense',
                          label: Text('Expense'),
                          icon: Icon(Icons.arrow_upward)),
                      ButtonSegment(
                          value: 'Income',
                          label: Text('Income'),
                          icon: Icon(Icons.arrow_downward)),
                      ButtonSegment(
                          value: 'Transfer',
                          label: Text('Transfer'),
                          icon: Icon(Icons.sync_alt)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setSt(() {
                      type = s.first;
                      if (type != 'Transfer') categoryEffect = '';
                    }),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_rounded,
                        color: AppTheme.primary),
                    title: const Text('Date'),
                    subtitle: Text(DateFormat('EEE, dd MMM yyyy').format(date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setSt(() => date = picked);
                    },
                  ),
                  TextField(
                    controller: titleC,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descC,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: CurrencyService.currencies
                            .any((c) => c.code == fxCurrency)
                        ? fxCurrency
                        : homeCode,
                    items: CurrencyService.currencies
                        .map((c) => DropdownMenuItem(
                              value: c.code,
                              child: Text('${c.code} — ${c.name}'),
                            ))
                        .toList(),
                    onChanged: (v) => setSt(() {
                      fxCurrency = (v ?? homeCode).toUpperCase();
                      if (fxCurrency == homeCode) {
                        showManualRate = false;
                        manualRateC.clear();
                      }
                    }),
                    decoration: InputDecoration(
                      labelText: 'Currency',
                      prefixIcon: const Icon(Icons.currency_exchange),
                      helperText: fxCurrency != homeCode
                          ? 'Remittance / foreign spend → converts to $homeCode at today’s rate'
                          : 'Home currency (Settings → Default currency)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountC,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSt(() {}),
                    decoration: InputDecoration(
                      labelText: 'Amount ($fxCurrency)',
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                  ),
                  if (fxCurrency != homeCode) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Final amount ($homeCode)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (ratesLoading)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  tooltip: 'Refresh rates',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                      minWidth: 28, minHeight: 28),
                                  icon: const Icon(Icons.refresh, size: 18),
                                  onPressed: () async {
                                    setSt(() => ratesLoading = true);
                                    await ExchangeRateService.instance
                                        .ensureRates(homeCode,
                                            forceRefresh: true);
                                    if (!context.mounted) return;
                                    setSt(() {
                                      ratesLoading =
                                          ExchangeRateService.instance.loading;
                                      ratesError = ExchangeRateService
                                          .instance.lastError;
                                    });
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            finalAmount == null
                                ? '—'
                                : CurrencyService.instance
                                    .format(finalAmount),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            effectiveRate == null
                                ? (ratesError != null
                                    ? 'Rate unavailable — enter manual rate'
                                    : 'Fetching rate…')
                                : '1 $fxCurrency = ${NumberFormat('#,##0.####').format(effectiveRate)} $homeCode'
                                    '${rateUpdated != null && (manualRate == null || manualRate <= 0) ? ' · ${DateFormat('dd MMM HH:mm').format(rateUpdated)}' : ''}'
                                    '${manualRate != null && manualRate > 0 ? ' · manual' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: ratesError != null && effectiveRate == null
                                  ? Colors.red.shade700
                                  : Colors.grey.shade600,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setSt(() => showManualRate = !showManualRate),
                            child: Text(showManualRate
                                ? 'Hide manual rate'
                                : 'Use manual rate'),
                          ),
                          if (showManualRate)
                            TextField(
                              controller: manualRateC,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setSt(() {}),
                              decoration: InputDecoration(
                                labelText: 'Manual rate (1 $fxCurrency → $homeCode)',
                                prefixIcon: const Icon(Icons.tune),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: accountNames.contains(acc) ? acc : null,
                    items: accountMenuItems(),
                    onChanged: (v) async {
                      if (v == addAccountSentinel) {
                        await createAccountAndSelect(forToAccount: false);
                      } else if (v != null) {
                        setSt(() => acc = v);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Account'),
                  ),
                  if (type == 'Transfer') ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: accountNames.contains(toAcc) ? toAcc : null,
                      items: accountMenuItems(),
                      onChanged: (v) async {
                        if (v == addAccountSentinel) {
                          await createAccountAndSelect(forToAccount: true);
                        } else if (v != null) {
                          setSt(() => toAcc = v);
                        }
                      },
                      decoration:
                          const InputDecoration(labelText: 'To Account'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: categoryNames.contains(cat) ? cat : null,
                          items: categoryNames
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setSt(() {
                            cat = v ?? cat;
                            subCat = null;
                          }),
                          decoration:
                              const InputDecoration(labelText: 'Category'),
                        ),
                      ),
                      if (type == 'Transfer') ...[
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            children: [
                              const Text(
                                'Budget',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _CatEffectChip(
                                    label: '∅',
                                    selected: categoryEffect.isEmpty,
                                    color: Colors.grey,
                                    onTap: () =>
                                        setSt(() => categoryEffect = ''),
                                  ),
                                  const SizedBox(width: 4),
                                  _CatEffectChip(
                                    label: '+',
                                    selected: categoryEffect == '+',
                                    color: AppTheme.income,
                                    onTap: () =>
                                        setSt(() => categoryEffect = '+'),
                                  ),
                                  const SizedBox(width: 4),
                                  _CatEffectChip(
                                    label: '−',
                                    selected: categoryEffect == '-',
                                    color: AppTheme.expense,
                                    onTap: () =>
                                        setSt(() => categoryEffect = '-'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (familyMembers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: memberName != null &&
                              familyMembers.contains(memberName)
                          ? memberName
                          : null,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No family member'),
                        ),
                        ...familyMembers.map((m) => DropdownMenuItem<String?>(
                              value: m,
                              child: Text(m),
                            )),
                      ],
                      onChanged: (v) => setSt(() => memberName = v),
                      decoration: const InputDecoration(
                        labelText: 'Family member (optional)',
                        prefixIcon: Icon(Icons.family_restroom),
                      ),
                    ),
                  ],
                  if (availableSubCats.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: subCat,
                      items: availableSubCats
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setSt(() => subCat = v),
                      decoration: const InputDecoration(
                        labelText: 'Sub Category',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('Receipts (${images.length}/5)',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (images.length < 5) ...[
                        if (supportsDeviceCamera)
                          IconButton(
                            tooltip: 'Camera (normal photo)',
                            onPressed: pickFromCamera,
                            icon: const Icon(Icons.camera_alt_outlined),
                          ),
                        if (supportsDeviceCamera)
                          IconButton(
                            tooltip: 'Scan receipt (edge detect)',
                            onPressed: pickReceiptScan,
                            icon: const Icon(Icons.document_scanner_outlined),
                          ),
                        IconButton(
                          tooltip: 'Gallery',
                          onPressed: pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                        ),
                      ],
                    ],
                  ),
                  if (images.isNotEmpty)
                    SizedBox(
                      height: 88,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        itemBuilder: (c, i) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        FullScreenImage(imagePath: images[i]),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: kIsWeb
                                      ? Image.network(images[i],
                                          width: 80, height: 80, fit: BoxFit.cover)
                                      : Image.file(File(images[i]),
                                          width: 80, height: 80, fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: GestureDetector(
                                  onTap: () => setSt(() => images.removeAt(i)),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: AppTheme.expense,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () async {
                      if (titleC.text.trim().isEmpty ||
                          amountC.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Title and amount required')),
                        );
                        return;
                      }
                      final entered = double.tryParse(amountC.text.trim());
                      if (entered == null || entered <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid amount')),
                        );
                        return;
                      }
                      if (type == 'Transfer') {
                        if (toAcc.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Select a To Account')),
                          );
                          return;
                        }
                        if (toAcc == acc) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'To Account must be different from Account')),
                          );
                          return;
                        }
                      }
                      if (fxCurrency != homeCode &&
                          (effectiveRate == null || finalAmount == null)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Rate not available — refresh or enter a manual rate'),
                          ),
                        );
                        return;
                      }
                      final savedHomeAmount =
                          fxCurrency == homeCode ? entered : finalAmount!;
                      final savedRate =
                          fxCurrency == homeCode ? 1.0 : effectiveRate!;
                      final savedImages =
                          await ImageHelper.persistPaths(images, 'tx');
                      final now = DateTime.now();
                      final existingTime = editTx != null
                          ? DateTime.tryParse(editTx['date']?.toString() ?? '')
                          : null;
                      final data = {
                        'title': titleC.text.trim(),
                        'desc': descC.text.trim(),
                        'amount': savedHomeAmount,
                        'type': type,
                        'account': acc,
                        'toAccount': type == 'Transfer' ? toAcc : '',
                        'category': cat,
                        'sub_category': subCat,
                        'category_effect': type == 'Transfer'
                            ? (categoryEffect == '+' || categoryEffect == '-'
                                ? categoryEffect
                                : '')
                            : '',
                        'date': DateTime(
                          date.year,
                          date.month,
                          date.day,
                          existingTime?.hour ?? now.hour,
                          existingTime?.minute ?? now.minute,
                        ).toIso8601String(),
                        'imgs': jsonEncode(savedImages),
                        'fx_currency': fxCurrency,
                        'fx_amount': entered,
                        'fx_rate': savedRate,
                        'member_name': memberName ?? '',
                      };
                      await onSave(data);
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: AppTheme.primary,
                    ),
                    child: const Text('Save Transaction'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _CatEffectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _CatEffectChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

