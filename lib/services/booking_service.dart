import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class BookingService {
  BookingService._();

  static String _formatZhCnNow() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}/${now.month}/${now.day} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  static String _usernameFromUser(User user) {
    final metaName = (user.userMetadata?['username'] ?? '').toString().trim();
    if (metaName.isNotEmpty) return metaName;
    final email = (user.email ?? '').trim();
    if (email.contains('@')) return email.split('@').first;
    return email.isEmpty ? user.id : email;
  }

  static Future<void> addReservation({
    required Map<String, dynamic> maid,
    required String timeSlot,
    required bool withFriend,
    required String friendVrcid,
  }) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      throw Exception('请先登录');
    }

    final maidVrcid = (maid['vrcid'] ?? '').toString().trim();
    final maidName = (maid['name'] ?? '').toString().trim();
    if (maidVrcid.isEmpty || maidName.isEmpty) {
      throw Exception('女仆信息不完整，无法预约');
    }

    await SupabaseService.client.rpc(
      'add_reservation',
      params: {
        'p_maid_vrcid': maidVrcid,
        'p_maid_name': maidName,
        'p_guest_username': _usernameFromUser(user),
        'p_guest_user_id': user.id,
        'p_time_slot': timeSlot,
        'p_time': _formatZhCnNow(),
        'p_created_at': DateTime.now().millisecondsSinceEpoch,
        'p_with_friend': withFriend,
        'p_friend_vrcid': friendVrcid.trim(),
      },
    );
  }
}
