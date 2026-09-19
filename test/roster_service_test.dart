import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suki/models/roster_entry.dart';
import 'package:suki/services/roster_service.dart';
import 'package:suki/services/supabase_service.dart';

void main() {
  const row = {
    'script_name': '夜眠花',
    'session_at': '2026-09-19T13:30:00Z',
    'session_end': null,
    'group_name': 'DMW',
    'guests': 2,
    'booking_id': 'booking-1',
    'companions': <String>[],
  };

  test('GETs witch_roster with the unchanged apikey', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, WitchRosterApiService.endpoint);
      expect(request.headers['apikey'], SupabaseService.supabaseAnonKey);
      return http.Response.bytes(utf8.encode(jsonEncode([row])), 200);
    });

    final entries = await WitchRosterApiService(client: client).fetchRoster();
    expect(entries.single.bookingId, 'booking-1');
  });

  test('rejects a non-array payload', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    expect(
      WitchRosterApiService(client: client).fetchRoster(),
      throwsA(isA<RosterRequestException>()),
    );
  });

  test('writes refreshed data and can load the resulting cache', () async {
    final cache = _MemoryCache();
    final repository = RosterRepository(
      remote: _Remote([_entryFromRow(row)]),
      cache: cache,
    );

    expect(await repository.loadCached(), isNull);
    final refreshed = await repository.refresh();
    final cached = await repository.loadCached();

    expect(refreshed.entries.single.bookingId, 'booking-1');
    expect(cached?.entries.single.bookingId, 'booking-1');
    expect(cache.writeCount, 1);
  });

  test('a failed refresh leaves existing cache untouched', () async {
    final existing = RosterSnapshot(
      entries: [_entryFromRow(row)],
      fetchedAt: DateTime(2026),
    );
    final cache = _MemoryCache()..snapshot = existing;
    final repository = RosterRepository(remote: _FailingRemote(), cache: cache);

    await expectLater(repository.refresh(), throwsException);
    expect(await repository.loadCached(), same(existing));
    expect(cache.writeCount, 0);
  });
}

RosterEntry _entryFromRow(Map<String, dynamic> row) =>
    RosterEntry.fromJson(row);

class _Remote implements RosterRemoteDataSource {
  _Remote(this.entries);
  final List<RosterEntry> entries;

  @override
  Future<List<RosterEntry>> fetchRoster() async => entries;
}

class _FailingRemote implements RosterRemoteDataSource {
  @override
  Future<List<RosterEntry>> fetchRoster() => Future.error(Exception('offline'));
}

class _MemoryCache implements RosterCache {
  RosterSnapshot? snapshot;
  int writeCount = 0;

  @override
  Future<RosterSnapshot?> read() async => snapshot;

  @override
  Future<void> write(RosterSnapshot value) async {
    writeCount++;
    snapshot = value;
  }
}
