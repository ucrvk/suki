import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
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
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3EFF5),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF5DAF)),
        useMaterial3: true,
        fontFamily: 'IceMoon',
      ),
      darkTheme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF141218),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF5DAF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'IceMoon',
      ),
      home: const AppShell(),
    );
  }
}
