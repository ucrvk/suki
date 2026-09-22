import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking_session.dart';
import 'supabase_service.dart';

/// 场次数据源：`suki_witch_sessions` + `suki_witch_counts` 合并结果，
/// 返回全部行，是否「未来且有票」由调用方按当前时间判断。
abstract interface class BookingSessionDataSource {
  Future<List<BookingSession>> fetchSessions();
}

class RepositoryBookingSessionDataSource implements BookingSessionDataSource {
  RepositoryBookingSessionDataSource([BookingSessionService? service])
    : _service = service ?? BookingSessionService();

  final BookingSessionService _service;

  @override
  Future<List<BookingSession>> fetchSessions() => _service.fetchSessions();
}

class BookingSessionService {
  BookingSessionService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  static final Uri sessionsEndpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/'
    'suki_witch_sessions?select=*&order=starts_at.asc',
  );

  static final Uri countsEndpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/'
    'suki_witch_counts?select=session_id%2Cbooked',
  );

  Future<List<BookingSession>> fetchSessions() async {
    final results = await Future.wait<Object?>([
      _effectiveClient.from('suki_witch_sessions').select('*'),
      _effectiveClient.from('suki_witch_counts').select('session_id,booked'),
    ]);

    final sessionRows = _rowsOf(results[0], '场次数据必须是数组');
    final countRows = _rowsOf(results[1], '名额数据必须是数组');

    final bookedBySession = <String, int>{};
    for (final row in countRows) {
      final sessionId = (row['session_id'] ?? '').toString();
      final booked = row['booked'];
      if (sessionId.isEmpty || booked is! num) continue;
      bookedBySession[sessionId] = booked.toInt();
    }

    return sessionRows
        .map(
          (row) => BookingSession.fromJson(
            row,
            booked: bookedBySession[(row['id'] ?? '').toString()] ?? 0,
          ),
        )
        .where(
          (session) => session.id.isNotEmpty && session.scriptId.isNotEmpty,
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _rowsOf(Object? data, String invalidMessage) {
    if (data is! List) throw FormatException(invalidMessage);
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
