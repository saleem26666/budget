import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';

import '../utils/share_file_helper.dart';
import 'budget_alert_service.dart';
import 'currency_service.dart';
import 'report_translation_service.dart';

enum StatementPdfLanguage { english, urdu }

class ReportExportService {
  static pw.Font? _urduFont;
  static const _assetFont = 'assets/fonts/NotoSansArabic.ttf';

  static Future<pw.Font> _loadUrduFont() async {
    if (_urduFont != null) return _urduFont!;
    try {
      final data = await rootBundle.load(_assetFont);
      _urduFont = pw.Font.ttf(data);
      return _urduFont!;
    } catch (_) {
      // Fallback if asset missing (e.g. hot reload without full rebuild)
      final res = await http.get(Uri.parse(
        'https://github.com/google/fonts/raw/main/ofl/notosansarabic/NotoSansArabic%5Bwdth,wght%5D.ttf',
      ));
      if (res.statusCode != 200) {
        throw Exception(
          'Urdu font not found. Reinstall the app or check assets/fonts/NotoSansArabic.ttf',
        );
      }
      _urduFont = pw.Font.ttf(res.bodyBytes.buffer.asByteData());
      return _urduFont!;
    }
  }

  static String _desc(Map t) =>
      (t['desc'] ?? t['description'] ?? '').toString();

  static bool _isCategoryReport(String selectedCategory) =>
      selectedCategory != 'All Categories' && selectedCategory.isNotEmpty;

  static String _openingSummaryLabel({
    required bool urdu,
    required String selectedCategory,
  }) {
    if (_isCategoryReport(selectedCategory)) {
      return urdu
          ? 'کیٹگری ابتدائی (مدت سے پہلے)'
          : 'Opening category (before period)';
    }
    return urdu
        ? 'ابتدائی بیلنس (مدت کی شروعات)'
        : 'Opening balance (start of period)';
  }

  static String _netSummaryLabel({
    required bool urdu,
    required String selectedCategory,
  }) {
    if (_isCategoryReport(selectedCategory)) {
      return urdu ? 'کیٹگری خالص (مدت)' : 'Category net (period)';
    }
    return urdu ? 'خالص بیلنس' : 'Net balance';
  }

  static String _closingSummaryLabel({
    required bool urdu,
    required String selectedCategory,
  }) {
    if (_isCategoryReport(selectedCategory)) {
      return urdu ? 'کیٹگری اختتام (ابتدائی + خالص)' : 'Category close (open + net)';
    }
    return urdu ? 'خالص بیلنس' : 'Net balance';
  }

  static double _summaryClosing(Map<String, dynamic> summary) {
    final closing = summary['closing'];
    if (closing != null) return (closing as num).toDouble();
    return (summary['initial'] as num).toDouble() +
        (summary['current'] as num).toDouble();
  }

