import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class MyBooking {
  const MyBooking({required this.sessionId, required this.guests});

  final String sessionId;
  final int guests;
}

abstract interface class MyBookingService {
  Future<List<MyBooking>> fetch(String userId);
  Future<void> cancel(String sessionId);
}

class SupabaseMyBookingService implements MyBookingService {
  SupabaseMyBookingService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  @override
  Future<List<MyBooking>> fetch(String userId) async {
    final rows = await _effectiveClient
        .from('suki_witch_bookings')
        .select('session_id,guests')
        .eq('user_id', userId);
    return rows
        .map((row) {
          final sessionId = row['session_id'];
          final guests = row['guests'];
          if (sessionId is! String || sessionId.isEmpty || guests is! int) {
            throw const FormatException('本人预约数据格式错误');
          }
          return MyBooking(sessionId: sessionId, guests: guests);
        })
        .toList(growable: false);
  }

  @override
  Future<void> cancel(String sessionId) async {
    await _effectiveClient.rpc(
      'cancel_witch_session',
      params: {'p_session_id': sessionId},
    );
  }
}
