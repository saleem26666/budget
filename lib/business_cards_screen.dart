import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'utils/document_ocr.dart';
import 'utils/document_scan_helper.dart';
import 'utils/image_helper.dart';
import 'widgets/full_screen_image.dart';

/// Vault → Business Cards: scan with edge detection, auto-title from heading,
/// master search across full OCR text on every card.
class BusinessCardsPage extends StatefulWidget {
  const BusinessCardsPage({super.key});

  @override
  State<BusinessCardsPage> createState() => _BusinessCardsPageState();
}

class _BusinessCardsPageState extends State<BusinessCardsPage> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;
  bool _scanning = false;
  String _query = '';
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final list = _query.trim().isEmpty
          ? await DatabaseHelper.instance.getBusinessCards()
          : await DatabaseHelper.instance.searchBusinessCards(_query);
      if (!mounted) return;
      setState(() {
        _cards = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load cards: $e')),
      );
    }
  }

  Future<void> _scanAndSave() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final path = await DocumentScanHelper.pickDocumentImage(context);
      if (path == null || !mounted) return;

      final saved = await ImageHelper.copyToAppStorage(path, 'biz_card');

      String title = 'Business Card';
      String ocrText = '';
      if (DocumentOcr.isSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reading card text…'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        final ocr = await DocumentOcr.recognize(saved);
        if (ocr != null) {
          ocrText = ocr.fullText;
          final heading = ocr.heading?.trim();
          if (heading != null && heading.isNotEmpty) {
            title = heading;
          }
        }
      }

      if (!mounted) return;
      final confirmed = await _confirmTitleDialog(
        initialTitle: title,
        ocrPreview: ocrText,
        imagePath: saved,
      );
      if (confirmed == null) return;

      await DatabaseHelper.instance.addBusinessCard({
        'title': confirmed.trim().isEmpty ? 'Business Card' : confirmed.trim(),
        'ocr_text': ocrText,
        'notes': '',
        'image_path': saved,
        'created_at': DateTime.now().toIso8601String(),
      });
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business card saved'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<String?> _confirmTitleDialog({
    required String initialTitle,
    required String ocrPreview,
    required String imagePath,
  }) async {
    final c = TextEditingController(text: initialTitle);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save business card'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: kIsWeb
                      ? Image.network(imagePath, fit: BoxFit.cover)
                      : Image.file(File(imagePath), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Card title',
                  hintText: 'Auto-detected heading — edit if needed',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              if (ocrPreview.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Detected text (used for master search)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      ocrPreview,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _openCard(Map<String, dynamic> card) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessCardDetailPage(
          cardId: card['id'] as int,
          onChanged: _refresh,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _deleteCard(Map<String, dynamic> card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete card?'),
        content: Text('Remove "${card['title'] ?? 'Business Card'}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteBusinessCard(card['id'] as int);
    final path = card['image_path']?.toString();
    if (path != null && path.isNotEmpty && !kIsWeb) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Business Cards'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _scanAndSave,
        icon: const Icon(Icons.document_scanner_rounded),
        label: const Text('Scan card'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchC,
              decoration: InputDecoration(
                hintText: 'Master search — name, Dr, company, phone…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchC.clear();
                          setState(() => _query = '');
                          _refresh();
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                setState(() => _query = v);
                _refresh();
              },
            ),
          ),
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_cards.length} card${_cards.length == 1 ? '' : 's'} match “${_query.trim()}”',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _cards.isEmpty
                    ? _buildEmpty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: _cards.length,
                        itemBuilder: (_, i) => _buildCardTile(_cards[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.badge_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _query.trim().isEmpty
                  ? 'No business cards yet'
                  : 'No cards match your search',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _query.trim().isEmpty
                  ? 'Tap Scan card — edge detect + auto title from heading'
                  : 'Try another name, title, or word from the card',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardTile(Map<String, dynamic> card) {
    final title = (card['title'] ?? 'Business Card').toString();
    final ocr = (card['ocr_text'] ?? '').toString();
    final path = card['image_path']?.toString();
    String? created;
    try {
      final raw = card['created_at']?.toString();
      if (raw != null && raw.isNotEmpty) {
        created = DateFormat('dd MMM yyyy').format(DateTime.parse(raw));
      }
    } catch (_) {}

    String? snippet;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty && ocr.isNotEmpty) {
      final lower = ocr.toLowerCase();
      final idx = lower.indexOf(q);
      if (idx >= 0) {
        final start = (idx - 24).clamp(0, ocr.length);
        final end = (idx + q.length + 40).clamp(0, ocr.length);
        snippet =
            '${start > 0 ? '…' : ''}${ocr.substring(start, end)}${end < ocr.length ? '…' : ''}';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openCard(card),
        onLongPress: () => _deleteCard(card),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 52,
                  child: path != null && path.isNotEmpty
                      ? (kIsWeb
                          ? Image.network(path, fit: BoxFit.cover)
                          : Image.file(File(path),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _thumbPlaceholder()))
                      : _thumbPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (snippet != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                    ] else if (created != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        created,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: AppTheme.primary.withValues(alpha: 0.1),
      child: const Icon(Icons.badge_outlined, color: AppTheme.primary),
    );
  }
}

class BusinessCardDetailPage extends StatefulWidget {
  final int cardId;
  final VoidCallback onChanged;

  const BusinessCardDetailPage({
    super.key,
    required this.cardId,
    required this.onChanged,
  });

  @override
  State<BusinessCardDetailPage> createState() => _BusinessCardDetailPageState();
}

class _BusinessCardDetailPageState extends State<BusinessCardDetailPage> {
  Map<String, dynamic>? _card;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await DatabaseHelper.instance.getBusinessCards();
    Map<String, dynamic>? found;
    for (final c in all) {
      if (c['id'] == widget.cardId) {
        found = c;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _card = found;
      _loading = false;
    });
  }

  Future<void> _editTitle() async {
    final card = _card;
    if (card == null) return;
    final c = TextEditingController(text: (card['title'] ?? '').toString());
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Card title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null || next.isEmpty) return;
    await DatabaseHelper.instance.updateBusinessCard(widget.cardId, {
      'title': next,
    });
    widget.onChanged();
    await _load();
  }

  Future<void> _editNotes() async {
    final card = _card;
    if (card == null) return;
    final c = TextEditingController(text: (card['notes'] ?? '').toString());
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Extra notes (also searchable)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null) return;
    await DatabaseHelper.instance.updateBusinessCard(widget.cardId, {
      'notes': next,
    });
    widget.onChanged();
    await _load();
  }

  Future<void> _share() async {
    final card = _card;
    if (card == null) return;
    final path = card['image_path']?.toString();
    final title = (card['title'] ?? 'Business Card').toString();
    final ocr = (card['ocr_text'] ?? '').toString();
    if (path != null && path.isNotEmpty && !kIsWeb && await File(path).exists()) {
      await Share.shareXFiles(
        [XFile(path)],
        text: '$title\n\n$ocr'.trim(),
      );
    } else {
      await Share.share('$title\n\n$ocr'.trim());
    }
  }

  Future<void> _reOcr() async {
    final card = _card;
    if (card == null) return;
    final path = card['image_path']?.toString();
    if (path == null || path.isEmpty || !DocumentOcr.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR not available on this device')),
      );
      return;
    }
    final ocr = await DocumentOcr.recognize(path);
    if (ocr == null) return;
    final updates = <String, dynamic>{'ocr_text': ocr.fullText};
    final currentTitle = (card['title'] ?? '').toString().trim();
    if ((currentTitle.isEmpty || currentTitle == 'Business Card') &&
        ocr.heading != null &&
        ocr.heading!.trim().isNotEmpty) {
      updates['title'] = ocr.heading!.trim();
    }
    await DatabaseHelper.instance.updateBusinessCard(widget.cardId, updates);
    widget.onChanged();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OCR refreshed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final card = _card;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Business Card')),
        body: const Center(child: Text('Card not found')),
      );
    }

    final title = (card['title'] ?? 'Business Card').toString();
    final path = card['image_path']?.toString();
    final ocr = (card['ocr_text'] ?? '').toString();
    final notes = (card['notes'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit title',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editTitle,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (path != null && path.isNotEmpty)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenImage(imagePath: path),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: kIsWeb
                      ? Image.network(path, fit: BoxFit.cover)
                      : Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Title',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            subtitle: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editTitle,
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notes',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            subtitle: Text(
              notes.isEmpty ? 'Tap to add notes' : notes,
              style: TextStyle(
                color: notes.isEmpty ? Colors.grey : Colors.black87,
              ),
            ),
            trailing: const Icon(Icons.notes_outlined),
            onTap: _editNotes,
          ),
          const Divider(),
          Row(
            children: [
              const Text(
                'Card text (OCR)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _reOcr,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Re-read'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              ocr.trim().isEmpty ? 'No text detected on this card' : ocr,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ocr.trim().isEmpty ? Colors.grey : Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
