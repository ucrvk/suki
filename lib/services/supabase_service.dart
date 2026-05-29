import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SupabaseService {
  SupabaseService._();

  static const String supabaseUrl = 'https://uzlzkjuijruqanetagxh.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_6_fvEEW8e1DNGvtVhXPzxw_h2i04w7b';
  static const String _userAgentPrefix = 'appointApp';
  static const String _userAgentSuffix = 'admin@wenwen12305.top';

  static Future<String> buildUserAgent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      final versionPart = build.isEmpty ? version : '$version+$build';
      return '$_userAgentPrefix-$versionPart/$_userAgentSuffix';
    } catch (_) {
      return '$_userAgentPrefix-unknown/$_userAgentSuffix';
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
}