  static String _escapeHtml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// English statement as Word document (.doc — opens in Microsoft Word)
  static Future<void> shareEnglishDocx({
    required List<Map<String, dynamic>> data,
    required Map<String, dynamic> summary,
    required String selectedAccount,
    required String selectedCategory,
    required DateTimeRange? dateRange,
  }) async {
    final dateRangeStr = dateRange == null
        ? 'All Time'
        : '${DateFormat('dd-MMM-yyyy').format(dateRange.start)} to ${DateFormat('dd-MMM-yyyy').format(dateRange.end)}';

    final rows = StringBuffer();
    for (final t in data.reversed) {
      final date = t['date'].toString().split('T')[0];
      final title = _escapeHtml((t['title'] ?? 'No Title').toString());
      final desc = _escapeHtml(_desc(t));
      final isPlus = t['type'] == 'Income' ||
          (t['type'] == 'Transfer' && t['toAccount'] == selectedAccount);
      final amt =
          '${isPlus ? '+' : '-'} ${CurrencyService.fmt((t['amount'] as num).toDouble())}';
      rows.writeln(
        '<tr><td>$date</td><td>$title</td><td>$desc</td><td>${t['type']}</td>'
        '<td>${_escapeHtml((t['sub_category'] ?? '').toString())}</td>'
        '<td>$amt</td><td>${t['running_balance']}</td></tr>',
      );
    }

    final html = '''
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word">
<head><meta charset="utf-8"><title>Account Statement</title>
<style>
  body { font-family: Calibri, Arial, sans-serif; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #ccc; padding: 6px; font-size: 11pt; }
  th { background: #4F46E5; color: white; }
  h1 { color: #4F46E5; }
</style>
</head>
<body>
<h1>Professional Account Statement</h1>
<p><b>Account:</b> ${_escapeHtml(selectedAccount)}</p>
<p><b>Category:</b> ${_escapeHtml(selectedCategory)}</p>
<p><b>Period:</b> $dateRangeStr</p>
<p><b>Generated:</b> ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}</p>
<p><b>${_openingSummaryLabel(urdu: false, selectedCategory: selectedCategory)}:</b> ${CurrencyService.fmt((summary['initial'] as num).toDouble())}</p>
<table>
<tr>
  <th>Date</th><th>Title</th><th>Description</th><th>Type</th>
  <th>Sub-Category</th><th>Amount</th><th>Balance</th>
</tr>
$rows
</table>
<h2>Summary</h2>
<p>Opening: ${CurrencyService.fmt((summary['initial'] as num).toDouble())}</p>
<p>${_isCategoryReport(selectedCategory) ? 'Category in' : 'Total In'}: ${CurrencyService.fmt((summary['totalIn'] as num).toDouble())}</p>
<p>${_isCategoryReport(selectedCategory) ? 'Category out' : 'Total Out'}: ${CurrencyService.fmt((summary['totalOut'] as num).toDouble())}</p>
<p>${_netSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['current'] as num).toDouble())}</p>
${_isCategoryReport(selectedCategory) ? '<p><b>${_closingSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt(_summaryClosing(summary))}</b></p>' : '<p><b>Net Balance: ${CurrencyService.fmt((summary['current'] as num).toDouble())}</b></p>'}
<p><i>Budget Pro</i></p>
</body></html>''';

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final docPath = '${dir.path}/BudgetPro_Statement_EN_$ts.doc';
    final htmlPath = '${dir.path}/BudgetPro_Statement_EN_$ts.html';
    await File(docPath).writeAsString(html);
    await File(htmlPath).writeAsString(html);
    // HTML opens in browser, Drive, WPS; .doc for desktop Word
    await ShareFileHelper.share(
      path: htmlPath,
      fileName: 'BudgetPro_Statement_EN.html',
      mimeType: 'text/html',
      text: 'Budget Pro statement (open in browser, WPS, Google Docs, or Word)',
    );
  }

  /// Real Excel .xlsx
  static Future<void> shareExcelXlsx({
    required List<Map<String, dynamic>> data,
    required Map<String, dynamic> summary,
    required String selectedAccount,
    required String selectedCategory,
    required DateTimeRange? dateRange,
  }) async {
    final excel = Excel.createExcel();
    final defaultName = excel.getDefaultSheet();
    if (defaultName != null) {
      excel.rename(defaultName, 'Statement');
    }
    final sheet = excel['Statement'];

    void row(List<CellValue?> cells) => sheet.appendRow(cells);

    row([TextCellValue('Budget Pro — Account Statement')]);
    row([TextCellValue('Account'), TextCellValue(selectedAccount)]);
    row([TextCellValue('Category'), TextCellValue(selectedCategory)]);
    if (dateRange != null) {
      row([
        TextCellValue('From'),
        TextCellValue(DateFormat('yyyy-MM-dd').format(dateRange.start)),
        TextCellValue('To'),
        TextCellValue(DateFormat('yyyy-MM-dd').format(dateRange.end)),
      ]);
    }
    row([]);
    row([
      TextCellValue('Date'),
      TextCellValue('Title'),
      TextCellValue('Description'),
      TextCellValue('Category'),
      TextCellValue('Sub Category'),
      TextCellValue('Type'),
      TextCellValue('Account'),
      TextCellValue(CurrencyService.instance.amountLabel()),
      TextCellValue('Balance (${CurrencyService.instance.code})'),
    ]);

    for (final t in data.reversed) {
      final isPlus = t['type'] == 'Income' ||
          (t['type'] == 'Transfer' && t['toAccount'] == selectedAccount);
      final amt = (t['amount'] as num).toDouble();
      row([
        TextCellValue(t['date'].toString().split('T')[0]),
        TextCellValue((t['title'] ?? '').toString()),
        TextCellValue(_desc(t)),
        TextCellValue((t['category'] ?? '').toString()),
        TextCellValue((t['sub_category'] ?? '').toString()),
        TextCellValue((t['type'] ?? '').toString()),
        TextCellValue((t['account'] ?? '').toString()),
        DoubleCellValue(isPlus ? amt : -amt),
        DoubleCellValue((t['running_balance'] as num?)?.toDouble() ?? 0),
      ]);
    }

    row([]);
    row([TextCellValue('SUMMARY')]);
    row([
      TextCellValue('Opening (start of period)'),
      DoubleCellValue((summary['initial'] as num).toDouble()),
    ]);
    row([
      TextCellValue('Total In'),
      DoubleCellValue((summary['totalIn'] as num).toDouble()),
    ]);
    row([
      TextCellValue('Total Out'),
      DoubleCellValue((summary['totalOut'] as num).toDouble()),
    ]);
    row([
      TextCellValue('Net Balance'),
      DoubleCellValue((summary['current'] as num).toDouble()),
    ]);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel encode failed');

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/Statement_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await File(path).writeAsBytes(bytes);
    await ShareFileHelper.share(
      path: path,
      fileName: 'BudgetPro_Statement.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      text: 'Budget Pro Excel statement',
    );
  }

