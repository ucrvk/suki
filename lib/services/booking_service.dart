import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class BookingService {
  BookingService._();

  static String _formatZhCn(DateTime now) {
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
    required List<String> services,
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

    final now = DateTime.now();
    await SupabaseService.client.rpc(
      'add_reservation',
      params: buildAddReservationParams(
        maidVrcid: maidVrcid,
        maidName: maidName,
        guestUsername: _usernameFromUser(user),
        guestUserId: user.id,
        timeSlot: timeSlot,
        time: _formatZhCn(now),
        createdAt: now.millisecondsSinceEpoch,
        withFriend: withFriend,
        friendVrcid: friendVrcid,
        services: services,
      ),
    );
  }

  /// 构造 `add_reservation` 的参数，抽出来便于测试。
  @visibleForTesting
  static Map<String, dynamic> buildAddReservationParams({
    required String maidVrcid,
    required String maidName,
    required String guestUsername,
    required String guestUserId,
    required String timeSlot,
    required String time,
    required int createdAt,
    required bool withFriend,
    required String friendVrcid,
    required List<String> services,
  }) {
    return {
      'p_maid_vrcid': maidVrcid,
      'p_maid_name': maidName,
      'p_guest_username': guestUsername,
      'p_guest_user_id': guestUserId,
      'p_time_slot': timeSlot,
      'p_time': time,
      'p_created_at': createdAt,
      'p_with_friend': withFriend,
      'p_friend_vrcid': friendVrcid.trim(),
      'p_services': [
        for (final service in services)
          if (service.trim().isNotEmpty) service.trim(),
      ],
    };
  }
}
