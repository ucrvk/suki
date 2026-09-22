import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// 提交预约：`POST /rest/v1/rpc/book_witch_session`。
abstract interface class BookingSubmitService {
  Future<void> book({
    required String sessionId,
    required int guests,
    required List<String> companions,
  });
}

class SupabaseBookingService implements BookingSubmitService {
  SupabaseBookingService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  @override
  Future<void> book({
    required String sessionId,
    required int guests,
    required List<String> companions,
  }) async {
    await _effectiveClient.rpc(
      'book_witch_session',
      params: {
        'p_session_id': sessionId,
        'p_guests': guests,
        'p_companions': companions,
      },
    );
  }
}

/// 取出对用户可读的失败原因（重复预约、名额不足等由服务端 message 透出）。
String bookingErrorMessage(Object error) {
  if (error is PostgrestException) {
    final message = error.message.trim();
    if (message.isNotEmpty) return message;
    if (error.details != null) return error.details.toString();
  }
  if (error is FormatException) return error.message;
  final text = error.toString().trim();
  return text.isEmpty ? '预约失败，请稍后重试' : text;
}
