/// 一场可预约的场次：`suki_witch_sessions` 一行 + `suki_witch_counts.booked`。
class BookingSession {
  const BookingSession({
    required this.id,
    required this.scriptId,
    required this.startsAt,
    required this.capacity,
    required this.booked,
    this.endsAt,
  });

  final String id;
  final String scriptId;
  final DateTime startsAt;
  final DateTime? endsAt;
  final int capacity;
  final int booked;

  int get remaining => capacity - booked < 0 ? 0 : capacity - booked;

  bool isUpcomingAt(DateTime now) => startsAt.isAfter(now);

  bool hasSeatsAt(DateTime now) => isUpcomingAt(now) && remaining > 0;

  factory BookingSession.fromJson(Map<String, dynamic> json, {int booked = 0}) {
    final capacityValue = json['capacity'];
    final bookedValue = json['booked'];
    return BookingSession(
      id: (json['id'] ?? '').toString(),
      scriptId: (json['script_id'] ?? '').toString(),
      startsAt: _parseDate(json['starts_at']) ?? DateTime.now().toUtc(),
      endsAt: _parseDate(json['ends_at']),
      capacity: capacityValue is num ? capacityValue.toInt() : 0,
      booked: bookedValue is num ? bookedValue.toInt() : booked,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toUtc();
  }

  /// 展示用：`09-23 21:30`（按本地时区）。
  String get label {
    final local = startsAt.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
