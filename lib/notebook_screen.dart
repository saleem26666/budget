import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'database_helper.dart';
import 'utils/image_helper.dart';
import 'utils/link_helper.dart';
import 'widgets/category_filter_bar.dart';
import 'widgets/editor_media_bar.dart';
import 'widgets/linkified_text.dart';
import 'widgets/note_link_panel.dart';
import 'widgets/voice_input_bar.dart';

/// Quick notes — colors, voice, categories, clickable YouTube / website links.
class NotebookScreen extends StatefulWidget {
  final String activeProfileId;
  final List<String>? sharedImages;
  final int? sharedNoteId;
  final int sharedNonce;
  final VoidCallback? onSharedConsumed;

  const NotebookScreen({
    super.key,
    this.activeProfileId = 'default',
    this.sharedImages,
    this.sharedNoteId,
    this.sharedNonce = 0,
    this.onSharedConsumed,
  });

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  List<Map<String, dynamic>> _notes = [];
  List<Map<String, dynamic>> _categories = [];
  String _search = '';
  String _categoryFilter = 'All';
  final _searchC = TextEditingController();
  int _handledShareNonce = -1;

  static const _palette = [
    Color(0xFFFFFFFF),
    Color(0xFFFEE2E2),
    Color(0xFFFFEDD5),
    Color(0xFFFEF9C3),
    Color(0xFFD1FAE5),
    Color(0xFFDBEAFE),
    Color(0xFFEDE9FE),
  ];

