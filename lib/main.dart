import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_shell.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'services/maid_content_cache_store.dart';
import 'services/queue_tab_settings.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
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
  unawaited(FcmService.initialize());
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
