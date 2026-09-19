import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/roster_entry.dart';
import 'package:suki/pages/roster_page.dart';

void main() {
  Map<String, dynamic> row({
    String script = '夜眠花',
    String at = '2026-09-19T13:30:00+00:00',
    Object? end,
    String group = 'DMW',
    Object guests = 2,
    String id = 'booking-1',
    Object companions = const ['肆安_Sensei'],
  }) => {
    'script_name': script,
    'session_at': at,
    'session_end': end,
    'group_name': group,
    'guests': guests,
    'booking_id': id,
    'companions': companions,
    'ignored_future_field': true,
  };

  test('parses valid response and tolerates null session_end', () {
    final entry = RosterEntry.fromJson(row());

    expect(entry.scriptName, '夜眠花');
    expect(entry.sessionEnd, isNull);
    expect(entry.guests, 2);
    expect(entry.companions, ['肆安_Sensei']);
  });

  test('accepts an empty companions list', () {
    final entry = RosterEntry.fromJson(row(companions: const []));
    expect(entry.companions, isEmpty);
  });

  test('rejects invalid field types and invalid dates', () {
    expect(() => RosterEntry.fromJson(row(guests: '2')), throwsFormatException);
    expect(
      () => RosterEntry.fromJson(row(at: 'not-a-date')),
      throwsFormatException,
    );
    expect(
      () => RosterEntry.fromJson(row(companions: 'none')),
      throwsFormatException,
    );
  });

  test('groups equal sessions and sorts sessions chronologically', () {
    final late = RosterEntry.fromJson(
      row(at: '2026-09-20T13:30:00Z', id: 'late'),
    );
    final first = RosterEntry.fromJson(row(id: 'first', group: 'B'));
    final second = RosterEntry.fromJson(row(id: 'second', group: 'A'));

    final sessions = groupRosterEntries([late, first, second]);

    expect(sessions, hasLength(2));
    expect(sessions.first.entries, hasLength(2));
    expect(sessions.first.entries.first.groupName, 'A');
    expect(sessions.last.entries.single.bookingId, 'late');
  });

  test('formats start-only and same-day ranges', () {
    expect(
      formatSessionTime(DateTime(2026, 9, 19, 21, 30), null),
      '09月19日  21:30',
    );
    expect(
      formatSessionTime(
        DateTime(2026, 9, 19, 21, 30),
        DateTime(2026, 9, 19, 23),
      ),
      '09月19日  21:30 - 23:00',
    );
  });
}
