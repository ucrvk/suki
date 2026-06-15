import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fcm_service.dart';
import 'supabase_service.dart';

class SysbookingQueueItem {
  const SysbookingQueueItem({
    required this.maidId,
    required this.timeslot,
    required this.queue,
    required this.autoqueue,
  });

  final String maidId;
  final int timeslot;
  final int queue;
  final bool autoqueue;

  factory SysbookingQueueItem.fromJson(Map<String, dynamic> json) {
    return SysbookingQueueItem(
      maidId: (json['maid_id'] ?? '').toString().trim(),
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

  static const String _baseUrl = String.fromEnvironment(
    'SYSBOOKING_BASE_URL',
    defaultValue: 'https://api.wenwen12305.top/suki',
  );

  static Uri _resolve(String path) {
    final base = Uri.parse(_baseUrl.trim());
    final normalizedBasePath = base.path.endsWith('/')
        ? base.path
        : (base.path.isEmpty ? '/' : '${base.path}/');
    final normalizedBase = base.replace(path: normalizedBasePath);
    final relativePath = path.startsWith('/') ? path.substring(1) : path;
    return normalizedBase.resolve(relativePath);
  }

  static Map<String, String> _jsonHeaders([Map<String, String>? extra]) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (extra != null) ...extra,
    };
  }

  static Future<String> loginAndGetBookingToken({
    required String email,
    required String password,
    String? fcmToken,
  }) async {
    final authResponse = await SupabaseService.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final session = authResponse.session;
    if (session == null) {
      throw const SysbookingApiException('登录失败，未获取到有效会话');
    }
    return exchangeSessionForBookingToken(session: session, fcmToken: fcmToken);
  }

  static Future<String> exchangeSessionForBookingToken({
    required Session session,
    String? fcmToken,
  }) async {
    final refreshToken = session.refreshToken?.trim() ?? '';
    final userId = session.user.id.trim();
    if (refreshToken.isEmpty || userId.isEmpty) {
      throw const SysbookingApiException('登录失败，未获取到有效会话');
    }

    final resolvedFcmToken = await _resolveFcmToken(fcmToken);
    final body = <String, dynamic>{
      'user_id': userId,
      'sb_refreshtoken': refreshToken,
    };
    if (resolvedFcmToken != null) {
      body['fcm_token'] = resolvedFcmToken;
    }

    final response = await http.post(
      _resolve('/sysbooking/login'),
      headers: _jsonHeaders(),
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

  static Future<String?> _resolveFcmToken(String? provided) async {
    final normalizedProvided = provided?.trim();
    if (normalizedProvided != null && normalizedProvided.isNotEmpty) {
      return normalizedProvided;
    }

    try {
      final currentToken = await FcmService.getCurrentToken()
          .timeout(const Duration(seconds: 2));
      final normalizedCurrent = currentToken?.trim();
      if (normalizedCurrent == null || normalizedCurrent.isEmpty) {
        return null;
      }
      return normalizedCurrent;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<SysbookingQueueItem>> fetchQueueList(
    String bookingToken,
  ) async {
    final response = await http.get(
      _resolve('/sysbooking/queuelist'),
      headers: _jsonHeaders({'x-booking-token': bookingToken.trim()}),
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