  static const _defaultCategories = [
    {'id': '1', 'name': 'General'},
    {'id': '2', 'name': 'Useful Links'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _reload().then((_) => _consumeSharedImages());
  }

  @override
  void didUpdateWidget(covariant NotebookScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedNonce != oldWidget.sharedNonce ||
        widget.sharedImages != oldWidget.sharedImages ||
        widget.sharedNoteId != oldWidget.sharedNoteId) {
      _consumeSharedImages();
    }
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _consumeSharedImages() async {
    final imgs = widget.sharedImages;
    if (imgs == null || imgs.isEmpty) return;
    if (_handledShareNonce == widget.sharedNonce) return;
    _handledShareNonce = widget.sharedNonce;

    Map<String, dynamic>? edit;
    final noteId = widget.sharedNoteId;
    if (noteId != null) {
      try {
        edit = _notes.firstWhere((n) => n['id'] == noteId);
      } catch (_) {
        final rows = await DatabaseHelper.instance.getNotes();
        try {
          edit = rows.firstWhere((n) => n['id'] == noteId);
        } catch (_) {
          edit = null;
        }
      }
    }

    if (!mounted) return;
    widget.onSharedConsumed?.call();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openEditor(edit: edit, initialImages: imgs);
    });
  }

  String get _categoriesPrefKey =>
      '${widget.activeProfileId}_notebook_categories';

  Future<void> _loadCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesPrefKey) ??
        prefs.getString('notebook_categories');
    var cats = <Map<String, dynamic>>[];
    if (raw != null) {
      cats = List<Map<String, dynamic>>.from(jsonDecode(raw));
    }
    if (cats.isEmpty) {
      cats = List<Map<String, dynamic>>.from(_defaultCategories);
      await prefs.setString(_categoriesPrefKey, jsonEncode(cats));
    }
    if (mounted) setState(() => _categories = cats);
  }

  Future<void> _reload() async {
    final rows = await DatabaseHelper.instance.getNotes();
    if (mounted) setState(() => _notes = rows);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.toLowerCase();
    return _notes.where((n) {
      final cat = (n['cat'] ?? 'General').toString();
      final catOk = _categoryFilter == 'All' || cat == _categoryFilter;
      final searchOk = q.isEmpty ||
          (n['title'] ?? '').toString().toLowerCase().contains(q) ||
          (n['content'] ?? '').toString().toLowerCase().contains(q);
      return catOk && searchOk;
    }).toList();
  }

  void _openEditor({
    Map<String, dynamic>? edit,
    String? initialCategory,
    List<String>? initialImages,
  }) {
    final titleC = TextEditingController(text: edit?['title']?.toString() ?? '');
    final contentC =
        TextEditingController(text: edit?['content']?.toString() ?? '');
    var colorIdx = (edit?['color'] as int?) ?? 0;
    var cat = edit?['cat']?.toString() ??
        initialCategory ??
        (_categories.isNotEmpty ? _categories.first['name'].toString() : 'General');
    var images = ImageHelper.decodeImagePaths(edit?['imgs']);
    if (initialImages != null) {
      for (final p in initialImages) {
        if (p.isEmpty) continue;
        if (images.length >= 6) break;
        if (!images.contains(p)) images.add(p);
      }
    }
    DateTime? reminder;
    final r = edit?['reminder']?.toString();
    if (r != null && r.isNotEmpty) reminder = DateTime.tryParse(r);

    Future<void> saveNote(BuildContext ctx) async {
      if (titleC.text.trim().isEmpty) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Please add note title')),
          );
        }
        return;
      }
      final savedImgs = await EditorMediaBar.persist(images, 'note');
      final data = {
        'title': titleC.text.trim(),
        'content': contentC.text,
        'cat': cat,
        'color': colorIdx,
        'imgs': jsonEncode(savedImgs),
        'reminder': reminder?.toIso8601String(),
        'date': edit?['date'] ??
            DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      };
      if (edit == null) {
        await DatabaseHelper.instance.addNote(data);
      } else {
        await DatabaseHelper.instance.updateNote(edit['id'], data);
      }
      await _reload();
      if (ctx.mounted) Navigator.pop(ctx);
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) {
            final contentPreview = contentC.text;
            final links = LinkHelper.extractUrls(contentPreview);
            final useful = cat == 'Useful Links';

            return Scaffold(
              backgroundColor: _palette[colorIdx.clamp(0, _palette.length - 1)],
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: Colors.grey.shade900,
                title: Text(edit == null ? 'New note' : 'Edit note'),
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
                actions: [
                  if (edit != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        await DatabaseHelper.instance.deleteNote(edit['id']);
                        await _reload();
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                  IconButton(
                    tooltip: 'Save note',
                    onPressed: () => saveNote(ctx),
                    icon: const Icon(Icons.save_rounded, color: AppTheme.primary),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_categories.isNotEmpty) ...[
                      Text('Category',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categories.map((c) {
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
                    if (useful)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.link_rounded,
                                color: AppTheme.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Paste a YouTube or website link in the note, '
                                'then write details below. Saved links open with one tap.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade800,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: titleC,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: useful
                            ? 'Link title (e.g. Budget tips video)'
                            : 'Note title',
                        border: InputBorder.none,
                      ),
                    ),
                    TextField(
                      controller: contentC,
                      onChanged: (_) => setSt(() {}),
                      minLines: 8,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: useful
                            ? 'https://youtube.com/...\n\nWrite details about this link...'
                            : 'Write anything... Paste links to open later.',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      NoteLinkPanel(text: contentPreview),
                      const SizedBox(height: 12),
                      Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LinkifiedText(
                        text: contentPreview,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    VoiceInputBar(controller: contentC),
                    const SizedBox(height: 16),
                    EditorMediaBar(
                      images: images,
                      maxImages: 6,
                      persistPrefix: 'note',
                      onImagesChanged: (l) => setSt(() => images = l),
                    ),
                    const SizedBox(height: 16),
                    Text('Color',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: List.generate(_palette.length, (i) {
                        return GestureDetector(
                          onTap: () => setSt(() => colorIdx = i),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _palette[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorIdx == i
                                    ? AppTheme.primary
                                    : Colors.grey.shade300,
                                width: colorIdx == i ? 3 : 1,
                              ),
                              boxShadow:
                                  colorIdx == i ? AppTheme.cardShadow : null,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.alarm_rounded,
                          color: Colors.amber.shade700),
                      title: Text(reminder == null
                          ? 'Set reminder'
                          : DateFormat('dd MMM yyyy, HH:mm').format(reminder!)),
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
                  onPressed: () => saveNote(ctx),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Note'),
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
    final filterOptions = [
      'All',
      ..._categories.map((c) => c['name'].toString()),
    ];

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
                    color: const Color(0xFF0D9488).withValues(alpha: 0.08),
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
                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sticky_note_2_rounded,
                            color: Color(0xFF0D9488), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            Text(
                              'Ideas · Useful Links · YouTube',
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
                      hintText: 'Search notes…',
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
                            color: Color(0xFF0D9488), width: 1.2),
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
              categories: filterOptions,
              selected: _categoryFilter,
              onSelected: (name) => setState(() => _categoryFilter = name),
              accent: const Color(0xFF0D9488),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 10)),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Tap + to capture an idea',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                delegate: SliverChildBuilderDelegate(
                  (c, i) => _noteCard(list[i]),
                  childCount: list.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'note_link',
            onPressed: () => _openEditor(initialCategory: 'Useful Links'),
            backgroundColor: const Color(0xFF6366F1),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Useful Link'),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'note_add',
            onPressed: () => _openEditor(),
            backgroundColor: const Color(0xFF0D9488),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Note'),
          ),
        ],
      ),
    );
  }

  Widget _noteCard(Map<String, dynamic> note) {
    final ci = (note['color'] as int?) ?? 0;
    final bg = _palette[ci.clamp(0, _palette.length - 1)];
    final hasR = (note['reminder']?.toString() ?? '').isNotEmpty;
    final content = note['content']?.toString() ?? '';
    final links = LinkHelper.extractUrls(content);
    final cat = (note['cat'] ?? 'General').toString();

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openEditor(edit: note),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note['title'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (links.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        links.any(LinkHelper.isYoutube)
                            ? Icons.play_circle_outline
                            : Icons.link_rounded,
                        size: 18,
                        color: AppTheme.primary,
                      ),
                    ),
                  if (hasR)
                    Icon(Icons.alarm_rounded,
                        size: 16, color: Colors.amber.shade800),
                ],
              ),
              if (cat.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    cat,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Expanded(
                child: LinkifiedText(
                  text: content.isEmpty ? ' ' : content,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade800,
                    height: 1.4,
                  ),
                ),
              ),
              Text(
                note['date']?.toString().split(' ').first ?? '',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
