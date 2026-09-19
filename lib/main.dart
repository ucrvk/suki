import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'services/maid_content_cache_store.dart';
import 'services/supabase_service.dart';

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
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF1F1338),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A2F80),
          brightness: Brightness.dark,
          surface: const Color(0xFF33205C),
        ),
        useMaterial3: true,
        fontFamily: 'IceMoon',
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF33205C),
          indicatorColor: Color(0xFF4A2F80),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Color(0xFFF4EEFF)),
          ),
          iconTheme: WidgetStatePropertyAll(
            IconThemeData(color: Color(0xFFF4EEFF)),
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
