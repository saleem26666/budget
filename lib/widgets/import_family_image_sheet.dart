import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';
import '../utils/image_helper.dart';

/// Bottom sheet: save shared image(s) as one Family Document.
class ImportFamilyImageSheet extends StatefulWidget {
  final List<String> imagePaths;
  final VoidCallback? onSaved;

  const ImportFamilyImageSheet({
    super.key,
    required this.imagePaths,
    this.onSaved,
  });

  /// Shows sheet; returns true if saved.
  static Future<bool> show(
    BuildContext context, {
    required List<String> imagePaths,
    VoidCallback? onSaved,
  }) async {
    if (imagePaths.isEmpty) return false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ImportFamilyImageSheet(
        imagePaths: imagePaths,
        onSaved: onSaved,
      ),
    );
    return result == true;
  }

  @override
  State<ImportFamilyImageSheet> createState() => _ImportFamilyImageSheetState();
}

class _ImportFamilyImageSheetState extends State<ImportFamilyImageSheet> {
  static const _types = [
    'Identity',
    'Education',
    'Medical',
    'Finance',
    'Other',
  ];

  final _newPersonC = TextEditingController();
  final _docNumberC = TextEditingController();
  List<String> _people = [];
  String? _selectedPerson;
  bool _useNewPerson = false;
  String _docType = 'Identity';
  DateTime? _expiry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _newPersonC.dispose();
    _docNumberC.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    final rows = await DatabaseHelper.instance.getFamilyVault();
    final names = <String>{};
    for (final r in rows) {
      final n = (r['member_name'] ?? '').toString().trim();
      if (n.isNotEmpty) names.add(n);
    }
    final sorted = names.toList()..sort();
    if (!mounted) return;
    setState(() {
      _people = sorted;
      if (sorted.isNotEmpty) {
        _selectedPerson = sorted.first;
        _useNewPerson = false;
      } else {
        _useNewPerson = true;
      }
    });
  }

  String get _personName {
    if (_useNewPerson) return _newPersonC.text.trim();
    return (_selectedPerson ?? '').trim();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    final person = _personName;
    if (person.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Person name required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final savedPaths = await ImageHelper.persistPaths(
        widget.imagePaths,
        'family_share',
      );
      if (savedPaths.isEmpty) {
        throw Exception('Could not copy images');
      }
      await DatabaseHelper.instance.addFamilyVault({
        'member_name': person,
        'doc_type': _docType,
        'doc_number': _docNumberC.text.trim().isEmpty
            ? null
            : _docNumberC.text.trim(),
        'expiry_date':
            _expiry == null ? null : DateFormat('yyyy-MM-dd').format(_expiry!),
        'images': jsonEncode(savedPaths),
        'notes': null,
      });
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
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
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Save to Family Documents',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 88,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.imagePaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = widget.imagePaths[i];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(p),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 88,
                          height: 88,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text('Person', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              if (_people.isNotEmpty && !_useNewPerson)
                DropdownButtonFormField<String>(
                  value: _selectedPerson,
                  items: [
                    ..._people.map(
                      (n) => DropdownMenuItem(value: n, child: Text(n)),
                    ),
                    const DropdownMenuItem(
                      value: '__new__',
                      child: Text('+ New person'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == '__new__') {
                      setState(() => _useNewPerson = true);
                    } else {
                      setState(() => _selectedPerson = v);
                    }
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )
              else ...[
                TextField(
                  controller: _newPersonC,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Person name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (_people.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _useNewPerson = false),
                    child: const Text('Pick existing person'),
                  ),
              ],
              const SizedBox(height: 12),
              Text('Document type',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _docType,
                items: _types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _docType = v);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _docNumberC,
                decoration: const InputDecoration(
                  labelText: 'Doc number (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _expiry == null
                      ? 'Expiry (optional)'
                      : 'Expiry: ${DateFormat('dd MMM yyyy').format(_expiry!)}',
                ),
                trailing: IconButton(
                  icon: Icon(_expiry == null
                      ? Icons.calendar_today
                      : Icons.clear),
                  onPressed: _expiry == null
                      ? _pickExpiry
                      : () => setState(() => _expiry = null),
                ),
                onTap: _pickExpiry,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
