import 'package:flutter/material.dart';

import '../diary_screen.dart';
import '../notebook_screen.dart';

/// Single tab that hosts Diary + Notes — reduces bottom-nav clutter.
class JournalHub extends StatefulWidget {
  final List<Map<String, dynamic>> diaryEntries;
  final List<Map<String, dynamic>> diaryCategories;
  final String activeProfileId;
  final List<String>? sharedImages;
  final int? sharedNoteId;
  final int sharedNonce;
  final VoidCallback? onSharedConsumed;
  final int initialTab;

  const JournalHub({
    super.key,
    required this.diaryEntries,
    required this.diaryCategories,
    required this.activeProfileId,
    this.sharedImages,
    this.sharedNoteId,
    this.sharedNonce = 0,
    this.onSharedConsumed,
    this.initialTab = 0,
  });

  @override
  State<JournalHub> createState() => _JournalHubState();
}

class _JournalHubState extends State<JournalHub>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    final start = widget.sharedImages != null && widget.sharedImages!.isNotEmpty
        ? 1
        : widget.initialTab.clamp(0, 1);
    _tabs = TabController(length: 2, vsync: this, initialIndex: start);
  }

  @override
  void didUpdateWidget(covariant JournalHub oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedImages != null &&
        widget.sharedImages!.isNotEmpty &&
        widget.sharedNonce != oldWidget.sharedNonce) {
      _tabs.animateTo(1);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.menu_book_rounded, size: 20), text: 'Diary'),
              Tab(
                icon: Icon(Icons.sticky_note_2_rounded, size: 20),
                text: 'Notes · Links',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              DiaryScreen(
                diaryEntries: widget.diaryEntries,
                diaryCategories: widget.diaryCategories,
                onSaveEntry: (_) {},
                onDeleteEntry: (_) {},
              ),
              NotebookScreen(
                key: ValueKey('nb_${widget.sharedNonce}'),
                activeProfileId: widget.activeProfileId,
                sharedImages: widget.sharedImages,
                sharedNoteId: widget.sharedNoteId,
                sharedNonce: widget.sharedNonce,
                onSharedConsumed: widget.onSharedConsumed,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
