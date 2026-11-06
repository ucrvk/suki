import 'package:flutter/material.dart';

const String appFontFamily = 'IceMoon';

/// 应用主题（亮 / 暗各一份）。
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFFFF5DAF),
    brightness: brightness,
  );

  return ThemeData(
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF141218)
        : const Color(0xFFF3EFF5),
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: appFontFamily,
  );
}
