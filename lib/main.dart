import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'services/maid_content_cache_store.dart';
import 'services/spoiler_mode_store.dart';
import 'services/supabase_service.dart';
import 'theme/app_colors.dart';

/// 全局字体。NavigationRail 的标签样式是裸 TextStyle（会整体替换环境
/// DefaultTextStyle），必须显式引用同一常量，否则标签会掉出该字体。
const _appFontFamily = 'IceMoon';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final userAgent = await SupabaseService.buildUserAgent();
  await Supabase.initialize(
    url: SupabaseService.supabaseUrl,
    anonKey: SupabaseService.supabaseAnonKey,
    headers: {
      'apikey': SupabaseService.supabaseAnonKey,
      if (!kIsWeb) 'User-Agent': userAgent,
    },
  );
  await MaidContentCacheStore.ensureInitialized();
  final spoilerModeStore = await HiveSpoilerModeStore.instance();
  runApp(MainApp(spoilerModeStore: spoilerModeStore));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.spoilerModeStore});

  final SpoilerModeStore? spoilerModeStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: buildAppTheme(),
      home: AppShell(spoilerModeStore: spoilerModeStore),
    );
  }
}

/// 应用全局主题；独立成函数便于测试（导航标签字体等回归）。
ThemeData buildAppTheme() {
  return ThemeData(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.accentInk,
      secondary: AppColors.accentSoft,
      onSecondary: AppColors.accentInk,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.field,
      outline: AppColors.outline,
      outlineVariant: AppColors.divider,
    ),
    useMaterial3: true,
    fontFamily: _appFontFamily,
    fontFamilyFallback: const ['AppFallback'],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.field,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: _appFontFamily,
          color: selected ? AppColors.accent : AppColors.textMuted,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.textMuted,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.field,
      selectedIconTheme: IconThemeData(color: AppColors.accent),
      unselectedIconTheme: IconThemeData(color: AppColors.textMuted),
      // NavigationRail 用 DefaultTextStyle 整体替换环境样式，
      // 必须显式带上 fontFamily，否则标签会掉出 IceMoon 字体。
      selectedLabelTextStyle: TextStyle(
        fontFamily: _appFontFamily,
        color: AppColors.accent,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: _appFontFamily,
        color: AppColors.textMuted,
        fontSize: 17,
        fontWeight: FontWeight.w500,
      ),
      minWidth: 72,
    ),
  );
}
