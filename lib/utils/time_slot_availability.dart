Set<String> normalizeDisabledTimeSlots(Object? rawSlots) {
  if (rawSlots is! List) return <String>{};

  return rawSlots
      .map((slot) => slot.toString().trim())
      .where((slot) => slot.isNotEmpty)
      .toSet();
}

List<String> availableTimeSlots(
  Iterable<String> timeSlots,
  Set<String> disabledTimeSlots,
) {
  return timeSlots.where((slot) => !disabledTimeSlots.contains(slot)).toList();
}

bool areAllBookableTimeSlotsBooked({
  required Iterable<String> timeSlots,
  required Set<String> disabledTimeSlots,
  required Set<String> bookedSlotKeys,
  required String maidVrcid,
}) {
  final bookableSlots = availableTimeSlots(timeSlots, disabledTimeSlots);
  return bookableSlots.isNotEmpty &&
      bookableSlots.every(
        (slot) => bookedSlotKeys.contains('$maidVrcid|$slot'),
      );
}

/// 当前用户对指定女仆仍能预约的时段：
/// 排除女仆不营业的时段、已被他人占用的时段，以及自己已经约过的时段。
List<String> availableTimeSlotsForUser({
  required Iterable<String> timeSlots,
  required Set<String> disabledTimeSlots,
  required Set<String> bookedSlotKeys,
  required Set<String> myBookedSlots,
  required String maidVrcid,
}) {
  return availableTimeSlots(timeSlots, disabledTimeSlots)
      .where(
        (slot) =>
            !bookedSlotKeys.contains('$maidVrcid|$slot') &&
            !myBookedSlots.contains(slot),
      )
      .toList();
}
