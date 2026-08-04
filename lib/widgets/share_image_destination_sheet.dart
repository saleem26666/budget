import 'dart:io';

import 'package:flutter/material.dart';

enum ShareImageDestination { transaction, vault, notebook }

/// First step after sharing images: where should they go?
class ShareImageDestinationSheet extends StatelessWidget {
  final List<String> imagePaths;

  const ShareImageDestinationSheet({super.key, required this.imagePaths});

  static Future<ShareImageDestination?> show(
    BuildContext context, {
    required List<String> imagePaths,
  }) {
    return showModalBottomSheet<ShareImageDestination>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ShareImageDestinationSheet(imagePaths: imagePaths),
    );
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
              'Save photo where?',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imagePaths.length.clamp(0, 8),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final p = imagePaths[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(p),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _DestTile(
              icon: Icons.receipt_long,
              color: const Color(0xFF0EA5E9),
              title: 'Transaction',
              subtitle: 'Add to wallet expense / income',
              onTap: () =>
                  Navigator.pop(context, ShareImageDestination.transaction),
            ),
            _DestTile(
              icon: Icons.folder_shared_outlined,
              color: const Color(0xFF4F46E5),
              title: 'Family Documents',
              subtitle: 'Save in Vault',
              onTap: () => Navigator.pop(context, ShareImageDestination.vault),
            ),
            _DestTile(
              icon: Icons.note_alt_outlined,
              color: const Color(0xFF10B981),
              title: 'Notebook',
              subtitle: 'Attach to a note',
              onTap: () =>
                  Navigator.pop(context, ShareImageDestination.notebook),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DestTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
