import 'package:shared_preferences/shared_preferences.dart';

class SysbookingSessionStore {
  SysbookingSessionStore._();

  static const String bookingTokenKey = 'sysbooking_booking_token';
  static const String lastEmailKey = 'sysbooking_last_email';

  static Future<String?> loadBookingToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(bookingTokenKey)?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  static Future<void> saveBookingToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(bookingTokenKey, token.trim());
  }

  static Future<void> clearBookingToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(bookingTokenKey);
  }

  static Future<String?> loadLastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(lastEmailKey)?.trim();
    return email == null || email.isEmpty ? null : email;
  }

  static Future<void> saveLastEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastEmailKey, email.trim());
  }
}
