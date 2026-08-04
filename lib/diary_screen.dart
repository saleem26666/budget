import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'utils/image_helper.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/editor_media_bar.dart';
import 'widgets/voice_input_bar.dart';

/// Modern diary — voice (EN/UR + translate), scanner, camera, photos, reminders.
class DiaryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> diaryEntries;
  final List<Map<String, dynamic>> diaryCategories;
  final Function(Map<String, dynamic>)? onSaveEntry;
  final Function(Map<String, dynamic>)? onDeleteEntry;

  const DiaryScreen({
    super.key,
    required this.diaryEntries,
    required this.diaryCategories,
    this.onSaveEntry,
    this.onDeleteEntry,
  });

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  List<Map<String, dynamic>> _entries = [];
  String _search = '';
  String _category = 'All';
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await DatabaseHelper.instance.getDiary();
    if (mounted) setState(() => _entries = rows);
  }

  List<Map<String, dynamic>> get _filtered {
    return _entries.where((e) {
      final catOk = _category == 'All' || e['cat'] == _category;
      final q = _search.toLowerCase();
      final searchOk = q.isEmpty ||
          (e['title'] ?? '').toString().toLowerCase().contains(q) ||
          (e['content'] ?? '').toString().toLowerCase().contains(q);
      return catOk && searchOk;
    }).toList();
  }

  Future<void> _share(Map<String, dynamic> entry) async {
    final date = entry['date']?.toString() ?? '';
    final text =
        '${entry['title'] ?? ''}\n\n${entry['content'] ?? ''}\n\nWritten on: $date';
    List<String> imgs = [];
    if (entry['imgs'] != null && entry['imgs'].toString().isNotEmpty) {
      try {
        imgs = List<String>.from(jsonDecode(entry['imgs']));
      } catch (_) {}
    }
    if (imgs.isNotEmpty && !kIsWeb) {
      await Share.shareXFiles(imgs.map((p) => XFile(p)).toList(), text: text);
    } else {
      await Share.share(text);
    }
  }

  void _openEditor({Map<String, dynamic>? edit}) {
    final titleC = TextEditingController(text: edit?['title']?.toString() ?? '');
    final contentC =
        TextEditingController(text: edit?['content']?.toString() ?? '');
    var cat = edit?['cat']?.toString() ??
        (widget.diaryCategories.isNotEmpty
            ? widget.diaryCategories.first['name'].toString()
            : 'General');
    var images = ImageHelper.decodeImagePaths(edit?['imgs']);
    DateTime? reminder;
    final r = edit?['reminder']?.toString();
    if (r != null && r.isNotEmpty) reminder = DateTime.tryParse(r);

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) {
            return Scaffold(
              backgroundColor: AppTheme.surface,
              appBar: AppBar(
                title: Text(edit == null ? 'New diary' : 'Edit diary'),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
                actions: [
                  if (edit != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await DatabaseHelper.instance.deleteDiary(edit['id']);
                        await _reload();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  IconButton(
                    tooltip: 'Save diary',
                    onPressed: () async {
                      final saved = await EditorMediaBar.persist(images, 'diary');
                      final data = {
                        'title': titleC.text.trim(),
                        'content': contentC.text,
                        'cat': cat,
                        'imgs': jsonEncode(saved),
                        'reminder': reminder?.toIso8601String(),
                        'date': edit?['date'] ??
                            DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      };
                      if (edit == null) {
                        await DatabaseHelper.instance.addDiary(data);
                      } else {
                        await DatabaseHelper.instance.updateDiary(edit['id'], data);
                      }
                      await _reload();
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.save_rounded),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleC,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        hintText: 'Today I felt...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.diaryCategories.isNotEmpty) ...[
                      Text('Category',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: widget.diaryCategories.map((c) {
                          final name = c['name'].toString();
                          final sel = cat == name;
                          return FilterChip(
                            label: Text(name),
                            selected: sel,
                            onSelected: (_) => setSt(() => cat = name),
                            selectedColor:
                                AppTheme.primary.withValues(alpha: 0.15),
                            checkmarkColor: AppTheme.primary,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: contentC,
                      minLines: 10,
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: 'Your story',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    VoiceInputBar(controller: contentC),
                    const SizedBox(height: 20),
                    EditorMediaBar(
                      images: images,
                      maxImages: 10,
                      persistPrefix: 'diary',
                      onImagesChanged: (list) => setSt(() => images = list),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.notifications_active_outlined,
                            color: Colors.amber.shade800),
                      ),
                      title: Text(
                        reminder == null
                            ? 'Add reminder'
                            : DateFormat('EEE, dd MMM · HH:mm').format(reminder!),
                      ),
                      subtitle: const Text('Optional alert time'),
                      trailing: reminder != null
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setSt(() => reminder = null),
                            )
                          : null,
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: reminder ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2035),
                        );
                        if (d == null) return;
                        if (!ctx.mounted) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(
                              reminder ?? DateTime.now()),
                        );
                        if (t != null) {
                          setSt(() {
                            reminder = DateTime(
                                d.year, d.month, d.day, t.hour, t.minute);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () async {
                    final saved = await EditorMediaBar.persist(images, 'diary');
                    final data = {
                      'title': titleC.text.trim(),
                      'content': contentC.text,
                      'cat': cat,
                      'imgs': jsonEncode(saved),
                      'reminder': reminder?.toIso8601String(),
                      'date': edit?['date'] ??
                          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                    };
                    if (edit == null) {
                      await DatabaseHelper.instance.addDiary(data);
                    } else {
                      await DatabaseHelper.instance.updateDiary(edit['id'], data);
                    }
                    await _reload();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Diary'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.auto_stories_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Diary',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              'Stories · voice · scan',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchC,
                    onChanged: (v) => setState(() => _search = v),
                    decoration: InputDecoration(
                      hintText: 'Search entries…',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: AppTheme.primary, width: 1.2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
          SliverToBoxAdapter(
            child: CategoryFilterBar(
              categories: [
                'All',
                ...widget.diaryCategories.map((c) => c['name'].toString()),
              ],
              selected: _category,
              onSelected: (name) => setState(() => _category = name),
              accent: AppTheme.primary,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_note_rounded,
                        size: 72, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Start your first entry',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (c, i) => _entryCard(list[i]),
                  childCount: list.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Write'),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    List<String> imgs = [];
    if (entry['imgs'] != null && entry['imgs'].toString().isNotEmpty) {
      try {
        imgs = List<String>.from(jsonDecode(entry['imgs']));
      } catch (_) {}
    }
    final hasReminder = (entry['reminder']?.toString() ?? '').isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openEditor(edit: entry),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['title']?.toString().isNotEmpty == true
                                ? entry['title']
                                : 'Untitled',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (entry['cat'] != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    entry['cat'].toString(),
                                    style: const TextStyle(
                                        fontSize: 11, color: AppTheme.primary),
                                  ),
                                ),
                              if (hasReminder) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.alarm_rounded,
                                    size: 14, color: Colors.amber.shade700),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      onPressed: () => _share(entry),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  entry['content']?.toString() ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (imgs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 56,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: imgs.length.clamp(0, 4),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) => ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(imgs[idx]),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  entry['date']?.toString().split(' ').first ?? '',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
