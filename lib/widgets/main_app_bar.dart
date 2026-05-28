import 'package:flutter/material.dart';

class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MainAppBar({
    super.key,
    required this.title,
    this.actions,
    this.centerTitle = false,
  });

  final Widget title;
  final List<Widget>? actions;
  final bool centerTitle;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: const Color(0xFFF3EFF5),
      centerTitle: centerTitle,
      title: DefaultTextStyle.merge(
        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF3A3250)),
        child: title,
      ),
      foregroundColor: const Color(0xFF3A3250),
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
