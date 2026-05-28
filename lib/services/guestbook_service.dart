import 'supabase_service.dart';

class GuestbookEntry {
  final String id;
  final String userId;
  final String username;
  final String? avatarUrl;
  final String content;
  final int likes;
  final bool approved;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;

  GuestbookEntry({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.content,
    required this.likes,
    required this.approved,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
  });

  factory GuestbookEntry.fromJson(Map<String, dynamic> json) {
    return GuestbookEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      content: json['content'] as String,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      approved: json['approved'] as bool? ?? false,
      createdAt: _parseTimestamp(json['created_at']),
      updatedAt: _parseTimestamp(json['updated_at']),
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is num) {
      // Supabase returns unix timestamps as double
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
    }
    return DateTime.now();
  }
}

class GuestbookService {
  GuestbookService._();

  static Future<String> submitGuestbookMessage({
    required String content,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw Exception('留言内容不能为空');
    }

    final result = await SupabaseService.client.rpc(
      'submit_guestbook_message',
      params: {'p_content': trimmed},
    );

    return (result ?? '').toString().trim();
  }
}
