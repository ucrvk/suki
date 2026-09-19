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

abstract interface class RosterRemoteDataSource {
  Future<List<RosterEntry>> fetchRoster();
}

abstract interface class RosterCache {
  Future<RosterSnapshot?> read();
  Future<void> write(RosterSnapshot snapshot);
}

class WitchRosterApiService implements RosterRemoteDataSource {
  WitchRosterApiService({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri endpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/rpc/witch_roster',
  );

  final http.Client _client;

  @override
  Future<List<RosterEntry>> fetchRoster() async {
    final userAgent = await SupabaseService.buildUserAgent();
    final headers = <String, String>{
      'apikey': SupabaseService.supabaseAnonKey,
      'Accept': 'application/json',
    };
    // Browsers forbid scripts from setting User-Agent themselves.
    if (!kIsWeb) headers['User-Agent'] = userAgent;
    final response = await _client.get(endpoint, headers: headers);
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
  static const cacheKey = 'witch_roster_snapshot_v1';

  @override
  Future<RosterSnapshot?> read() async {
    await MaidContentCacheStore.ensureInitialized();
    final raw = MaidContentCacheStore.read<Map>(cacheKey);
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
  Future<void> write(RosterSnapshot snapshot) async {
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(cacheKey, {
      'entries': snapshot.entries.map((entry) => entry.toJson()).toList(),
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    });
  }
}

class RosterRepository {
  RosterRepository({RosterRemoteDataSource? remote, RosterCache? cache})
    : _remote = remote ?? WitchRosterApiService(),
      _cache = cache ?? HiveRosterCache();

  final RosterRemoteDataSource _remote;
  final RosterCache _cache;

  Future<RosterSnapshot?> loadCached() => _cache.read();

  Future<RosterSnapshot> refresh() async {
    final snapshot = RosterSnapshot(
      entries: await _remote.fetchRoster(),
      fetchedAt: DateTime.now(),
    );
    await _cache.write(snapshot);
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
