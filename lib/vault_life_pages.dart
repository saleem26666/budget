import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'utils/document_scan_helper.dart';
import 'utils/image_helper.dart';
import 'utils/platform_utils.dart';
import 'widgets/full_screen_image.dart';

const _birthdayAccent = Color(0xFFEC4899);
const _anniversaryAccent = Color(0xFFBE185D);
const _documentAccent = Color(0xFF7C3AED);
const _reminderAccent = Color(0xFF0EA5E9);

DateTime? parseStoredDate(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

DateTime nextBirthdayOf(DateTime birth, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  var next = DateTime(today.year, birth.month, birth.day);
  if (next.isBefore(today)) {
    next = DateTime(today.year + 1, birth.month, birth.day);
  }
  return next;
}

int turningAge(DateTime birth, DateTime next) {
  final age = next.year - birth.year;
  return age < 0 ? 0 : age;
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.bmp');
}

List<Map<String, String>> decodeVaultFiles(dynamic raw) {
  if (raw == null) return [];
  final text = raw.toString().trim();
  if (text.isEmpty || text == '[]') return [];
  try {
    final list = jsonDecode(text);
    if (list is! List) return [];
    return list.map((e) {
      if (e is String) {
        return {
          'path': e,
          'name': e.split(RegExp(r'[\\/]')).last,
          'kind': _isImagePath(e) ? 'image' : 'file',
        };
      }
      final map = Map<String, dynamic>.from(e as Map);
      final path = (map['path'] ?? '').toString();
      return {
        'path': path,
        'name': (map['name'] ?? path.split(RegExp(r'[\\/]')).last).toString(),
        'kind': (map['kind'] ?? (_isImagePath(path) ? 'image' : 'file'))
            .toString(),
      };
    }).toList();
  } catch (_) {
    return [];
  }
}

String encodeVaultFiles(List<Map<String, String>> files) => jsonEncode(files);

Future<void> _openAttachment(BuildContext context, Map<String, String> file) async {
  final path = file['path'] ?? '';
  if (path.isEmpty || !File(path).existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on this device')),
      );
    }
    return;
  }
  if (file['kind'] == 'image' || _isImagePath(path)) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FullScreenImage(imagePath: path)),
    );
    return;
  }
  await Share.shareXFiles(
    [XFile(path, name: file['name'] ?? 'document')],
    text: file['name'] ?? 'Document',
  );
}

InputDecoration _fieldDeco(String label, IconData icon, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
  );
}

// =============================================================================
// BIRTHDAY REMINDERS
// =============================================================================

class BirthdayRemindersPage extends StatefulWidget {
  const BirthdayRemindersPage({super.key});

  @override
  State<BirthdayRemindersPage> createState() => _BirthdayRemindersPageState();
}

