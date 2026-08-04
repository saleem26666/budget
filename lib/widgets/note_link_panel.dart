import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/link_helper.dart';

/// Shows detected links from note text with one-tap open buttons.
class NoteLinkPanel extends StatelessWidget {
  final String text;

  const NoteLinkPanel({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final urls = LinkHelper.extractUrls(text);
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Links in this note',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ...urls.map((url) => _linkTile(context, url)),
      ],
    );
  }

  Widget _linkTile(BuildContext context, String url) {
    final isYt = LinkHelper.isYoutube(url);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: isYt
              ? Colors.red.shade50
              : AppTheme.primary.withValues(alpha: 0.1),
          child: Icon(
            isYt ? Icons.play_circle_outline : Icons.language_rounded,
            color: isYt ? Colors.red : AppTheme.primary,
            size: 22,
          ),
        ),
        title: Text(
          LinkHelper.labelFor(url),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          url,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        trailing: IconButton(
          tooltip: 'Open link',
          icon: const Icon(Icons.open_in_new_rounded, color: AppTheme.primary),
          onPressed: () async {
            final ok = await LinkHelper.open(url);
            if (!context.mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open: $url')),
              );
            }
          },
        ),
        onTap: () async {
          final ok = await LinkHelper.open(url);
          if (!context.mounted) return;
          if (!ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open: $url')),
            );
          }
        },
      ),
    );
  }
}
