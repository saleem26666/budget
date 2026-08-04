import 'package:flutter/material.dart';

/// Horizontal category filters — full label visible, scrollable, modern chips.
class CategoryFilterBar extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  final Color accent;

  const CategoryFilterBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.accent = const Color(0xFF4F46E5),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final name = categories[i];
          final sel = name == selected;
          return Material(
            color: sel ? accent.withValues(alpha: 0.12) : Colors.white,
            elevation: 0,
            shape: StadiumBorder(
              side: BorderSide(
                color: sel ? accent.withValues(alpha: 0.45) : Colors.grey.shade300,
                width: sel ? 1.4 : 1,
              ),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelected(name),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sel) ...[
                      Icon(Icons.check_rounded, size: 16, color: accent),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? accent : Colors.grey.shade800,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
