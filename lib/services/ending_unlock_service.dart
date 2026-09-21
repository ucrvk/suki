import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'maid_content_cache_store.dart';
import 'supabase_service.dart';

/// 结局解锁记录：哪些结局对指定用户已解锁。
abstract interface class EndingUnlockRemote {
  Future<Set<String>> fetchUnlockedEndingIds(String userId);
}

class SupabaseEndingUnlockService implements EndingUnlockRemote {
  SupabaseEndingUnlockService({http.Client? client})
    : _client = client ?? http.Client();

  static Uri endpointFor(String userId) => Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/suki_witch_ending_unlocks'
    '?select=ending_id&user_id=eq.${Uri.encodeComponent(userId)}',
  );

  final http.Client _client;

  @override
  Future<Set<String>> fetchUnlockedEndingIds(String userId) async {
    final headers = <String, String>{
      'apikey': SupabaseService.supabaseAnonKey,
      'Accept': 'application/json',
    };
    if (!kIsWeb) headers['User-Agent'] = await SupabaseService.buildUserAgent();

    final http.Response response;
    try {
      response = await _client.get(endpointFor(userId), headers: headers);
    } on http.ClientException catch (error) {
      throw EndingUnlockException('无法连接服务器', cause: error);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw EndingUnlockException('HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw EndingUnlockException('服务器返回了无效 JSON', cause: error);
    }
    if (decoded is! List) {
      throw const EndingUnlockException('解锁数据必须是数组');
    }
    return decoded
        .map((row) {
          if (row is! Map) throw const FormatException('数组包含无效记录');
          final id = row['ending_id'];
          if (id is! String) return '';
          return id.trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}

class EndingUnlockRepository {
  EndingUnlockRepository({EndingUnlockRemote? remote})
    : _remote = remote ?? SupabaseEndingUnlockService();

  static const String _cachePrefix = 'ending_unlocks_v1_';

  final EndingUnlockRemote _remote;

  static String cacheKeyFor(String userId) => '$_cachePrefix$userId';

  Future<Set<String>> loadCached(String userId) async {
    await MaidContentCacheStore.ensureInitialized();
    final raw = MaidContentCacheStore.read<Map>(cacheKeyFor(userId));
    if (raw == null) return <String>{};
    final ids = raw['ids'];
    if (ids is! List) return <String>{};
    return ids.whereType<String>().map((id) => id.trim()).toSet();
  }

  Future<Set<String>> refresh(String userId) async {
    final ids = await _remote.fetchUnlockedEndingIds(userId);
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(cacheKeyFor(userId), {
      'ids': ids.toList(growable: false),
      'fetchedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return ids;
  }
}

class EndingUnlockException implements Exception {
  const EndingUnlockException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
