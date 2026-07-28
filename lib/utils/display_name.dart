import 'package:flutter/material.dart';

/// Displays [name] in one line and shortens it only when it exceeds its actual
/// layout width.
class ResponsiveDisplayName extends StatelessWidget {
  const ResponsiveDisplayName({
    super.key,
    required this.name,
    required this.style,
  });

  final String name;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) {
          return _buildText(name);
        }

        final displayName = _resolveDisplayName(context, constraints.maxWidth);
        return _buildText(displayName);
      },
    );
  }

  Widget _buildText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  String _resolveDisplayName(BuildContext context, double maxWidth) {
    if (!_overflows(context, name, maxWidth)) return name;

    final withoutParentheses = name
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'（[^）]*）'), '')
        .trim();
    if (withoutParentheses != name &&
        !_overflows(context, withoutParentheses, maxWidth)) {
      return withoutParentheses;
    }

    final chineseOnly = String.fromCharCodes(
      withoutParentheses.runes.where(_isChinese),
    );
    if (chineseOnly.isNotEmpty && !_overflows(context, chineseOnly, maxWidth)) {
      return chineseOnly;
    }

    // Keep the original text so the ellipsis communicates that it was clipped.
    return name;
  }

  bool _overflows(BuildContext context, String text, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}

bool _isChinese(int rune) {
  return (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2EBEF);
}