class _BirthdayRemindersPageState extends State<BirthdayRemindersPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final rows = (await DatabaseHelper.instance.getVaultBirthdays())
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.sort((a, b) {
        final da = parseStoredDate(a['birth_date']);
        final db = parseStoredDate(b['birth_date']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return nextBirthdayOf(da).compareTo(nextBirthdayOf(db));
      });
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BirthdayEditorSheet(edit: item),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete birthday?'),
        content: Text('Remove ${(item['name'] ?? 'this person')} from reminders.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.expense),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteVaultBirthday(item['id'] as int);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Birthday Reminders'),
        backgroundColor: _birthdayAccent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _birthdayAccent,
        onPressed: () => _edit(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyVaultState(
                  icon: Icons.cake_rounded,
                  color: _birthdayAccent,
                  title: 'No birthdays yet',
                  subtitle: 'Add family and friends so you never miss a birthday',
                  actionLabel: 'Add birthday',
                  onAction: () => _edit(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final birth = parseStoredDate(item['birth_date']);
                    final next = birth == null ? null : nextBirthdayOf(birth);
                    final today = DateTime.now();
                    final isToday = next != null &&
                        next.year == today.year &&
                        next.month == today.month &&
                        next.day == today.day;
                    final days = next?.difference(
                            DateTime(today.year, today.month, today.day))
                        .inDays;
                    final age = birth == null || next == null
                        ? null
                        : turningAge(birth, next);
                    return Card(
                      child: ListTile(
                        onTap: () => _edit(item: item),
                        onLongPress: () => _delete(item),
                        leading: CircleAvatar(
                          backgroundColor: (isToday ? AppTheme.expense : _birthdayAccent)
                              .withValues(alpha: 0.15),
                          child: Icon(
                            isToday ? Icons.celebration_rounded : Icons.cake_outlined,
                            color: isToday ? AppTheme.expense : _birthdayAccent,
                          ),
                        ),
                        title: Text(
                          (item['name'] ?? 'Someone').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [
                            if ((item['relation'] ?? '').toString().trim().isNotEmpty)
                              item['relation'].toString(),
                            if (next != null)
                              isToday
                                  ? (age == null
                                      ? 'Today'
                                      : 'Turns $age today')
                                  : (age == null
                                      ? DateFormat('dd MMM').format(next)
                                      : 'Turns $age · ${DateFormat('dd MMM').format(next)}'),
                          ].join(' · '),
                        ),
                        trailing: days == null
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (isToday ? AppTheme.expense : _birthdayAccent)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isToday ? 'Today' : '${days}d',
                                  style: TextStyle(
                                    color: isToday ? AppTheme.expense : _birthdayAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _BirthdayEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? edit;
  const _BirthdayEditorSheet({this.edit});

  @override
  State<_BirthdayEditorSheet> createState() => _BirthdayEditorSheetState();
}

class _BirthdayEditorSheetState extends State<_BirthdayEditorSheet> {
  late final TextEditingController _nameC;
  late final TextEditingController _notesC;
  String _relation = 'Family';
  DateTime? _birth;
  int _remindDays = 3;

  static const _relations = ['Family', 'Friend', 'Colleague', 'Other'];
  static const _remindOptions = [0, 1, 3, 7, 14];

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _nameC = TextEditingController(text: e?['name']?.toString() ?? '');
    _notesC = TextEditingController(text: e?['notes']?.toString() ?? '');
    final rel = (e?['relation'] ?? 'Family').toString();
    _relation = _relations.contains(rel) ? rel : 'Other';
    _birth = parseStoredDate(e?['birth_date']);
    _remindDays = int.tryParse('${e?['remind_days'] ?? 3}') ?? 3;
  }

  @override
  void dispose() {
    _nameC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty || _birth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and date are required')),
      );
      return;
    }
    final data = {
      'name': name,
      'relation': _relation,
      'birth_date': DateFormat('yyyy-MM-dd').format(_birth!),
      'notes': _notesC.text.trim(),
      'remind_days': _remindDays,
      'created_at': widget.edit?['created_at'] ?? DateTime.now().toIso8601String(),
    };
    if (widget.edit == null) {
      await DatabaseHelper.instance.addVaultBirthday(data);
    } else {
      await DatabaseHelper.instance
          .updateVaultBirthday(widget.edit!['id'] as int, data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                widget.edit == null ? 'Add birthday' : 'Edit birthday',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameC,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDeco('Name', Icons.person_outline),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _relation,
                items: _relations
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => _relation = v ?? 'Family'),
                decoration: _fieldDeco('Relation', Icons.favorite_outline),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded, color: _birthdayAccent),
                title: Text(
                  _birth == null
                      ? 'Pick birthday date'
                      : DateFormat('dd MMMM yyyy').format(_birth!),
                ),
                subtitle: const Text('Year is used to show their age'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _birth ?? DateTime(2000, 1, 1),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _birth = picked);
                },
              ),
              DropdownButtonFormField<int>(
                value: _remindOptions.contains(_remindDays) ? _remindDays : 3,
                items: _remindOptions
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d == 0 ? 'On the day' : '$d days before'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _remindDays = v ?? 3),
                decoration: _fieldDeco('Remind me', Icons.notifications_outlined),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesC,
                maxLines: 2,
                decoration: _fieldDeco('Notes (gift idea, etc.)', Icons.notes_rounded),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _birthdayAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                child: const Text('Save birthday'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MARRIAGE ANNIVERSARIES
// =============================================================================

class MarriageAnniversaryPage extends StatefulWidget {
  const MarriageAnniversaryPage({super.key});

  @override
  State<MarriageAnniversaryPage> createState() =>
      _MarriageAnniversaryPageState();
}

class _MarriageAnniversaryPageState extends State<MarriageAnniversaryPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final rows = (await DatabaseHelper.instance.getVaultAnniversaries())
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.sort((a, b) {
        final da = parseStoredDate(a['marriage_date']);
        final db = parseStoredDate(b['marriage_date']);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return nextBirthdayOf(da).compareTo(nextBirthdayOf(db));
      });
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnniversaryEditorSheet(edit: item),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete anniversary?'),
        content: Text(
            'Remove ${(item['name'] ?? 'this anniversary')} from reminders.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.expense),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteVaultAnniversary(item['id'] as int);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Marriage Anniversary'),
        backgroundColor: _anniversaryAccent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _anniversaryAccent,
        onPressed: () => _edit(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _EmptyVaultState(
                  icon: Icons.favorite_rounded,
                  color: _anniversaryAccent,
                  title: 'No anniversaries yet',
                  subtitle:
                      'Add wedding dates so you never miss a marriage anniversary',
                  actionLabel: 'Add anniversary',
                  onAction: () => _edit(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
                    final married = parseStoredDate(item['marriage_date']);
                    final next =
                        married == null ? null : nextBirthdayOf(married);
                    final today = DateTime.now();
                    final isToday = next != null &&
                        next.year == today.year &&
                        next.month == today.month &&
                        next.day == today.day;
                    final days = next
                        ?.difference(
                            DateTime(today.year, today.month, today.day))
                        .inDays;
                    final years = married == null || next == null
                        ? null
                        : turningAge(married, next);
                    return Card(
                      child: ListTile(
                        onTap: () => _edit(item: item),
                        onLongPress: () => _delete(item),
                        leading: CircleAvatar(
                          backgroundColor:
                              (isToday ? AppTheme.expense : _anniversaryAccent)
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            isToday
                                ? Icons.celebration_rounded
                                : Icons.favorite_outline_rounded,
                            color: isToday
                                ? AppTheme.expense
                                : _anniversaryAccent,
                          ),
                        ),
                        title: Text(
                          (item['name'] ?? 'Couple').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          next == null
                              ? 'No date'
                              : (isToday
                                  ? (years == null
                                      ? 'Today'
                                      : '$years years today')
                                  : (years == null
                                      ? DateFormat('dd MMM').format(next)
                                      : '$years years · ${DateFormat('dd MMM').format(next)}')),
                        ),
                        trailing: days == null
                            ? null
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: (isToday
                                          ? AppTheme.expense
                                          : _anniversaryAccent)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isToday ? 'Today' : '${days}d',
                                  style: TextStyle(
                                    color: isToday
                                        ? AppTheme.expense
                                        : _anniversaryAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AnniversaryEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? edit;
  const _AnniversaryEditorSheet({this.edit});

  @override
  State<_AnniversaryEditorSheet> createState() =>
      _AnniversaryEditorSheetState();
}

class _AnniversaryEditorSheetState extends State<_AnniversaryEditorSheet> {
  late final TextEditingController _nameC;
  late final TextEditingController _notesC;
  DateTime? _date;
  int _remindDays = 7;

  static const _remindOptions = [0, 1, 3, 7, 14, 30];

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _nameC = TextEditingController(text: e?['name']?.toString() ?? '');
    _notesC = TextEditingController(text: e?['notes']?.toString() ?? '');
    _date = parseStoredDate(e?['marriage_date']);
    _remindDays = int.tryParse('${e?['remind_days'] ?? 7}') ?? 7;
  }

  @override
  void dispose() {
    _nameC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameC.text.trim();
    if (name.isEmpty || _date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and marriage date are required')),
      );
      return;
    }
    final data = {
      'name': name,
      'marriage_date': DateFormat('yyyy-MM-dd').format(_date!),
      'notes': _notesC.text.trim(),
      'remind_days': _remindDays,
      'created_at':
          widget.edit?['created_at'] ?? DateTime.now().toIso8601String(),
    };
    if (widget.edit == null) {
      await DatabaseHelper.instance.addVaultAnniversary(data);
    } else {
      await DatabaseHelper.instance
          .updateVaultAnniversary(widget.edit!['id'] as int, data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                widget.edit == null ? 'Add anniversary' : 'Edit anniversary',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameC,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDeco(
                  'Couple / name',
                  Icons.favorite_outline,
                  hint: 'e.g. Ali & Sara',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_rounded,
                    color: _anniversaryAccent),
                title: Text(
                  _date == null
                      ? 'Pick marriage date'
                      : DateFormat('dd MMMM yyyy').format(_date!),
                ),
                subtitle: const Text('Year is used to show years married'),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date ?? DateTime(2015, 1, 1),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
              DropdownButtonFormField<int>(
                value: _remindOptions.contains(_remindDays) ? _remindDays : 7,
                items: _remindOptions
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child:
                              Text(d == 0 ? 'On the day' : '$d days before'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _remindDays = v ?? 7),
                decoration:
                    _fieldDeco('Remind me', Icons.notifications_outlined),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesC,
                maxLines: 2,
                decoration: _fieldDeco(
                    'Notes (gift, plan, etc.)', Icons.notes_rounded),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _anniversaryAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                child: const Text('Save anniversary'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// IMPORTANT DOCUMENTS
// =============================================================================

class ImportantDocumentsPage extends StatefulWidget {
  const ImportantDocumentsPage({super.key});

  @override
  State<ImportantDocumentsPage> createState() => _ImportantDocumentsPageState();
}

class _ImportantDocumentsPageState extends State<ImportantDocumentsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
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
      final rows = (await DatabaseHelper.instance.getVaultDocuments())
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((d) {
      final files = decodeVaultFiles(d['files']);
      final names = files.map((f) => f['name'] ?? '').join(' ');
      return '${d['title']} ${d['notes']} $names'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _edit({Map<String, dynamic>? item}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ImportantDocumentEditorPage(edit: item)),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _quickAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add important document',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: _documentAccent),
              title: const Text('Camera / Scan'),
              subtitle: const Text('Take a photo or scan the document'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file_rounded, color: _documentAccent),
              title: const Text('Choose file'),
              subtitle: const Text('PDF, image, or any file from storage'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Add details only'),
              onTap: () => Navigator.pop(ctx, 'form'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportantDocumentEditorPage(startWith: choice),
      ),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Important Documents'),
        backgroundColor: _documentAccent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _documentAccent,
        onPressed: _quickAdd,
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchC,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: 'Search documents…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchC.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? _EmptyVaultState(
                          icon: Icons.folder_special_rounded,
                          color: _documentAccent,
                          title: 'No documents yet',
                          subtitle: 'Add files from storage or capture with camera',
                          actionLabel: 'Add document',
                          onAction: _quickAdd,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final doc = filtered[i];
                            final files = decodeVaultFiles(doc['files']);
                            final created = parseStoredDate(doc['created_at']);
                            return Card(
                              child: ListTile(
                                onTap: () => _edit(item: doc),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      _documentAccent.withValues(alpha: 0.12),
                                  child: Icon(
                                    files.any((f) => f['kind'] == 'image')
                                        ? Icons.image_rounded
                                        : Icons.insert_drive_file_rounded,
                                    color: _documentAccent,
                                  ),
                                ),
                                title: Text(
                                  (doc['title'] ?? 'Untitled').toString(),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  [
                                    '${files.length} file${files.length == 1 ? '' : 's'}',
                                    if (created != null)
                                      DateFormat('dd MMM yyyy').format(created),
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class ImportantDocumentEditorPage extends StatefulWidget {
  final Map<String, dynamic>? edit;
  final String? startWith;
  const ImportantDocumentEditorPage({super.key, this.edit, this.startWith});

  @override
  State<ImportantDocumentEditorPage> createState() =>
      _ImportantDocumentEditorPageState();
}

class _ImportantDocumentEditorPageState extends State<ImportantDocumentEditorPage> {
  late final TextEditingController _titleC;
  late final TextEditingController _notesC;
  List<Map<String, String>> _files = [];
  bool _busy = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _titleC = TextEditingController(text: widget.edit?['title']?.toString() ?? '');
    _notesC = TextEditingController(text: widget.edit?['notes']?.toString() ?? '');
    _files = decodeVaultFiles(widget.edit?['files']);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (_started || widget.edit != null) return;
    _started = true;
    if (widget.startWith == 'camera') {
      await _addFromCamera();
    } else if (widget.startWith == 'file') {
      await _addFromFiles();
    }
  }

  @override
  void dispose() {
    _titleC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _addFromCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? path;
      if (supportsDeviceCamera) {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('Scan document'),
                  subtitle: const Text('Edge detect + crop'),
                  onTap: () => Navigator.pop(ctx, 'scan'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take photo'),
                  onTap: () => Navigator.pop(ctx, 'photo'),
                ),
              ],
            ),
          ),
        );
        if (!mounted || choice == null) return;
        path = choice == 'scan'
            ? await DocumentScanHelper.pickDocumentImage(context)
            : await DocumentScanHelper.pickNormalCamera();
      } else {
        path = await DocumentScanHelper.pickDocumentImage(context);
      }
      if (path == null) return;
      final saved = await ImageHelper.copyToAppStorage(path, 'vault_imp_doc');
      if (!mounted) return;
      setState(() {
        _files.add({
          'path': saved,
          'name': saved.split(RegExp(r'[\\/]')).last,
          'kind': 'image',
        });
        if (_titleC.text.trim().isEmpty) {
          _titleC.text = 'Scanned ${DateFormat('dd MMM').format(DateTime.now())}';
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;
      for (final f in result.files) {
        final path = f.path;
        if (path == null || path.isEmpty) continue;
        final saved = await ImageHelper.copyToAppStorage(path, 'vault_imp_file');
        _files.add({
          'path': saved,
          'name': f.name,
          'kind': _isImagePath(f.name) ? 'image' : 'file',
        });
        if (_titleC.text.trim().isEmpty) {
          _titleC.text = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
        }
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final title = _titleC.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    final data = {
      'title': title,
      'notes': _notesC.text.trim(),
      'files': encodeVaultFiles(_files),
      'created_at':
          widget.edit?['created_at'] ?? DateTime.now().toIso8601String(),
    };
    if (widget.edit == null) {
      await DatabaseHelper.instance.addVaultDocument(data);
    } else {
      await DatabaseHelper.instance
          .updateVaultDocument(widget.edit!['id'] as int, data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (widget.edit == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This removes the saved copy from your vault.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.expense),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteVaultDocument(widget.edit!['id'] as int);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.edit == null ? 'Add document' : 'Edit document'),
        backgroundColor: _documentAccent,
        actions: [
          if (widget.edit != null)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          TextField(
            controller: _titleC,
            textCapitalization: TextCapitalization.sentences,
            decoration: _fieldDeco('Title', Icons.title_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesC,
            maxLines: 3,
            decoration: _fieldDeco('Notes', Icons.notes_rounded),
          ),
          const SizedBox(height: 18),
          const Text(
            'ATTACHMENTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AttachAction(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  color: _documentAccent,
                  onTap: _busy ? null : _addFromCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AttachAction(
                  icon: Icons.attach_file_rounded,
                  label: 'File',
                  color: const Color(0xFF4F46E5),
                  onTap: _busy ? null : _addFromFiles,
                ),
              ),
            ],
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),
          if (_files.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                'No files yet. Use Camera or File to attach.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ..._files.asMap().entries.map((e) {
              final file = e.value;
              final path = file['path'] ?? '';
              final isImg = file['kind'] == 'image' || _isImagePath(path);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  onTap: () => _openAttachment(context, file),
                  leading: isImg && File(path).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(path), width: 44, height: 44, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.insert_drive_file_rounded, color: _documentAccent),
                  title: Text(
                    file['name'] ?? 'File',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(isImg ? 'Image' : 'File'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _files.removeAt(e.key)),
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _documentAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _save,
            child: const Text('Save document'),
          ),
        ],
      ),
    );
  }
}

class _AttachAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _AttachAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// IMPORTANT REMINDERS
// =============================================================================

class ImportantRemindersPage extends StatefulWidget {
  const ImportantRemindersPage({super.key});

  @override
  State<ImportantRemindersPage> createState() => _ImportantRemindersPageState();
}

class _ImportantRemindersPageState extends State<ImportantRemindersPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _showDone = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final rows = (await DatabaseHelper.instance.getVaultReminders())
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.sort((a, b) {
        final da = (a['done'] ?? 0) == 1 ? 1 : 0;
        final db = (b['done'] ?? 0) == 1 ? 1 : 0;
        if (da != db) return da.compareTo(db);
        final ta = parseStoredDate(a['remind_at']) ?? DateTime(9999);
        final tb = parseStoredDate(b['remind_at']) ?? DateTime(9999);
        return ta.compareTo(tb);
      });
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({Map<String, dynamic>? item}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReminderEditorSheet(edit: item),
    );
    if (saved == true) await _refresh();
  }

  Future<void> _toggleDone(Map<String, dynamic> item) async {
    final done = (item['done'] ?? 0) == 1 ? 0 : 1;
    await DatabaseHelper.instance.updateVaultReminder(item['id'] as int, {
      ...Map<String, dynamic>.from(item),
      'done': done,
    });
    await _refresh();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete reminder?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.expense),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.deleteVaultReminder(item['id'] as int);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visible = _items.where((e) {
      final done = (e['done'] ?? 0) == 1;
      return _showDone ? done : !done;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Important Reminders'),
        backgroundColor: _reminderAccent,
        actions: [
          TextButton(
            onPressed: () => setState(() => _showDone = !_showDone),
            child: Text(
              _showDone ? 'Open' : 'Done',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _reminderAccent,
        onPressed: () => _edit(),
        child: const Icon(Icons.add_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : visible.isEmpty
              ? _EmptyVaultState(
                  icon: Icons.notification_important_rounded,
                  color: _reminderAccent,
                  title: _showDone ? 'No completed reminders' : 'No reminders yet',
                  subtitle: 'Bills, renewals, appointments — keep them here',
                  actionLabel: 'Add reminder',
                  onAction: () => _edit(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final item = visible[i];
                    final when = parseStoredDate(item['remind_at']);
                    final done = (item['done'] ?? 0) == 1;
                    final overdue = !done &&
                        when != null &&
                        when.isBefore(now);
                    final color = done
                        ? Colors.grey
                        : (overdue ? AppTheme.expense : _reminderAccent);
                    return Card(
                      child: ListTile(
                        onTap: () => _edit(item: item),
                        onLongPress: () => _delete(item),
                        leading: IconButton(
                          onPressed: () => _toggleDone(item),
                          icon: Icon(
                            done
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: color,
                          ),
                        ),
                        title: Text(
                          (item['title'] ?? 'Reminder').toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: done ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          when == null
                              ? 'No date'
                              : (overdue
                                  ? 'Overdue · ${DateFormat('EEE, dd MMM · HH:mm').format(when)}'
                                  : DateFormat('EEE, dd MMM · HH:mm').format(when)),
                          style: TextStyle(color: overdue ? AppTheme.expense : null),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ReminderEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? edit;
  const _ReminderEditorSheet({this.edit});

  @override
  State<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  late final TextEditingController _titleC;
  late final TextEditingController _notesC;
  late DateTime _when;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _titleC = TextEditingController(text: e?['title']?.toString() ?? '');
    _notesC = TextEditingController(text: e?['notes']?.toString() ?? '');
    _when = parseStoredDate(e?['remind_at']) ??
        DateTime.now().add(const Duration(days: 1)).copyWith(
              hour: 9,
              minute: 0,
              second: 0,
              millisecond: 0,
              microsecond: 0,
            );
  }

  @override
  void dispose() {
    _titleC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    setState(() {
      _when = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _when.hour,
        time?.minute ?? _when.minute,
      );
    });
  }

  Future<void> _save() async {
    final title = _titleC.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    final data = {
      'title': title,
      'notes': _notesC.text.trim(),
      'remind_at': _when.toIso8601String(),
      'done': widget.edit?['done'] ?? 0,
      'created_at': widget.edit?['created_at'] ?? DateTime.now().toIso8601String(),
    };
    if (widget.edit == null) {
      await DatabaseHelper.instance.addVaultReminder(data);
    } else {
      await DatabaseHelper.instance
          .updateVaultReminder(widget.edit!['id'] as int, data);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                widget.edit == null ? 'Add reminder' : 'Edit reminder',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleC,
                textCapitalization: TextCapitalization.sentences,
                decoration: _fieldDeco('Title', Icons.flag_outlined,
                    hint: 'e.g. Pay electricity, Visa renewal'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_rounded, color: _reminderAccent),
                title: Text(DateFormat('EEE, dd MMM yyyy · HH:mm').format(_when)),
                subtitle: const Text('Tap to change date & time'),
                onTap: _pickWhen,
              ),
              TextField(
                controller: _notesC,
                maxLines: 3,
                decoration: _fieldDeco('Notes', Icons.notes_rounded),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _reminderAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _save,
                child: const Text('Save reminder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyVaultState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyVaultState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: color),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
