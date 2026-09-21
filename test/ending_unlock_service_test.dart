import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:suki/services/ending_unlock_service.dart';

void main() {
  test('requests the unlock rows of the given user', () async {
    final client = _FakeClient(
      (request) => http.Response(
        jsonEncode([
          {'ending_id': 'ending-1'},
          {'ending_id': 'ending-2'},
        ]),
        200,
      ),
    );
    final service = SupabaseEndingUnlockService(client: client);

    final ids = await service.fetchUnlockedEndingIds('user-1');

    expect(ids, {'ending-1', 'ending-2'});
    expect(client.lastRequest!.url.query, 'select=ending_id&user_id=eq.user-1');
    expect(
      client.lastRequest!.url.path,
      endsWith('/rest/v1/suki_witch_ending_unlocks'),
    );
  });

  test('drops blank rows and accepts an empty result', () async {
    final client = _FakeClient(
      (_) => http.Response(
        jsonEncode([
          {'ending_id': 'ending-1'},
          {'ending_id': ''},
          {},
        ]),
        200,
      ),
    );

    final ids = await SupabaseEndingUnlockService(
      client: client,
    ).fetchUnlockedEndingIds('user-1');

    expect(ids, {'ending-1'});

    final empty = await SupabaseEndingUnlockService(
      client: _FakeClient((_) => http.Response('[]', 200)),
    ).fetchUnlockedEndingIds('user-1');

    expect(empty, isEmpty);
  });

  test('reports transport and payload failures', () async {
    expect(
      () => SupabaseEndingUnlockService(
        client: _FakeClient((_) => http.Response('nope', 500)),
      ).fetchUnlockedEndingIds('user-1'),
      throwsA(isA<EndingUnlockException>()),
    );
    expect(
      () => SupabaseEndingUnlockService(
        client: _FakeClient((_) => http.Response('{"code":"400"}', 200)),
      ).fetchUnlockedEndingIds('user-1'),
      throwsA(isA<EndingUnlockException>()),
    );
    expect(
      () => SupabaseEndingUnlockService(
        client: _FakeClient((_) => throw http.ClientException('offline')),
      ).fetchUnlockedEndingIds('user-1'),
      throwsA(isA<EndingUnlockException>()),
    );
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final http.Response Function(http.BaseRequest request) _handler;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final response = _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([utf8.encode(response.body)]),
      response.statusCode,
      request: request,
      headers: response.headers,
    );
  }
}
