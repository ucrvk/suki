import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suki/models/world_content_entry.dart';
import 'package:suki/services/supabase_service.dart';
import 'package:suki/services/world_content_service.dart';

void main() {
  const codexRow = {
    'id': 'codex-1',
    'kind': 'witch',
    'title': '纸樱',
    'subtitle': '',
    'image_url': '',
    'image_url2': null,
    'tags': <String>[],
    'body': '介绍',
    'sort': 1,
    'created_at': '2026-09-09T02:04:03+08:00',
  };
  const endingRow = {
    'id': 'ending-1',
    'script': '夜眠花',
    'title': '黎明之誓',
    'subtitle': '',
    'image_url': '',
    'tags': <String>[],
    'body': '结局正文',
    'sort': 2,
    'created_at': '2026-09-09T02:04:03+08:00',
  };

  test('uses both ordered GET endpoints and unchanged apikey', () async {
    final visited = <Uri>[];
    final client = MockClient((request) async {
      visited.add(request.url);
      expect(request.method, 'GET');
      expect(request.headers['apikey'], SupabaseService.supabaseAnonKey);
      final payload = request.url.path.endsWith('suki_witch_codex')
          ? [codexRow]
          : [endingRow];
      return http.Response.bytes(utf8.encode(jsonEncode(payload)), 200);
    });
    final api = SupabaseWorldContentApi(client: client);

    expect((await api.fetchCodex()).single.title, '纸樱');
    expect((await api.fetchEndings()).single.title, '黎明之誓');
    expect(visited, [
      SupabaseWorldContentApi.codexEndpoint,
      SupabaseWorldContentApi.endingsEndpoint,
    ]);
  });

  test('ignores unknown codex kinds', () async {
    final unknown = Map<String, dynamic>.from(codexRow)..['kind'] = 'future';
    final client = MockClient(
      (_) async => http.Response.bytes(utf8.encode(jsonEncode([unknown])), 200),
    );
    expect(await SupabaseWorldContentApi(client: client).fetchCodex(), isEmpty);
  });

  test('codex and endings caches update independently', () async {
    final cache = _MemoryWorldCache();
    final repository = WorldContentRepository(
      remote: _RemoteWorld(
        codex: [WorldContentEntry.fromCodexJson(codexRow)],
        endings: [WorldContentEntry.fromEndingJson(endingRow)],
      ),
      cache: cache,
    );

    await repository.refreshCodex();
    expect(await repository.loadCachedCodex(), isNotNull);
    expect(await repository.loadCachedEndings(), isNull);

    await repository.refreshEndings();
    expect(await repository.loadCachedEndings(), isNotNull);
    expect(cache.codexWrites, 1);
    expect(cache.endingsWrites, 1);
  });

  test('one failed endpoint does not overwrite the other cache', () async {
    final existingEnding = WorldContentSnapshot(
      entries: [WorldContentEntry.fromEndingJson(endingRow)],
      fetchedAt: DateTime(2026),
    );
    final cache = _MemoryWorldCache()..endings = existingEnding;
    final repository = WorldContentRepository(
      remote: _RemoteWorld(
        codex: [WorldContentEntry.fromCodexJson(codexRow)],
        endingsError: Exception('offline'),
      ),
      cache: cache,
    );

    await repository.refreshCodex();
    await expectLater(repository.refreshEndings(), throwsException);
    expect(await repository.loadCachedEndings(), same(existingEnding));
    expect(cache.endingsWrites, 0);
  });
}

class _RemoteWorld implements WorldContentRemote {
  _RemoteWorld({
    this.codex = const [],
    this.endings = const [],
    this.endingsError,
  });

  final List<WorldContentEntry> codex;
  final List<WorldContentEntry> endings;
  final Object? endingsError;

  @override
  Future<List<WorldContentEntry>> fetchCodex() async => codex;

  @override
  Future<List<WorldContentEntry>> fetchEndings() async {
    if (endingsError != null) throw endingsError!;
    return endings;
  }
}

class _MemoryWorldCache implements WorldContentCache {
  WorldContentSnapshot? codex;
  WorldContentSnapshot? endings;
  int codexWrites = 0;
  int endingsWrites = 0;

  @override
  Future<WorldContentSnapshot?> readCodex() async => codex;

  @override
  Future<WorldContentSnapshot?> readEndings() async => endings;

  @override
  Future<void> writeCodex(WorldContentSnapshot snapshot) async {
    codexWrites++;
    codex = snapshot;
  }

  @override
  Future<void> writeEndings(WorldContentSnapshot snapshot) async {
    endingsWrites++;
    endings = snapshot;
  }
}
