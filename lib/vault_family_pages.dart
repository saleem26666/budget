import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'widgets/full_screen_image.dart';

typedef FamilyDocEditor = Future<void> Function({
  Map<String, dynamic>? editDoc,
  String? prefilledName,
});

typedef FamilyDocsChanged = Future<void> Function();

String familyDisplayName(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return 'Unknown';
  return s.split(RegExp(r'\s+')).map((w) {
    if (w.isEmpty) return w;
    return '${w[0].toUpperCase()}${w.substring(1)}';
  }).join(' ');
}

List<String> parseFamilyImages(Map<String, dynamic> doc) {
  if (doc['images'] != null &&
      doc['images'] != '' &&
      doc['images'] != 'null') {
    try {
      return List<String>.from(jsonDecode(doc['images'].toString()));
    } catch (_) {}
  }
  return [
    if (doc['front_image'] != null) doc['front_image'].toString(),
    if (doc['back_image'] != null) doc['back_image'].toString(),
  ];
}

DateTime? _parseExpiry(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().split('T').first.trim();
  if (s.isEmpty || s == 'N/A') return null;
  return DateTime.tryParse(s);
}

enum _ExpiryStatus { ok, soon, expired }

_ExpiryStatus expiryStatus(dynamic raw) {
  final d = _parseExpiry(raw);
  if (d == null) return _ExpiryStatus.ok;
  final today = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final now = DateTime(today.year, today.month, today.day);
  if (day.isBefore(now)) return _ExpiryStatus.expired;
  if (!day.isAfter(now.add(const Duration(days: 30)))) {
    return _ExpiryStatus.soon;
  }
  return _ExpiryStatus.ok;
}

Color _typeColor(String type) {
  switch (type.toLowerCase()) {
    case 'education':
      return const Color(0xFF3B82F6);
    case 'medical':
    case 'hospital mr':
      return const Color(0xFF10B981);
    case 'identity':
      return const Color(0xFF6366F1);
    case 'finance':
      return const Color(0xFF0EA5E9);
    default:
      return AppTheme.primary;
  }
}

String familyDocTitle(Map<String, dynamic> doc) {
  final t = (doc['title'] ?? '').toString().trim();
  if (t.isNotEmpty) return t;
  return (doc['doc_type'] ?? 'Document').toString();
}

// ==================== HUB ====================
class FamilyVaultHubPage extends StatefulWidget {
  final FamilyDocEditor openEditor;

  const FamilyVaultHubPage({super.key, required this.openEditor});

  @override
  State<FamilyVaultHubPage> createState() => _FamilyVaultHubPageState();
}

