import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/link_helper.dart';

/// Read-only text with tappable links (YouTube, websites).
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? const TextStyle(fontSize: 13, height: 1.4);
    final spans = <InlineSpan>[];
    var index = 0;

    for (final match in LinkHelper.urlPattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(
          text: text.substring(index, match.start),
          style: baseStyle,
        ));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: baseStyle.copyWith(
          color: AppTheme.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final ok = await LinkHelper.open(url);
            if (!context.mounted) return;
            if (!ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not open link: $url')),
              );
            }
          },
      ));
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: baseStyle));
    }

    if (spans.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
