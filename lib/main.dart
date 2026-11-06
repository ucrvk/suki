import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'app_theme.dart';
import 'services/maid_content_cache_store.dart';
import 'services/queue_tab_settings.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final userAgent = await SupabaseService.buildUserAgent();
  await Supabase.initialize(
    url: SupabaseService.supabaseUrl,
    anonKey: SupabaseService.supabaseAnonKey,
    headers: {
      'apikey': SupabaseService.supabaseAnonKey,
      'User-Agent': userAgent,
    },
  );
  await MaidContentCacheStore.ensureInitialized();
  await QueueTabSettings.load();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const AppShell(),
    );
  }
}
