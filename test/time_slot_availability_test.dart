import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/time_slot_availability.dart';

void main() {
  group('normalizeDisabledTimeSlots', () {
    test('trims values and removes empty and duplicate entries', () {
      expect(
        normalizeDisabledTimeSlots([
          ' 21:30-22:30 ',
          '',
          '22:30-23:30',
          '21:30-22:30',
          '   ',
        ]),
        {'21:30-22:30', '22:30-23:30'},
      );
    });

    test('returns an empty set for missing or invalid values', () {
      expect(normalizeDisabledTimeSlots(null), isEmpty);
      expect(normalizeDisabledTimeSlots('21:30-22:30'), isEmpty);
    });
  });

  test('availableTimeSlots excludes only the supplied maid disabled slots', () {
    expect(
      availableTimeSlots(
        ['20:30-21:30', '21:30-22:30', '22:30-23:30'],
        {'21:30-22:30', '22:30-23:30'},
      ),
      ['20:30-21:30'],
    );
  });

  test('treats a maid as full when every bookable slot is booked', () {
    expect(
      areAllBookableTimeSlotsBooked(
        timeSlots: ['21:30-22:30', '22:30-23:30'],
        disabledTimeSlots: {'22:30-23:30'},
        bookedSlotKeys: {'maid-1|21:30-22:30'},
        maidVrcid: 'maid-1',
      ),
      isTrue,
    );
    expect(
      areAllBookableTimeSlotsBooked(
        timeSlots: ['21:30-22:30', '22:30-23:30'],
        disabledTimeSlots: const <String>{},
        bookedSlotKeys: {'maid-1|21:30-22:30'},
        maidVrcid: 'maid-1',
      ),
      isFalse,
    );
  });
}
