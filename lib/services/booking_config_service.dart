import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

abstract interface class BookingConfigDataSource {
  Future<bool> fetchBookingEnabled();
}

class RepositoryBookingConfigDataSource implements BookingConfigDataSource {
  RepositoryBookingConfigDataSource([BookingConfigService? service])
    : _service = service ?? BookingConfigService();

  final BookingConfigService _service;

  @override
  Future<bool> fetchBookingEnabled() => _service.fetchBookingEnabled();
}

class BookingConfigService {
  BookingConfigService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  /// Reads `suki_witch_config.enabled` for `id = true`.
  /// Returns true when the row/value is missing so a bad config
  /// never blocks the booking list; callers treat fetch errors
  /// as "keep previous value".
  Future<bool> fetchBookingEnabled() async {
    final row = await _effectiveClient
        .from('suki_witch_config')
        .select('enabled')
        .eq('id', true)
        .maybeSingle();
    final enabled = row?['enabled'];
    if (enabled is bool) return enabled;
    return true;
  }
}
