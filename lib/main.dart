import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'services/maid_content_cache_store.dart';
import 'services/spoiler_mode_store.dart';
import 'services/supabase_service.dart';
import 'theme/app_colors.dart';

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
      theme: ThemeData(
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
        fontFamily: 'IceMoon',
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          space: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.accent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.field,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
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
      ),
      home: AppShell(spoilerModeStore: spoilerModeStore),
    );
  }
}
