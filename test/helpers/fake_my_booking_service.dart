import 'package:suki/services/my_booking_service.dart';

class FakeMyBookingService implements MyBookingService {
  List<MyBooking> bookings = [];
  Object? fetchError;
  Object? cancelError;
  final List<String> canceled = [];
  final List<String> fetchedUsers = [];

  @override
  Future<List<MyBooking>> fetch(String userId) async {
    fetchedUsers.add(userId);
    if (fetchError != null) throw fetchError!;
    return List.of(bookings);
  }

  @override
  Future<void> cancel(String sessionId) async {
    canceled.add(sessionId);
    if (cancelError != null) throw cancelError!;
    bookings.removeWhere((b) => b.sessionId == sessionId);
  }
}
