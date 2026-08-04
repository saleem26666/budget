import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/document_scan_helper.dart';
import '../utils/image_helper.dart';
import 'full_screen_image.dart';

/// Gallery, Scan (edge), and normal Camera for editors.
class EditorMediaBar extends StatelessWidget {
  final List<String> images;
  final int maxImages;
  final ValueChanged<List<String>> onImagesChanged;
  final String persistPrefix;

  const EditorMediaBar({
    super.key,
    required this.images,
    required this.maxImages,
    required this.onImagesChanged,
    this.persistPrefix = 'media',
  });

  Future<void> _add(BuildContext context, Future<String?> Function() pick) async {
    if (images.length >= maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Maximum $maxImages images')),
      );
      return;
    }
    final path = await pick();
    if (path != null) {
      onImagesChanged([...images, path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos (${images.length}/$maxImages)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _toolBtn(
              context,
              icon: Icons.photo_library_rounded,
              label: 'Gallery',
              onTap: () => _add(
                context,
                () => DocumentScanHelper.pickNormalGallery(),
              ),
            ),
            const SizedBox(width: 8),
            _toolBtn(
              context,
              icon: Icons.camera_alt_rounded,
              label: 'Camera',
              color: AppTheme.accent,
              onTap: () => _add(
                context,
                () => DocumentScanHelper.pickNormalCamera(),
              ),
            ),
            const SizedBox(width: 8),
            _toolBtn(
              context,
              icon: Icons.document_scanner_outlined,
              label: 'Scan',
              color: AppTheme.primary,
              onTap: () => _add(
                context,
                () => DocumentScanHelper.pickDocumentImage(context),
              ),
            ),
          ],
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (c, i) => Stack(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FullScreenImage(imagePath: images[i]),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(images[i]),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: () {
                        final next = List<String>.from(images)..removeAt(i);
                        onImagesChanged(next);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _toolBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(icon, color: color ?? Colors.grey.shade700, size: 22),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Future<List<String>> persist(List<String> paths, String prefix) =>
      ImageHelper.persistPaths(paths, prefix);
}
