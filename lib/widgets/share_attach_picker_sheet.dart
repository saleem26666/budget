import 'package:flutter/material.dart';

/// Pick an existing item or create new (transaction / note).
class ShareAttachPickerSheet extends StatelessWidget {
  final String title;
  final String newLabel;
  final List<ShareAttachItem> items;

  const ShareAttachPickerSheet({
    super.key,
    required this.title,
    required this.newLabel,
    required this.items,
  });

  /// Returns selected item id, or `-1` for "new", or null if cancelled.
  static Future<int?> show(
    BuildContext context, {
    required String title,
    required String newLabel,
    required List<ShareAttachItem> items,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareAttachPickerSheet(
        title: title,
        newLabel: newLabel,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.65;
    return Container(
      margin: const EdgeInsets.all(12),
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.add),
            ),
            title: Text(newLabel,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => Navigator.pop(context, -1),
          ),
          const Divider(height: 1),
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No recent items — create new'),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      return ListTile(
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: item.subtitle == null
                            ? null
                            : Text(
                                item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: item.trailing == null
                            ? null
                            : Text(
                                item.trailing!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        onTap: () => Navigator.pop(context, item.id),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class ShareAttachItem {
  final int id;
  final String title;
  final String? subtitle;
  final String? trailing;

  const ShareAttachItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.trailing,
  });
}