  static Future<void> shareEnglishPdf({
    required List<Map<String, dynamic>> data,
    required Map<String, dynamic> summary,
    required String selectedAccount,
    required String selectedCategory,
    required DateTimeRange? dateRange,
  }) =>
      shareStatementPdf(
        language: StatementPdfLanguage.english,
        data: data,
        summary: summary,
        selectedAccount: selectedAccount,
        selectedCategory: selectedCategory,
        dateRange: dateRange,
      );

  /// Urdu statement PDF
  static Future<void> shareUrduPdf({
    required List<Map<String, dynamic>> data,
    required Map<String, dynamic> summary,
    required String selectedAccount,
    required String selectedCategory,
    required DateTimeRange? dateRange,
  }) =>
      shareStatementPdf(
        language: StatementPdfLanguage.urdu,
        data: data,
        summary: summary,
        selectedAccount: selectedAccount,
        selectedCategory: selectedCategory,
        dateRange: dateRange,
      );

  /// Statement PDF — English (LTR) or Urdu (RTL).
  static Future<void> shareStatementPdf({
    required StatementPdfLanguage language,
    required List<Map<String, dynamic>> data,
    required Map<String, dynamic> summary,
    required String selectedAccount,
    required String selectedCategory,
    required DateTimeRange? dateRange,
  }) async {
    final urdu = language == StatementPdfLanguage.urdu;
    final pw.Font font;
    if (urdu) {
      font = await _loadUrduFont();
    } else {
      font = pw.Font.helvetica();
    }
    final style = pw.TextStyle(font: font, fontSize: 11);
    final styleBold = pw.TextStyle(font: font, fontSize: 12, fontWeight: pw.FontWeight.bold);
    final styleTitle = pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold);

    final textDir =
        urdu ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final dateRangeStr = dateRange == null
        ? (urdu
            ? ReportTranslationService.fixedOrSelf('All Time')
            : 'All Time')
        : urdu
            ? '${DateFormat('dd-MMM-yyyy').format(dateRange.start)} سے ${DateFormat('dd-MMM-yyyy').format(dateRange.end)}'
            : '${DateFormat('dd-MMM-yyyy').format(dateRange.start)} to ${DateFormat('dd-MMM-yyyy').format(dateRange.end)}';

    final tAccount = urdu
        ? ReportTranslationService.fixedOrSelf(selectedAccount)
        : selectedAccount;
    final tCategory = urdu
        ? (selectedCategory == 'All Categories'
            ? ReportTranslationService.fixedOrSelf('All Categories')
            : await ReportTranslationService.toUrdu(selectedCategory))
        : selectedCategory;

