/// 排班页的预约条目。
///
/// 数据来自 `suki_booking.reservations`，兼容 `suki_schedule.appointments` 的
/// `guest` 字段。`friendVrcid` 在实际数据中存的是好友名称。
class ReservationDetails {
  const ReservationDetails({
    required this.guest,
    required this.guestUserId,
    required this.maidName,
    required this.maidVrcid,
    required this.timeSlot,
    required this.withFriend,
    required this.createdAt,
    required this.services,
    required this.friendName,
  });

  final String guest;
  final String guestUserId;
  final String maidName;
  final String maidVrcid;
  final String timeSlot;
  final bool withFriend;
  final int createdAt;
  final List<String> services;
  final String friendName;

  /// 带好友或选择了「玩什么」时，才展示预约详情。
  bool get hasDetails => withFriend || services.isNotEmpty;

  String get guestDisplay => guest.isEmpty ? '匿名' : guest;

  String get maidDisplay {
    if (maidName.isNotEmpty) return maidName;
    return maidVrcid.isEmpty ? '未命名' : maidVrcid;
  }

  String get friendDisplay {
    if (!withFriend) return '';
    return friendName.isEmpty ? '已带好友' : friendName;
  }

  factory ReservationDetails.fromRow(Map<String, dynamic> row) {
    final services = <String>[];
    final seen = <String>{};
    final rawServices = row['services'];
    if (rawServices is List) {
      for (final raw in rawServices) {
        final value = raw?.toString().trim() ?? '';
        if (value.isEmpty || !seen.add(value)) continue;
        services.add(value);
      }
    }

    return ReservationDetails(
      guest: _firstNonEmpty([row['guestUsername'], row['guest']]),
      guestUserId: (row['guestUserId'] ?? '').toString().trim(),
      maidName: (row['maidName'] ?? '').toString().trim(),
      maidVrcid: (row['maidVrcid'] ?? '').toString().trim(),
      timeSlot: (row['timeSlot'] ?? '').toString().trim(),
      withFriend: row['withFriend'] == true,
      createdAt: row['createdAt'] is num
          ? (row['createdAt'] as num).toInt()
          : 0,
      services: List.unmodifiable(services),
      friendName: _firstNonEmpty([
        row['friendVrcid'],
        row['friendName'],
        row['friend'],
      ]),
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
