import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking_script_entry.dart';
import 'supabase_service.dart';

class BookingScriptService {
  BookingScriptService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  Future<List<BookingScriptEntry>> fetchScripts() async {
    final rows = await _effectiveClient
        .from('suki_witch_scripts')
        .select('*')
        .order('sort', ascending: true);
    return rows
        .whereType<Map>()
        .map(
          (row) => BookingScriptEntry.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((entry) => entry.name.isNotEmpty)
        .toList(growable: false);
  }
}
