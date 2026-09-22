import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/booking_slot.dart';
import 'supabase_service.dart';

/// 预约时间槽数据源：`suki_witch_slots` 全量（含 `enabled=false`，由上层判断）。
abstract interface class BookingSlotDataSource {
  Future<List<BookingSlot>> fetchSlots();
}

class RepositoryBookingSlotDataSource implements BookingSlotDataSource {
  RepositoryBookingSlotDataSource([BookingSlotService? service])
    : _service = service ?? BookingSlotService();

  final BookingSlotService _service;

  @override
  Future<List<BookingSlot>> fetchSlots() => _service.fetchSlots();
}

class BookingSlotService {
  BookingSlotService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _effectiveClient => _client ?? SupabaseService.client;

  Future<List<BookingSlot>> fetchSlots() async {
    // `select` 返回的一定是数组，非法行由 tryParse 逐条跳过。
    final rows = await _effectiveClient.from('suki_witch_slots').select('*');

    final slots = <BookingSlot>[];
    var fallbackSort = 0;
    for (final row in rows) {
      final slot = BookingSlot.tryParse(row, fallbackSort: fallbackSort);
      fallbackSort += 1;
      if (slot != null) slots.add(slot);
    }
    slots.sort((a, b) => a.sort.compareTo(b.sort));
    return slots;
  }
}
