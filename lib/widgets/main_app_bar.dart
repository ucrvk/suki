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
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      elevation: 0,
      backgroundColor: scheme.surface,
      centerTitle: centerTitle,
      title: DefaultTextStyle.merge(
        style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
        child: title,
      ),
      foregroundColor: scheme.onSurface,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
