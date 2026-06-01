import 'supabase_service.dart';

class ScheduleMaid {
  const ScheduleMaid({
    required this.vrcid,
    required this.name,
    required this.maidName,
  });

  final String vrcid;
  final String name;
  final String maidName;
}

class ScheduleAppointment {
  const ScheduleAppointment({
    required this.guest,
    required this.guestUserId,
    required this.maidName,
    required this.maidVrcid,
    required this.timeSlot,
    required this.withFriend,
    required this.createdAt,
  });

  final String guest;
  final String guestUserId;
  final String maidName;
  final String maidVrcid;
  final String timeSlot;
  final bool withFriend;
  final int createdAt;
}

class ScheduleSnapshot {
  const ScheduleSnapshot({
    required this.date,
    required this.timeSlots,
    required this.maids,
    required this.appointments,
    required this.fetchedAt,
  });

  final String date;
  final List<String> timeSlots;
  final List<ScheduleMaid> maids;
  final List<ScheduleAppointment> appointments;
  final DateTime fetchedAt;
}

class ScheduleCacheService {
  ScheduleCacheService._();

  static ScheduleSnapshot? _snapshot;

  static Future<ScheduleSnapshot> getTodaySchedule({bool forceRefresh = false}) async {
    if (!forceRefresh && _snapshot != null) return _snapshot!;

    final today = _todayInUtc();
    final rows = await SupabaseService.client
        .from('suki_schedule')
        .select('*')
        .lte('date', today)
        .order('date', ascending: false)
        .limit(1);

    if (rows.isEmpty) {
      _snapshot = ScheduleSnapshot(
        date: today,
        timeSlots: const [],
        maids: const [],
        appointments: const [],
        fetchedAt: DateTime.now(),
      );
      return _snapshot!;
    }

    final first = Map<String, dynamic>.from(rows.first);
    final scheduleDate = (first['date'] ?? today).toString().trim().isEmpty
        ? today
        : (first['date'] ?? today).toString().trim();

    final timeSlots = ((first['time_slots'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final maids = ((first['maids'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (m) => ScheduleMaid(
            vrcid: (m['vrcid'] ?? '').toString().trim(),
            name: (m['name'] ?? '').toString().trim(),
            maidName: (m['maidName'] ?? '').toString().trim(),
          ),
        )
        .where((m) => m.vrcid.isNotEmpty)
        .toList();

    final appointments = ((first['appointments'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (a) => ScheduleAppointment(
            guest: (a['guest'] ?? '').toString().trim(),
            guestUserId: (a['guestUserId'] ?? '').toString().trim(),
            maidName: (a['maidName'] ?? '').toString().trim(),
            maidVrcid: (a['maidVrcid'] ?? '').toString().trim(),
            timeSlot: (a['timeSlot'] ?? '').toString().trim(),
            withFriend: a['withFriend'] == true,
            createdAt: a['createdAt'] is num ? (a['createdAt'] as num).toInt() : 0,
          ),
        )
        .toList();

    _snapshot = ScheduleSnapshot(
      date: scheduleDate,
      timeSlots: timeSlots,
      maids: maids,
      appointments: appointments,
      fetchedAt: DateTime.now(),
    );

    return _snapshot!;
  }

  static void invalidate() {
    _snapshot = null;
  }

  static String _todayInUtc() {
    final utcNow = DateTime.now().toUtc();
    final y = utcNow.year.toString().padLeft(4, '0');
    final m = utcNow.month.toString().padLeft(2, '0');
    final d = utcNow.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
