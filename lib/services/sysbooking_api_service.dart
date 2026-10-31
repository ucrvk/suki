import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_log_service.dart';
import 'backend_request_headers.dart';
import 'supabase_service.dart';

class SysbookingQueueItem {
  const SysbookingQueueItem({
    required this.bookingId,
    required this.maidId,
    required this.withFriend,
    required this.friendVrcid,
    required this.timeslot,
    required this.queue,
    required this.autoqueue,
  });

  final String bookingId;
  final String maidId;
  final bool withFriend;
  final String friendVrcid;
  final int timeslot;
  final int queue;
  final bool autoqueue;

  factory SysbookingQueueItem.fromJson(Map<String, dynamic> json) {
    return SysbookingQueueItem(
      bookingId: (json['booking_id'] ?? '').toString().trim(),
      maidId: (json['maid_id'] ?? '').toString().trim(),
      withFriend: json['with_friend'] == true,
      friendVrcid: (json['friend_vrcid'] ?? '').toString().trim(),
      timeslot: json['timeslot'] is num
          ? (json['timeslot'] as num).toInt()
          : int.tryParse((json['timeslot'] ?? '').toString().trim()) ?? 0,
      queue: json['queue'] is num
          ? (json['queue'] as num).toInt()
          : int.tryParse((json['queue'] ?? '').toString().trim()) ?? 0,
      autoqueue: json['autoqueue'] == true,
    );
  }
}

class SysbookingApiException implements Exception {
  const SysbookingApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

class SysbookingUnauthorizedException extends SysbookingApiException {
  const SysbookingUnauthorizedException(super.message, {super.statusCode});
}

class SysbookingApiService {
  SysbookingApiService._();

  static const String _baseUrl = BackendRequestHeaders.baseUrl;

  static Uri _resolve(String path) {
    final base = Uri.parse(_baseUrl.trim());
    final normalizedBasePath = base.path.endsWith('/')
        ? base.path
        : (base.path.isEmpty ? '/' : '${base.path}/');
    final normalizedBase = base.replace(path: normalizedBasePath);
    final relativePath = path.startsWith('/') ? path.substring(1) : path;
    return normalizedBase.resolve(relativePath);
  }

  static Future<Map<String, String>> _jsonHeaders([
    Map<String, String>? extra,
  ]) async {
    await BackendRequestHeaders.initialize();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...BackendRequestHeaders.forUrl(_baseUrl),
      ...?extra,
    };
  }

  static Future<String> loginAndGetBookingToken({
    required String email,
    required String password,
  }) async {
    try {
      final authResponse = await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await AuthLogService.record(
        event: 'password_sign_in',
        source: 'SysbookingApiService.loginAndGetBookingToken',
        succeeded: authResponse.session != null,
        email: email,
        detail: authResponse.session == null ? '认证服务未返回会话' : null,
        session: authResponse.session,
      );
      final session = authResponse.session;
      if (session == null) {
        throw const SysbookingApiException('登录失败，未获取到有效会话');
      }
      return await exchangeSessionForBookingToken(session: session);
    } catch (error) {
      if (error is! SysbookingApiException) {
        await AuthLogService.record(
          event: 'password_sign_in',
          source: 'SysbookingApiService.loginAndGetBookingToken',
          succeeded: false,
          email: email,
          detail: error is AuthException
              ? error.message
              : AuthLogService.errorDetail(error),
        );
      }
      rethrow;
    }
  }

  static Future<String> exchangeSessionForBookingToken({
    required Session session,
  }) async {
    final refreshToken = session.refreshToken?.trim() ?? '';
    final userId = session.user.id.trim();
    if (refreshToken.isEmpty || userId.isEmpty) {
      throw const SysbookingApiException('登录失败，未获取到有效会话');
    }

    final body = <String, dynamic>{
      'user_id': userId,
      'sb_refreshtoken': refreshToken,
    };

    final response = await http.post(
      _resolve('/sysbooking/login'),
      headers: await _jsonHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '换取排队登录态失败'),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const SysbookingApiException('换取排队登录态失败，响应格式错误');
    }

    final token = (decoded['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw const SysbookingApiException('换取排队登录态失败，未返回 token');
    }
    return token;
  }

