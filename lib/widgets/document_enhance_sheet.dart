import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../utils/document_image_filters.dart';
import '../utils/document_ocr.dart';

/// After scan: pick filter (CamScanner-style) + optional OCR.
class DocumentEnhanceSheet extends StatefulWidget {
  final String imagePath;
  final bool offerOcr;

  const DocumentEnhanceSheet({
    super.key,
    required this.imagePath,
    this.offerOcr = true,
  });

  /// Returns the final image path (filtered or original), or null if cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String imagePath,
    bool offerOcr = true,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentEnhanceSheet(
        imagePath: imagePath,
        offerOcr: offerOcr,
      ),
    );
  }

  @override
  State<DocumentEnhanceSheet> createState() => _DocumentEnhanceSheetState();
}

class _DocumentEnhanceSheetState extends State<DocumentEnhanceSheet> {
  DocFilter _filter = DocFilter.enhance;
  String? _previewPath;
  bool _busy = false;
  bool _ocrBusy = false;
  DocumentOcrResult? _ocr;

  @override
  void initState() {
    super.initState();
    _previewPath = widget.imagePath;
    _rebuildPreview();
  }

  Future<void> _rebuildPreview() async {
    setState(() => _busy = true);
    try {
      final path =
          await DocumentImageFilters.applyAndSave(widget.imagePath, _filter);
      if (!mounted) return;
      setState(() {
        _previewPath = path;
        _ocr = null;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _previewPath = widget.imagePath;
        _busy = false;
      });
    }
  }

  Future<void> _runOcr() async {
    final path = _previewPath ?? widget.imagePath;
    if (!DocumentOcr.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('OCR works on Android/iOS phone (not desktop)')),
      );
      return;
    }
    setState(() => _ocrBusy = true);
    final result = await DocumentOcr.recognize(path);
    if (!mounted) return;
    setState(() {
      _ocr = result;
      _ocrBusy = false;
    });
    if (result == null || result.fullText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text found in this image')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewPath ?? widget.imagePath;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Improve scan',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Edge crop done — pick a filter (CamScanner style)',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.38,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(File(preview), fit: BoxFit.contain),
                        if (_busy)
                          Container(
                            color: Colors.black26,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: DocFilter.values.map((f) {
                      final sel = f == _filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: sel,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(() => _filter = f);
                                  _rebuildPreview();
                                },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (widget.offerOcr) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _ocrBusy ? null : _runOcr,
                      icon: _ocrBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.text_snippet_outlined),
                      label: const Text('Read text (OCR)'),
                    ),
                  ),
                ],
                if (_ocr != null && _ocr!.fullText.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 120),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_ocr!.cnic != null)
                            Text('CNIC: ${_ocr!.cnic}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary)),
                          if (_ocr!.amountHint != null)
                            Text('Amount?: ${_ocr!.amountHint}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal.shade800)),
                          const SizedBox(height: 4),
                          Text(_ocr!.fullText,
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final buf = StringBuffer(_ocr!.fullText);
                        if (_ocr!.cnic != null) {
                          buf.writeln('\nCNIC: ${_ocr!.cnic}');
                        }
                        await Clipboard.setData(
                            ClipboardData(text: buf.toString()));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Text copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy text'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.pop(
                                context, _previewPath ?? widget.imagePath),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary),
                        child: const Text('Use image'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
