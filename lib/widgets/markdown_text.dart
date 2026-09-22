import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 解析 `**加粗**` 行内标记，返回可直接传给 [Text.rich] 的 [TextSpan]。
///
/// 标记段默认渲染为强调色（[AppColors.accent]）+ `FontWeight.w700`，
/// 让重点在正文里一眼可辨；未配对的 `**` 按字面保留，不抛错也不吞字符。
TextSpan boldTextSpan(String text, {TextStyle? boldStyle}) {
  final children = <InlineSpan>[];
  final pattern = RegExp(r'\*\*([\s\S]+?)\*\*');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    children.add(
      TextSpan(
        text: match.group(1),
        style:
            boldStyle ??
            const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(children: children);
}

/// 渲染支持 `**加粗**` 的文本，接口与 [Text] 保持一致。
///
/// 纯文本（无标记）时渲染结果与普通 [Text] 等价。
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.text, {
    super.key,
    this.style,
    this.boldStyle,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
  });

  final String text;
  final TextStyle? style;

  /// 加粗片段的样式，默认 `FontWeight.w700`。
  final TextStyle? boldStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    // 无标记时与普通 Text 完全一致。
    if (!text.contains('**')) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      );
    }
    return Text.rich(
      boldTextSpan(text, boldStyle: boldStyle),
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
    );
  }
}
