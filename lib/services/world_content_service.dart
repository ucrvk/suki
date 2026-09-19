import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/world_content_entry.dart';
import 'maid_content_cache_store.dart';
import 'supabase_service.dart';

class WorldContentSnapshot {
  const WorldContentSnapshot({required this.entries, required this.fetchedAt});

  final List<WorldContentEntry> entries;
  final DateTime fetchedAt;
}

abstract interface class WorldContentRemote {
  Future<List<WorldContentEntry>> fetchCodex();
  Future<List<WorldContentEntry>> fetchEndings();
}

abstract interface class WorldContentCache {
  Future<WorldContentSnapshot?> readCodex();
  Future<WorldContentSnapshot?> readEndings();
  Future<void> writeCodex(WorldContentSnapshot snapshot);
  Future<void> writeEndings(WorldContentSnapshot snapshot);
}

class SupabaseWorldContentApi implements WorldContentRemote {
  SupabaseWorldContentApi({http.Client? client})
    : _client = client ?? http.Client();

  static final Uri codexEndpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/suki_witch_codex'
    '?select=*&order=sort.asc%2Ccreated_at.asc',
  );
  static final Uri endingsEndpoint = Uri.parse(
    '${SupabaseService.supabaseUrl}/rest/v1/suki_witch_endings'
    '?select=*&order=script.asc%2Csort.asc',
  );

  final http.Client _client;

  @override
  Future<List<WorldContentEntry>> fetchCodex() async {
    final rows = await _getRows(codexEndpoint);
    return rows
        .map(WorldContentEntry.fromCodexJson)
        .where((entry) => entry.kind != WorldContentKind.unknown)
        .toList(growable: false);
  }

  @override
  Future<List<WorldContentEntry>> fetchEndings() async {
    final rows = await _getRows(endingsEndpoint);
    return rows.map(WorldContentEntry.fromEndingJson).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _getRows(Uri endpoint) async {
    final headers = <String, String>{
      'apikey': SupabaseService.supabaseAnonKey,
      'Accept': 'application/json',
    };
    if (!kIsWeb) headers['User-Agent'] = await SupabaseService.buildUserAgent();
    final response = await _client.get(endpoint, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WorldContentRequestException('HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw WorldContentRequestException('服务器返回了无效 JSON', cause: error);
    }
    if (decoded is! List) {
      throw const WorldContentRequestException('世界内容必须是数组');
    }
    try {
      return decoded
          .map((row) {
            if (row is! Map) throw const FormatException('数组包含无效记录');
            return Map<String, dynamic>.from(row);
          })
          .toList(growable: false);
    } on FormatException catch (error) {
      throw WorldContentRequestException(
        '世界内容格式错误：${error.message}',
        cause: error,
      );
    }
  }
}

class HiveWorldContentCache implements WorldContentCache {
  static const codexCacheKey = 'witch_codex_snapshot_v1';
  static const endingsCacheKey = 'witch_endings_snapshot_v1';

  @override
  Future<WorldContentSnapshot?> readCodex() =>
      _read(codexCacheKey, WorldContentEntry.fromCodexJson);

  @override
  Future<WorldContentSnapshot?> readEndings() =>
      _read(endingsCacheKey, WorldContentEntry.fromEndingJson);

  @override
  Future<void> writeCodex(WorldContentSnapshot snapshot) =>
      _write(codexCacheKey, snapshot);

  @override
  Future<void> writeEndings(WorldContentSnapshot snapshot) =>
      _write(endingsCacheKey, snapshot);

  Future<WorldContentSnapshot?> _read(
    String key,
    WorldContentEntry Function(Map<String, dynamic>) parser,
  ) async {
    await MaidContentCacheStore.ensureInitialized();
    final raw = MaidContentCacheStore.read<Map>(key);
    if (raw == null) return null;
    try {
      final rows = raw['entries'];
      final fetchedAt = raw['fetchedAt'];
      if (rows is! List || fetchedAt is! int) return null;
      return WorldContentSnapshot(
        entries: rows
            .whereType<Map>()
            .map((row) => parser(Map<String, dynamic>.from(row)))
            .where((entry) => entry.kind != WorldContentKind.unknown)
            .toList(growable: false),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(fetchedAt),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, WorldContentSnapshot snapshot) async {
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(key, {
      'entries': snapshot.entries.map((entry) => entry.toJson()).toList(),
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    });
  }
}

class WorldContentRepository {
  WorldContentRepository({WorldContentRemote? remote, WorldContentCache? cache})
    : _remote = remote ?? SupabaseWorldContentApi(),
      _cache = cache ?? HiveWorldContentCache();

  final WorldContentRemote _remote;
  final WorldContentCache _cache;

  Future<WorldContentSnapshot?> loadCachedCodex() => _cache.readCodex();
  Future<WorldContentSnapshot?> loadCachedEndings() => _cache.readEndings();

  Future<WorldContentSnapshot> refreshCodex() async {
    final snapshot = WorldContentSnapshot(
      entries: await _remote.fetchCodex(),
      fetchedAt: DateTime.now(),
    );
    await _cache.writeCodex(snapshot);
    return snapshot;
  }

  Future<WorldContentSnapshot> refreshEndings() async {
    final snapshot = WorldContentSnapshot(
      entries: await _remote.fetchEndings(),
      fetchedAt: DateTime.now(),
    );
    await _cache.writeEndings(snapshot);
    return snapshot;
  }
}

class WorldContentRequestException implements Exception {
  const WorldContentRequestException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
