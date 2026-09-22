import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/booking_slot.dart';

void main() {
  Map<String, Object?> slotRow({
    Object? weekdays = const [6],
    String start = '14:00:00',
    String end = '23:59:00',
    bool enabled = true,
    int sort = 0,
    Object? id = 'slot-1',
  }) => {
    'id': id,
    'weekdays': weekdays,
    'start_time': start,
    'end_time': end,
    'enabled': enabled,
    'sort': sort,
    'created_at': '2026-09-09T05:44:08.587042+00:00',
  };

  BookingSlot parse(Map<String, Object?> row) => BookingSlot.tryParse(row)!;

  group('BookingSlot.tryParse', () {
    test('parses the sample rows', () {
      final slot = parse(slotRow());
      expect(slot.id, 'slot-1');
      expect(slot.weekdays, {6});
      expect(slot.startSeconds, 14 * 3600);
      expect(slot.endSeconds, 23 * 3600 + 59 * 60);
      expect(slot.enabled, isTrue);
      expect(slot.sort, 0);
    });

    test('accepts 24:00:00 as an all-day end', () {
      final slot = parse(slotRow(end: '24:00:00'));
      expect(slot.endSeconds, 86400);
    });

    test('rejects malformed rows', () {
      expect(BookingSlot.tryParse(null), isNull);
      expect(BookingSlot.tryParse('x'), isNull);
      expect(BookingSlot.tryParse(slotRow(weekdays: '6')), isNull);
      expect(BookingSlot.tryParse(slotRow(weekdays: const [7])), isNull);
      expect(BookingSlot.tryParse(slotRow(start: 'noon')), isNull);
      expect(BookingSlot.tryParse(slotRow(end: '25:00:00')), isNull);
    });

    test('a disabled slot never opens the window', () {
      // 2026-09-19 是周六。
      final now = DateTime(2026, 9, 19, 15);
      final disabled = parse(slotRow(enabled: false));
      expect(disabled.contains(now), isFalse);

      final window = resolveBookingWindow([disabled], now);
      expect(window.isOpen, isFalse);
    });
  });

  group('BookingSlot.contains', () {
    // 2026-09-19 是周六（js weekday = 6）。
    final saturday = DateTime(2026, 9, 19);
    final slot = parse(
      slotRow(weekdays: const [6], start: '14:00:00', end: '17:15:00'),
    );

    test('start is inclusive and end is exclusive', () {
      expect(slot.contains(DateTime(2026, 9, 19, 14, 0, 0)), isTrue);
      expect(slot.contains(DateTime(2026, 9, 19, 14, 0, 1)), isTrue);
      expect(slot.contains(DateTime(2026, 9, 19, 13, 59, 59)), isFalse);
      expect(slot.contains(DateTime(2026, 9, 19, 17, 14, 59)), isTrue);
      expect(slot.contains(DateTime(2026, 9, 19, 17, 15, 0)), isFalse);
    });

    test('only matches the configured weekdays', () {
      final friday = DateTime(2026, 9, 18, 15);
      expect(BookingSlot.jsWeekdayOf(saturday), 6);
      expect(BookingSlot.jsWeekdayOf(DateTime(2026, 9, 20)), 0);
      expect(slot.contains(friday), isFalse);
      expect(slot.contains(DateTime(2026, 9, 19, 15)), isTrue);
    });
  });

  group('resolveBookingWindow', () {
    final saturdaySlot = parse(
      slotRow(weekdays: const [6], start: '14:00:00', end: '23:59:00'),
    );

    test('is open inside the window', () {
      final window = resolveBookingWindow([
        saturdaySlot,
      ], DateTime(2026, 9, 19, 15));
      expect(window.isOpen, isTrue);
      expect(window.nextOpenAt, isNull);
      // 正在开放时，上一次开放就是本次窗口的开始。
      expect(window.prevOpenAt, DateTime(2026, 9, 19, 14));
    });

    test('later the same day points to today\'s start', () {
      final window = resolveBookingWindow([
        saturdaySlot,
      ], DateTime(2026, 9, 19, 10));
      expect(window.isOpen, isFalse);
      expect(window.nextOpenAt, DateTime(2026, 9, 19, 14));
      // 今天还没开，上一次是上周六。
      expect(window.prevOpenAt, DateTime(2026, 9, 12, 14));
      expect(formatNextOpen(window.nextOpenAt!), '下次开放 周六 14:00');
    });

    test('after today\'s window rolls to next week', () {
      final window = resolveBookingWindow([
        saturdaySlot,
      ], DateTime(2026, 9, 19, 23, 59, 30));
      expect(window.isOpen, isFalse);
      expect(window.nextOpenAt, DateTime(2026, 9, 26, 14));
      expect(window.prevOpenAt, DateTime(2026, 9, 19, 14));
      expect(formatNextOpen(window.nextOpenAt!), '下次开放 周六 14:00');
    });

    test('on another weekday points to the next matching day', () {
      final window = resolveBookingWindow(
        [saturdaySlot],
        DateTime(2026, 9, 18, 15), // 周五
      );
      expect(window.isOpen, isFalse);
      expect(window.nextOpenAt, DateTime(2026, 9, 19, 14));
      expect(formatNextOpen(window.nextOpenAt!), '下次开放 周六 14:00');
    });

    test('without any slot nothing is open', () {
      final window = resolveBookingWindow([], DateTime(2026, 9, 19, 15));
      expect(window.isOpen, isFalse);
      expect(window.nextOpenAt, isNull);
      expect(window.prevOpenAt, isNull);
    });
  });

  group('formatNextOpenFull', () {
    test('renders date, weekday and xx:xx time', () {
      expect(formatNextOpenFull(DateTime(2026, 9, 26, 14)), '09月26日星期六14:00');
      expect(
        formatNextOpenFull(DateTime(2026, 9, 23, 21, 30)),
        '09月23日星期三21:30',
      );
      expect(formatNextOpenFull(DateTime(2026, 9, 20, 0, 5)), '09月20日星期日00:05');
    });
  });
}
