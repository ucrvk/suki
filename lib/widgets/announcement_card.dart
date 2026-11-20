import 'package:flutter/material.dart';

/// 「我」页面的公告卡片。
///
/// 公告超过 10 行时默认折叠，并在底部显示一个箭头按钮用于展开 / 收起。
class AnnouncementCard extends StatefulWidget {
  const AnnouncementCard({super.key, required this.text});

  final String text;

  @override
  State<AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<AnnouncementCard> {
  static const int _collapsedLines = 10;

  bool _expanded = false;

  @override
  void didUpdateWidget(covariant AnnouncementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark
        ? const Color(0xFFF1EAF8)
        : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    final text = widget.text.trim();
    final displayText = text.isEmpty ? '暂无公告' : text;
    final contentStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: subColor);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        titleAlignment: ListTileTitleAlignment.top,
        title: Text(
          '公告',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        subtitle: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final painter = TextPainter(
              text: TextSpan(text: displayText, style: contentStyle),
              maxLines: _collapsedLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: maxWidth);
            final canExpand = text.isNotEmpty && painter.didExceedMaxLines;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayText,
                  maxLines: _expanded ? null : _collapsedLines,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  style: contentStyle,
                ),
                if (canExpand)
                  Align(
                    alignment: Alignment.center,
                    child: IconButton(
                      onPressed: () {
                        setState(() => _expanded = !_expanded);
                      },
                      tooltip: _expanded ? '收起公告' : '展开公告',
                      color: subColor,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 40,
                      ),
                      icon: AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
