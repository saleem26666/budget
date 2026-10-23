import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';
import '../utils/document_image_filters.dart';
import '../utils/document_ocr.dart';

/// After scan: pick filter (CamScanner-style) + optional OCR.
///
/// Uses an opaque full-screen route (not a transparent sheet) so Android
/// reliably redraws after the native document-scanner Activity closes.
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
    // rootNavigator: true — works even when opened from an AlertDialog
    // (Family Documents add form), which otherwise leaves a blank surface.
    return Navigator.of(context, rootNavigator: true).push<String>(
      PageRouteBuilder<String>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.white,
            ),
            child: DocumentEnhanceSheet(
              imagePath: imagePath,
              offerOcr: offerOcr,
            ),
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<DocumentEnhanceSheet> createState() => _DocumentEnhanceSheetState();
}

class _DocumentEnhanceSheetState extends State<DocumentEnhanceSheet> {
  DocFilter _filter = DocFilter.original;
  String? _previewPath;
  bool _busy = false;
  bool _ocrBusy = false;
  DocumentOcrResult? _ocr;
  final Map<DocFilter, String> _cache = {};

  @override
  void initState() {
    super.initState();
    // Keep Original by default so "Use image" is instant — no auto Improving.
    _previewPath = widget.imagePath;
    _cache[DocFilter.original] = widget.imagePath;
  }

  Future<void> _rebuildPreview() async {
    if (_filter == DocFilter.original) {
      setState(() {
        _previewPath = widget.imagePath;
        _ocr = null;
        _busy = false;
      });
      return;
    }
    final cached = _cache[_filter];
    if (cached != null) {
      setState(() {
        _previewPath = cached;
        _ocr = null;
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final path =
          await DocumentImageFilters.applyAndSave(widget.imagePath, _filter);
      if (!mounted) return;
      _cache[_filter] = path;
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Improve scan'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap Use image to keep the scan, or pick a filter',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.grey.shade100,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(preview),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined, size: 48),
                          ),
                        ),
                        if (_busy)
                          Container(
                            color: Colors.black26,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 10),
                                  Text(
                                    'Improving…',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.text_snippet_outlined),
                    label: const Text('Read text (OCR)'),
                  ),
                ),
              ],
              if (_ocr != null && _ocr!.fullText.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 100),
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
    );
  }
}
