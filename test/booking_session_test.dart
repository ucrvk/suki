import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/booking_script_entry.dart';
import 'package:suki/models/booking_session.dart';

void main() {
  group('BookingNotice', () {
    test('parses a full notice', () {
      final notice = BookingNotice.tryParse({
        'title': '预约前，请听魔女一句',
        'intro': 'intro',
        'items': ['a', ' b ', ''],
        'footer': 'footer',
      });
      expect(notice, isNotNull);
      expect(notice!.title, '预约前，请听魔女一句');
      expect(notice.intro, 'intro');
      expect(notice.items, ['a', 'b']);
      expect(notice.footer, 'footer');
    });

    test('returns null for missing or malformed values', () {
      expect(BookingNotice.tryParse(null), isNull);
      expect(BookingNotice.tryParse('oops'), isNull);
      expect(BookingNotice.tryParse({}), isNull);
      expect(
        BookingNotice.tryParse({'title': '  ', 'items': <Object?>[]}),
        isNull,
      );
    });
  });

  group('BookingScriptEntry.fromJson', () {
    test('keeps notice when present', () {
      final entry = BookingScriptEntry.fromJson({
        'id': 's1',
        'name': '夜眠花',
        'sort': 1,
        'tags': ['剧情'],
        'notice': {
          'title': 't',
          'intro': 'i',
          'items': ['x'],
          'footer': 'f',
        },
      });
      expect(entry.notice, isNotNull);
      expect(entry.notice!.title, 't');
    });

    test('tolerates absent notice', () {
      final entry = BookingScriptEntry.fromJson({'id': 's1', 'name': 'n'});
      expect(entry.notice, isNull);
    });
  });

  group('BookingSession', () {
    BookingSession session({
      int capacity = 10,
      int booked = 4,
      String startsAt = '2099-01-02T03:04:05+00:00',
    }) => BookingSession.fromJson({
      'id': 'sess-1',
      'script_id': 's1',
      'starts_at': startsAt,
      'ends_at': null,
      'capacity': capacity,
    }, booked: booked);

    test('merges booked count and clamps remaining at zero', () {
      expect(session().remaining, 6);
      expect(session(capacity: 2, booked: 5).remaining, 0);
    });

    test('hasSeats requires future start and free seats', () {
      final now = DateTime.utc(2026, 9, 22);
      expect(session().hasSeatsAt(now), isTrue);
      expect(
        session(startsAt: '2026-09-21T00:00:00+00:00').hasSeatsAt(now),
        isFalse,
      );
      expect(session(booked: 10).hasSeatsAt(now), isFalse);
      expect(
        session(startsAt: '2026-09-23T13:30:00+00:00').isUpcomingAt(now),
        isTrue,
      );
    });

    test('parses null ends_at and missing booked fallback', () {
      final parsed = BookingSession.fromJson({
        'id': 'sess-1',
        'script_id': 's1',
        'starts_at': '2026-09-23T13:30:00+00:00',
        'ends_at': null,
        'capacity': 100,
      });
      expect(parsed.endsAt, isNull);
      expect(parsed.booked, 0);
      expect(parsed.startsAt.isUtc, isTrue);
    });
  });
}
