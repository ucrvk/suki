import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/roster_entry.dart';
import 'maid_content_cache_store.dart';
import 'supabase_service.dart';

class RosterSnapshot {
  const RosterSnapshot({required this.entries, required this.fetchedAt});

  final List<RosterEntry> entries;
  final DateTime fetchedAt;
}

/// 排班按天查询，`day` 统一使用本地时区的 `YYYY-MM-DD`。
String rosterDayKey(DateTime local) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// 归一化到本地时区当天零点。
DateTime rosterDayOf(DateTime local) =>
    DateTime(local.year, local.month, local.day);

/// 解析手动输入的 `YYYY-MM-DD`，非法返回 null。
DateTime? parseRosterDay(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  final normalized = rosterDayOf(parsed);
  return rosterDayKey(normalized) == value ? normalized : null;
}

/// `09月19日 星期六`
String formatRosterDayLabel(DateTime local) {
  final weekday = '日一二三四五六'[local.weekday % 7];
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.month)}月${two(local.day)}日 星期$weekday';
}

abstract interface class RosterRemoteDataSource {
  Future<List<RosterEntry>> fetchRoster({required String day});
}

class WitchRosterApiService implements RosterRemoteDataSource {
  WitchRosterApiService({
    http.Client? client,
    Future<String?> Function()? accessToken,
  }) : _client = client ?? http.Client(),
       _accessToken = accessToken ?? _supabaseAccessToken;

  static final Uri endpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/rpc/witch_roster',
  );

  final http.Client _client;
  final Future<String?> Function() _accessToken;

  static Future<String?> _supabaseAccessToken() async {
    try {
      return SupabaseService.client.auth.currentSession?.accessToken;
    } catch (_) {
      // 测试环境未初始化 Supabase 时视为未登录。
      return null;
    }
  }

  @override
  Future<List<RosterEntry>> fetchRoster({required String day}) async {
    final userAgent = await SupabaseService.buildUserAgent();
    final headers = <String, String>{
      'apikey': SupabaseService.supabaseAnonKey,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    // Browsers forbid scripts from setting User-Agent themselves.
    if (!kIsWeb) headers['User-Agent'] = userAgent;
    final token = await _accessToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _client.post(
      endpoint,
      headers: headers,
      body: jsonEncode({'p_day': day}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RosterRequestException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw RosterRequestException('服务器返回了无效 JSON', cause: error);
    }
    if (decoded is! List) {
      throw const RosterRequestException('排班数据必须是数组');
    }

    return decoded
        .map((item) {
          if (item is! Map) {
            throw const RosterRequestException('排班数组包含无效记录');
          }
          try {
            return RosterEntry.fromJson(Map<String, dynamic>.from(item));
          } on FormatException catch (error) {
            throw RosterRequestException(
              '排班记录格式错误：${error.message}',
              cause: error,
            );
          }
        })
        .toList(growable: false);
  }
}

class HiveRosterCache implements RosterCache {
  static String cacheKey(String day) => 'witch_roster_snapshot_v2_$day';

  @override
  Future<RosterSnapshot?> read(String day) async {
    await MaidContentCacheStore.ensureInitialized();
    final raw = MaidContentCacheStore.read<Map>(cacheKey(day));
    if (raw == null) return null;
    try {
      final rows = raw['entries'];
      final fetchedAt = raw['fetchedAt'];
      if (rows is! List || fetchedAt is! int) return null;
      return RosterSnapshot(
        entries: rows
            .whereType<Map>()
            .map((row) => RosterEntry.fromJson(Map<String, dynamic>.from(row)))
            .toList(growable: false),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String day, RosterSnapshot snapshot) async {
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(cacheKey(day), {
      'entries': snapshot.entries.map((entry) => entry.toJson()).toList(),
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    });
  }
}

abstract interface class RosterCache {
  Future<RosterSnapshot?> read(String day);
  Future<void> write(String day, RosterSnapshot snapshot);
}

class RosterRepository {
  RosterRepository({RosterRemoteDataSource? remote, RosterCache? cache})
    : _remote = remote ?? WitchRosterApiService(),
      _cache = cache ?? HiveRosterCache();

  final RosterRemoteDataSource _remote;
  final RosterCache _cache;

  Future<RosterSnapshot?> loadCached(String day) => _cache.read(day);

  Future<RosterSnapshot> refresh(String day) async {
    final snapshot = RosterSnapshot(
      entries: await _remote.fetchRoster(day: day),
      fetchedAt: DateTime.now(),
    );
    await _cache.write(day, snapshot);
    return snapshot;
  }
}

class RosterRequestException implements Exception {
  const RosterRequestException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => message;
}
