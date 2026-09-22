/// 预约开放时间槽：`suki_witch_slots` 一行。
///
/// `weekdays` 采用 0=周日 … 6=周六；`start_time`/`end_time` 按用户设备本地
/// 时区解释，边界为 `start ≤ now < end`。
class BookingSlot {
  const BookingSlot({
    required this.id,
    required this.weekdays,
    required this.startSeconds,
    required this.endSeconds,
    required this.enabled,
    required this.sort,
  });

  final String id;
  final Set<int> weekdays;
  final int startSeconds;
  final int endSeconds;
  final bool enabled;
  final int sort;

  /// Dart 的 `DateTime.weekday` 是 1=周一 … 7=周日，转换成 0=周日 … 6=周六。
  static int jsWeekdayOf(DateTime local) => local.weekday % 7;

  bool contains(DateTime local) {
    if (!enabled || weekdays.isEmpty) return false;
    final seconds = local.hour * 3600 + local.minute * 60 + local.second;
    if (seconds < startSeconds || seconds >= endSeconds) return false;
    return weekdays.contains(jsWeekdayOf(local));
  }

  /// 返回 null 表示该行格式非法，调用方直接跳过。
  static BookingSlot? tryParse(Object? raw, {int fallbackSort = 0}) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);

    final rawWeekdays = json['weekdays'];
    if (rawWeekdays is! List) return null;
    final weekdays = <int>{};
    for (final value in rawWeekdays) {
      if (value is! num || value % 1 != 0) return null;
      final day = value.toInt();
      if (day < 0 || day > 6) return null;
      weekdays.add(day);
    }

    final start = _secondsOf(json['start_time']);
    final end = _secondsOf(json['end_time']);
    if (start == null || end == null) return null;

    final sortValue = json['sort'];
    return BookingSlot(
      id: (json['id'] ?? '').toString(),
      weekdays: weekdays,
      startSeconds: start,
      endSeconds: end,
      enabled: json['enabled'] == true,
      sort: sortValue is num ? sortValue.toInt() : fallbackSort,
    );
  }

  /// `"HH:mm:ss"` → 当日秒数；允许结束时间写成 `24:00:00`。
  static int? _secondsOf(Object? raw) {
    if (raw is! String) return null;
    final parts = raw.trim().split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) : 0;
    if (hour == null || minute == null || second == null) return null;
    if (hour == 24 && minute == 0 && second == 0) return 86400;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    if (second < 0 || second > 59) return null;
    return hour * 3600 + minute * 60 + second;
  }
}

/// 当前预约窗口状态：是否开放、下一次开放时刻、上一次已开始的开放时刻。
class BookingWindowState {
  const BookingWindowState({
    required this.isOpen,
    this.nextOpenAt,
    this.prevOpenAt,
  });

  final bool isOpen;
  final DateTime? nextOpenAt;
  final DateTime? prevOpenAt;
}

/// 向前/向后最多查找的天数，用于推算上下一次开放。
const int bookingWindowLookAheadDays = 14;

BookingWindowState resolveBookingWindow(List<BookingSlot> slots, DateTime now) {
  final local = now.toLocal();
  final candidates =
      slots
          .where(
            (slot) =>
                slot.enabled &&
                slot.weekdays.isNotEmpty &&
                slot.endSeconds > slot.startSeconds,
          )
          .toList(growable: false)
        ..sort((a, b) => a.sort.compareTo(b.sort));

  final today = DateTime(local.year, local.month, local.day);
  for (final slot in candidates) {
    if (slot.contains(local)) {
      // 正在开放：本次窗口的开始时刻就是「上一次开放」。
      return BookingWindowState(
        isOpen: true,
        prevOpenAt: today.add(Duration(seconds: slot.startSeconds)),
      );
    }
  }

  final nowSeconds = local.hour * 3600 + local.minute * 60 + local.second;

  // 下一次开放：从今天往后找最早的未来开始时刻。
  DateTime? bestNext;
  int bestNextSort = 0;
  for (var offset = 0; offset <= bookingWindowLookAheadDays; offset++) {
    final day = DateTime(local.year, local.month, local.day + offset);
    final weekday = BookingSlot.jsWeekdayOf(day);
    for (final slot in candidates) {
      if (!slot.weekdays.contains(weekday)) continue;
      if (offset == 0 && slot.startSeconds <= nowSeconds) continue;
      final opensAt = day.add(Duration(seconds: slot.startSeconds));
      if (opensAt.isAfter(local) &&
          (bestNext == null ||
              opensAt.isBefore(bestNext) ||
              (opensAt.isAtSameMomentAs(bestNext) &&
                  slot.sort < bestNextSort))) {
        bestNext = opensAt;
        bestNextSort = slot.sort;
      }
    }
    if (bestNext != null && offset > 0) break;
  }

  // 上一次开放：从今天往前找最近的已开始时刻。
  DateTime? bestPrev;
  for (var offset = 0; offset <= bookingWindowLookAheadDays; offset++) {
    final day = DateTime(local.year, local.month, local.day - offset);
    final weekday = BookingSlot.jsWeekdayOf(day);
    DateTime? dayPrev;
    for (final slot in candidates) {
      if (!slot.weekdays.contains(weekday)) continue;
      if (offset == 0 && slot.startSeconds > nowSeconds) continue;
      final opensAt = day.add(Duration(seconds: slot.startSeconds));
      if (opensAt.isAfter(local)) continue;
      if (dayPrev == null || opensAt.isAfter(dayPrev)) dayPrev = opensAt;
    }
    if (dayPrev != null) {
      bestPrev = dayPrev;
      break;
    }
  }

  return BookingWindowState(
    isOpen: false,
    nextOpenAt: bestNext,
    prevOpenAt: bestPrev,
  );
}

/// `下次开放 周六 14:00`
String formatNextOpen(DateTime local) {
  final weekday = '日一二三四五六'[BookingSlot.jsWeekdayOf(local)];
  String two(int value) => value.toString().padLeft(2, '0');
  return '下次开放 周$weekday ${two(local.hour)}:${two(local.minute)}';
}

/// 顶栏用的完整表述：`预计下次开放时间为09月26日星期六14:00`。
String formatNextOpenFull(DateTime local) {
  final weekday = '日一二三四五六'[BookingSlot.jsWeekdayOf(local)];
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.month)}月${two(local.day)}日星期$weekday'
      '${two(local.hour)}:${two(local.minute)}';
}
