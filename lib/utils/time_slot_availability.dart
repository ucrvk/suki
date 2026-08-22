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
