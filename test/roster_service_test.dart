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

  test('POSTs witch_roster with p_day and the unchanged apikey', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, WitchRosterApiService.endpoint);
      expect(request.headers['apikey'], SupabaseService.supabaseAnonKey);
      expect(request.headers['Content-Type'], 'application/json');
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(request.body), {'p_day': '2026-09-19'});
      return http.Response.bytes(utf8.encode(jsonEncode([row])), 200);
    });

    final entries = await WitchRosterApiService(
      client: client,
      accessToken: () async => null,
    ).fetchRoster(day: '2026-09-19');
    expect(entries.single.bookingId, 'booking-1');
  });

  test('sends the bearer token when signed in', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer signed-in-token');
      return http.Response.bytes(utf8.encode(jsonEncode([row])), 200);
    });

    await WitchRosterApiService(
      client: client,
      accessToken: () async => 'signed-in-token',
    ).fetchRoster(day: '2026-09-19');
  });

  test('rejects a non-array payload', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    expect(
      WitchRosterApiService(
        client: client,
        accessToken: () async => null,
      ).fetchRoster(day: '2026-09-19'),
      throwsA(isA<RosterRequestException>()),
    );
  });

  test('writes refreshed data per day and loads it back', () async {
    final cache = _MemoryCache();
    final repository = RosterRepository(
      remote: _Remote([RosterEntry.fromJson(row)]),
      cache: cache,
    );

    expect(await repository.loadCached('2026-09-19'), isNull);
    final refreshed = await repository.refresh('2026-09-19');
    final cached = await repository.loadCached('2026-09-19');

    expect(refreshed.entries.single.bookingId, 'booking-1');
    expect(cached?.entries.single.bookingId, 'booking-1');
    expect(cache.writeCount, 1);
    // 其它日期不会读到这天的数据。
    expect(await repository.loadCached('2026-09-20'), isNull);
  });

  test('a failed refresh leaves existing cache untouched', () async {
    final existing = RosterSnapshot(
      entries: [RosterEntry.fromJson(row)],
      fetchedAt: DateTime(2026),
    );
    final cache = _MemoryCache()..snapshotFor('2026-09-19', existing);
    final repository = RosterRepository(remote: _FailingRemote(), cache: cache);

    await expectLater(
      repository.refresh('2026-09-19'),
      throwsA(isA<RosterRequestException>()),
    );
    expect(await repository.loadCached('2026-09-19'), same(existing));
    expect(cache.writeCount, 0);
  });

  group('day helpers', () {
    test('rosterDayKey uses the local calendar day', () {
      expect(rosterDayKey(DateTime(2026, 9, 19)), '2026-09-19');
      expect(rosterDayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });

    test('parseRosterDay accepts only zero-padded valid dates', () {
      expect(parseRosterDay('2026-09-19'), DateTime(2026, 9, 19));
      expect(parseRosterDay(' 2026-09-19 '), DateTime(2026, 9, 19));
      expect(parseRosterDay('2026-9-19'), isNull);
      expect(parseRosterDay('2026-13-01'), isNull);
      expect(parseRosterDay('2026-02-30'), isNull);
      expect(parseRosterDay('yesterday'), isNull);
      expect(parseRosterDay(''), isNull);
    });

    test('formatRosterDayLabel renders month, day and weekday', () {
      // 2026-09-19 是星期六。
      expect(formatRosterDayLabel(DateTime(2026, 9, 19)), '09月19日 星期六');
      expect(formatRosterDayLabel(DateTime(2026, 9, 20)), '09月20日 星期日');
    });
  });
}

class _Remote implements RosterRemoteDataSource {
  _Remote(this.entries);
  final List<RosterEntry> entries;

  @override
  Future<List<RosterEntry>> fetchRoster({required String day}) async => entries;
}

class _FailingRemote implements RosterRemoteDataSource {
  @override
  Future<List<RosterEntry>> fetchRoster({required String day}) =>
      Future.error(const RosterRequestException('HTTP 500', statusCode: 500));
}

class _MemoryCache implements RosterCache {
  final Map<String, RosterSnapshot> _byDay = {};
  int writeCount = 0;

  void snapshotFor(String day, RosterSnapshot snapshot) =>
      _byDay[day] = snapshot;

  @override
  Future<RosterSnapshot?> read(String day) async => _byDay[day];

  @override
  Future<void> write(String day, RosterSnapshot value) async {
    writeCount++;
    _byDay[day] = value;
  }
}