  static Future<List<SysbookingQueueItem>> fetchQueueList(
    String bookingToken,
  ) async {
    final response = await http.get(
      _resolve('/sysbooking/queuelist'),
      headers: await _jsonHeaders({'x-booking-token': bookingToken.trim()}),
    );

    if (response.statusCode == 401) {
      throw SysbookingUnauthorizedException(
        _extractError(response.body, fallback: '登录已失效，请重新登录'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '获取排队列表失败'),
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const SysbookingApiException('获取排队列表失败，响应格式错误');
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              SysbookingQueueItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.maidId.isNotEmpty)
        .toList();
  }

  static Future<void> updateQueueAutoqueue({
    required String bookingToken,
    required String bookingId,
    required bool autoqueue,
  }) async {
    await updateQueueBooking(
      bookingToken: bookingToken,
      bookingId: bookingId,
      autoqueue: autoqueue,
    );
  }

  static Future<void> updateQueueBooking({
    required String bookingToken,
    required String bookingId,
    bool? autoqueue,
    bool? withFriend,
    String? friendVrcid,
  }) async {
    final payload = <String, dynamic>{'booking_id': bookingId.trim()};
    if (autoqueue != null) {
      payload['autoqueue'] = autoqueue;
    }
    if (withFriend != null) {
      payload['with_friend'] = withFriend;
    }
    if (friendVrcid != null) {
      payload['friend_vrcid'] = friendVrcid.trim();
    }

    if (payload.length == 1) {
      throw const SysbookingApiException('未提供可修改的字段');
    }

    final response = await http.put(
      _resolve('/sysbooking/booking'),
      headers: await _jsonHeaders({'x-booking-token': bookingToken.trim()}),
      body: jsonEncode(payload),
    );

    if (response.statusCode == 401) {
      throw SysbookingUnauthorizedException(
        _extractError(response.body, fallback: '登录已失效，请重新登录'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '更新预约失败'),
        statusCode: response.statusCode,
      );
    }
  }

  static Future<void> logoutOtherQueueAccounts({
    required String bookingToken,
  }) async {
    final response = await http.get(
      _resolve('/sysbooking/logout'),
      headers: await _jsonHeaders({'x-booking-token': bookingToken.trim()}),
    );

    if (response.statusCode == 401) {
      throw SysbookingUnauthorizedException(
        _extractError(response.body, fallback: '登录已失效，请重新登录'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '登出其他预约系统账户失败'),
        statusCode: response.statusCode,
      );
    }
  }

  static Future<void> deleteQueueBooking({
    required String bookingToken,
    required String bookingId,
  }) async {
    final response = await http.delete(
      _resolve('/sysbooking/booking'),
      headers: await _jsonHeaders({'x-booking-token': bookingToken.trim()}),
      body: jsonEncode({'booking_id': bookingId.trim()}),
    );

    if (response.statusCode == 401) {
      throw SysbookingUnauthorizedException(
        _extractError(response.body, fallback: '登录已失效，请重新登录'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '删除预约失败'),
        statusCode: response.statusCode,
      );
    }
  }

  static Future<String> createQueueBooking({
    required String bookingToken,
    required String maidId,
    required int timeslot,
    required bool autoqueue,
    required bool withFriend,
    required String friendVrcid,
  }) async {
    final response = await http.post(
      _resolve('/sysbooking/booking'),
      headers: await _jsonHeaders({'x-booking-token': bookingToken.trim()}),
      body: jsonEncode({
        'maid_id': maidId.trim(),
        'timeslot': timeslot,
        'autoqueue': autoqueue,
        'with_friend': withFriend,
        'friend_vrcid': friendVrcid.trim(),
      }),
    );

    if (response.statusCode == 401) {
      throw SysbookingUnauthorizedException(
        _extractError(response.body, fallback: '登录已失效，请重新登录'),
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw SysbookingApiException(
        _extractError(response.body, fallback: '添加排队失败'),
        statusCode: response.statusCode,
      );
    }

    if (response.body.trim().isEmpty) {
      return '';
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return (decoded['booking_id'] ?? '').toString().trim();
    }

    throw const SysbookingApiException('添加排队失败，响应格式错误');
  }

  static String _extractError(String body, {required String fallback}) {
    final text = body.trim();
    if (text.isEmpty) return fallback;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        final error = (decoded['error'] ?? decoded['message'] ?? '')
            .toString()
            .trim();
        if (error.isNotEmpty) return error;
      }
    } catch (_) {
      // Ignore non-JSON bodies.
    }
    return text;
  }
}
