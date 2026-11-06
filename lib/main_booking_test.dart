import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'app_theme.dart';
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
  runApp(const BookingTestApp());
}

class BookingTestApp extends StatelessWidget {
  const BookingTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      home: const AppShell(forceAllBookableForTest: true),
    );
  }
}
