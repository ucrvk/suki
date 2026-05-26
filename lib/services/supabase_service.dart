import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String supabaseUrl = 'https://uzlzkjuijruqanetagxh.supabase.co';
  static const String supabaseAnonKey = 'sb_publishable_6_fvEEW8e1DNGvtVhXPzxw_h2i04w7b';
  static const String fixedUserAgent = 'appointApp-1.0.0/admin@wenwen12305.top';

  static SupabaseClient get client => Supabase.instance.client;
}