    final doc = pw.Document();
    final lines = <pw.Widget>[
      pw.Text(
        urdu ? 'اکاؤنٹ سٹیٹمنٹ' : 'Account Statement',
        style: styleTitle,
        textDirection: textDir,
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        urdu ? 'اکاؤنٹ: $tAccount' : 'Account: $tAccount',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu ? 'کیٹگری: $tCategory' : 'Category: $tCategory',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu ? 'مدت: $dateRangeStr' : 'Period: $dateRangeStr',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu
            ? 'وقت: ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}'
            : 'Generated: ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}',
        style: style,
        textDirection: textDir,
      ),
      pw.Divider(),
      pw.Text(
        urdu
            ? '${_openingSummaryLabel(urdu: true, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['initial'] as num).toDouble())}'
            : '${_openingSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['initial'] as num).toDouble())}',
        style: styleBold,
        textDirection: textDir,
      ),
      pw.SizedBox(height: 12),
    ];

    if (selectedCategory != 'All Categories' && selectedCategory.isNotEmpty) {
      final subData = BudgetAlertService.subCategoryExpenses(
        data,
        forCategory: selectedCategory,
      );
      if (subData.isNotEmpty) {
        final catTotal = subData.values.fold<double>(0, (a, b) => a + b);
        lines.add(
          pw.Text(
            urdu
                ? 'ذیلی کیٹگری کا خلاصہ ($tCategory)'
                : 'Sub-category summary ($tCategory)',
            style: styleBold,
            textDirection: textDir,
          ),
        );
        lines.add(
          pw.Text(
            urdu
                ? 'کل خرچ: ${CurrencyService.fmt(catTotal)}'
                : 'Total: ${CurrencyService.fmt(catTotal)}',
            style: style,
            textDirection: textDir,
          ),
        );
        for (final e in subData.entries) {
          final subName =
              urdu ? await ReportTranslationService.toUrdu(e.key) : e.key;
          final pct = catTotal == 0 ? 0.0 : (e.value / catTotal) * 100;
          lines.add(
            pw.Text(
              urdu
                  ? '$subName: ${CurrencyService.fmt(e.value)} (${pct.toStringAsFixed(0)}%)'
                  : '$subName: ${CurrencyService.fmt(e.value)} (${pct.toStringAsFixed(0)}%)',
              style: style,
              textDirection: textDir,
            ),
          );
        }
        lines.add(pw.SizedBox(height: 12));
      }
    } else {
      final breakdown = BudgetAlertService.subCategoryExpenses(data);
      if (breakdown.isNotEmpty) {
        lines.add(
          pw.Text(
            urdu ? 'کیٹگری و ذیلی کیٹگری خلاصہ' : 'Category & sub-category summary',
            style: styleBold,
            textDirection: textDir,
          ),
        );
        for (final e in breakdown.entries) {
          lines.add(
            pw.Text(
              '${e.key}: ${CurrencyService.fmt(e.value)}',
              style: style,
              textDirection: textDir,
            ),
          );
        }
        lines.add(pw.SizedBox(height: 12));
      }
    }

    for (final t in data.reversed) {
      final date = t['date'].toString().split('T')[0];
      final rawTitle = (t['title'] ?? 'No Title').toString();
      final title = urdu
          ? await ReportTranslationService.toUrdu(rawTitle)
          : rawTitle;
      final desc = _desc(t);
      final tDesc = desc.isEmpty
          ? ''
          : (urdu ? await ReportTranslationService.toUrdu(desc) : desc);
      final typeInfo = urdu
          ? await ReportTranslationService.typeLabelUrdu(
              t['type'].toString(),
              account: t['account']?.toString(),
              toAccount: t['toAccount']?.toString(),
              selectedAccount: selectedAccount,
            )
          : _englishTypeLabel(t, selectedAccount);
      final isPlus = t['type'] == 'Income' ||
          (t['type'] == 'Transfer' && t['toAccount'] == selectedAccount);
      final amtStr =
          '${isPlus ? '+' : '-'} ${CurrencyService.fmt((t['amount'] as num).toDouble())}';
      final sub = (t['sub_category'] ?? '').toString().trim();
      final subLine = sub.isEmpty
          ? ''
          : (urdu
              ? 'ذیلی کیٹگری: ${await ReportTranslationService.toUrdu(sub)}'
              : 'Sub-category: $sub');

      lines.addAll([
        pw.Text(
          urdu ? 'تاریخ: $date' : 'Date: $date',
          style: style,
          textDirection: textDir,
        ),
        pw.Text(
          urdu ? 'عنوان: $title' : 'Title: $title',
          style: style,
          textDirection: textDir,
        ),
        if (tDesc.isNotEmpty)
          pw.Text(
            urdu ? 'تفصیل: $tDesc' : 'Description: $tDesc',
            style: style,
            textDirection: textDir,
          ),
        if (subLine.isNotEmpty)
          pw.Text(subLine, style: style, textDirection: textDir),
        pw.Text(
          urdu ? 'قسم: $typeInfo' : 'Type: $typeInfo',
          style: style,
          textDirection: textDir,
        ),
        pw.Text(
          urdu ? 'رقم: $amtStr' : 'Amount: $amtStr',
          style: style,
          textDirection: textDir,
        ),
        pw.Text(
          urdu
              ? 'بیلنس: ${CurrencyService.fmt((t['running_balance'] as num).toDouble())}'
              : 'Balance: ${CurrencyService.fmt((t['running_balance'] as num).toDouble())}',
          style: style,
          textDirection: textDir,
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.grey300),
      ]);
    }