class _FamilyVaultHubPageState extends State<FamilyVaultHubPage> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  String _query = '';
  String? _memberFilter;
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
      // sqflite returns an unmodifiable list — copy before sort.
      final rows = (await DatabaseHelper.instance.queryAllRows('family_vault'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rows.sort((a, b) {
        final ma = (a['member_name'] ?? '').toString().toLowerCase();
        final mb = (b['member_name'] ?? '').toString().toLowerCase();
        final c = ma.compareTo(mb);
        if (c != 0) return c;
        return (a['doc_type'] ?? '')
            .toString()
            .compareTo((b['doc_type'] ?? '').toString());
      });
      if (!mounted) return;
      setState(() {
        _docs = rows;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('FamilyVaultHubPage load failed: $e\n$st');
      if (mounted) {
        setState(() {
          _docs = [];
          _loading = false;
        });
      }
    }
  }

  List<String> get _members {
    final set = <String>{};
    for (final d in _docs) {
      final n = (d['member_name'] ?? '').toString().trim();
      if (n.isNotEmpty) set.add(n);
    }
    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _docs.where((d) {
      if (_memberFilter != null &&
          (d['member_name'] ?? '').toString() != _memberFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      final blob =
          '${d['member_name']} ${d['title']} ${d['doc_type']} ${d['doc_number']}'
              .toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  Future<void> _edit(
      {Map<String, dynamic>? editDoc, String? prefilledName}) async {
    await widget.openEditor(editDoc: editDoc, prefilledName: prefilledName);
    await _refresh();
  }

  void _openMember(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyMemberDocsPage(
          memberName: name,
          openEditor: widget.openEditor,
          onChanged: _refresh,
        ),
      ),
    ).then((_) => _refresh());
  }

  void _openDetail(Map<String, dynamic> doc) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FamilyDocDetailPage(
          docId: doc['id'] as int,
          openEditor: widget.openEditor,
          onChanged: _refresh,
        ),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Family Documents'),
        actions: [
          IconButton(
            tooltip: 'Add document',
            onPressed: () => _edit(prefilledName: _memberFilter),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
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
                      hintText: 'Search title, hospital, member, or number…',
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
                if (members.isNotEmpty)
                  SizedBox(
                    height: 108,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        _MemberChip(
                          label: 'All',
                          initial: 'A',
                          selected: _memberFilter == null,
                          onTap: () => setState(() => _memberFilter = null),
                        ),
                        ...members.map(
                          (n) => _MemberChip(
                            label: familyDisplayName(n),
                            initial: n.isNotEmpty ? n[0].toUpperCase() : '?',
                            selected: _memberFilter == n,
                            onTap: () => setState(() => _memberFilter = n),
                            onLongPress: () => _openMember(n),
                          ),
                        ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} document${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      if (_memberFilter != null)
                        TextButton(
                          onPressed: () => _openMember(_memberFilter!),
                          child: Text(
                            'Open ${familyDisplayName(_memberFilter)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_open_rounded,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No documents',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: () =>
                                    _edit(prefilledName: _memberFilter),
                                icon: const Icon(Icons.add_rounded),
                                label: const Text('Add document'),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final doc = filtered[i];
                            return _DocListTile(
                              doc: doc,
                              onTap: () => _openDetail(doc),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final String label;
  final String initial;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _MemberChip({
    required this.label,
    required this.initial,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 78,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: selected
                    ? AppTheme.primary
                    : AppTheme.primary.withValues(alpha: 0.15),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocListTile extends StatelessWidget {
  final Map<String, dynamic> doc;
  final VoidCallback onTap;

  const _DocListTile({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = (doc['doc_type'] ?? 'Other').toString();
    final title = familyDocTitle(doc);
    final member = familyDisplayName(doc['member_name']?.toString());
    final number = (doc['doc_number'] ?? '').toString().trim();
    final status = expiryStatus(doc['expiry_date']);
    final accent = _typeColor(type);
    Color? bg;
    if (status == _ExpiryStatus.expired) {
      bg = AppTheme.expense.withValues(alpha: 0.06);
    } else if (status == _ExpiryStatus.soon) {
      bg = Colors.orange.withValues(alpha: 0.06);
    }

    String subtitle = member;
    if (number.isNotEmpty) subtitle = '$member · $number';
    if (status == _ExpiryStatus.expired) {
      subtitle = '$subtitle · Expired';
    } else if (status == _ExpiryStatus.soon) {
      subtitle = '$subtitle · Expires soon';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(14),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: status == _ExpiryStatus.expired
                                ? AppTheme.expense
                                : status == _ExpiryStatus.soon
                                    ? Colors.orange.shade800
                                    : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          type,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== MEMBER DOCS ====================
class FamilyMemberDocsPage extends StatefulWidget {
  final String memberName;
  final FamilyDocEditor openEditor;
  final FamilyDocsChanged? onChanged;

  const FamilyMemberDocsPage({
    super.key,
    required this.memberName,
    required this.openEditor,
    this.onChanged,
  });

  @override
  State<FamilyMemberDocsPage> createState() => _FamilyMemberDocsPageState();
}

class _FamilyMemberDocsPageState extends State<FamilyMemberDocsPage> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final rows = (await DatabaseHelper.instance.queryAllRows('family_vault'))
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final mine = rows
          .where(
              (d) => (d['member_name'] ?? '').toString() == widget.memberName)
          .toList();
      if (!mounted) return;
      setState(() {
        _docs = mine;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('FamilyMemberDocsPage load failed: $e\n$st');
      if (mounted) {
        setState(() {
          _docs = [];
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit({Map<String, dynamic>? editDoc}) async {
    await widget.openEditor(
      editDoc: editDoc,
      prefilledName: widget.memberName,
    );
    await _refresh();
    await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final title = familyDisplayName(widget.memberName);
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text("$title's Documents"),
        actions: [
          IconButton(
            tooltip: 'Add document',
            onPressed: () => _edit(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _docs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No documents for this member'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add document'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _docs.length,
                  itemBuilder: (c, i) {
                    final doc = _docs[i];
                    return _DocListTile(
                      doc: doc,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FamilyDocDetailPage(
                              docId: doc['id'] as int,
                              openEditor: widget.openEditor,
                              onChanged: () async {
                                await _refresh();
                                await widget.onChanged?.call();
                              },
                            ),
                          ),
                        ).then((_) => _refresh());
                      },
                    );
                  },
                ),
    );
  }
}

// ==================== DETAIL ====================
class FamilyDocDetailPage extends StatefulWidget {
  final int docId;
  final FamilyDocEditor openEditor;
  final FamilyDocsChanged? onChanged;

  const FamilyDocDetailPage({
    super.key,
    required this.docId,
    required this.openEditor,
    this.onChanged,
  });

  @override
  State<FamilyDocDetailPage> createState() => _FamilyDocDetailPageState();
}

class _FamilyDocDetailPageState extends State<FamilyDocDetailPage> {
  Map<String, dynamic>? _doc;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.queryAllRows('family_vault');
    Map<String, dynamic>? found;
    for (final r in rows) {
      if (r['id'] == widget.docId) {
        found = r;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _doc = found;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final doc = _doc;
    if (doc == null) return;
    await widget.openEditor(editDoc: doc);
    await _load();
    await widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final doc = _doc;
    if (doc == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete document?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseHelper.instance.delete('family_vault', doc['id']);
    await widget.onChanged?.call();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _share() async {
    final doc = _doc;
    if (doc == null) return;
    final imgs = parseFamilyImages(doc);
    final txt =
        'Title: ${familyDocTitle(doc)}\nName: ${doc['member_name']}\nType: ${doc['doc_type']}\nNo: ${doc['doc_number']}\nExp: ${doc['expiry_date']?.toString().split('T').first ?? 'N/A'}';
    if (imgs.isNotEmpty) {
      await Share.shareXFiles(imgs.map((p) => XFile(p)).toList(), text: txt);
    } else {
      await Share.share(txt);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final doc = _doc;
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: const Center(child: Text('Document not found')),
      );
    }

    final imgs = parseFamilyImages(doc);
    final status = expiryStatus(doc['expiry_date']);
    final type = (doc['doc_type'] ?? 'Document').toString();
    final title = familyDocTitle(doc);
    final expLabel =
        doc['expiry_date']?.toString().split('T').first ?? 'N/A';
    final numberLabel =
        (type == 'Medical' || type == 'Hospital MR') ? 'MR / Number' : 'Number';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _share,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (status != _ExpiryStatus.ok)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: status == _ExpiryStatus.expired
                    ? AppTheme.expense.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: status == _ExpiryStatus.expired
                      ? AppTheme.expense.withValues(alpha: 0.35)
                      : Colors.orange.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: status == _ExpiryStatus.expired
                        ? AppTheme.expense
                        : Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status == _ExpiryStatus.expired
                          ? 'This document has expired ($expLabel)'
                          : 'Expires within 30 days ($expLabel)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          _infoCard(Icons.title_rounded, 'Title', title),
          _infoCard(Icons.person_outline, 'Member',
              familyDisplayName(doc['member_name']?.toString())),
          _infoCard(Icons.badge_outlined, 'Type', type),
          _infoCard(Icons.numbers_rounded, numberLabel,
              (doc['doc_number'] ?? '—').toString()),
          _infoCard(Icons.calendar_today_outlined, 'Expiry', expLabel,
              valueColor: status == _ExpiryStatus.expired
                  ? AppTheme.expense
                  : status == _ExpiryStatus.soon
                      ? Colors.orange.shade800
                      : null),
          if (imgs.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Attached images',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: imgs.map((path) {
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FullScreenImage(imagePath: path),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(path),
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