    lines.addAll([
      pw.SizedBox(height: 12),
      pw.Text(
        urdu ? 'حتمی خلاصہ' : 'Final summary',
        style: styleTitle,
        textDirection: textDir,
      ),
      pw.Text(
        urdu
            ? '${_openingSummaryLabel(urdu: true, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['initial'] as num).toDouble())}'
            : '${_openingSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['initial'] as num).toDouble())}',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu
            ? '${_isCategoryReport(selectedCategory) ? 'کیٹگری آمدنی' : 'کل آمدنی'}: ${CurrencyService.fmt((summary['totalIn'] as num).toDouble())}'
            : '${_isCategoryReport(selectedCategory) ? 'Category in' : 'Total in'}: ${CurrencyService.fmt((summary['totalIn'] as num).toDouble())}',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu
            ? '${_isCategoryReport(selectedCategory) ? 'کیٹگری خرچ' : 'کل خرچ'}: ${CurrencyService.fmt((summary['totalOut'] as num).toDouble())}'
            : '${_isCategoryReport(selectedCategory) ? 'Category out' : 'Total out'}: ${CurrencyService.fmt((summary['totalOut'] as num).toDouble())}',
        style: style,
        textDirection: textDir,
      ),
      pw.Text(
        urdu
            ? '${_netSummaryLabel(urdu: true, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['current'] as num).toDouble())}'
            : '${_netSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt((summary['current'] as num).toDouble())}',
        style: _isCategoryReport(selectedCategory) ? style : styleBold,
        textDirection: textDir,
      ),
      if (_isCategoryReport(selectedCategory))
        pw.Text(
          urdu
              ? '${_closingSummaryLabel(urdu: true, selectedCategory: selectedCategory)}: ${CurrencyService.fmt(_summaryClosing(summary))}'
              : '${_closingSummaryLabel(urdu: false, selectedCategory: selectedCategory)}: ${CurrencyService.fmt(_summaryClosing(summary))}',
          style: styleBold,
          textDirection: textDir,
        ),
      pw.SizedBox(height: 8),
      pw.Text('Budget Pro', style: style, textDirection: textDir),
    ]);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: urdu ? pw.TextDirection.rtl : textDir,
        build: (_) => lines,
      ),
    );

    final outDir = await getTemporaryDirectory();
    final fileName = urdu
        ? 'BudgetPro_Statement_Urdu.pdf'
        : 'BudgetPro_Statement_English.pdf';
    final path = '${outDir.path}/$fileName';
    await File(path).writeAsBytes(await doc.save());
    await ShareFileHelper.share(
      path: path,
      fileName: fileName,
      mimeType: 'application/pdf',
      text: urdu ? 'Budget Pro Urdu PDF statement' : 'Budget Pro English PDF statement',
    );
  }

  static String _englishTypeLabel(Map t, String selectedAccount) {
    final type = t['type'].toString();
    if (type == 'Transfer') {
      if (t['toAccount'] == selectedAccount) {
        return 'Transfer (received from ${t['account']})';
      }
      if (t['account'] == selectedAccount) {
        return 'Transfer (sent to ${t['toAccount']})';
      }
    }
    return type;
  }
}
